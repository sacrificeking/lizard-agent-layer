Set-StrictMode -Version 2.0

$script:TransactionContext = $null

Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')

function New-LizardTransactionException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['transaction_code'] = $Code
  return $exception
}

function Get-LizardTransactionSha256 {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) { $Value = '' }
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-LizardTransactionRootIdentity {
  param([Parameter(Mandatory = $true)][string]$TargetRoot)
  $root = ConvertTo-LizardFullPath -Path $TargetRoot
  if ((Get-LizardPathComparison) -eq [System.StringComparison]::OrdinalIgnoreCase) { $root = $root.ToLowerInvariant() }
  $normalized = $root.Replace('\', '/')
  return Get-LizardTransactionSha256 -Value ("target-root-v1|{0}" -f $normalized)
}

function Assert-LizardTransactionProperties {
  param($Document, [string[]]$Required, [string[]]$Allowed, [string]$Label)
  if ($null -eq $Document) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message "$Label is null.") }
  $names = @($Document.PSObject.Properties.Name)
  foreach ($name in $Required) {
    if ($names -notcontains $name) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message "$Label is missing '$name'.") }
  }
  foreach ($name in $names) {
    if ($Allowed -notcontains $name) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message "$Label contains unsupported property '$name'.") }
  }
}

function Test-LizardTransactionRelativePath {
  param([AllowNull()][string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 1000 -or [System.IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:') { return $false }
  if ($Path -match '[\\:\x00-\x1f]') { return $false }
  $normalized = $Path
  if ($normalized.StartsWith('/') -or $normalized.EndsWith('/')) { return $false }
  foreach ($segment in @($normalized.Split('/'))) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..')) { return $false }
  }
  if ($normalized -eq '.lizard-agent-layer.lock' -or $normalized.StartsWith('.lizard-agent-layer-transactions/', [System.StringComparison]::OrdinalIgnoreCase) -or $normalized -eq '.lizard-agent-layer-transactions') { return $false }
  return $true
}

function Test-LizardTransactionTimestamp {
  param([AllowNull()][string]$Value)
  $parsed = [DateTimeOffset]::MinValue
  return (-not [string]::IsNullOrWhiteSpace($Value) -and [DateTimeOffset]::TryParseExact($Value, 'o', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed))
}

function Test-LizardTransactionInteger {
  param($Value)
  return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64])
}

function Assert-LizardTransactionLockDocument {
  param($Lock, [string]$ExpectedTargetRoot)
  $required = @('schema_version', 'operation_id', 'operation_name', 'target_root', 'target_root_hash', 'owner_pid', 'started_at', 'journal_path')
  Assert-LizardTransactionProperties -Document $Lock -Required $required -Allowed $required -Label 'Transaction lock'
  if (-not (Test-LizardTransactionInteger $Lock.schema_version) -or [int64]$Lock.schema_version -ne 2) { throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_SCHEMA_UNSUPPORTED' -Message "Expected integer lock schema 2, got $($Lock.schema_version).") }
  if ($Lock.operation_id -isnot [string] -or [string]$Lock.operation_id -notmatch '^[a-f0-9]{32}$') { throw (New-LizardTransactionException -Code 'TRANSACTION_ID_INVALID' -Message 'Lock operation ID is invalid.') }
  if ($Lock.target_root -isnot [string] -or $Lock.target_root_hash -isnot [string] -or $Lock.started_at -isnot [string] -or $Lock.journal_path -isnot [string]) { throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_INVALID' -Message 'Lock path, identity, and timestamp fields must be JSON strings.') }
  $root = ConvertTo-LizardFullPath -Path $ExpectedTargetRoot
  if (-not (ConvertTo-LizardFullPath -Path ([string]$Lock.target_root)).Equals($root, (Get-LizardPathComparison))) { throw (New-LizardTransactionException -Code 'TRANSACTION_TARGET_MISMATCH' -Message 'Lock target root does not match the selected target.') }
  $expectedRootHash = Get-LizardTransactionRootIdentity -TargetRoot $root
  if ([string]$Lock.target_root_hash -ne $expectedRootHash) { throw (New-LizardTransactionException -Code 'TRANSACTION_TARGET_IDENTITY_MISMATCH' -Message 'Lock target-root identity is invalid.') }
  $expectedJournal = ".lizard-agent-layer-transactions/$($Lock.operation_id)/journal.json"
  if ([string]$Lock.journal_path -ne $expectedJournal) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_PATH_INVALID' -Message 'Lock journal path is not canonical.') }
  if (-not (Test-LizardTransactionInteger $Lock.owner_pid) -or [int64]$Lock.owner_pid -lt 1 -or $Lock.operation_name -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Lock.operation_name)) { throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_INVALID' -Message 'Lock owner or operation name is invalid.') }
  if ([string]$Lock.operation_name -notmatch '^[^\x00-\x1f]{1,200}$' -or -not (Test-LizardTransactionTimestamp -Value ([string]$Lock.started_at))) { throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_INVALID' -Message 'Lock operation name or timestamp is invalid.') }
}

function Assert-LizardTransactionJournalDocument {
  param($Journal, [string]$ExpectedTargetRoot, [string]$ExpectedOperationId)
  $required = @('schema_version', 'operation_id', 'operation_name', 'target_root', 'target_root_hash', 'owner_pid', 'state', 'started_at', 'updated_at', 'fail_after_mutation', 'next_sequence', 'mutations')
  $allowed = @($required + 'committed_at')
  Assert-LizardTransactionProperties -Document $Journal -Required $required -Allowed $allowed -Label 'Transaction journal'
  if (-not (Test-LizardTransactionInteger $Journal.schema_version) -or [int64]$Journal.schema_version -ne 2) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_SCHEMA_UNSUPPORTED' -Message "Expected integer journal schema 2, got $($Journal.schema_version).") }
  if ($Journal.operation_id -isnot [string] -or [string]$Journal.operation_id -notmatch '^[a-f0-9]{32}$' -or [string]$Journal.operation_id -ne $ExpectedOperationId) { throw (New-LizardTransactionException -Code 'TRANSACTION_ID_MISMATCH' -Message 'Journal operation ID does not match the lock and transaction directory.') }
  if ($Journal.target_root -isnot [string] -or $Journal.target_root_hash -isnot [string]) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message 'Journal target and target identity must be JSON strings.') }
  $root = ConvertTo-LizardFullPath -Path $ExpectedTargetRoot
  if (-not (ConvertTo-LizardFullPath -Path ([string]$Journal.target_root)).Equals($root, (Get-LizardPathComparison))) { throw (New-LizardTransactionException -Code 'TRANSACTION_TARGET_MISMATCH' -Message 'Journal target root does not match the selected target.') }
  if ([string]$Journal.target_root_hash -ne (Get-LizardTransactionRootIdentity -TargetRoot $root)) { throw (New-LizardTransactionException -Code 'TRANSACTION_TARGET_IDENTITY_MISMATCH' -Message 'Journal target-root identity is invalid.') }
  if ($Journal.state -isnot [string] -or [string]$Journal.state -notin @('active', 'recovery-required', 'rolled-back', 'committed')) { throw (New-LizardTransactionException -Code 'TRANSACTION_STATE_INVALID' -Message "Journal state '$($Journal.state)' is invalid.") }
  if (-not (Test-LizardTransactionInteger $Journal.owner_pid) -or -not (Test-LizardTransactionInteger $Journal.fail_after_mutation) -or -not (Test-LizardTransactionInteger $Journal.next_sequence) -or [int64]$Journal.owner_pid -lt 1 -or [int64]$Journal.fail_after_mutation -lt 0 -or [int64]$Journal.next_sequence -lt 1) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message 'Journal owner, fault counter, or next sequence must be valid integers.') }
  if ([string]$Journal.operation_name -notmatch '^[^\x00-\x1f]{1,200}$' -or -not (Test-LizardTransactionTimestamp -Value ([string]$Journal.started_at)) -or -not (Test-LizardTransactionTimestamp -Value ([string]$Journal.updated_at))) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message 'Journal operation name or timestamps are invalid.') }
  if ($Journal.operation_name -isnot [string] -or $Journal.started_at -isnot [string] -or $Journal.updated_at -isnot [string] -or $Journal.mutations -isnot [System.Array]) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message 'Journal names, timestamps, and mutations must use their declared JSON types.') }

  $mutationRequired = @('sequence', 'path', 'kind', 'original_state', 'original_hash', 'backup_path', 'status')
  $seen = New-Object 'System.Collections.Generic.HashSet[int]'
  $previousSequence = 0
  $rolledBackSuffixStarted = $false
  foreach ($mutation in @($Journal.mutations)) {
    Assert-LizardTransactionProperties -Document $mutation -Required $mutationRequired -Allowed $mutationRequired -Label 'Transaction mutation'
    if (-not (Test-LizardTransactionInteger $mutation.sequence)) { throw (New-LizardTransactionException -Code 'TRANSACTION_SEQUENCE_INVALID' -Message 'Mutation sequences must be JSON integers.') }
    $sequence = [int64]$mutation.sequence
    if ($sequence -ne ($previousSequence + 1) -or -not $seen.Add($sequence)) { throw (New-LizardTransactionException -Code 'TRANSACTION_SEQUENCE_INVALID' -Message 'Mutation sequences must be contiguous, unique, and stored in ascending order.') }
    $previousSequence = $sequence
    if ($mutation.path -isnot [string] -or -not (Test-LizardTransactionRelativePath -Path ([string]$mutation.path))) { throw (New-LizardTransactionException -Code 'TRANSACTION_DESTINATION_PATH_INVALID' -Message "Mutation path '$($mutation.path)' is unsafe.") }
    if ($mutation.kind -isnot [string] -or $mutation.original_state -isnot [string] -or $mutation.status -isnot [string] -or [string]$mutation.kind -notin @('file', 'directory') -or [string]$mutation.original_state -notin @('missing', 'file', 'directory') -or [string]$mutation.status -notin @('pending', 'applied', 'rolled-back')) { throw (New-LizardTransactionException -Code 'TRANSACTION_MUTATION_INVALID' -Message "Mutation $sequence has an invalid kind, original state, or status.") }
    if ([string]$mutation.status -eq 'rolled-back') { $rolledBackSuffixStarted = $true }
    elseif ($rolledBackSuffixStarted) { throw (New-LizardTransactionException -Code 'TRANSACTION_ROLLBACK_ORDER_INVALID' -Message 'Rolled-back mutations must form a contiguous highest-sequence suffix.') }
    if ([string]$mutation.original_state -eq 'file') {
      if ([string]$mutation.kind -ne 'file') { throw (New-LizardTransactionException -Code 'TRANSACTION_MUTATION_INVALID' -Message "Mutation $sequence cannot restore a file through a directory mutation.") }
      $expectedBackup = 'backups/{0:D6}.bin' -f $sequence
      if ($mutation.backup_path -isnot [string] -or $mutation.original_hash -isnot [string]) { throw (New-LizardTransactionException -Code 'TRANSACTION_MUTATION_INVALID' -Message "Mutation $sequence backup fields must be JSON strings.") }
      if ([string]$mutation.backup_path -ne $expectedBackup) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_PATH_INVALID' -Message "Mutation $sequence backup path is not canonical.") }
      if ([string]$mutation.original_hash -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_HASH_INVALID' -Message "Mutation $sequence backup hash is invalid.") }
    } elseif ($null -ne $mutation.backup_path -or $null -ne $mutation.original_hash) {
      throw (New-LizardTransactionException -Code 'TRANSACTION_MUTATION_INVALID' -Message "Mutation $sequence must not declare a backup for original state '$($mutation.original_state)'.")
    }
    if ([string]$mutation.original_state -eq 'directory' -and [string]$mutation.kind -ne 'directory') { throw (New-LizardTransactionException -Code 'TRANSACTION_MUTATION_INVALID' -Message "Mutation $sequence cannot restore a directory through a file mutation.") }
  }
  if ([int]$Journal.next_sequence -ne ($previousSequence + 1)) { throw (New-LizardTransactionException -Code 'TRANSACTION_SEQUENCE_INVALID' -Message 'Journal next_sequence does not follow the stored mutation sequence.') }
  $pending = @($Journal.mutations | Where-Object { $_.status -eq 'pending' })
  if ($pending.Count -gt 1 -or ($pending.Count -eq 1 -and [int]$pending[0].sequence -ne $previousSequence)) { throw (New-LizardTransactionException -Code 'TRANSACTION_PENDING_ORDER_INVALID' -Message 'Only the highest-sequence mutation may be pending.') }
  if ([string]$Journal.state -eq 'committed' -and @($Journal.mutations | Where-Object { $_.status -ne 'applied' }).Count -gt 0) { throw (New-LizardTransactionException -Code 'TRANSACTION_STATE_INVALID' -Message 'Committed journal must contain only applied mutations.') }
  if ([string]$Journal.state -eq 'committed' -and (($Journal.PSObject.Properties.Name -notcontains 'committed_at') -or $Journal.committed_at -isnot [string] -or -not (Test-LizardTransactionTimestamp -Value ([string]$Journal.committed_at)))) { throw (New-LizardTransactionException -Code 'TRANSACTION_STATE_INVALID' -Message 'Committed journal requires a valid committed_at timestamp.') }
  if ([string]$Journal.state -ne 'committed' -and $Journal.PSObject.Properties.Name -contains 'committed_at') { throw (New-LizardTransactionException -Code 'TRANSACTION_STATE_INVALID' -Message 'Only a committed journal may declare committed_at.') }
  if ([string]$Journal.state -eq 'rolled-back' -and @($Journal.mutations | Where-Object { $_.status -ne 'rolled-back' }).Count -gt 0) { throw (New-LizardTransactionException -Code 'TRANSACTION_STATE_INVALID' -Message 'Rolled-back journal contains unfinished mutations.') }
}

function Write-LizardUtf8File {
  param([string]$Path, [string]$Value)
  [System.IO.File]::WriteAllText($Path, $Value, (New-Object System.Text.UTF8Encoding($false)))
}

function Write-LizardTransactionJson {
  param([string]$Path, $Document)
  $tempPath = "$Path.tmp"
  Write-LizardUtf8File -Path $tempPath -Value ($Document | ConvertTo-Json -Depth 12)
  if (Test-Path -LiteralPath $Path) {
    $previousPath = "$Path.previous"
    try {
      if (Test-Path -LiteralPath $previousPath) { [System.IO.File]::Delete($previousPath) }
      [System.IO.File]::Replace($tempPath, $Path, $previousPath)
      if (Test-Path -LiteralPath $previousPath) { [System.IO.File]::Delete($previousPath) }
    } catch {
      if (Test-Path -LiteralPath $tempPath) { [System.IO.File]::Delete($tempPath) }
      throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_ATOMIC_WRITE_FAILED' -Message $_.Exception.Message)
    }
  } else {
    [System.IO.File]::Move($tempPath, $Path)
  }
}

function Get-LizardTransactionPaths {
  param([string]$TargetRoot, [string]$OperationId)
  if ($OperationId -notmatch '^[a-f0-9]{32}$') { throw (New-LizardTransactionException -Code 'TRANSACTION_ID_INVALID' -Message 'OperationId must be 32 lowercase hexadecimal characters.') }
  $root = Resolve-SafeRoot -Path $TargetRoot -RequireExisting
  $lockPath = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $root '.lizard-agent-layer.lock')
  $storeRoot = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $root '.lizard-agent-layer-transactions')
  $transactionDir = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $storeRoot $OperationId)
  [pscustomobject]@{
    target_root = $root
    lock_path = $lockPath
    store_root = $storeRoot
    transaction_dir = $transactionDir
    journal_path = Join-Path $transactionDir 'journal.json'
    backup_dir = Join-Path $transactionDir 'backups'
  }
}

function Read-LizardTransactionJournal {
  param([string]$JournalPath, [string]$ExpectedTargetRoot, [string]$ExpectedOperationId)
  if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_MISSING' -Message "Journal not found: $JournalPath")
  }
  try {
    $transactionDir = Split-Path -Parent $JournalPath
    $metadata = Get-SafeFileMetadata -AuthorizedRoot $transactionDir -Path $JournalPath
    if ([int64]$metadata.length -gt 4194304) { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_TOO_LARGE' -Message 'Journal exceeds the 4 MiB parsing limit.') }
    $journal = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $transactionDir -Path $JournalPath -Raw)
    Assert-LizardTransactionJournalDocument -Journal $journal -ExpectedTargetRoot $ExpectedTargetRoot -ExpectedOperationId $ExpectedOperationId
    return $journal
  }
  catch {
    if ($_.Exception.Data['transaction_code']) { throw }
    throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message $_.Exception.Message)
  }
}

function Sync-LizardTransactionContext {
  if ($null -eq $script:TransactionContext) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_NOT_ACTIVE' -Message 'No transaction is active in this process.')
  }
  $script:TransactionContext.journal = Read-LizardTransactionJournal -JournalPath $script:TransactionContext.journal_path -ExpectedTargetRoot $script:TransactionContext.target_root -ExpectedOperationId $script:TransactionContext.operation_id
  return $script:TransactionContext
}

function Save-LizardTransactionContext {
  param($Context)
  $Context.journal.updated_at = (Get-Date).ToUniversalTime().ToString('o')
  Assert-LizardTransactionJournalDocument -Journal $Context.journal -ExpectedTargetRoot $Context.target_root -ExpectedOperationId $Context.operation_id
  Write-LizardTransactionJson -Path $Context.journal_path -Document $Context.journal
}

function Start-LizardTransaction {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [Parameter(Mandatory = $true)][string]$OperationName,
    [int]$FailAfterMutation = 0
  )

  $operationId = [Guid]::NewGuid().ToString('N')
  $paths = Get-LizardTransactionPaths -TargetRoot $TargetRoot -OperationId $operationId
  $lockDocument = [ordered]@{
    schema_version = 2
    operation_id = $operationId
    operation_name = $OperationName
    target_root = $paths.target_root
    target_root_hash = Get-LizardTransactionRootIdentity -TargetRoot $paths.target_root
    owner_pid = $PID
    started_at = (Get-Date).ToUniversalTime().ToString('o')
    journal_path = ".lizard-agent-layer-transactions/$operationId/journal.json"
  }

  $stream = $null
  try {
    $stream = [System.IO.File]::Open($paths.lock_path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes(($lockDocument | ConvertTo-Json -Depth 6))
    $stream.Write($bytes, 0, $bytes.Length)
  } catch [System.IO.IOException] {
    throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_HELD' -Message "Target is locked. Recover or complete the operation recorded in $($paths.lock_path).")
  } finally {
    if ($null -ne $stream) { $stream.Dispose() }
  }

  try {
    [System.IO.Directory]::CreateDirectory($paths.backup_dir) | Out-Null
    $journal = [pscustomobject][ordered]@{
      schema_version = 2
      operation_id = $operationId
      operation_name = $OperationName
      target_root = $paths.target_root
      target_root_hash = $lockDocument.target_root_hash
      owner_pid = $PID
      state = 'active'
      started_at = $lockDocument.started_at
      updated_at = $lockDocument.started_at
      fail_after_mutation = $FailAfterMutation
      next_sequence = 1
      mutations = @()
    }
    $script:TransactionContext = [pscustomobject]@{
      operation_id = $operationId
      target_root = $paths.target_root
      lock_path = $paths.lock_path
      store_root = $paths.store_root
      transaction_dir = $paths.transaction_dir
      journal_path = $paths.journal_path
      backup_dir = $paths.backup_dir
      journal = $journal
    }
    Save-LizardTransactionContext -Context $script:TransactionContext
    return $script:TransactionContext
  } catch {
    if (Test-Path -LiteralPath $paths.transaction_dir) { [System.IO.Directory]::Delete($paths.transaction_dir, $true) }
    if (Test-Path -LiteralPath $paths.lock_path) { [System.IO.File]::Delete($paths.lock_path) }
    $script:TransactionContext = $null
    throw
  }
}

function Join-LizardTransaction {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [Parameter(Mandatory = $true)][string]$OperationId,
    [int]$FailAfterMutation = 0
  )

  $paths = Get-LizardTransactionPaths -TargetRoot $TargetRoot -OperationId $OperationId
  if (-not (Test-Path -LiteralPath $paths.lock_path -PathType Leaf)) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_MISSING' -Message "Transaction lock not found: $($paths.lock_path)")
  }
  $lock = Get-LizardTransactionLock -TargetRoot $paths.target_root
  if ([string]$lock.operation_id -ne $OperationId) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_ID_MISMATCH' -Message "Lock belongs to operation $($lock.operation_id), not $OperationId.")
  }
  $journal = Read-LizardTransactionJournal -JournalPath $paths.journal_path -ExpectedTargetRoot $paths.target_root -ExpectedOperationId $OperationId
  if ([string]$journal.operation_name -ne [string]$lock.operation_name -or [int]$journal.owner_pid -ne [int]$lock.owner_pid -or [string]$journal.started_at -ne [string]$lock.started_at) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_JOURNAL_MISMATCH' -Message 'Lock and journal identity fields do not match.')
  }
  if ([string]$journal.state -notin @('active', 'recovery-required')) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_NOT_ACTIVE' -Message "Transaction $OperationId is $($journal.state).")
  }
  $script:TransactionContext = [pscustomobject]@{
    operation_id = $OperationId
    target_root = $paths.target_root
    lock_path = $paths.lock_path
    store_root = $paths.store_root
    transaction_dir = $paths.transaction_dir
    journal_path = $paths.journal_path
    backup_dir = $paths.backup_dir
    journal = $journal
  }
  if ($FailAfterMutation -gt 0) {
    $script:TransactionContext.journal.fail_after_mutation = $FailAfterMutation
    Save-LizardTransactionContext -Context $script:TransactionContext
  }
  return $script:TransactionContext
}

function Get-LizardTransactionRelativePath {
  param($Context, [string]$Path)
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath $Path
  $prefix = $Context.target_root.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
  return $safePath.Substring($prefix.Length).Replace('\', '/')
}

function Add-LizardTransactionMutation {
  param($Context, [string]$Path, [ValidateSet('file', 'directory')][string]$Kind)
  $Context = Sync-LizardTransactionContext
  if ([string]$Context.journal.state -ne 'active') {
    throw (New-LizardTransactionException -Code 'TRANSACTION_NOT_ACTIVE' -Message "Transaction $($Context.operation_id) is not active.")
  }
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath $Path
  $relative = Get-LizardTransactionRelativePath -Context $Context -Path $safePath
  $existing = Get-Item -LiteralPath $safePath -Force -ErrorAction SilentlyContinue
  if ($null -ne $existing -and $Kind -eq 'file' -and $existing.PSIsContainer) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_DESTINATION_TYPE' -Message "Expected a file destination but found a directory: $relative")
  }
  if ($null -ne $existing -and $Kind -eq 'directory' -and -not $existing.PSIsContainer) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_DESTINATION_TYPE' -Message "Expected a directory destination but found a file: $relative")
  }
  $sequence = [int]$Context.journal.next_sequence
  $backupRel = $null
  $originalState = 'missing'
  $originalHash = $null
  if ($null -ne $existing) {
    $originalState = if ($existing.PSIsContainer) { 'directory' } else { 'file' }
    if (-not $existing.PSIsContainer) {
      $backupRel = "backups/{0:D6}.bin" -f $sequence
      $backupPath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.backup_dir -DestinationPath (Join-Path $Context.backup_dir ("{0:D6}.bin" -f $sequence))
      $originalHash = Get-SafeFileHash -AuthorizedRoot $Context.target_root -Path $safePath
      Copy-SafeItem -AuthorizedRoot $Context.target_root -Source $safePath -Destination $backupPath
      $backupHash = Get-SafeFileHash -AuthorizedRoot $Context.backup_dir -Path $backupPath
      if ($backupHash -ne $originalHash) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_COPY_MISMATCH' -Message "Backup copy hash mismatch for $relative.") }
      $confirmedSourceHash = Get-SafeFileHash -AuthorizedRoot $Context.target_root -Path $safePath
      if ($confirmedSourceHash -ne $originalHash) { throw (New-LizardTransactionException -Code 'TRANSACTION_SOURCE_CHANGED' -Message "Source changed while backup was created for $relative.") }
    }
  }
  $mutation = [pscustomobject][ordered]@{
    sequence = $sequence
    path = $relative
    kind = $Kind
    original_state = $originalState
    original_hash = $originalHash
    backup_path = $backupRel
    status = 'pending'
  }
  $Context.journal.mutations = @(@($Context.journal.mutations) + $mutation)
  $Context.journal.next_sequence = $sequence + 1
  Save-LizardTransactionContext -Context $Context
  return $mutation
}

function Complete-LizardTransactionMutation {
  param($Mutation)
  $Context = Sync-LizardTransactionContext
  $entry = @($Context.journal.mutations) | Where-Object { [int]$_.sequence -eq [int]$Mutation.sequence } | Select-Object -First 1
  if ($null -eq $entry) { throw (New-LizardTransactionException -Code 'TRANSACTION_MUTATION_MISSING' -Message "Mutation $($Mutation.sequence) is not journaled.") }
  $entry.status = 'applied'
  Save-LizardTransactionContext -Context $Context
  $appliedCount = @($Context.journal.mutations | Where-Object { $_.status -eq 'applied' }).Count
  if ([int]$Context.journal.fail_after_mutation -gt 0 -and $appliedCount -ge [int]$Context.journal.fail_after_mutation) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_FAULT_INJECTED' -Message "Injected failure after mutation $appliedCount.")
  }
}

function New-LizardTransactionalDirectory {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)
  $Context = Sync-LizardTransactionContext
  if ((ConvertTo-LizardFullPath -Path $Path) -eq (ConvertTo-LizardFullPath -Path $Context.target_root)) { return $Context.target_root }
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath $Path
  if (Test-Path -LiteralPath $safePath) {
    $item = Get-Item -LiteralPath $safePath -Force
    if (-not $item.PSIsContainer) { throw (New-LizardTransactionException -Code 'TRANSACTION_DESTINATION_TYPE' -Message "Expected directory: $safePath") }
    return $safePath
  }
  $missing = New-Object System.Collections.Generic.List[string]
  $cursor = $safePath
  while (-not (Test-Path -LiteralPath $cursor)) {
    $missing.Add($cursor) | Out-Null
    $cursor = Split-Path -Parent $cursor
    if (-not (Test-LizardPathWithinRoot -Path $cursor -AuthorizedRoot $Context.target_root -AllowRoot)) {
      throw (New-LizardTransactionException -Code 'TRANSACTION_PARENT_ESCAPE' -Message "Directory parent escaped target: $cursor")
    }
  }
  for ($index = $missing.Count - 1; $index -ge 0; $index--) {
    $candidate = $missing[$index]
    $mutation = Add-LizardTransactionMutation -Context $Context -Path $candidate -Kind directory
    New-SafeDirectory -AuthorizedRoot $Context.target_root -Path $candidate | Out-Null
    Complete-LizardTransactionMutation -Mutation $mutation
  }
  return $safePath
}

function Set-LizardTransactionalContent {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path, [AllowNull()][object]$Value, [string]$Encoding = 'UTF8')
  $Context = Sync-LizardTransactionContext
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath $Path
  New-LizardTransactionalDirectory -Path (Split-Path -Parent $safePath) | Out-Null
  $mutation = Add-LizardTransactionMutation -Context $Context -Path $safePath -Kind file
  Set-SafeContent -AuthorizedRoot $Context.target_root -Path $safePath -Value $Value -Encoding $Encoding
  Complete-LizardTransactionMutation -Mutation $mutation
}

function Add-LizardTransactionalContent {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path, [AllowNull()][object]$Value, [string]$Encoding = 'UTF8')
  $Context = Sync-LizardTransactionContext
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath $Path
  New-LizardTransactionalDirectory -Path (Split-Path -Parent $safePath) | Out-Null
  $mutation = Add-LizardTransactionMutation -Context $Context -Path $safePath -Kind file
  Add-SafeContent -AuthorizedRoot $Context.target_root -Path $safePath -Value $Value -Encoding $Encoding
  Complete-LizardTransactionMutation -Mutation $mutation
}

function Copy-LizardTransactionalFile {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Destination, [switch]$Force)
  if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Missing source file: $Source" }
  $Context = Sync-LizardTransactionContext
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath $Destination
  New-LizardTransactionalDirectory -Path (Split-Path -Parent $safePath) | Out-Null
  $mutation = Add-LizardTransactionMutation -Context $Context -Path $safePath -Kind file
  Copy-SafeItem -AuthorizedRoot $Context.target_root -Source $Source -Destination $safePath -Force:$Force
  Complete-LizardTransactionMutation -Mutation $mutation
}

function Remove-LizardTransactionMetadata {
  param($Context)
  if (Test-Path -LiteralPath $Context.lock_path) {
    $lock = Get-LizardTransactionLock -TargetRoot $Context.target_root
    if ([string]$lock.operation_id -ne [string]$Context.operation_id) { throw (New-LizardTransactionException -Code 'TRANSACTION_ID_MISMATCH' -Message 'Refusing to remove a lock owned by another operation.') }
    [System.IO.File]::Delete($Context.lock_path)
  }
  if (Test-Path -LiteralPath $Context.transaction_dir) { [System.IO.Directory]::Delete($Context.transaction_dir, $true) }
  if (Test-Path -LiteralPath $Context.store_root) {
    $remaining = @([System.IO.Directory]::EnumerateFileSystemEntries($Context.store_root))
    if ($remaining.Count -eq 0) { [System.IO.Directory]::Delete($Context.store_root) }
  }
}

function Resolve-LizardTransactionBackupPath {
  param($Context, $Mutation)
  $expectedRelative = 'backups/{0:D6}.bin' -f [int]$Mutation.sequence
  if ([string]$Mutation.backup_path -ne $expectedRelative) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_PATH_INVALID' -Message "Mutation $($Mutation.sequence) backup path is not canonical.") }
  $leaf = '{0:D6}.bin' -f [int]$Mutation.sequence
  return Resolve-SafeTargetDestination -AuthorizedRoot $Context.backup_dir -DestinationPath (Join-Path $Context.backup_dir $leaf)
}

function Undo-LizardTransaction {
  [CmdletBinding()]
  param([int]$TestFailAfterRollback = 0)
  $Context = Sync-LizardTransactionContext
  if ([string]$Context.journal.state -notin @('active', 'recovery-required')) { throw (New-LizardTransactionException -Code 'TRANSACTION_NOT_ACTIVE' -Message "Transaction $($Context.operation_id) cannot be rolled back from state $($Context.journal.state).") }
  $Context.journal.state = 'recovery-required'
  Save-LizardTransactionContext -Context $Context
  $rolledBackThisRun = 0
  $replay = @($Context.journal.mutations | Sort-Object { [int]$_.sequence } -Descending)
  foreach ($mutation in $replay) {
    if ([string]$mutation.status -eq 'rolled-back') { continue }
    try {
      $destination = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath (Join-Path $Context.target_root ([string]$mutation.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
      if ([string]$mutation.original_state -eq 'file') {
        $backupPath = Resolve-LizardTransactionBackupPath -Context $Context -Mutation $mutation
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_MISSING' -Message "Backup missing for mutation $($mutation.sequence).") }
        $backupHash = Get-SafeFileHash -AuthorizedRoot $Context.backup_dir -Path $backupPath
        if ($backupHash -ne [string]$mutation.original_hash) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_HASH_MISMATCH' -Message "Backup hash mismatch for $($mutation.path).") }
        Copy-SafeItem -AuthorizedRoot $Context.target_root -Source $backupPath -Destination $destination -Force
      } elseif ([string]$mutation.original_state -eq 'missing') {
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
          [System.IO.File]::Delete($destination)
        } elseif (Test-Path -LiteralPath $destination -PathType Container) {
          $children = @([System.IO.Directory]::EnumerateFileSystemEntries($destination))
          if ($children.Count -eq 0) { [System.IO.Directory]::Delete($destination) }
          elseif ([string]$mutation.kind -eq 'file') { throw "Expected rollback file but found non-empty directory: $destination" }
        }
      } elseif ([string]$mutation.original_state -eq 'directory') {
        if (-not (Test-Path -LiteralPath $destination -PathType Container)) { throw (New-LizardTransactionException -Code 'TRANSACTION_ORIGINAL_DIRECTORY_MISSING' -Message "Original directory is not present for $($mutation.path).") }
      }
      $entry = @($Context.journal.mutations | Where-Object { [int]$_.sequence -eq [int]$mutation.sequence })[0]
      $entry.status = 'rolled-back'
      Save-LizardTransactionContext -Context $Context
      $rolledBackThisRun++
      if ($TestFailAfterRollback -gt 0 -and $rolledBackThisRun -ge $TestFailAfterRollback) { throw (New-LizardTransactionException -Code 'TRANSACTION_RECOVERY_FAULT_INJECTED' -Message "Injected recovery failure after $rolledBackThisRun rollback mutation(s).") }
    } catch {
      try { $Context.journal.state = 'recovery-required'; Save-LizardTransactionContext -Context $Context } catch { }
      if ($_.Exception.Data['transaction_code'] -eq 'TRANSACTION_RECOVERY_FAULT_INJECTED') { throw }
      throw (New-LizardTransactionException -Code 'TRANSACTION_ROLLBACK_FAILED' -Message ("Mutation {0} ({1}): {2}" -f $mutation.sequence, $mutation.path, $_.Exception.Message))
    }
  }
  $Context.journal.state = 'rolled-back'
  Save-LizardTransactionContext -Context $Context
  $result = [pscustomobject]@{
    operation_id = $Context.operation_id
    state = 'rolled-back'
    mutation_count = @($Context.journal.mutations).Count
    rolled_back_this_run = $rolledBackThisRun
    errors = @()
  }
  Remove-LizardTransactionMetadata -Context $Context
  $script:TransactionContext = $null
  return $result
}

function Complete-LizardTransaction {
  [CmdletBinding()]
  param([switch]$TestFailBeforeCleanup)
  $Context = Sync-LizardTransactionContext
  $pending = @($Context.journal.mutations | Where-Object { $_.status -eq 'pending' })
  if ($pending.Count -gt 0) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_PENDING_MUTATIONS' -Message "$($pending.Count) mutations are still pending.")
  }
  $Context.journal.state = 'committed'
  $committedAt = (Get-Date).ToUniversalTime().ToString('o')
  if ($Context.journal.PSObject.Properties.Name -contains 'committed_at') { $Context.journal.committed_at = $committedAt }
  else { $Context.journal | Add-Member -NotePropertyName committed_at -NotePropertyValue $committedAt }
  Save-LizardTransactionContext -Context $Context
  $result = [pscustomobject]@{
    operation_id = $Context.operation_id
    state = 'committed'
    mutation_count = @($Context.journal.mutations).Count
    committed_at = $Context.journal.committed_at
  }
  if ($TestFailBeforeCleanup) { throw (New-LizardTransactionException -Code 'TRANSACTION_COMMIT_CLEANUP_FAULT_INJECTED' -Message 'Injected failure after commit persistence and before metadata cleanup.') }
  Remove-LizardTransactionMetadata -Context $Context
  $script:TransactionContext = $null
  return $result
}

function Get-LizardTransactionLock {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$TargetRoot)
  $root = Resolve-SafeRoot -Path $TargetRoot -RequireExisting
  $lockPath = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $root '.lizard-agent-layer.lock')
  if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) { return $null }
  try {
    $metadata = Get-SafeFileMetadata -AuthorizedRoot $root -Path $lockPath
    if ([int64]$metadata.length -gt 65536) { throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_TOO_LARGE' -Message 'Lock exceeds the 64 KiB parsing limit.') }
    $lock = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $root -Path $lockPath -Raw)
    Assert-LizardTransactionLockDocument -Lock $lock -ExpectedTargetRoot $root
    return $lock
  } catch {
    if ($_.Exception.Data['transaction_code']) { throw }
    throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_INVALID' -Message $_.Exception.Message)
  }
}

function Get-LizardTransactionRecoveryInfo {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$TargetRoot)
  $root = Resolve-SafeRoot -Path $TargetRoot -RequireExisting
  $lock = Get-LizardTransactionLock -TargetRoot $root
  if ($null -eq $lock) { return $null }
  $paths = Get-LizardTransactionPaths -TargetRoot $root -OperationId ([string]$lock.operation_id)
  $journal = Read-LizardTransactionJournal -JournalPath $paths.journal_path -ExpectedTargetRoot $root -ExpectedOperationId ([string]$lock.operation_id)
  if ([string]$journal.operation_name -ne [string]$lock.operation_name -or [int]$journal.owner_pid -ne [int]$lock.owner_pid -or [string]$journal.started_at -ne [string]$lock.started_at -or [string]$journal.target_root_hash -ne [string]$lock.target_root_hash) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_JOURNAL_MISMATCH' -Message 'Lock and journal identity fields do not match.')
  }
  $kind = if ([string]$journal.state -in @('active', 'recovery-required')) { 'rollback' } else { 'cleanup' }
  if ($kind -eq 'rollback') {
    $backupContext = [pscustomobject]@{ backup_dir = $paths.backup_dir }
    foreach ($mutation in @($journal.mutations | Where-Object { $_.status -ne 'rolled-back' -and $_.original_state -eq 'file' })) {
      $backupPath = Resolve-LizardTransactionBackupPath -Context $backupContext -Mutation $mutation
      if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_MISSING' -Message "Backup missing for mutation $($mutation.sequence).") }
      $backupHash = Get-SafeFileHash -AuthorizedRoot $paths.backup_dir -Path $backupPath
      if ($backupHash -ne [string]$mutation.original_hash) { throw (New-LizardTransactionException -Code 'TRANSACTION_BACKUP_HASH_MISMATCH' -Message "Backup hash mismatch for $($mutation.path).") }
    }
  }
  return [pscustomobject]@{
    lock = $lock
    journal = $journal
    journal_state = [string]$journal.state
    recovery_kind = $kind
    paths = $paths
  }
}

function Complete-LizardTransactionCleanup {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$TargetRoot, [Parameter(Mandatory = $true)][string]$OperationId)
  $info = Get-LizardTransactionRecoveryInfo -TargetRoot $TargetRoot
  if ($null -eq $info) { return [pscustomobject]@{ operation_id = $OperationId; state = 'clean'; mutation_count = 0 } }
  if ([string]$info.lock.operation_id -ne $OperationId) { throw (New-LizardTransactionException -Code 'TRANSACTION_ID_MISMATCH' -Message 'Cleanup operation ID does not match the current lock.') }
  if ([string]$info.journal_state -notin @('committed', 'rolled-back')) { throw (New-LizardTransactionException -Code 'TRANSACTION_CLEANUP_STATE_INVALID' -Message "Transaction state $($info.journal_state) requires rollback, not cleanup.") }
  $context = [pscustomobject]@{
    operation_id = $OperationId; target_root = $info.paths.target_root; lock_path = $info.paths.lock_path
    store_root = $info.paths.store_root; transaction_dir = $info.paths.transaction_dir
    journal_path = $info.paths.journal_path; backup_dir = $info.paths.backup_dir; journal = $info.journal
  }
  Remove-LizardTransactionMetadata -Context $context
  return [pscustomobject]@{ operation_id = $OperationId; state = [string]$info.journal_state; mutation_count = @($info.journal.mutations).Count }
}

Export-ModuleMember -Function @(
  'Add-LizardTransactionalContent',
  'Complete-LizardTransaction',
  'Complete-LizardTransactionCleanup',
  'Copy-LizardTransactionalFile',
  'Get-LizardTransactionLock',
  'Get-LizardTransactionRecoveryInfo',
  'Join-LizardTransaction',
  'New-LizardTransactionalDirectory',
  'Set-LizardTransactionalContent',
  'Start-LizardTransaction',
  'Undo-LizardTransaction'
)
