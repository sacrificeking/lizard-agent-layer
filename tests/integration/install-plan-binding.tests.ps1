param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests\TestHelpers.psm1') -Force

$fixtureRoot = Join-Path $RepoRoot '.tmp\tests\install-plan-binding'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$target = Join-Path $fixtureRoot 'target'
New-Item -ItemType Directory -Path $target -Force | Out-Null

try {
  $approval = New-TestInstallApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $target, '-Profile', 'minimal')
  Assert-True (Test-Path -LiteralPath ($approval.plan_path + '.sha256') -PathType Leaf) 'Preview must emit a convenience digest sidecar.'
  $apply = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts\install.ps1') -Arguments $approval.arguments
  Assert-Equal 0 $apply.exit_code "Exact approved install plan must apply: $($apply.output)"
  $manifestPath = Join-Path $target '.agent\lizard-agent-layer.install.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-LizardJson
  Assert-Equal $approval.sha256 ([string]$manifest.applied_plan_sha256) 'Manifest must record the exact independently supplied plan digest.'
  Assert-Equal 32 ([string]$manifest.applied_plan_id).Length 'Manifest must record the approved plan ID.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Committed install must remove its transaction lock.'
  Assert-JsonSchemaValid -LayerRoot $RepoRoot -SchemaPath 'schemas/install-manifest.schema.json' -InstancePath $manifestPath -Message 'Plan-bound install manifest must satisfy schema.'
  Write-Host 'PASS tests\integration\install-plan-binding.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
}
