param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.Transaction.psm1') -Force

$fixtureRoot = Join-Path $RepoRoot '.tmp\tests\transactions'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

function Get-TargetSnapshot {
  param([string]$Path)
  $entries = New-Object System.Collections.Generic.List[string]
  Get-ChildItem -LiteralPath $Path -Recurse -Force | Where-Object {
    $_.FullName -notmatch '[\\/]\.lizard-agent-layer-transactions([\\/]|$)' -and $_.Name -ne '.lizard-agent-layer.lock'
  } | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($Path.Length).TrimStart('\', '/').Replace('\', '/')
    if ($_.PSIsContainer) { $entries.Add("D:$relative") | Out-Null }
    else { $entries.Add("F:${relative}:$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant())") | Out-Null }
  }
  return (@($entries.ToArray()) -join "`n")
}

function Assert-NoTransactionMetadata {
  param([string]$Target)
  Assert-False (Test-Path -LiteralPath (Join-Path $Target '.lizard-agent-layer.lock')) 'Transaction lock must be removed.'
  Assert-False (Test-Path -LiteralPath (Join-Path $Target '.lizard-agent-layer-transactions')) 'Transaction store must be removed when empty.'
}

$installScript = Join-Path $RepoRoot 'scripts\install.ps1'
$updateScript = Join-Path $RepoRoot 'scripts\update-target.ps1'
$recoverScript = Join-Path $RepoRoot 'scripts\transaction-recover.ps1'
$loopInitScript = Join-Path $RepoRoot 'scripts\loop-init.ps1'
$loopSyncScript = Join-Path $RepoRoot 'scripts\loop-sync.ps1'

try {
  $failedTarget = Join-Path $fixtureRoot 'failed-install'
  New-Item -ItemType Directory -Path $failedTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $failedTarget 'sentinel.txt') -Value 'preserve-me'
  $beforeFailure = Get-TargetSnapshot $failedTarget
  $failedInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $failedTarget, '-Profile', 'minimal', '-Apply', '-TestFailAfterMutation', '4')
  Assert-False ($failedInstall.exit_code -eq 0) 'Fault-injected install must fail.'
  Assert-True ($failedInstall.output -match 'TRANSACTION_FAULT_INJECTED') 'Fault injection must expose a stable error code.'
  Assert-Equal $beforeFailure (Get-TargetSnapshot $failedTarget) 'Failed install must restore the exact target tree.'
  Assert-NoTransactionMetadata $failedTarget

  $successTarget = Join-Path $fixtureRoot 'successful-install'
  New-Item -ItemType Directory -Path $successTarget -Force | Out-Null
  $successfulInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $successTarget, '-Profile', 'minimal', '-Apply')
  Assert-Equal 0 $successfulInstall.exit_code "Successful transaction install failed: $($successfulInstall.output)"
  $manifest = Get-Content -LiteralPath (Join-Path $successTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$manifest.transaction_operation_id)) 'Install manifest must bind to its transaction operation ID.'
  Assert-NoTransactionMetadata $successTarget

  $beforeUpdate = Get-TargetSnapshot $successTarget
  $failedUpdate = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments @('-TargetPath', $successTarget, '-Profile', 'minimal', '-Apply', '-ForceManaged', '-TestFailAfterMutation', '3', '-OutputDir', (Join-Path $fixtureRoot 'failed-update-report'))
  Assert-False ($failedUpdate.exit_code -eq 0) 'Fault-injected update must fail.'
  Assert-Equal $beforeUpdate (Get-TargetSnapshot $successTarget) 'Failed update must roll back install and history as one unit.'
  Assert-NoTransactionMetadata $successTarget

  $beforeLoopInit = Get-TargetSnapshot $successTarget
  $failedLoopInit = Invoke-TestPowerShell -ScriptPath $loopInitScript -Arguments @('-TargetPath', $successTarget, '-Pattern', 'daily-triage', '-OutputDir', (Join-Path $fixtureRoot 'failed-loop-init-report'), '-Apply', '-TestFailAfterMutation', '3')
  Assert-False ($failedLoopInit.exit_code -eq 0) 'Fault-injected loop init must fail.'
  Assert-Equal $beforeLoopInit (Get-TargetSnapshot $successTarget) 'Failed loop init must restore the exact target tree.'
  Assert-NoTransactionMetadata $successTarget

  $successfulLoopInit = Invoke-TestPowerShell -ScriptPath $loopInitScript -Arguments @('-TargetPath', $successTarget, '-Pattern', 'daily-triage', '-OutputDir', (Join-Path $fixtureRoot 'successful-loop-init-report'), '-Apply')
  Assert-Equal 0 $successfulLoopInit.exit_code "Successful loop init failed: $($successfulLoopInit.output)"
  Assert-NoTransactionMetadata $successTarget
  $beforeLoopSync = Get-TargetSnapshot $successTarget
  $failedLoopSync = Invoke-TestPowerShell -ScriptPath $loopSyncScript -Arguments @('-TargetPath', $successTarget, '-OutputDir', (Join-Path $fixtureRoot 'failed-loop-sync-report'), '-Apply', '-ForceTemplates', '-TestFailAfterMutation', '2')
  Assert-False ($failedLoopSync.exit_code -eq 0) 'Fault-injected loop sync must fail.'
  Assert-Equal $beforeLoopSync (Get-TargetSnapshot $successTarget) 'Failed loop sync must restore templates and manifest.'
  Assert-NoTransactionMetadata $successTarget

  $lockedTarget = Join-Path $fixtureRoot 'locked-target'
  New-Item -ItemType Directory -Path $lockedTarget -Force | Out-Null
  $lockTransaction = Start-LizardTransaction -TargetRoot $lockedTarget -OperationName 'test-lock'
  $lockedInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $lockedTarget, '-Profile', 'minimal', '-Apply')
  Assert-False ($lockedInstall.exit_code -eq 0) 'Concurrent writer must be rejected.'
  Assert-True ($lockedInstall.output -match 'TRANSACTION_LOCK_HELD') 'Lock rejection must expose a stable error code.'
  Undo-LizardTransaction | Out-Null
  Assert-NoTransactionMetadata $lockedTarget

  $collisionTarget = Join-Path $fixtureRoot 'type-collision'
  New-Item -ItemType Directory -Path $collisionTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $collisionTarget '.agent') -Value 'not-a-directory'
  $beforeCollision = Get-TargetSnapshot $collisionTarget
  $collision = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $collisionTarget, '-Profile', 'minimal', '-Apply')
  Assert-False ($collision.exit_code -eq 0) 'Destination type collision must fail.'
  Assert-True ($collision.output -match 'DESTINATION_TYPE_CONFLICT') 'Preflight collision must expose a stable error code.'
  Assert-Equal $beforeCollision (Get-TargetSnapshot $collisionTarget) 'Preflight failure must not mutate the target.'
  Assert-NoTransactionMetadata $collisionTarget

  $crashTarget = Join-Path $fixtureRoot 'crash-target'
  New-Item -ItemType Directory -Path $crashTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $crashTarget 'existing.txt') -Value 'original'
  $beforeCrash = Get-TargetSnapshot $crashTarget
  $crashHelper = Join-Path $fixtureRoot 'simulate-crash.ps1'
  $modulePath = Join-Path $RepoRoot 'scripts\Lizard.Transaction.psm1'
  $helperContent = @"
param([string]`$Target)
Import-Module '$modulePath' -Force
Start-LizardTransaction -TargetRoot `$Target -OperationName 'simulated-crash' | Out-Null
Set-LizardTransactionalContent -Path (Join-Path `$Target 'existing.txt') -Value 'changed'
Set-LizardTransactionalContent -Path (Join-Path `$Target 'created.txt') -Value 'created'
"@
  Set-Content -LiteralPath $crashHelper -Value $helperContent
  $crash = Invoke-TestPowerShell -ScriptPath $crashHelper -Arguments @('-Target', $crashTarget)
  Assert-Equal 0 $crash.exit_code "Crash simulation setup failed: $($crash.output)"
  Assert-True (Test-Path -LiteralPath (Join-Path $crashTarget '.lizard-agent-layer.lock')) 'Simulated crash must leave a recoverable lock.'
  $previewRecovery = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $crashTarget, '-OutputDir', (Join-Path $fixtureRoot 'recovery-preview'), '-Json')
  Assert-Equal 0 $previewRecovery.exit_code "Recovery preview failed: $($previewRecovery.output)"
  Assert-True ($previewRecovery.output -match 'RECOVERY_AVAILABLE') 'Recovery preview must discover stale operation.'
  $applyRecovery = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $crashTarget, '-OutputDir', (Join-Path $fixtureRoot 'recovery-apply'), '-Apply', '-HumanApproved', '-Json')
  Assert-Equal 0 $applyRecovery.exit_code "Recovery apply failed: $($applyRecovery.output)"
  Assert-Equal $beforeCrash (Get-TargetSnapshot $crashTarget) 'Crash recovery must restore exact pre-operation content.'
  Assert-NoTransactionMetadata $crashTarget

  Write-Host 'PASS tests\integration\transaction.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
}
