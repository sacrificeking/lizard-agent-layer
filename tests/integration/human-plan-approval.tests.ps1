param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Json.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Plan.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Host.psm1') -Force

$testRoot = Join-Path $LayerRoot ('.tmp/tests/human-approval-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$targetRoot = Join-Path $testRoot 'target'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null

$installScript = Join-Path $LayerRoot 'scripts/install.ps1'
$uninstallScript = Join-Path $LayerRoot 'scripts/uninstall.ps1'
$newApprovalScript = Join-Path $LayerRoot 'scripts/new-approval.ps1'

try {
  # --------------------------------------------------------------------------
  # Test 1: Summary mode install without -ApprovedPlanSha256
  # --------------------------------------------------------------------------
  $planDir = Join-Path $testRoot 'plans'
  New-Item -ItemType Directory -Path $planDir -Force | Out-Null
  $planPath = Join-Path $planDir 'install-plan.md'
  $canonicalPlanPath = Join-Path $planDir 'install-plan.json'

  $previewResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Profile', 'standard',
    '-Harnesses', 'github-copilot',
    '-PlanPath', $planPath,
    '-CanonicalPlanPath', $canonicalPlanPath
  )
  Assert-Equal 0 $previewResult.exit_code "Preview failed: $($previewResult.output)"
  Assert-True ($previewResult.output -match 'Plan Approval Card') 'Console output should include Plan Approval Card'
  Assert-True ($previewResult.output -match 'APPROVE PLAN [a-f0-9]{32}') 'Console output should display APPROVE PLAN <id>'

  $mdContent = Get-Content -LiteralPath $planPath -Raw
  Assert-True ($mdContent -match '## Plan Approval Card') 'Markdown report should include Plan Approval Card'
  Assert-True ($mdContent -match 'APPROVE PLAN [a-f0-9]{32}') 'Markdown report should display APPROVE PLAN <id>'

  # Apply WITHOUT -ApprovedPlanSha256
  $applyResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Profile', 'standard',
    '-Harnesses', 'github-copilot',
    '-Apply',
    '-ApprovedPlanPath', $canonicalPlanPath,
    '-HumanApproved'
  )
  Assert-Equal 0 $applyResult.exit_code "Summary mode apply failed: $($applyResult.output)"

  $manifestPath = Join-Path $targetRoot '.agent/lizard-agent-layer.install.json'
  Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Install manifest must exist after apply.'
  $manifest = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $manifestPath -Raw)
  Assert-Equal 'summary' ([string]$manifest.plan_approval_mode) 'Manifest plan_approval_mode should be summary.'
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$manifest.applied_plan_sha256)) 'Manifest must record applied_plan_sha256.'
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$manifest.layer_root)) 'Manifest must record layer_root.'

  # --------------------------------------------------------------------------
  # Test 2: Tamper detection in summary mode
  # --------------------------------------------------------------------------
  $target2 = Join-Path $testRoot 'target2'
  New-Item -ItemType Directory -Path $target2 -Force | Out-Null
  $plan2Path = Join-Path $planDir 'plan2.md'
  $canonical2Path = Join-Path $planDir 'plan2.json'

  $preview2Result = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $target2,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-PlanPath', $plan2Path,
    '-CanonicalPlanPath', $canonical2Path
  )
  Assert-Equal 0 $preview2Result.exit_code "Preview 2 failed: $($preview2Result.output)"

  # Corrupt canonical plan JSON bytes
  $rawPlan2 = Get-Content -LiteralPath $canonical2Path -Raw
  $corruptedPlan2 = $rawPlan2 -replace 'minimal', 'standard'
  Set-Content -LiteralPath $canonical2Path -Value $corruptedPlan2 -Encoding UTF8

  $tamperedResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $target2,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-Apply',
    '-ApprovedPlanPath', $canonical2Path,
    '-HumanApproved'
  )
  Assert-False ($tamperedResult.exit_code -eq 0) 'Tampered plan must fail closed.'
  Assert-True ($tamperedResult.output -match 'PLAN_BINDING_DIGEST_MISMATCH|PLAN_BINDING_NONCANONICAL|PLAN_BINDING_OPTIONS_MISMATCH') "Tampered plan should fail with digest or binding error: $($tamperedResult.output)"

  # --------------------------------------------------------------------------
  # Test 3: Opt-in digest mode requires -ApprovedPlanSha256
  # --------------------------------------------------------------------------
  $target3 = Join-Path $testRoot 'target3'
  New-Item -ItemType Directory -Path $target3 -Force | Out-Null
  $plan3Path = Join-Path $planDir 'plan3.md'
  $canonical3Path = Join-Path $planDir 'plan3.json'

  $preview3Result = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $target3,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-PlanApprovalMode', 'digest',
    '-PlanPath', $plan3Path,
    '-CanonicalPlanPath', $canonical3Path
  )
  Assert-Equal 0 $preview3Result.exit_code "Preview 3 failed: $($preview3Result.output)"

  # Apply in digest mode without sha256 should fail
  $digestMissingResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $target3,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-PlanApprovalMode', 'digest',
    '-Apply',
    '-ApprovedPlanPath', $canonical3Path,
    '-HumanApproved'
  )
  Assert-False ($digestMissingResult.exit_code -eq 0) 'Digest mode without sha256 must fail closed.'
  Assert-True ($digestMissingResult.output -match 'PLAN_APPROVAL_REQUIRED') 'Expected PLAN_APPROVAL_REQUIRED error.'

  # Apply with correct sha256 should succeed
  $plan3Sha = (Get-FileHash -LiteralPath $canonical3Path -Algorithm SHA256).Hash.ToLowerInvariant()
  $digestApplyResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $target3,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-PlanApprovalMode', 'digest',
    '-Apply',
    '-ApprovedPlanPath', $canonical3Path,
    '-ApprovedPlanSha256', $plan3Sha,
    '-HumanApproved'
  )
  Assert-Equal 0 $digestApplyResult.exit_code "Digest mode apply failed: $($digestApplyResult.output)"

  # --------------------------------------------------------------------------
  # Test 4: scripts/new-approval.ps1 generates signed materials for complete uninstall
  # --------------------------------------------------------------------------
  $unPlanPath = Join-Path $planDir 'uninstall-plan.md'
  $unCanonicalPath = Join-Path $planDir 'uninstall-plan.json'
  $unReceiptPath = Join-Path $planDir 'uninstall-receipt.json'

  $unPreview = Invoke-TestPowerShell -ScriptPath $uninstallScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Scope', 'complete',
    '-ConfirmModifiedLayerOwnedPurge',
    '-PlanPath', $unPlanPath,
    '-CanonicalPlanPath', $unCanonicalPath,
    '-ReceiptPath', $unReceiptPath
  )
  Assert-Equal 0 $unPreview.exit_code "Uninstall preview failed: $($unPreview.output)"

  # Unapproved apply without signed materials must fail
  $unBlocked = Invoke-TestPowerShell -ScriptPath $uninstallScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Scope', 'complete',
    '-ConfirmModifiedLayerOwnedPurge',
    '-Apply',
    '-ApprovedPlanPath', $unCanonicalPath,
    '-HumanApproved'
  )
  Assert-False ($unBlocked.exit_code -eq 0) 'Complete uninstall without signed approval must fail closed.'
  Assert-True ($unBlocked.output -match 'PLAN_SIGNED_APPROVAL_REQUIRED') 'Expected PLAN_SIGNED_APPROVAL_REQUIRED error.'

  # Mint signed approval materials with new-approval.ps1
  $approvalOutDir = Join-Path $testRoot 'approval-kit'
  $unSha = (Get-FileHash -LiteralPath $unCanonicalPath -Algorithm SHA256).Hash.ToLowerInvariant()

  $mintResult = Invoke-TestPowerShell -ScriptPath $newApprovalScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-ApprovedPlanPath', $unCanonicalPath,
    '-ApprovedPlanSha256', $unSha,
    '-OutputDir', $approvalOutDir
  )
  Assert-Equal 0 $mintResult.exit_code "new-approval.ps1 failed: $($mintResult.output)"

  $envPath = Join-Path $approvalOutDir 'approval-envelope.json'
  $tsPath = Join-Path $approvalOutDir 'trust-store.json'
  $chPath = Join-Path $approvalOutDir 'challenge.json'
  $rpPath = Join-Path $approvalOutDir 'replay-ledger.jsonl'
  $pkPath = Join-Path $approvalOutDir 'private-key.jwk.json'

  Assert-True (Test-Path -LiteralPath $envPath -PathType Leaf) 'Envelope file must exist.'
  Assert-True (Test-Path -LiteralPath $tsPath -PathType Leaf) 'Trust store file must exist.'
  Assert-True (Test-Path -LiteralPath $chPath -PathType Leaf) 'Challenge file must exist.'
  Assert-True (Test-Path -LiteralPath $rpPath -PathType Leaf) 'Replay ledger must exist.'
  Assert-True (Test-Path -LiteralPath $pkPath -PathType Leaf) 'Private key must exist.'

  $tsSha = (Get-FileHash -LiteralPath $tsPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $chSha = (Get-FileHash -LiteralPath $chPath -Algorithm SHA256).Hash.ToLowerInvariant()

  # Apply with minted materials
  $unApply = Invoke-TestPowerShell -ScriptPath $uninstallScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Scope', 'complete',
    '-ConfirmModifiedLayerOwnedPurge',
    '-Apply',
    '-ApprovedPlanPath', $unCanonicalPath,
    '-ApprovedPlanSha256', $unSha,
    '-ApprovalEnvelopePath', $envPath,
    '-TrustStorePath', $tsPath,
    '-TrustStoreSha256', $tsSha,
    '-ChallengePath', $chPath,
    '-ChallengeSha256', $chSha,
    '-ReplayLedgerPath', $rpPath,
    '-HumanApproved'
  )
  Assert-Equal 0 $unApply.exit_code "Signed complete uninstall failed: $($unApply.output)"
  Assert-False (Test-Path -LiteralPath (Join-Path $targetRoot '.agent')) 'Target .agent directory should be completely removed.'

  Write-Host "PASS tests\integration\human-plan-approval.tests.ps1"
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
