Set-StrictMode -Version 2.0

$script:TransactionContext = $null

Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')

function New-LizardTransactionException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['transaction_code'] = $Code
  return $exception
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
    try {
      [System.IO.File]::Replace($tempPath, $Path, $null)
    } catch {
      [System.IO.File]::Copy($tempPath, $Path, $true)
      [System.IO.File]::Delete($tempPath)
    }
  } else {
    [System.IO.File]::Move($tempPath, $Path)
  }
}

function Get-LizardTransactionPaths {
  param([string]$TargetRoot, [string]$OperationId)
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
  param([string]$JournalPath)
  if (-not (Test-Path -LiteralPath $JournalPath -PathType Leaf)) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_MISSING' -Message "Journal not found: $JournalPath")
  }
  try { return Get-Content -LiteralPath $JournalPath -Raw | ConvertFrom-Json }
  catch { throw (New-LizardTransactionException -Code 'TRANSACTION_JOURNAL_INVALID' -Message $_.Exception.Message) }
}

function Sync-LizardTransactionContext {
  if ($null -eq $script:TransactionContext) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_NOT_ACTIVE' -Message 'No transaction is active in this process.')
  }
  $script:TransactionContext.journal = Read-LizardTransactionJournal -JournalPath $script:TransactionContext.journal_path
  return $script:TransactionContext
}

function Save-LizardTransactionContext {
  param($Context)
  $Context.journal.updated_at = (Get-Date).ToUniversalTime().ToString('o')
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
    schema_version = 1
    operation_id = $operationId
    operation_name = $OperationName
    target_root = $paths.target_root
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
      schema_version = 1
      operation_id = $operationId
      operation_name = $OperationName
      target_root = $paths.target_root
      owner_pid = $PID
      state = 'active'
      started_at = $lockDocument.started_at
      updated_at = $lockDocument.started_at
      fail_after_mutation = $FailAfterMutation
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
  $lock = Get-Content -LiteralPath $paths.lock_path -Raw | ConvertFrom-Json
  if ([string]$lock.operation_id -ne $OperationId) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_ID_MISMATCH' -Message "Lock belongs to operation $($lock.operation_id), not $OperationId.")
  }
  $journal = Read-LizardTransactionJournal -JournalPath $paths.journal_path
  if ([string]$journal.state -notin @('active', 'recovery-required')) {
    throw (New-LizardTransactionException -Code 'TRANSACTION_NOT_ACTIVE' -Message "Transaction $OperationId is $($journal.state).")
  }
  if ($FailAfterMutation -gt 0) {
    $journal.fail_after_mutation = $FailAfterMutation
    Write-LizardTransactionJson -Path $paths.journal_path -Document $journal
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
  $sequence = @($Context.journal.mutations).Count + 1
  $backupRel = $null
  $originalState = 'missing'
  $originalHash = $null
  if ($null -ne $existing) {
    $originalState = if ($existing.PSIsContainer) { 'directory' } else { 'file' }
    if (-not $existing.PSIsContainer) {
      $backupRel = "backups/{0:D6}.bin" -f $sequence
      $backupPath = Join-Path $Context.transaction_dir $backupRel.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
      Copy-Item -LiteralPath $safePath -Destination $backupPath
      $originalHash = (Get-FileHash -LiteralPath $safePath -Algorithm SHA256).Hash.ToLowerInvariant()
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
  if (Test-Path -LiteralPath $Context.transaction_dir) { [System.IO.Directory]::Delete($Context.transaction_dir, $true) }
  if (Test-Path -LiteralPath $Context.store_root) {
    $remaining = @([System.IO.Directory]::EnumerateFileSystemEntries($Context.store_root))
    if ($remaining.Count -eq 0) { [System.IO.Directory]::Delete($Context.store_root) }
  }
  if (Test-Path -LiteralPath $Context.lock_path) {
    $lock = Get-Content -LiteralPath $Context.lock_path -Raw | ConvertFrom-Json
    if ([string]$lock.operation_id -eq [string]$Context.operation_id) { [System.IO.File]::Delete($Context.lock_path) }
  }
}

function Undo-LizardTransaction {
  [CmdletBinding()]
  param()
  $Context = Sync-LizardTransactionContext
  $errors = New-Object System.Collections.Generic.List[string]
  $mutations = @($Context.journal.mutations)
  [array]::Reverse($mutations)
  foreach ($mutation in $mutations) {
    try {
      $destination = Resolve-SafeTargetDestination -AuthorizedRoot $Context.target_root -DestinationPath (Join-Path $Context.target_root ([string]$mutation.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
      if ([string]$mutation.original_state -eq 'file') {
        $backupPath = Join-Path $Context.transaction_dir ([string]$mutation.backup_path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { throw "Backup missing: $backupPath" }
        $backupHash = (Get-FileHash -LiteralPath $backupPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($backupHash -ne [string]$mutation.original_hash) { throw "Backup hash mismatch for $($mutation.path)" }
        Copy-SafeItem -AuthorizedRoot $Context.target_root -Source $backupPath -Destination $destination -Force
      } elseif ([string]$mutation.original_state -eq 'missing') {
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
          [System.IO.File]::Delete($destination)
        } elseif (Test-Path -LiteralPath $destination -PathType Container) {
          $children = @([System.IO.Directory]::EnumerateFileSystemEntries($destination))
          if ($children.Count -eq 0) { [System.IO.Directory]::Delete($destination) }
          elseif ([string]$mutation.kind -eq 'file') { throw "Expected rollback file but found non-empty directory: $destination" }
        }
      }
      $mutation.status = 'rolled-back'
    } catch {
      $errors.Add(("{0}: {1}" -f $mutation.path, $_.Exception.Message)) | Out-Null
    }
  }
  $Context.journal.mutations = $mutations
  $Context.journal.state = if ($errors.Count -eq 0) { 'rolled-back' } else { 'recovery-required' }
  Save-LizardTransactionContext -Context $Context
  $result = [pscustomobject]@{
    operation_id = $Context.operation_id
    state = $Context.journal.state
    mutation_count = $mutations.Count
    errors = @($errors.ToArray())
  }
  if ($errors.Count -eq 0) {
    Remove-LizardTransactionMetadata -Context $Context
    $script:TransactionContext = $null
    return $result
  }
  throw (New-LizardTransactionException -Code 'TRANSACTION_ROLLBACK_FAILED' -Message ($errors -join '; '))
}

function Complete-LizardTransaction {
  [CmdletBinding()]
  param()
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
  try { return Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json }
  catch { throw (New-LizardTransactionException -Code 'TRANSACTION_LOCK_INVALID' -Message $_.Exception.Message) }
}

Export-ModuleMember -Function @(
  'Add-LizardTransactionalContent',
  'Complete-LizardTransaction',
  'Copy-LizardTransactionalFile',
  'Get-LizardTransactionLock',
  'Join-LizardTransaction',
  'New-LizardTransactionalDirectory',
  'Set-LizardTransactionalContent',
  'Start-LizardTransaction',
  'Undo-LizardTransaction'
)
