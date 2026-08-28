param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Plan.psm1') -Force

$testRoot = Join-Path $LayerRoot ('.tmp/tests/skill-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $testRoot 'target'
$faultTarget = Join-Path $testRoot 'fault-target'
$plans = Join-Path $testRoot 'plans'
New-Item -ItemType Directory -Path $target, $faultTarget, $plans -Force | Out-Null
$script = Join-Path $LayerRoot 'scripts/skill-lifecycle.ps1'

function Invoke-Lifecycle {
  param([string]$SelectedTarget, [string]$Action, [string]$Skill = 'git-safety', [switch]$Apply, [string]$PlanPath, [string]$Sha256, [int]$FailAfterMutation = 0, [switch]$HumanApproved)
  $arguments = @('-LayerRoot', $LayerRoot, '-TargetRoot', $SelectedTarget, '-SkillName', $Skill, '-Action', $Action)
  if (-not [string]::IsNullOrWhiteSpace($PlanPath)) { $arguments += if ($Apply) { @('-ApprovedPlanPath', $PlanPath) } else { @('-CanonicalPlanPath', $PlanPath) } }
  if ($Apply) { $arguments += @('-Apply', '-ApprovedPlanSha256', $Sha256); if ($HumanApproved) { $arguments += '-HumanApproved' } }
  if ($FailAfterMutation -gt 0) { $arguments += @('-FailAfterMutation', [string]$FailAfterMutation) }
  return Invoke-TestPowerShell -ScriptPath $script -Arguments $arguments
}

function Invoke-ApprovedLifecycle {
  param([string]$SelectedTarget, [string]$Action, [string]$Skill = 'git-safety', [int]$FailAfterMutation = 0)
  $planPath = Join-Path $plans ("{0}-{1}-{2}.json" -f (Split-Path -Leaf $SelectedTarget), $Skill, $Action.ToLowerInvariant())
  $preview = Invoke-Lifecycle -SelectedTarget $SelectedTarget -Action $Action -Skill $Skill -PlanPath $planPath
  Assert-Equal 0 $preview.exit_code "$Action preview must succeed. $($preview.output)"
  $sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $applyResult = Invoke-Lifecycle -SelectedTarget $SelectedTarget -Action $Action -Skill $Skill -Apply -PlanPath $planPath -Sha256 $sha256 -HumanApproved -FailAfterMutation $FailAfterMutation
  return [pscustomobject]@{ preview = $preview; apply = $applyResult; plan_path = $planPath; sha256 = $sha256 }
}

try {
  $validate = Invoke-Lifecycle -SelectedTarget $target -Action Validate
  Assert-Equal 0 $validate.exit_code "Repository package validation must succeed. $($validate.output)"
  Assert-True ($validate.output -match 'git-safety') 'Validation must identify the checked package.'

  $installPlan = Join-Path $plans 'target-git-safety-install.json'
  $installPreview = Invoke-Lifecycle -SelectedTarget $target -Action Install -PlanPath $installPlan
  Assert-Equal 0 $installPreview.exit_code "Install preview must succeed. $($installPreview.output)"
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent')) 'Preview must not mutate the target.'
  $installSha = (Get-FileHash -LiteralPath $installPlan -Algorithm SHA256).Hash.ToLowerInvariant()
  $withoutApproval = Invoke-Lifecycle -SelectedTarget $target -Action Install -Apply -PlanPath $installPlan -Sha256 $installSha
  Assert-True ($withoutApproval.exit_code -ne 0 -and $withoutApproval.output -match 'SKILL_APPROVAL_REQUIRED') 'Apply must require explicit human approval.'
  $install = Invoke-Lifecycle -SelectedTarget $target -Action Install -Apply -PlanPath $installPlan -Sha256 $installSha -HumanApproved
  Assert-Equal 0 $install.exit_code "Approved install must succeed. $($install.output)"
  $packageRoot = Join-Path $target '.agent/skills/git-safety'
  $statePath = Join-Path $target '.agent/skill-lifecycle/git-safety.json'
  Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot 'SKILL.md') -PathType Leaf) 'Install must copy SKILL.md.'
  Assert-True (Test-Path -LiteralPath (Join-Path $packageRoot 'skill.json') -PathType Leaf) 'Install must copy version metadata.'
  $state = Get-SafeContent -AuthorizedRoot $target -Path $statePath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'active' ([string]$state.status) 'Install state must be active.'
  Assert-Equal 2 @($state.files).Count 'Install state must bind both package files.'
  Assert-Equal 0 @($state.directories).Count 'Empty directory inventory must remain an array.'

  $update = Invoke-ApprovedLifecycle -SelectedTarget $target -Action Update
  Assert-Equal 0 $update.apply.exit_code "Idempotent update must succeed. $($update.apply.output)"
  Assert-True ($update.apply.output -match 'mutations\s+:\s+0') 'Idempotent update must commit zero target mutations.'

  $installedInstructions = Join-Path $packageRoot 'SKILL.md'
  $originalInstructionBytes = Get-SafeBytes -AuthorizedRoot $target -Path $installedInstructions
  $originalInstructions = Get-SafeContent -AuthorizedRoot $target -Path $installedInstructions -Raw
  Set-SafeContent -AuthorizedRoot $target -Path $installedInstructions -Value ($originalInstructions + "`nuser change")
  $tamperPlan = Join-Path $plans 'tampered-update.json'
  $tampered = Invoke-Lifecycle -SelectedTarget $target -Action Update -PlanPath $tamperPlan
  Assert-True ($tampered.exit_code -ne 0 -and $tampered.output -match 'SKILL_PACKAGE_MODIFIED') 'Modified managed content must block update.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Tamper rejection must occur before transaction lock creation.'
  Set-SafeBytes -AuthorizedRoot $target -Path $installedInstructions -Bytes $originalInstructionBytes

  $legacyState = Get-SafeContent -AuthorizedRoot $target -Path $statePath -Raw | ConvertFrom-LizardJson
  $legacyState.version = '0.9.0'
  $legacyState.previous_version = $null
  $legacyJson = ConvertTo-LizardCanonicalJson $legacyState
  Set-SafeBytes -AuthorizedRoot $target -Path $statePath -Bytes ((New-Object System.Text.UTF8Encoding($false)).GetBytes($legacyJson))
  $migration = Invoke-ApprovedLifecycle -SelectedTarget $target -Action Migrate
  Assert-Equal 0 $migration.apply.exit_code "Declared migration must succeed. $($migration.apply.output)"
  $migratedState = Get-SafeContent -AuthorizedRoot $target -Path $statePath -Raw | ConvertFrom-LizardJson
  Assert-Equal '1.0.0' ([string]$migratedState.version) 'Migration must install the reviewed package version.'
  Assert-Equal '0.9.0' ([string]$migratedState.previous_version) 'Migration must retain the source version.'

  $disable = Invoke-ApprovedLifecycle -SelectedTarget $target -Action Disable
  Assert-Equal 0 $disable.apply.exit_code "Disable must succeed. $($disable.apply.output)"
  Assert-False (Test-Path -LiteralPath $packageRoot) 'Disable must remove unchanged managed package content.'
  $disabledState = Get-SafeContent -AuthorizedRoot $target -Path $statePath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'disabled' ([string]$disabledState.status) 'Disable must retain a recoverable tombstone.'
  Assert-Equal 2 @($disabledState.files).Count 'Disable must retain exact recovery hashes.'

  $recover = Invoke-ApprovedLifecycle -SelectedTarget $target -Action Recover
  Assert-Equal 0 $recover.apply.exit_code "Recovery must succeed. $($recover.apply.output)"
  Assert-True (Test-Path -LiteralPath $packageRoot -PathType Container) 'Recovery must recreate the exact reviewed package.'

  $remove = Invoke-ApprovedLifecycle -SelectedTarget $target -Action Remove
  Assert-Equal 0 $remove.apply.exit_code "Removal must succeed. $($remove.apply.output)"
  Assert-False (Test-Path -LiteralPath $packageRoot) 'Removal must leave no package directory.'
  $removedState = Get-SafeContent -AuthorizedRoot $target -Path $statePath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'removed' ([string]$removedState.status) 'Removal must retain an ownership tombstone.'
  Assert-Equal 0 @($removedState.files).Count 'Removal tombstone must not claim installed files.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Completed lifecycle must leave no transaction lock.'

  $missingDependencyPlan = Join-Path $plans 'minimal-fix-install.json'
  $missingDependency = Invoke-Lifecycle -SelectedTarget $faultTarget -Action Install -Skill minimal-fix -PlanPath $missingDependencyPlan
  Assert-True ($missingDependency.exit_code -ne 0 -and $missingDependency.output -match 'SKILL_DEPENDENCY_NOT_ACTIVE') 'Required inactive dependencies must fail closed before plan creation.'

  $faultPlan = Join-Path $plans 'fault-target-git-safety-install.json'
  $faultPreview = Invoke-Lifecycle -SelectedTarget $faultTarget -Action Install -PlanPath $faultPlan
  Assert-Equal 0 $faultPreview.exit_code "Fault fixture preview must succeed. $($faultPreview.output)"
  $faultSha = (Get-FileHash -LiteralPath $faultPlan -Algorithm SHA256).Hash.ToLowerInvariant()
  $faultApply = Invoke-Lifecycle -SelectedTarget $faultTarget -Action Install -Apply -PlanPath $faultPlan -Sha256 $faultSha -HumanApproved -FailAfterMutation 2
  Assert-True ($faultApply.exit_code -ne 0 -and $faultApply.output -match 'TRANSACTION_FAULT_INJECTED') 'Injected mutation failure must be observable.'
  Assert-False (Test-Path -LiteralPath (Join-Path $faultTarget '.agent/skills/git-safety')) 'Failed install must roll back package content.'
  Assert-False (Test-Path -LiteralPath (Join-Path $faultTarget '.lizard-agent-layer.lock')) 'Failed install rollback must clear the transaction lock.'

  Write-Host 'PASS tests\integration\skill-lifecycle.tests.ps1'
} finally {
  Clear-TestDirectory -Path $testRoot -AllowedRoot (Join-Path $LayerRoot '.tmp/tests')
}
