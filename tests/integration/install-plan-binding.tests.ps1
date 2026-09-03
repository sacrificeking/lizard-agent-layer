param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.Host.psm1') -Force

$fixtureRoot = Join-Path $RepoRoot '.tmp/tests/install-plan-binding'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$target = Join-Path $fixtureRoot 'target'
New-Item -ItemType Directory -Path $target -Force | Out-Null

try {
  $approval = New-TestInstallApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $target, '-Profile', 'minimal')
  Assert-True (Test-Path -LiteralPath ($approval.plan_path + '.sha256') -PathType Leaf) 'Preview must emit a convenience digest sidecar.'
  $apply = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/install.ps1') -Arguments $approval.arguments
  Assert-Equal 0 $apply.exit_code "Exact approved install plan must apply: $($apply.output)"
  $manifestPath = Join-Path $target '.agent/lizard-agent-layer.install.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-LizardJson
  Assert-Equal $approval.sha256 ([string]$manifest.applied_plan_sha256) 'Manifest must record the exact independently supplied plan digest.'
  Assert-Equal 32 ([string]$manifest.applied_plan_id).Length 'Manifest must record the approved plan ID.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Committed install must remove its transaction lock.'
  Assert-JsonSchemaValid -LayerRoot $RepoRoot -SchemaPath 'schemas/install-manifest.schema.json' -InstancePath $manifestPath -Message 'Plan-bound install manifest must satisfy schema.'

  # 2. Test Markdown Apply Block execution with -MemoryMode off and -WritePlan -PlanPath
  $target2 = Join-Path $fixtureRoot 'target-markdown-apply'
  New-Item -ItemType Directory -Path $target2 -Force | Out-Null
  $planMdPath = Join-Path $fixtureRoot 'install-plan-custom.md'
  $canonicalPlanPath = Join-Path $fixtureRoot 'install-plan-custom.json'

  $previewArgs = @(
    '-TargetPath', $target2,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-MemoryMode', 'off',
    '-WritePlan',
    '-PlanPath', $planMdPath,
    '-CanonicalPlanPath', $canonicalPlanPath
  )
  $previewRes = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/install.ps1') -Arguments $previewArgs
  Assert-Equal 0 $previewRes.exit_code "Preview with custom plan path must succeed: $($previewRes.output)"
  Assert-True (Test-Path -LiteralPath $planMdPath -PathType Leaf) 'Markdown plan report must exist.'
  Assert-True (Test-Path -LiteralPath $canonicalPlanPath -PathType Leaf) 'Canonical plan file must exist.'

  $planSha = (Get-FileHash -LiteralPath $canonicalPlanPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $mdContent = Get-Content -LiteralPath $planMdPath -Raw
  $match = [regex]::Match($mdContent, '(?ms)Apply:\s*```powershell\s*\r?\n(.*?)\r?\n```')
  Assert-True $match.Success 'Markdown plan must contain an Apply command block.'
  $applyCmdRaw = $match.Groups[1].Value.Trim()
  $applyCmdReplaced = $applyCmdRaw -replace '<independently-reviewed-sha256>', $planSha

  $applyRes = & (Get-LizardPowerShellHostPath) -Command $applyCmdReplaced 2>&1 | Out-String
  Assert-Equal 0 ([int]$LASTEXITCODE) "Executing printed Apply command from markdown must succeed: $applyRes"
  Assert-True (Test-Path -LiteralPath (Join-Path $target2 '.agent/lizard-agent-layer.install.json')) 'Target must be installed by markdown Apply command.'

  # 3. Negative: conflicting memory mode must fail closed with PLAN_BINDING_OPTIONS_MISMATCH
  $mismatchArgs = @(
    '-TargetPath', $target2,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-MemoryMode', 'curated',
    '-Apply',
    '-ApprovedPlanPath', $canonicalPlanPath,
    '-ApprovedPlanSha256', $planSha,
    '-HumanApproved'
  )
  $mismatchRes = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/install.ps1') -Arguments $mismatchArgs
  Assert-True ($mismatchRes.output -match 'PLAN_BINDING_OPTIONS_MISMATCH') "Conflicting memory mode must fail closed with PLAN_BINDING_OPTIONS_MISMATCH: $($mismatchRes.output)"

  Write-Host 'PASS tests\integration\install-plan-binding.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
}
