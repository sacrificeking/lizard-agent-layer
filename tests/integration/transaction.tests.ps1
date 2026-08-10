param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.Json.psm1') -Force
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
$doctorScript = Join-Path $RepoRoot 'scripts\doctor.ps1'
$modulePath = Join-Path $RepoRoot 'scripts\Lizard.Transaction.psm1'
$loopInitScript = Join-Path $RepoRoot 'scripts\loop-init.ps1'
$loopSyncScript = Join-Path $RepoRoot 'scripts\loop-sync.ps1'

try {
  $schemaTarget = Join-Path $fixtureRoot 'journal-schema'
  New-Item -ItemType Directory -Path $schemaTarget -Force | Out-Null
  $schemaTransaction = Start-LizardTransaction -TargetRoot $schemaTarget -OperationName 'schema-test'
  $schemaJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $schemaTransaction.journal_path -Raw)
  Assert-Equal 2 ([int]$schemaJournal.schema_version) 'New transactions must use the strict journal schema v2 contract.'
  Assert-JsonSchemaValid -LayerRoot $RepoRoot -SchemaPath 'schemas/transaction-journal.schema.json' -InstancePath $schemaTransaction.journal_path -Message 'A newly persisted transaction journal must satisfy the executable v2 schema.'
  Undo-LizardTransaction | Out-Null
  Assert-NoTransactionMetadata $schemaTarget

  $unknownFieldTarget = Join-Path $fixtureRoot 'unknown-journal-field'
  New-Item -ItemType Directory -Path $unknownFieldTarget -Force | Out-Null
  $unknownTransaction = Start-LizardTransaction -TargetRoot $unknownFieldTarget -OperationName 'unknown-field-test'
  $unknownJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $unknownTransaction.journal_path -Raw)
  $unknownJournal | Add-Member -NotePropertyName attacker_note -NotePropertyValue 'must-fail-closed'
  Set-Content -LiteralPath $unknownTransaction.journal_path -Value ($unknownJournal | ConvertTo-Json -Depth 12)
  $unknownPreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $unknownFieldTarget, '-OutputDir', (Join-Path $fixtureRoot 'unknown-preview'), '-Json')
  Assert-False ($unknownPreview.exit_code -eq 0) 'Unknown journal fields must fail closed.'
  Assert-True ($unknownPreview.output -match 'TRANSACTION_JOURNAL_INVALID') 'Unknown journal fields must expose a stable invalid-journal code.'

  $identityTarget = Join-Path $fixtureRoot 'identity-mismatch'
  New-Item -ItemType Directory -Path $identityTarget -Force | Out-Null
  $identityTransaction = Start-LizardTransaction -TargetRoot $identityTarget -OperationName 'identity-test'
  $identityJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $identityTransaction.journal_path -Raw)
  $identityJournal.operation_name = 'forged-operation'
  Set-Content -LiteralPath $identityTransaction.journal_path -Value ($identityJournal | ConvertTo-Json -Depth 12)
  $identityPreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $identityTarget, '-OutputDir', (Join-Path $fixtureRoot 'identity-preview'), '-Json')
  Assert-False ($identityPreview.exit_code -eq 0) 'A lock/journal identity mismatch must fail closed.'
  Assert-True ($identityPreview.output -match 'TRANSACTION_LOCK_JOURNAL_MISMATCH') 'Identity mismatch must expose a stable code.'

  $backupTraversalTarget = Join-Path $fixtureRoot 'backup-traversal'
  New-Item -ItemType Directory -Path $backupTraversalTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $backupTraversalTarget 'existing.txt') -Value 'original'
  $traversalTransaction = Start-LizardTransaction -TargetRoot $backupTraversalTarget -OperationName 'backup-traversal-test'
  Set-LizardTransactionalContent -Path (Join-Path $backupTraversalTarget 'existing.txt') -Value 'changed'
  $traversalJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $traversalTransaction.journal_path -Raw)
  $traversalJournal.mutations[0].backup_path = '../../outside-canary.txt'
  Set-Content -LiteralPath $traversalTransaction.journal_path -Value ($traversalJournal | ConvertTo-Json -Depth 12)
  $outsideCanary = Join-Path $fixtureRoot 'outside-canary.txt'
  Set-Content -LiteralPath $outsideCanary -Value 'do-not-read-or-write'
  $traversalPreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $backupTraversalTarget, '-OutputDir', (Join-Path $fixtureRoot 'traversal-preview'), '-Json')
  Assert-False ($traversalPreview.exit_code -eq 0) 'A traversing backup path must fail closed.'
  Assert-True ($traversalPreview.output -match 'TRANSACTION_BACKUP_PATH_INVALID') 'Backup traversal must expose a stable code.'
  Assert-True ((Get-Content -LiteralPath $outsideCanary -Raw) -match 'do-not-read-or-write') 'Backup traversal must not modify an outside canary.'

  $sequenceTarget = Join-Path $fixtureRoot 'invalid-sequence'
  New-Item -ItemType Directory -Path $sequenceTarget -Force | Out-Null
  $sequenceTransaction = Start-LizardTransaction -TargetRoot $sequenceTarget -OperationName 'invalid-sequence-test'
  Set-LizardTransactionalContent -Path (Join-Path $sequenceTarget 'created.txt') -Value 'created'
  $sequenceJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $sequenceTransaction.journal_path -Raw)
  $sequenceJournal.mutations[0].sequence = 2
  Set-Content -LiteralPath $sequenceTransaction.journal_path -Value ($sequenceJournal | ConvertTo-Json -Depth 12)
  $sequencePreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $sequenceTarget, '-OutputDir', (Join-Path $fixtureRoot 'sequence-preview'), '-Json')
  Assert-False ($sequencePreview.exit_code -eq 0) 'A non-contiguous mutation sequence must fail closed.'
  Assert-True ($sequencePreview.output -match 'TRANSACTION_SEQUENCE_INVALID') 'Invalid mutation order must expose a stable code.'

  $coercedTypeTarget = Join-Path $fixtureRoot 'coerced-numeric-type'
  New-Item -ItemType Directory -Path $coercedTypeTarget -Force | Out-Null
  $coercedTypeTransaction = Start-LizardTransaction -TargetRoot $coercedTypeTarget -OperationName 'coerced-type-test'
  $coercedTypeJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $coercedTypeTransaction.journal_path -Raw)
  $coercedTypeJournal.next_sequence = '1'
  Set-Content -LiteralPath $coercedTypeTransaction.journal_path -Value ($coercedTypeJournal | ConvertTo-Json -Depth 12)
  $coercedTypePreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $coercedTypeTarget, '-OutputDir', (Join-Path $fixtureRoot 'coerced-type-preview'), '-Json')
  Assert-False ($coercedTypePreview.exit_code -eq 0) 'Runtime validation must not coerce JSON strings into integer fields.'
  Assert-True ($coercedTypePreview.output -match 'TRANSACTION_JOURNAL_INVALID') 'Wrong JSON numeric types must expose a stable invalid-journal code.'

  $legacyTarget = Join-Path $fixtureRoot 'legacy-v1-journal'
  New-Item -ItemType Directory -Path $legacyTarget -Force | Out-Null
  $legacyTransaction = Start-LizardTransaction -TargetRoot $legacyTarget -OperationName 'legacy-v1-test'
  $legacyLockPath = Join-Path $legacyTarget '.lizard-agent-layer.lock'
  $legacyLock = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $legacyLockPath -Raw)
  $legacyJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $legacyTransaction.journal_path -Raw)
  $legacyLock.schema_version = 1
  $legacyJournal.schema_version = 1
  Set-Content -LiteralPath $legacyLockPath -Value ($legacyLock | ConvertTo-Json -Depth 12)
  Set-Content -LiteralPath $legacyTransaction.journal_path -Value ($legacyJournal | ConvertTo-Json -Depth 12)
  $legacyPreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $legacyTarget, '-OutputDir', (Join-Path $fixtureRoot 'legacy-preview'), '-Json')
  Assert-False ($legacyPreview.exit_code -eq 0) 'Retained journal v1 evidence must fail closed rather than be guessed or rewritten.'
  Assert-True ($legacyPreview.output -match 'TRANSACTION_LOCK_SCHEMA_UNSUPPORTED') 'Legacy v1 rejection must expose a stable unsupported-schema code.'

  $hashMismatchTarget = Join-Path $fixtureRoot 'backup-hash-mismatch'
  New-Item -ItemType Directory -Path $hashMismatchTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $hashMismatchTarget 'existing.txt') -Value 'original'
  $hashMismatchTransaction = Start-LizardTransaction -TargetRoot $hashMismatchTarget -OperationName 'backup-hash-test'
  Set-LizardTransactionalContent -Path (Join-Path $hashMismatchTarget 'existing.txt') -Value 'changed'
  Set-Content -LiteralPath (Join-Path $hashMismatchTransaction.backup_dir '000001.bin') -Value 'tampered-backup'
  $hashMismatchPreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $hashMismatchTarget, '-OutputDir', (Join-Path $fixtureRoot 'hash-mismatch-preview'), '-Json')
  Assert-False ($hashMismatchPreview.exit_code -eq 0) 'Preview must fail closed when a required backup hash mismatches.'
  Assert-True ($hashMismatchPreview.output -match 'TRANSACTION_BACKUP_HASH_MISMATCH') 'Backup hash mismatch must expose a stable code during preview.'

  $missingBackupTarget = Join-Path $fixtureRoot 'missing-backup'
  New-Item -ItemType Directory -Path $missingBackupTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $missingBackupTarget 'existing.txt') -Value 'original'
  $missingBackupTransaction = Start-LizardTransaction -TargetRoot $missingBackupTarget -OperationName 'missing-backup-test'
  Set-LizardTransactionalContent -Path (Join-Path $missingBackupTarget 'existing.txt') -Value 'changed'
  Remove-Item -LiteralPath (Join-Path $missingBackupTransaction.backup_dir '000001.bin') -Force
  $missingBackupRecovery = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $missingBackupTarget, '-OutputDir', (Join-Path $fixtureRoot 'missing-backup-recovery'), '-Apply', '-HumanApproved', '-Force', '-Json')
  Assert-False ($missingBackupRecovery.exit_code -eq 0) 'Recovery must stop when the next required backup is missing.'
  Assert-True ($missingBackupRecovery.output -match 'TRANSACTION_BACKUP_MISSING') 'Missing backup failure must expose a stable code.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $missingBackupTarget 'existing.txt') -Raw) -match '^changed') 'Failed recovery must not continue or invent original content.'
  Assert-True (Test-Path -LiteralPath (Join-Path $missingBackupTarget '.lizard-agent-layer.lock')) 'Failed recovery must retain transaction evidence.'

  $failedTarget = Join-Path $fixtureRoot 'failed-install'
  New-Item -ItemType Directory -Path $failedTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $failedTarget 'sentinel.txt') -Value 'preserve-me'
  $beforeFailure = Get-TargetSnapshot $failedTarget
  $failedApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $failedTarget, '-Profile', 'minimal', '-TestFailAfterMutation', '4')
  $failedInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $failedApproval.arguments
  Assert-False ($failedInstall.exit_code -eq 0) 'Fault-injected install must fail.'
  Assert-True ($failedInstall.output -match 'TRANSACTION_FAULT_INJECTED') 'Fault injection must expose a stable error code.'
  Assert-Equal $beforeFailure (Get-TargetSnapshot $failedTarget) 'Failed install must restore the exact target tree.'
  Assert-NoTransactionMetadata $failedTarget

  $successTarget = Join-Path $fixtureRoot 'successful-install'
  New-Item -ItemType Directory -Path $successTarget -Force | Out-Null
  $successApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $successTarget, '-Profile', 'minimal')
  $successfulInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $successApproval.arguments
  Assert-Equal 0 $successfulInstall.exit_code "Successful transaction install failed: $($successfulInstall.output)"
  $manifest = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath (Join-Path $successTarget '.agent\lizard-agent-layer.install.json') -Raw)
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$manifest.transaction_operation_id)) 'Install manifest must bind to its transaction operation ID.'
  Assert-NoTransactionMetadata $successTarget

  $beforeUpdate = Get-TargetSnapshot $successTarget
  $failedUpdateApproval = New-TestUpdateApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $successTarget, '-Profile', 'minimal', '-ForceManaged', '-TestFailAfterMutation', '3', '-OutputDir', (Join-Path $fixtureRoot 'failed-update-report'))
  $failedUpdate = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments $failedUpdateApproval.arguments
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
  $lockedApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $lockedTarget, '-Profile', 'minimal')
  $lockTransaction = Start-LizardTransaction -TargetRoot $lockedTarget -OperationName 'test-lock'
  $lockedInstall = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $lockedApproval.arguments
  Assert-False ($lockedInstall.exit_code -eq 0) 'Concurrent writer must be rejected.'
  Assert-True ($lockedInstall.output -match 'TRANSACTION_LOCK_HELD') 'Lock rejection must expose a stable error code.'
  Undo-LizardTransaction | Out-Null
  Assert-NoTransactionMetadata $lockedTarget

  $collisionTarget = Join-Path $fixtureRoot 'type-collision'
  New-Item -ItemType Directory -Path $collisionTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $collisionTarget '.agent') -Value 'not-a-directory'
  $beforeCollision = Get-TargetSnapshot $collisionTarget
  $collision = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $collisionTarget, '-Profile', 'minimal')
  Assert-False ($collision.exit_code -eq 0) 'Destination type collision must fail.'
  Assert-True ($collision.output -match 'DESTINATION_TYPE_CONFLICT') 'Preflight collision must expose a stable error code.'
  Assert-Equal $beforeCollision (Get-TargetSnapshot $collisionTarget) 'Preflight failure must not mutate the target.'
  Assert-NoTransactionMetadata $collisionTarget

  $crashTarget = Join-Path $fixtureRoot 'crash-target'
  New-Item -ItemType Directory -Path $crashTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $crashTarget 'existing.txt') -Value 'original'
  $beforeCrash = Get-TargetSnapshot $crashTarget
  $crashHelper = Join-Path $fixtureRoot 'simulate-crash.ps1'
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

  $repeatTarget = Join-Path $fixtureRoot 'repeated-path-crash'
  New-Item -ItemType Directory -Path $repeatTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $repeatTarget 'same.txt') -Value 'original'
  $repeatHelper = Join-Path $fixtureRoot 'simulate-repeated-path-crash.ps1'
  $repeatHelperContent = @"
param([string]`$Target)
Import-Module '$modulePath' -Force
Start-LizardTransaction -TargetRoot `$Target -OperationName 'repeated-path-crash' | Out-Null
Set-LizardTransactionalContent -Path (Join-Path `$Target 'same.txt') -Value 'middle'
Set-LizardTransactionalContent -Path (Join-Path `$Target 'same.txt') -Value 'latest'
"@
  Set-Content -LiteralPath $repeatHelper -Value $repeatHelperContent
  $repeatCrash = Invoke-TestPowerShell -ScriptPath $repeatHelper -Arguments @('-Target', $repeatTarget)
  Assert-Equal 0 $repeatCrash.exit_code "Repeated-path crash setup failed: $($repeatCrash.output)"
  $firstRepeatRecovery = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $repeatTarget, '-OutputDir', (Join-Path $fixtureRoot 'repeat-recovery-first'), '-Apply', '-HumanApproved', '-TestFailAfterRollback', '1', '-Json')
  Assert-False ($firstRepeatRecovery.exit_code -eq 0) 'Injected recovery interruption must fail after persisting one rollback step.'
  Assert-True ($firstRepeatRecovery.output -match 'TRANSACTION_RECOVERY_FAULT_INJECTED') 'Recovery interruption must expose a stable code.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $repeatTarget 'same.txt') -Raw) -match '^middle') 'First recovery pass must restore only the latest mutation.'
  $repeatLock = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath (Join-Path $repeatTarget '.lizard-agent-layer.lock') -Raw)
  $repeatJournalPath = Join-Path $repeatTarget ([string]$repeatLock.journal_path).Replace('/', '\')
  $repeatJournal = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $repeatJournalPath -Raw)
  Assert-Equal '1,2' ((@($repeatJournal.mutations | ForEach-Object { [string]$_.sequence })) -join ',') 'Recovery must preserve chronological journal order.'
  Assert-Equal 'applied,rolled-back' ((@($repeatJournal.mutations | ForEach-Object { [string]$_.status })) -join ',') 'Recovery must persist a rolled-back highest-sequence suffix.'
  $recoveryDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $repeatTarget)
  Assert-False ($recoveryDoctor.exit_code -eq 0) 'Doctor must decisively fail a recovery-required target.'
  Assert-True ($recoveryDoctor.output -match 'TRANSACTION_RECOVERY_REQUIRED') 'Doctor must classify a recovery-required journal.'
  $secondRepeatRecovery = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $repeatTarget, '-OutputDir', (Join-Path $fixtureRoot 'repeat-recovery-second'), '-Apply', '-HumanApproved', '-Json')
  Assert-Equal 0 $secondRepeatRecovery.exit_code "Retry-safe repeated-path recovery failed: $($secondRepeatRecovery.output)"
  Assert-True ((Get-Content -LiteralPath (Join-Path $repeatTarget 'same.txt') -Raw) -match '^original') 'Recovery retry must skip completed suffix entries and restore the exact original value.'
  Assert-NoTransactionMetadata $repeatTarget
  $thirdRepeatRecovery = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $repeatTarget, '-OutputDir', (Join-Path $fixtureRoot 'repeat-recovery-third'), '-Json')
  Assert-Equal 0 $thirdRepeatRecovery.exit_code 'Recovery after successful cleanup must be a clean no-op.'
  Assert-True ($thirdRepeatRecovery.output -match 'CLEAN') 'Clean recovery preview must report CLEAN.'

  $committedTarget = Join-Path $fixtureRoot 'committed-cleanup'
  New-Item -ItemType Directory -Path $committedTarget -Force | Out-Null
  $commitHelper = Join-Path $fixtureRoot 'simulate-committed-cleanup.ps1'
  $commitHelperContent = @"
param([string]`$Target)
Import-Module '$modulePath' -Force
Start-LizardTransaction -TargetRoot `$Target -OperationName 'committed-cleanup-crash' | Out-Null
Set-LizardTransactionalContent -Path (Join-Path `$Target 'committed.txt') -Value 'keep-committed'
Complete-LizardTransaction -TestFailBeforeCleanup | Out-Null
"@
  Set-Content -LiteralPath $commitHelper -Value $commitHelperContent
  $commitCrash = Invoke-TestPowerShell -ScriptPath $commitHelper -Arguments @('-Target', $committedTarget)
  Assert-False ($commitCrash.exit_code -eq 0) 'Commit cleanup fault injection must retain terminal metadata.'
  Assert-True ($commitCrash.output -match 'TRANSACTION_COMMIT_CLEANUP_FAULT_INJECTED') 'Commit cleanup interruption must expose a stable code.'
  $commitPreview = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $committedTarget, '-OutputDir', (Join-Path $fixtureRoot 'commit-cleanup-preview'), '-Json')
  Assert-Equal 0 $commitPreview.exit_code "Committed cleanup preview failed: $($commitPreview.output)"
  Assert-True ($commitPreview.output -match 'COMMITTED_CLEANUP_AVAILABLE') 'Committed metadata must be classified as cleanup, never rollback.'
  $commitDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $committedTarget)
  Assert-False ($commitDoctor.exit_code -eq 0) 'Doctor must decisively fail terminal metadata awaiting cleanup.'
  Assert-True ($commitDoctor.output -match 'TRANSACTION_CLEANUP_REQUIRED') 'Doctor must classify committed cleanup residue.'
  $commitCleanup = Invoke-TestPowerShell -ScriptPath $recoverScript -Arguments @('-TargetPath', $committedTarget, '-OutputDir', (Join-Path $fixtureRoot 'commit-cleanup-apply'), '-Apply', '-HumanApproved', '-Json')
  Assert-Equal 0 $commitCleanup.exit_code "Committed metadata cleanup failed: $($commitCleanup.output)"
  Assert-True ((Get-Content -LiteralPath (Join-Path $committedTarget 'committed.txt') -Raw) -match '^keep-committed') 'Committed cleanup must not roll back committed target content.'
  Assert-NoTransactionMetadata $committedTarget

  Write-Host 'PASS tests\integration\transaction.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
}
