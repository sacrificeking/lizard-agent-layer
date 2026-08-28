param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.Json.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.Plan.psm1') -Force

$fixtureRoot = Join-Path $RepoRoot '.tmp/tests/update-plan-binding'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$target = Join-Path $fixtureRoot 'target'
$output = Join-Path $fixtureRoot 'update-output'
New-Item -ItemType Directory -Path $target -Force | Out-Null

function Write-TestCanonicalPlan {
  param($Plan, [string]$Path)
  $canonical = ConvertTo-LizardCanonicalJson $Plan
  [System.IO.File]::WriteAllText($Path, $canonical, (New-Object System.Text.UTF8Encoding($false)))
  return Get-LizardPlanSha256 -CanonicalJson $canonical
}

Push-Location $RepoRoot
try {
  $installApproval = New-TestInstallApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $target, '-Profile', 'minimal')
  $install = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/install.ps1') -Arguments $installApproval.arguments
  Assert-Equal 0 $install.exit_code "Plan-bound prerequisite install must succeed: $($install.output)"

  $updateApproval = New-TestUpdateApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $target, '-OutputDir', $output)
  $updatePlan = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $updateApproval.plan_path -Raw)
  $boundLayerInputs = @($updatePlan.intent.inputs | Where-Object scope -eq 'layer' | ForEach-Object { [string]$_.path })
  Assert-True ($boundLayerInputs -contains 'scripts/Lizard.Host.psm1') 'Update plan must bind the host module it imports and executes.'
  Assert-True ($boundLayerInputs -contains 'scripts/manifest-diff.ps1') 'Update plan must bind the manifest-diff script it executes.'

  $missingChildPlan = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $updateApproval.plan_path -Raw)
  $missingChildPlan.intent.options.install_canonical_plan_path = Join-Path $fixtureRoot 'missing-child.json'
  $missingChildPlan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $missingChildPlan.intent
  $missingOuterPath = Join-Path $fixtureRoot 'missing-child-outer.json'
  $missingOuterSha256 = Write-TestCanonicalPlan -Plan $missingChildPlan -Path $missingOuterPath
  $missingChild = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/update-target.ps1') -Arguments @(
    '-TargetPath', $target, '-OutputDir', $output, '-Apply', '-ApprovedPlanPath', $missingOuterPath,
    '-ApprovedPlanSha256', $missingOuterSha256, '-HumanApproved'
  )
  Assert-False ($missingChild.exit_code -eq 0) 'Missing nested install plan must fail closed.'
  Assert-True ($missingChild.output -match 'SAFEFS_FILE_MISSING|PLAN_BINDING_NESTED_MISMATCH') 'Missing nested plan must expose a stable failure.'

  $wrongChildDigestPlan = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $updateApproval.plan_path -Raw)
  $wrongChildDigestPlan.intent.nested_plan.sha256 = ('0' * 64)
  $wrongChildDigestPlan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $wrongChildDigestPlan.intent
  $wrongOuterPath = Join-Path $fixtureRoot 'wrong-child-digest-outer.json'
  $wrongOuterSha256 = Write-TestCanonicalPlan -Plan $wrongChildDigestPlan -Path $wrongOuterPath
  $wrongChildDigest = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/update-target.ps1') -Arguments @(
    '-TargetPath', $target, '-OutputDir', $output, '-Apply', '-ApprovedPlanPath', $wrongOuterPath,
    '-ApprovedPlanSha256', $wrongOuterSha256, '-HumanApproved'
  )
  Assert-False ($wrongChildDigest.exit_code -eq 0) 'Wrong nested install digest must fail closed.'
  Assert-True ($wrongChildDigest.output -match 'PLAN_BINDING_DIGEST_MISMATCH') 'Wrong nested digest must expose a digest mismatch.'

  $staleOuterPlan = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $updateApproval.plan_path -Raw)
  $approvedChildPath = [string]$staleOuterPlan.intent.options.install_canonical_plan_path
  $staleChildPlan = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $approvedChildPath -Raw)
  $staleChildPlan.intent.source_git_head = ('0' * 40)
  $staleChildPlan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $staleChildPlan.intent
  $staleChildPath = Join-Path $fixtureRoot 'stale-child.json'
  $staleChildSha256 = Write-TestCanonicalPlan -Plan $staleChildPlan -Path $staleChildPath
  $staleOuterPlan.intent.options.install_canonical_plan_path = $staleChildPath
  $staleOuterPlan.intent.nested_plan.sha256 = $staleChildSha256
  $staleOuterPlan.intent.nested_plan.intent_sha256 = [string]$staleChildPlan.intent_sha256
  $staleOuterPlan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $staleOuterPlan.intent
  $staleOuterPath = Join-Path $fixtureRoot 'stale-child-outer.json'
  $staleOuterSha256 = Write-TestCanonicalPlan -Plan $staleOuterPlan -Path $staleOuterPath
  $staleChild = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/update-target.ps1') -Arguments @(
    '-TargetPath', $target, '-OutputDir', $output, '-Apply', '-ApprovedPlanPath', $staleOuterPath,
    '-ApprovedPlanSha256', $staleOuterSha256, '-HumanApproved'
  )
  Assert-False ($staleChild.exit_code -eq 0) 'Canonically redigested stale nested install plan must fail closed.'
  Assert-True ($staleChild.output -match 'PLAN_BINDING_NESTED_MISMATCH') "Stale nested plan must expose a nested binding mismatch. Output: $($staleChild.output)"

  $unbound = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/update-target.ps1') -Arguments @('-TargetPath', $target, '-OutputDir', $output, '-Apply')
  Assert-False ($unbound.exit_code -eq 0) 'Unbound update apply must fail closed.'
  Assert-True ($unbound.output -match 'PLAN_APPROVAL_REQUIRED') 'Unbound update must expose PLAN_APPROVAL_REQUIRED.'
  $apply = Invoke-TestPowerShell -ScriptPath (Join-Path $RepoRoot 'scripts/update-target.ps1') -Arguments $updateApproval.arguments
  Assert-Equal 0 $apply.exit_code "Exact approved update plan must apply: $($apply.output)"
  $historyPath = Join-Path $target '.agent/lizard-agent-layer.update-history.jsonl'
  $history = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $historyPath | Select-Object -Last 1)
  Assert-Equal $updateApproval.sha256 ([string]$history.applied_plan_sha256) 'Update history must record the exact approved outer plan digest.'
  Assert-Equal 64 ([string]$history.applied_install_plan_sha256).Length 'Update history must record the nested approved install digest.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Committed update must remove its transaction lock.'
  Write-Host 'PASS tests\integration\update-plan-binding.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
  Pop-Location
}
