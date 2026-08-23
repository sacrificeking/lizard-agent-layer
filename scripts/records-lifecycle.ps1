[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$TargetRoot,
  [ValidateSet('Inventory', 'Export', 'Purge')][string]$Action = 'Inventory',
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$PolicyPath,
  [string]$PolicySha256,
  [DateTimeOffset]$AsOf,
  [ValidateSet('memory', 'routing-decision', 'routing-execution', 'update-history', 'loop-events', 'loop-run-log')][string[]]$Classes,
  [string]$ReceiptId,
  [string]$ExportRoot,
  [string]$HoldEvidencePath,
  [string]$HoldTrustStorePath,
  [string]$HoldTrustStoreSha256,
  [string]$HoldChallengePath,
  [string]$HoldChallengeSha256,
  [string]$CanonicalPlanPath,
  [switch]$Apply,
  [string]$ApprovedPlanPath,
  [string]$ApprovedPlanSha256,
  [switch]$HumanApproved,
  [ValidateRange(1, 1440)][int]$PlanTtlMinutes = 30,
  [ValidateRange(0, 10000)][int]$FailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetRoot).Path
$ScriptDir = Join-Path $LayerRoot 'scripts'
Import-Module (Join-Path $ScriptDir 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Plan.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Records.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force

function New-RecordsLifecycleException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['records_lifecycle_code'] = $Code
  return $exception
}

function Get-RelativeRecordPath {
  param([string]$Path)
  return $Path.Substring($TargetRoot.TrimEnd([char[]]@('\', '/')).Length).TrimStart([char[]]@('\', '/')).Replace('\', '/')
}

function Get-RecordBytesHash {
  param([byte[]]$Bytes)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-ObservedTimestamp {
  param([string]$Path)
  $null = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $Path -Kind File
  return [DateTimeOffset](Get-Item -LiteralPath $Path -Force).LastWriteTimeUtc
}

function Add-FileArtifact {
  param($Artifacts, [string]$Path, [string]$ArtifactClass, [string]$TimestampMode)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $relative = Get-RelativeRecordPath $Path
  $bytes = Get-SafeBytes -AuthorizedRoot $TargetRoot -Path $Path -MaximumBytes 67108864
  $fileHash = Get-RecordBytesHash $bytes
  $timestamp = $null
  $timestampSource = $TimestampMode
  if ($TimestampMode -eq 'route-envelope') {
    try {
      $document = ConvertFrom-LizardJson -InputObject ((New-Object Text.UTF8Encoding($false, $true)).GetString($bytes))
      if ($null -eq $document.payload -or $document.payload.PSObject.Properties.Name -notcontains 'created_at') { throw 'payload.created_at missing' }
      $timestamp = ConvertTo-LizardRecordsTimestamp $document.payload.created_at 'route receipt payload.created_at'
    } catch { throw (New-RecordsLifecycleException 'RECORDS_ARTIFACT_INVALID' "Route receipt '$relative' cannot establish its timestamp: $($_.Exception.Message)") }
  } else {
    $timestamp = (Get-ObservedTimestamp $Path).ToUniversalTime()
    $timestampSource = 'filesystem-last-write-observed'
  }
  $recordId = New-LizardRecordId -ArtifactClass $ArtifactClass -RelativePath $relative
  $record = [pscustomobject]@{ record_id = $recordId; artifact_class = $ArtifactClass; path = $relative; kind = 'file'; timestamp = $timestamp; timestamp_source = $timestampSource; content_sha256 = $fileHash; raw_bytes = $bytes; raw_line = $null }
  $Artifacts.Add([pscustomobject]@{ path = $relative; full_path = $Path; kind = 'file'; sha256 = $fileHash; bytes = $bytes; records = [object[]]@($record) }) | Out-Null
}

function Add-JsonlArtifact {
  param($Artifacts, [string]$Path, [string]$ArtifactClass, [string]$TimestampProperty)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  $relative = Get-RelativeRecordPath $Path
  $bytes = Get-SafeBytes -AuthorizedRoot $TargetRoot -Path $Path -MaximumBytes 67108864
  $raw = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
  $records = New-Object System.Collections.Generic.List[object]
  $occurrences = @{}
  $lineNumber = 0
  foreach ($line in @($raw -split "`r?`n")) {
    $lineNumber++
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    try { $document = ConvertFrom-LizardJson -InputObject $line }
    catch { throw (New-RecordsLifecycleException 'RECORDS_ARTIFACT_INVALID' "JSONL artifact '$relative' line $lineNumber is invalid JSON.") }
    if ($document.PSObject.Properties.Name -notcontains $TimestampProperty) { throw (New-RecordsLifecycleException 'RECORDS_ARTIFACT_INVALID' "JSONL artifact '$relative' line $lineNumber lacks '$TimestampProperty'.") }
    $timestamp = ConvertTo-LizardRecordsTimestamp $document.$TimestampProperty "$relative line $lineNumber $TimestampProperty"
    $lineBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($line)
    $lineHash = Get-RecordBytesHash $lineBytes
    $occurrence = if ($occurrences.ContainsKey($lineHash)) { [int]$occurrences[$lineHash] + 1 } else { 1 }
    $occurrences[$lineHash] = $occurrence
    $locator = "line:$lineHash`:$occurrence"
    $recordId = New-LizardRecordId -ArtifactClass $ArtifactClass -RelativePath $relative -Locator $locator
    $records.Add([pscustomobject]@{ record_id = $recordId; artifact_class = $ArtifactClass; path = $relative; kind = 'jsonl-record'; timestamp = $timestamp; timestamp_source = "embedded-$TimestampProperty"; content_sha256 = $lineHash; raw_bytes = $lineBytes; raw_line = $line }) | Out-Null
  }
  $Artifacts.Add([pscustomobject]@{ path = $relative; full_path = $Path; kind = 'jsonl'; sha256 = (Get-RecordBytesHash $bytes); bytes = $bytes; records = [object[]]@($records.ToArray()) }) | Out-Null
}

function Get-RecordArtifacts {
  $artifacts = New-Object System.Collections.Generic.List[object]
  foreach ($relative in @('.agent/memory/personal/PREFERENCES.md', '.agent/memory/semantic/DECISIONS.md', '.agent/memory/semantic/LESSONS.md', '.agent/memory/working/WORKSPACE.md', '.agent/memory/episodic/EPISODES.md')) { Add-FileArtifact $artifacts (Join-Path $TargetRoot $relative.Replace('/', '\')) 'memory' 'filesystem' }
  foreach ($spec in @(
    [pscustomobject]@{ path = '.agent/routing/receipts/decisions'; class = 'routing-decision' },
    [pscustomobject]@{ path = '.agent/routing/receipts/executions'; class = 'routing-execution' }
  )) {
    $directory = Join-Path $TargetRoot $spec.path.Replace('/', '\')
    if (Test-Path -LiteralPath $directory -PathType Container) {
      foreach ($entry in @(Get-SafeDirectoryEntries -AuthorizedRoot $TargetRoot -Path $directory)) {
        if ($entry.kind -eq 'file' -and $entry.name.EndsWith('.json', [StringComparison]::OrdinalIgnoreCase)) { Add-FileArtifact $artifacts $entry.path $spec.class 'route-envelope' }
      }
    }
  }
  Add-JsonlArtifact $artifacts (Join-Path $TargetRoot '.agent\lizard-agent-layer.update-history.jsonl') 'update-history' 'updated_at'
  $loopsRoot = Join-Path $TargetRoot '.agent\loops'
  if (Test-Path -LiteralPath $loopsRoot -PathType Container) {
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($loopsRoot)
    while ($queue.Count -gt 0) {
      $directory = $queue.Dequeue()
      foreach ($entry in @(Get-SafeDirectoryEntries -AuthorizedRoot $TargetRoot -Path $directory)) {
        if ($entry.kind -eq 'directory') { $queue.Enqueue([string]$entry.path); continue }
        if ($entry.name -eq 'events.jsonl') { Add-JsonlArtifact $artifacts $entry.path 'loop-events' 'occurred_at' }
        elseif ($entry.name -eq 'loop-run-log.md') { Add-FileArtifact $artifacts $entry.path 'loop-run-log' 'filesystem' }
      }
    }
  }
  $array = [object[]]@($artifacts.ToArray())
  $paths = [string[]]@($array | ForEach-Object { [string]$_.path })
  [Array]::Sort($paths, [StringComparer]::Ordinal)
  $byPath = @{}; foreach ($artifact in $array) { $byPath[[string]$artifact.path] = $artifact }
  return [object[]]@($paths | ForEach-Object { $byPath[$_] })
}

function Get-PlanTargetEntry {
  param([string]$Path, [string]$Kind, [string]$Action, [AllowNull()]$IntendedSha256)
  $exists = Test-Path -LiteralPath $Path
  $preKind = if (-not $exists) { 'absent' } elseif (Test-Path -LiteralPath $Path -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $Path -PathType Container) { 'directory' } else { 'other' }
  $preHash = if ($preKind -eq 'file') { Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $Path } else { $null }
  $entry = [pscustomobject][ordered]@{ path = Get-RelativeRecordPath $Path; kind = $Kind; action = $Action; precondition_kind = $preKind; precondition_sha256 = $preHash }
  if ($Action -eq 'remove') {
    $metadataKind = if ($Kind -eq 'file') { 'File' } else { 'Directory' }
    $entry | Add-Member -NotePropertyName precondition_identity_sha256 -NotePropertyValue (Get-LizardPlanTargetIdentitySha256 -Metadata (Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $Path -Kind $metadataKind))
  }
  $entry | Add-Member -NotePropertyName ownership -NotePropertyValue 'layer-owned'
  $entry | Add-Member -NotePropertyName intended_sha256 -NotePropertyValue $IntendedSha256
  return $entry
}

function Assert-PlanPreconditions {
  param($Plan)
  if ((Get-LizardPlanRootHash $TargetRoot) -ne [string]$Plan.intent.target_root_hash) { throw (New-RecordsLifecycleException 'RECORDS_PLAN_DRIFT' 'Target root identity changed after approval.') }
  foreach ($inputRecord in @($Plan.intent.inputs)) {
    $path = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot ([string]$inputRecord.path).Replace('/', '\'))
    if ((Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $path) -ne [string]$inputRecord.sha256) { throw (New-RecordsLifecycleException 'RECORDS_PLAN_DRIFT' "Input '$($inputRecord.path)' changed after approval.") }
  }
  foreach ($entry in @($Plan.intent.target_entries)) {
    $path = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot ([string]$entry.path).Replace('/', '\'))
    $exists = Test-Path -LiteralPath $path
    $kind = if (-not $exists) { 'absent' } elseif (Test-Path -LiteralPath $path -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $path -PathType Container) { 'directory' } else { 'other' }
    if ($kind -ne [string]$entry.precondition_kind) { throw (New-RecordsLifecycleException 'RECORDS_PLAN_DRIFT' "Target '$($entry.path)' kind changed after approval.") }
    if ($kind -eq 'file' -and (Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $path) -ne [string]$entry.precondition_sha256) { throw (New-RecordsLifecycleException 'RECORDS_PLAN_DRIFT' "Target '$($entry.path)' content changed after approval.") }
    if ([string]$entry.action -eq 'remove') {
      $metadataKind = if ($kind -eq 'file') { 'File' } else { 'Directory' }
      $identity = Get-LizardPlanTargetIdentitySha256 -Metadata (Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $path -Kind $metadataKind)
      if ($identity -ne [string]$entry.precondition_identity_sha256) { throw (New-RecordsLifecycleException 'RECORDS_PLAN_DRIFT' "Target '$($entry.path)' identity changed after approval.") }
    }
  }
}

function Write-ExportBundle {
  param([object[]]$Records, [string]$Root, [string]$ManifestJson, [string]$ManifestName)
  $exportRootResolved = Resolve-SafeRoot -Path $Root -RequireExisting
  foreach ($record in $Records) {
    $path = Join-Path $exportRootResolved ($record.record_id + '.bin')
    $expected = [string]$record.content_sha256
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      if ((Get-SafeFileHash -AuthorizedRoot $exportRootResolved -Path $path) -ne $expected) { throw (New-RecordsLifecycleException 'RECORDS_EXPORT_COLLISION' "Export file collision for '$($record.record_id)'.") }
    } else { Set-SafeBytes -AuthorizedRoot $exportRootResolved -Path $path -Bytes ([byte[]]$record.raw_bytes) -CreateNew }
  }
  $manifestPath = Join-Path $exportRootResolved $ManifestName
  $manifestBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($ManifestJson)
  $manifestHash = Get-RecordBytesHash $manifestBytes
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    if ((Get-SafeFileHash -AuthorizedRoot $exportRootResolved -Path $manifestPath) -ne $manifestHash) { throw (New-RecordsLifecycleException 'RECORDS_EXPORT_COLLISION' 'Export manifest collision.') }
  } else { Set-SafeBytes -AuthorizedRoot $exportRootResolved -Path $manifestPath -Bytes $manifestBytes -CreateNew }
}

if ([string]::IsNullOrWhiteSpace($PolicyPath)) { $PolicyPath = Join-Path $LayerRoot 'retention-policies\conservative.json' }
if ([string]::IsNullOrWhiteSpace($PolicySha256)) { throw (New-RecordsLifecycleException 'RETENTION_POLICY_DIGEST_REQUIRED' 'Supply an independently calculated PolicySha256.') }
if ($Action -ne 'Inventory' -and -not $PSBoundParameters.ContainsKey('AsOf')) { throw (New-RecordsLifecycleException 'RECORDS_AS_OF_REQUIRED' 'Export and purge require an explicit AsOf boundary time.') }
if (-not $PSBoundParameters.ContainsKey('AsOf')) { $AsOf = [DateTimeOffset]::UtcNow }
$AsOf = $AsOf.ToUniversalTime()
Assert-PathOutsideRoot -Path $PolicyPath -ExcludedRoot $TargetRoot -Label 'Retention policy'
$policyRead = Read-LizardRetentionPolicy -Path $PolicyPath -ExpectedSha256 $PolicySha256 -AsOf $AsOf
$requestedClasses = [string[]]@($Classes | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$selectedClasses = if ($requestedClasses.Count -eq 0) { [string[]]@('memory', 'routing-decision', 'routing-execution', 'update-history', 'loop-events', 'loop-run-log') } else { [string[]]@($requestedClasses | Sort-Object -Unique) }
$targetRootHash = Get-LizardPlanRootHash $TargetRoot
$holdPayload = $null
$verifiedHold = $null

if ($Action -eq 'Purge') {
  foreach ($value in @($HoldEvidencePath, $HoldTrustStorePath, $HoldTrustStoreSha256, $HoldChallengePath, $HoldChallengeSha256)) { if ([string]::IsNullOrWhiteSpace($value)) { throw (New-RecordsLifecycleException 'RECORDS_HOLD_AUTHORITY_REQUIRED' 'Purge requires signed external hold evidence, trust store, challenge, and exact digests.') } }
  foreach ($path in @($HoldEvidencePath, $HoldTrustStorePath, $HoldChallengePath)) { Assert-PathOutsideRoot -Path $path -ExcludedRoot $TargetRoot -Label 'Records hold trust input' }
  $holdBinding = Get-LizardRecordsHoldBinding -PolicyId ([string]$policyRead.policy.policy_id) -PolicySha256 $policyRead.sha256 -TargetRootHash $targetRootHash -AsOf $AsOf
  $trust = Read-LizardTrustStore -Path $HoldTrustStorePath -ExpectedSha256 $HoldTrustStoreSha256
  $challenge = Read-LizardTrustChallenge -Path $HoldChallengePath -ExpectedSha256 $HoldChallengeSha256 -Now $AsOf
  $envelope = Read-LizardSignedEvidenceFile -Path $HoldEvidencePath
  $verifiedHold = Test-LizardSignedEvidenceEnvelope -Envelope $envelope -TrustStoreRead $trust -ChallengeRead $challenge -ExpectedPayloadKind 'records-hold-register' -ExpectedPurpose 'records-disposition' -ExpectedSubject ([string]$policyRead.policy.policy_id) -ExpectedBindingSha256 $holdBinding -RequiredRole 'records-officer' -Now $AsOf
  $holdPayload = Assert-LizardRecordsHoldPayload -Payload $verifiedHold.payload -PolicyId ([string]$policyRead.policy.policy_id) -PolicySha256 $policyRead.sha256 -TargetRootHash $targetRootHash -AsOf $AsOf
}

$artifacts = Get-RecordArtifacts
$loopOperational = Test-Path -LiteralPath (Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json') -PathType Leaf
$allRecords = New-Object System.Collections.Generic.List[object]
foreach ($artifact in @($artifacts)) {
  foreach ($record in @($artifact.records)) {
    $rule = $policyRead.classes[[string]$record.artifact_class]
    $expiresAt = ([DateTimeOffset]$record.timestamp).AddDays([int]$rule.retention_days)
    $held = if ($null -eq $holdPayload) { $false } else { Test-LizardRecordHeld -HoldPayload $holdPayload -ArtifactClass ([string]$record.artifact_class) -RecordId ([string]$record.record_id) -AsOf $AsOf }
    $operationalBlock = $loopOperational -and [string]$record.artifact_class -in @('loop-events', 'loop-run-log')
    $selected = $selectedClasses -contains [string]$record.artifact_class
    $eligible = $selected -and $expiresAt -le $AsOf -and -not $held -and -not $operationalBlock
    $record | Add-Member -NotePropertyName purpose -NotePropertyValue ([string]$rule.purpose)
    $record | Add-Member -NotePropertyName owner_id -NotePropertyValue ([string]$rule.owner_id)
    $record | Add-Member -NotePropertyName expires_at -NotePropertyValue $expiresAt
    $record | Add-Member -NotePropertyName selected -NotePropertyValue $selected
    $record | Add-Member -NotePropertyName held -NotePropertyValue $held
    $record | Add-Member -NotePropertyName operational_block -NotePropertyValue $operationalBlock
    $record | Add-Member -NotePropertyName eligible -NotePropertyValue $eligible
    $record | Add-Member -NotePropertyName export_required -NotePropertyValue ([bool]$rule.export_required)
    $allRecords.Add($record) | Out-Null
  }
}

if ($Action -eq 'Inventory') {
  $publicRecords = @($allRecords | ForEach-Object { [pscustomobject][ordered]@{ record_id = $_.record_id; artifact_class = $_.artifact_class; path = $_.path; kind = $_.kind; purpose = $_.purpose; owner_id = $_.owner_id; timestamp = ([DateTimeOffset]$_.timestamp).ToString('o'); timestamp_source = $_.timestamp_source; expires_at = ([DateTimeOffset]$_.expires_at).ToString('o'); content_sha256 = $_.content_sha256; selected = $_.selected; eligible = $_.eligible; hold_status = 'not-evaluated'; operational_block = $_.operational_block } })
  Write-Output ([pscustomobject]@{ schema_version = 1; policy_id = [string]$policyRead.policy.policy_id; policy_sha256 = $policyRead.sha256; target_root_hash = $targetRootHash; as_of = $AsOf.ToString('o'); record_count = $publicRecords.Count; records = $publicRecords })
  return
}

if ([string]::IsNullOrWhiteSpace($ReceiptId) -or $ReceiptId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw (New-RecordsLifecycleException 'RECORDS_RECEIPT_ID_INVALID' 'Export and purge require a stable ReceiptId.') }
$candidateRecords = if ($Action -eq 'Export') { [object[]]@($allRecords | Where-Object { $_.selected }) } else { [object[]]@($allRecords | Where-Object { $_.eligible }) }
if ($candidateRecords.Count -eq 0) { throw (New-RecordsLifecycleException 'RECORDS_NOTHING_SELECTED' 'No records satisfy the selected lifecycle action.') }
$needsExport = $Action -eq 'Export' -or @($candidateRecords | Where-Object { $_.export_required }).Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($ExportRoot)
if ($needsExport -and [string]::IsNullOrWhiteSpace($ExportRoot)) { throw (New-RecordsLifecycleException 'RECORDS_EXPORT_REQUIRED' 'Selected records require an existing export root outside the target.') }
if ($needsExport) { Assert-PathOutsideRoot -Path $ExportRoot -ExcludedRoot $TargetRoot -Label 'Records export root'; $ExportRoot = (Resolve-Path -LiteralPath $ExportRoot).Path }

$exportEntries = @($candidateRecords | ForEach-Object { [pscustomobject][ordered]@{ record_id = [string]$_.record_id; artifact_class = [string]$_.artifact_class; path = [string]$_.path; content_sha256 = [string]$_.content_sha256; file = ([string]$_.record_id + '.bin') } })
$exportManifest = [pscustomobject][ordered]@{ schema_version = 1; artifact_kind = 'records-export'; export_id = $ReceiptId; policy_id = [string]$policyRead.policy.policy_id; policy_sha256 = $policyRead.sha256; target_root_hash = $targetRootHash; as_of = $AsOf.ToString('o'); sensitivity = 'potentially-sensitive'; purpose = 'records-lifecycle-export'; audience = @('authorized-records-operators'); content_policy = 'exact-selected-record-bytes'; records = $exportEntries }
$exportManifestJson = ConvertTo-LizardCanonicalJson $exportManifest
$exportManifestHash = Get-LizardPlanSha256 -CanonicalJson $exportManifestJson
$exportManifestName = "records-export-$ReceiptId.json"

$inputs = New-Object System.Collections.Generic.List[object]
$inputSeen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
foreach ($artifact in @($artifacts)) {
  if (@($candidateRecords | Where-Object { $_.path -eq $artifact.path }).Count -gt 0 -and $inputSeen.Add([string]$artifact.path)) { $inputs.Add([pscustomobject][ordered]@{ scope = 'target'; path = [string]$artifact.path; sha256 = [string]$artifact.sha256 }) | Out-Null }
}
$entries = New-Object System.Collections.Generic.List[object]
$mutations = New-Object System.Collections.Generic.List[object]
$receiptJson = $null
$receiptPath = $null

if ($Action -eq 'Purge') {
  foreach ($artifact in @($artifacts)) {
    $removed = [object[]]@($candidateRecords | Where-Object { $_.path -eq $artifact.path })
    if ($removed.Count -eq 0) { continue }
    $kept = [object[]]@($artifact.records | Where-Object { $candidateRecords.record_id -notcontains $_.record_id })
    if ($artifact.kind -eq 'file' -or $kept.Count -eq 0) {
      $entries.Add((Get-PlanTargetEntry -Path $artifact.full_path -Kind file -Action remove -IntendedSha256 $null)) | Out-Null
      $mutations.Add([pscustomobject]@{ action = 'remove'; artifact = $artifact; bytes = $null; intended_sha256 = $null }) | Out-Null
    } else {
      $content = if ($kept.Count -eq 0) { '' } else { (@($kept | ForEach-Object { [string]$_.raw_line }) -join "`n") + "`n" }
      $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($content)
      $intended = Get-RecordBytesHash $bytes
      $entries.Add((Get-PlanTargetEntry -Path $artifact.full_path -Kind file -Action replace -IntendedSha256 $intended)) | Out-Null
      $mutations.Add([pscustomobject]@{ action = 'replace'; artifact = $artifact; bytes = $bytes; intended_sha256 = $intended }) | Out-Null
    }
  }
  $recordsRoot = Join-Path $TargetRoot '.agent\records'
  $receiptRoot = Join-Path $recordsRoot 'deletion-receipts'
  $receiptPath = Join-Path $receiptRoot ($ReceiptId + '.json')
  foreach ($directory in @($recordsRoot, $receiptRoot)) {
    $relative = Get-RelativeRecordPath $directory
    if (@($entries | Where-Object { $_.path -eq $relative }).Count -eq 0) { $entries.Add((Get-PlanTargetEntry -Path $directory -Kind directory -Action $(if (Test-Path -LiteralPath $directory -PathType Container) { 'preserve' } else { 'create' }) -IntendedSha256 $null)) | Out-Null }
  }
  $deletedRecords = @($candidateRecords | ForEach-Object { [pscustomobject][ordered]@{ record_id = [string]$_.record_id; artifact_class = [string]$_.artifact_class; path = [string]$_.path; content_sha256 = [string]$_.content_sha256; expired_at = ([DateTimeOffset]$_.expires_at).ToString('o'); disposition = 'deleted' } })
  $receipt = [pscustomobject][ordered]@{ schema_version = 1; artifact_kind = 'records-deletion-receipt'; receipt_id = $ReceiptId; policy_id = [string]$policyRead.policy.policy_id; policy_sha256 = $policyRead.sha256; hold_envelope_id = [string]$verifiedHold.envelope_id; records_officer = [string]$verifiedHold.principal_id; target_root_hash = $targetRootHash; as_of = $AsOf.ToString('o'); selected_classes = [string[]]$selectedClasses; deleted_records = $deletedRecords; export_performed = $needsExport; export_manifest_sha256 = if ($needsExport) { $exportManifestHash } else { $null }; sensitivity = 'metadata-only'; purpose = 'records-deletion-evidence'; audience = @('operators', 'auditors'); retention_class = 'organization-policy-required'; content_policy = 'identifiers-and-relative-paths-only'; raw_content_stored = $false; transactionally_bound = $true }
  $receiptJson = ConvertTo-LizardCanonicalJson $receipt
  $receiptHash = Get-LizardPlanSha256 -CanonicalJson $receiptJson
  if (Test-Path -LiteralPath $receiptPath) { throw (New-RecordsLifecycleException 'RECORDS_RECEIPT_EXISTS' "Deletion receipt '$ReceiptId' already exists.") }
  $entries.Add((Get-PlanTargetEntry -Path $receiptPath -Kind file -Action create -IntendedSha256 $receiptHash)) | Out-Null
}

$options = [pscustomobject][ordered]@{ action = $Action.ToLowerInvariant(); policy_path = (ConvertTo-LizardFullPath $PolicyPath); policy_sha256 = $policyRead.sha256; policy_id = [string]$policyRead.policy.policy_id; as_of = $AsOf.ToString('o'); classes = [string[]]$selectedClasses; receipt_id = $ReceiptId; export_root = if ($needsExport) { $ExportRoot } else { $null }; export_manifest_sha256 = if ($needsExport) { $exportManifestHash } else { $null }; hold_envelope_id = if ($null -eq $verifiedHold) { $null } else { [string]$verifiedHold.envelope_id } }
$candidatePlan = New-LizardOperationPlan -OperationKind records-lifecycle -TargetRoot $TargetRoot -LayerRoot $LayerRoot -Options $options -Inputs @($inputs.ToArray()) -TargetEntries @($entries.ToArray()) -TtlMinutes $PlanTtlMinutes

if (-not $Apply) {
  if ([string]::IsNullOrWhiteSpace($CanonicalPlanPath)) { $planRoot = Join-Path $LayerRoot '.tmp\records-plans'; if (-not (Test-Path -LiteralPath $planRoot)) { New-SafeDirectory -AuthorizedRoot $LayerRoot -Path $planRoot | Out-Null }; $CanonicalPlanPath = Join-Path $planRoot ("$ReceiptId-$($Action.ToLowerInvariant())-$([Guid]::NewGuid().ToString('N')).json") }
  $written = Write-LizardOperationPlan -Plan $candidatePlan -AuthorizedRoot $LayerRoot -Path $CanonicalPlanPath
  Write-Output ([pscustomobject]@{ mode = 'preview'; action = $Action.ToLowerInvariant(); policy_id = [string]$policyRead.policy.policy_id; as_of = $AsOf.ToString('o'); selected_records = $candidateRecords.Count; held_records = @($allRecords | Where-Object { $_.held }).Count; operationally_blocked = @($allRecords | Where-Object { $_.operational_block }).Count; plan_path = $written.path; plan_sha256 = $written.sha256; export_manifest_sha256 = if ($needsExport) { $exportManifestHash } else { $null } })
  return
}

if (-not $HumanApproved -or [string]::IsNullOrWhiteSpace($ApprovedPlanPath) -or [string]::IsNullOrWhiteSpace($ApprovedPlanSha256)) { throw (New-RecordsLifecycleException 'RECORDS_APPROVAL_REQUIRED' 'Apply requires HumanApproved, ApprovedPlanPath, and independently supplied ApprovedPlanSha256.') }
$approved = Read-LizardApprovedPlan -AuthorizedRoot $LayerRoot -Path $ApprovedPlanPath -Sha256 $ApprovedPlanSha256 -OperationKind records-lifecycle
$null = Assert-LizardPlanIntentMatch -ApprovedPlan $approved -CandidatePlan $candidatePlan

if ($Action -eq 'Export') {
  Assert-PlanPreconditions $candidatePlan
  Write-ExportBundle -Records $candidateRecords -Root $ExportRoot -ManifestJson $exportManifestJson -ManifestName $exportManifestName
  Write-Output ([pscustomobject]@{ mode = 'apply'; action = 'export'; exported_records = $candidateRecords.Count; export_manifest = (Join-Path $ExportRoot $exportManifestName); export_manifest_sha256 = $exportManifestHash })
  return
}

$transaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName ("records-purge-$ReceiptId") -FailAfterMutation $FailAfterMutation
try {
  Assert-PlanPreconditions $candidatePlan
  if ($needsExport) { Write-ExportBundle -Records $candidateRecords -Root $ExportRoot -ManifestJson $exportManifestJson -ManifestName $exportManifestName }
  foreach ($mutation in $mutations) {
    if ($mutation.action -eq 'remove') {
      $identity = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $mutation.artifact.full_path -Kind File
      Remove-LizardTransactionalItem -Path $mutation.artifact.full_path -Kind File -ExpectedIdentity $identity
    } else { Set-LizardTransactionalBytes -Path $mutation.artifact.full_path -Bytes ([byte[]]$mutation.bytes) }
  }
  Set-LizardTransactionalBytes -Path $receiptPath -Bytes ((New-Object Text.UTF8Encoding($false)).GetBytes($receiptJson))
  $result = Complete-LizardTransaction
} catch {
  $originalFailure = $_
  try { Undo-LizardTransaction | Out-Null }
  catch { throw (New-RecordsLifecycleException 'RECORDS_ROLLBACK_FAILED' "Original failure: $($originalFailure.Exception.Message) Rollback failure: $($_.Exception.Message)") }
  throw $originalFailure
}

Write-Output ([pscustomobject]@{ mode = 'apply'; action = 'purge'; receipt_id = $ReceiptId; deleted_records = $candidateRecords.Count; receipt_path = $receiptPath; receipt_sha256 = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $receiptPath; export_manifest_sha256 = if ($needsExport) { $exportManifestHash } else { $null }; transaction_id = $result.operation_id; mutations = $result.mutation_count })
