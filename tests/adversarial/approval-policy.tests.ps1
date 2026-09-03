param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $LayerRoot 'scripts'))) {
    $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }
}
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Plan.psm1') -Force

# 1. Test low-risk minimal profile policy
$lowRisk = Get-LizardOperationApprovalPolicy -OperationKind 'install' -RiskLevel 'low' -Profile 'minimal'
Assert-False $lowRisk.signed_approval_required 'Low risk minimal install does not require signed approval'
Assert-Equal 'standard-exact-plan' $lowRisk.reason 'Standard exact plan reason expected'

# 2. Test explicit signed approval request
$explicit = Get-LizardOperationApprovalPolicy -OperationKind 'install' -RiskLevel 'low' -Profile 'minimal' -RequireSignedApproval
Assert-True $explicit.signed_approval_required 'Explicit RequireSignedApproval flag requires signed approval'
Assert-Equal 'explicit-requirement' $explicit.reason 'Explicit requirement reason expected'

# 3. Test high risk profile (summary mode default vs explicit signed mode)
$highRiskSummary = Get-LizardOperationApprovalPolicy -OperationKind 'install' -RiskLevel 'high' -Profile 'enterprise-fullstack' -ApprovalMode 'summary'
Assert-False $highRiskSummary.signed_approval_required 'High risk enterprise profile in summary mode does not require signed approval'
Assert-Equal 'standard-exact-plan' $highRiskSummary.reason 'Standard exact plan reason expected'

$highRiskSigned = Get-LizardOperationApprovalPolicy -OperationKind 'install' -RiskLevel 'high' -Profile 'enterprise-fullstack' -ApprovalMode 'signed'
Assert-True $highRiskSigned.signed_approval_required 'High risk enterprise profile in signed mode requires signed approval'
Assert-Equal 'explicit-requirement' $highRiskSigned.reason 'Explicit requirement reason expected'

# 4. Test complete uninstall scope
$uninstallComplete = Get-LizardOperationApprovalPolicy -OperationKind 'uninstall' -RiskLevel 'low' -Scope 'complete'
Assert-True $uninstallComplete.signed_approval_required 'Complete uninstall scope requires signed approval'
Assert-Equal 'complete-uninstall-scope' $uninstallComplete.reason 'Complete uninstall reason expected'

# 5. Test Force / ForceManaged overrides
$forceInstall = Get-LizardOperationApprovalPolicy -OperationKind 'install' -RiskLevel 'low' -Force
Assert-True $forceInstall.signed_approval_required 'Force override requires signed approval'
Assert-Equal 'force-override-mutation' $forceInstall.reason 'Force override reason expected'

# 6. Test destructive records purge
$recordsPurge = Get-LizardOperationApprovalPolicy -OperationKind 'records-lifecycle' -RiskLevel 'low' -Action 'purge'
Assert-True $recordsPurge.signed_approval_required 'Records purge requires signed approval'
Assert-Equal 'destructive-records-lifecycle' $recordsPurge.reason 'Destructive records reason expected'

Write-Host "PASS tests\adversarial\approval-policy.tests.ps1"
