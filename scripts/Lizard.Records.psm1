Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.Plan.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')

$script:ArtifactClasses = @('memory', 'routing-decision', 'routing-execution', 'update-history', 'loop-events', 'loop-run-log')

function New-LizardRecordsException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['records_code'] = $Code
  return $exception
}

function Assert-LizardRecordsObject {
  param($Value, [string[]]$Required, [string[]]$Allowed, [string]$Label)
  if ($null -eq $Value -or $Value -isnot [System.Management.Automation.PSCustomObject]) { throw (New-LizardRecordsException 'RECORDS_SHAPE_INVALID' "$Label must be a JSON object.") }
  $names = @($Value.PSObject.Properties.Name)
  foreach ($name in $Required) { if ($names -notcontains $name) { throw (New-LizardRecordsException 'RECORDS_SHAPE_INVALID' "$Label is missing '$name'.") } }
  foreach ($name in $names) { if ($Allowed -notcontains $name) { throw (New-LizardRecordsException 'RECORDS_SHAPE_INVALID' "$Label contains unsupported property '$name'.") } }
}

function Test-LizardRecordsInteger {
  param($Value)
  return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64])
}

function ConvertTo-LizardRecordsTimestamp {
  [CmdletBinding()]
  param($Value, [string]$Label = 'timestamp')
  if ($Value -isnot [string]) { throw (New-LizardRecordsException 'RECORDS_TIMESTAMP_INVALID' "$Label must be an ISO-8601 string.") }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) { throw (New-LizardRecordsException 'RECORDS_TIMESTAMP_INVALID' "$Label is invalid.") }
  return $parsed.ToUniversalTime()
}

function Assert-LizardRetentionPolicyDocument {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$Policy, [DateTimeOffset]$AsOf = [DateTimeOffset]::UtcNow)
  $fields = @('schema_version', 'policy_id', 'version', 'owner_id', 'effective_from', 'review_due', 'default_disposition', 'artifact_classes')
  Assert-LizardRecordsObject $Policy $fields $fields 'Retention policy'
  if (-not (Test-LizardRecordsInteger $Policy.schema_version) -or [int64]$Policy.schema_version -ne 1) { throw (New-LizardRecordsException 'RETENTION_POLICY_SCHEMA_UNSUPPORTED' 'Retention policy schema_version must be integer 1.') }
  foreach ($name in @('policy_id', 'owner_id')) { if ($Policy.$name -isnot [string] -or [string]$Policy.$name -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:+-]{0,127}$') { throw (New-LizardRecordsException 'RETENTION_POLICY_ID_INVALID' "Policy $name is invalid.") } }
  if ($Policy.version -isnot [string] -or [string]$Policy.version -notmatch '^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$' -or [string]$Policy.default_disposition -ne 'retain') { throw (New-LizardRecordsException 'RETENTION_POLICY_INVALID' 'Policy version or default disposition is invalid.') }
  $effective = ConvertTo-LizardRecordsTimestamp $Policy.effective_from 'effective_from'
  $reviewDue = ConvertTo-LizardRecordsTimestamp $Policy.review_due 'review_due'
  if ($reviewDue -le $effective -or $AsOf.ToUniversalTime() -lt $effective) { throw (New-LizardRecordsException 'RETENTION_POLICY_NOT_EFFECTIVE' 'Retention policy is not effective at the evaluation time.') }
  if ($AsOf.ToUniversalTime() -ge $reviewDue) { throw (New-LizardRecordsException 'RETENTION_POLICY_REVIEW_OVERDUE' 'Retention policy review_due has been reached.') }
  if ($Policy.artifact_classes -isnot [System.Array]) { throw (New-LizardRecordsException 'RETENTION_POLICY_INVALID' 'artifact_classes must be a JSON array.') }
  $classes = @{}
  foreach ($rule in @($Policy.artifact_classes)) {
    $ruleFields = @('artifact_class', 'purpose', 'owner_id', 'retention_days', 'disposition', 'export_required')
    Assert-LizardRecordsObject $rule $ruleFields $ruleFields 'Retention class rule'
    $artifactClass = [string]$rule.artifact_class
    if ($script:ArtifactClasses -notcontains $artifactClass -or $classes.ContainsKey($artifactClass)) { throw (New-LizardRecordsException 'RETENTION_POLICY_CLASS_INVALID' "Artifact class '$artifactClass' is unsupported or duplicated.") }
    foreach ($name in @('purpose', 'owner_id')) { if ($rule.$name -isnot [string] -or [string]$rule.$name -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:+-]{0,127}$') { throw (New-LizardRecordsException 'RETENTION_POLICY_CLASS_INVALID' "Artifact class '$artifactClass' $name is invalid.") } }
    if (-not (Test-LizardRecordsInteger $rule.retention_days) -or [int64]$rule.retention_days -lt 1 -or [int64]$rule.retention_days -gt 3650 -or [string]$rule.disposition -ne 'delete-after-ttl' -or $rule.export_required -isnot [bool]) { throw (New-LizardRecordsException 'RETENTION_POLICY_CLASS_INVALID' "Artifact class '$artifactClass' retention or disposition is invalid.") }
    $classes[$artifactClass] = $rule
  }
  foreach ($artifactClass in $script:ArtifactClasses) { if (-not $classes.ContainsKey($artifactClass)) { throw (New-LizardRecordsException 'RETENTION_POLICY_CLASS_MISSING' "Policy is missing artifact class '$artifactClass'.") } }
  return [pscustomobject]@{ policy = $Policy; effective_from = $effective; review_due = $reviewDue; classes = $classes }
}

function Read-LizardRetentionPolicy {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ExpectedSha256, [DateTimeOffset]$AsOf = [DateTimeOffset]::UtcNow)
  if ($ExpectedSha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardRecordsException 'RETENTION_POLICY_DIGEST_INVALID' 'Expected policy SHA-256 must be lowercase hexadecimal.') }
  $full = ConvertTo-LizardFullPath -Path $Path
  $root = Resolve-SafeRoot -Path (Split-Path -Parent $full) -RequireExisting
  $safe = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath $full
  $actual = Get-SafeFileHash -AuthorizedRoot $root -Path $safe
  if ($actual -ne $ExpectedSha256) { throw (New-LizardRecordsException 'RETENTION_POLICY_DIGEST_MISMATCH' 'Retention policy bytes do not match the supplied SHA-256.') }
  try { $policy = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $root -Path $safe -Raw -MaximumBytes 1048576) }
  catch { if ($_.Exception.Data['records_code']) { throw }; throw (New-LizardRecordsException 'RETENTION_POLICY_JSON_INVALID' $_.Exception.Message) }
  $validated = Assert-LizardRetentionPolicyDocument -Policy $policy -AsOf $AsOf
  return [pscustomobject]@{ path = $safe; sha256 = $actual; policy = $validated.policy; classes = $validated.classes }
}

function Get-LizardRecordsHoldBinding {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$PolicyId, [Parameter(Mandatory = $true)][string]$PolicySha256, [Parameter(Mandatory = $true)][string]$TargetRootHash, [Parameter(Mandatory = $true)][DateTimeOffset]$AsOf)
  return Get-LizardPlanSha256 -InputObject ([pscustomobject][ordered]@{ schema_version = 1; policy_id = $PolicyId; policy_sha256 = $PolicySha256; target_root_hash = $TargetRootHash; as_of = $AsOf.ToUniversalTime().ToString('o') })
}

function Assert-LizardRecordsHoldPayload {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$Payload, [Parameter(Mandatory = $true)][string]$PolicyId, [Parameter(Mandatory = $true)][string]$PolicySha256, [Parameter(Mandatory = $true)][string]$TargetRootHash, [Parameter(Mandatory = $true)][DateTimeOffset]$AsOf)
  $fields = @('schema_version', 'artifact_kind', 'policy_id', 'policy_sha256', 'target_root_hash', 'effective_at', 'expires_at', 'holds')
  Assert-LizardRecordsObject $Payload $fields $fields 'Records hold payload'
  if (-not (Test-LizardRecordsInteger $Payload.schema_version) -or [int64]$Payload.schema_version -ne 1 -or [string]$Payload.artifact_kind -ne 'records-hold-register') { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' 'Hold payload schema or kind is invalid.') }
  if ([string]$Payload.policy_id -ne $PolicyId -or [string]$Payload.policy_sha256 -ne $PolicySha256 -or [string]$Payload.target_root_hash -ne $TargetRootHash) { throw (New-LizardRecordsException 'RECORDS_HOLD_CONTEXT_MISMATCH' 'Hold payload does not bind the selected policy and target.') }
  $effective = ConvertTo-LizardRecordsTimestamp $Payload.effective_at 'hold effective_at'
  $expires = ConvertTo-LizardRecordsTimestamp $Payload.expires_at 'hold expires_at'
  $clock = $AsOf.ToUniversalTime()
  if ($expires -le $effective -or $clock -lt $effective -or $clock -gt $expires) { throw (New-LizardRecordsException 'RECORDS_HOLD_EXPIRED' 'Hold register is not effective at the evaluation time.') }
  if ($Payload.holds -isnot [System.Array]) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' 'holds must be a JSON array.') }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($hold in @($Payload.holds)) {
    $holdFields = @('hold_id', 'scope', 'artifact_classes', 'record_ids', 'owner_id', 'reason_code', 'active_from', 'expires_at')
    Assert-LizardRecordsObject $hold $holdFields $holdFields 'Legal hold'
    if ($hold.hold_id -isnot [string] -or [string]$hold.hold_id -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:+-]{0,127}$' -or -not $seen.Add([string]$hold.hold_id)) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' 'Hold ID is invalid or duplicated.') }
    if ([string]$hold.scope -notin @('all', 'classes', 'records') -or $hold.artifact_classes -isnot [System.Array] -or $hold.record_ids -isnot [System.Array]) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Hold '$($hold.hold_id)' scope or selectors are invalid.") }
    foreach ($artifactClass in @($hold.artifact_classes)) { if ($artifactClass -isnot [string] -or $script:ArtifactClasses -notcontains [string]$artifactClass) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Hold '$($hold.hold_id)' contains invalid artifact class.") } }
    foreach ($recordId in @($hold.record_ids)) { if ($recordId -isnot [string] -or [string]$recordId -notmatch '^rec_[a-f0-9]{32}$') { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Hold '$($hold.hold_id)' contains invalid record ID.") } }
    if ([string]$hold.scope -eq 'all' -and (@($hold.artifact_classes).Count -ne 0 -or @($hold.record_ids).Count -ne 0)) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Global hold '$($hold.hold_id)' must not declare selectors.") }
    if ([string]$hold.scope -eq 'classes' -and (@($hold.artifact_classes).Count -eq 0 -or @($hold.record_ids).Count -ne 0)) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Class hold '$($hold.hold_id)' selectors are invalid.") }
    if ([string]$hold.scope -eq 'records' -and (@($hold.record_ids).Count -eq 0 -or @($hold.artifact_classes).Count -ne 0)) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Record hold '$($hold.hold_id)' selectors are invalid.") }
    $holdStart = ConvertTo-LizardRecordsTimestamp $hold.active_from "hold '$($hold.hold_id)' active_from"
    if ($null -ne $hold.expires_at) { $holdExpiry = ConvertTo-LizardRecordsTimestamp $hold.expires_at "hold '$($hold.hold_id)' expires_at"; if ($holdExpiry -le $holdStart) { throw (New-LizardRecordsException 'RECORDS_HOLD_INVALID' "Hold '$($hold.hold_id)' expiry is invalid.") } }
  }
  return $Payload
}

function Test-LizardRecordHeld {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$HoldPayload, [Parameter(Mandatory = $true)][string]$ArtifactClass, [Parameter(Mandatory = $true)][string]$RecordId, [Parameter(Mandatory = $true)][DateTimeOffset]$AsOf)
  $clock = $AsOf.ToUniversalTime()
  foreach ($hold in @($HoldPayload.holds)) {
    $start = ConvertTo-LizardRecordsTimestamp $hold.active_from 'hold active_from'
    if ($clock -lt $start) { continue }
    if ($null -ne $hold.expires_at -and $clock -gt (ConvertTo-LizardRecordsTimestamp $hold.expires_at 'hold expires_at')) { continue }
    if ([string]$hold.scope -eq 'all' -or ([string]$hold.scope -eq 'classes' -and @($hold.artifact_classes) -contains $ArtifactClass) -or ([string]$hold.scope -eq 'records' -and @($hold.record_ids) -contains $RecordId)) { return $true }
  }
  return $false
}

function New-LizardRecordId {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$ArtifactClass, [Parameter(Mandatory = $true)][string]$RelativePath, [string]$Locator = 'file')
  $hash = Get-LizardPlanSha256 -CanonicalJson ("records-v1|{0}|{1}|{2}" -f $ArtifactClass, $RelativePath.Replace('\', '/'), $Locator)
  return 'rec_' + $hash.Substring(0, 32)
}

Export-ModuleMember -Function @(
  'Assert-LizardRecordsHoldPayload', 'Assert-LizardRetentionPolicyDocument', 'ConvertTo-LizardRecordsTimestamp',
  'Get-LizardRecordsHoldBinding', 'New-LizardRecordId', 'Read-LizardRetentionPolicy', 'Test-LizardRecordHeld'
)
