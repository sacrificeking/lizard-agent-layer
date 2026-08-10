Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')

function New-LizardPlanException {
  param([Parameter(Mandatory = $true)][string]$Code, [Parameter(Mandatory = $true)][string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['plan_code'] = $Code
  return $exception
}

function ConvertTo-LizardCanonicalJsonString {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) { $Value = '' }
  $builder = New-Object System.Text.StringBuilder
  $null = $builder.Append('"')
  foreach ($character in $Value.ToCharArray()) {
    $code = [int][char]$character
    if ($code -eq 8) { $null = $builder.Append('\b') }
    elseif ($code -eq 9) { $null = $builder.Append('\t') }
    elseif ($code -eq 10) { $null = $builder.Append('\n') }
    elseif ($code -eq 12) { $null = $builder.Append('\f') }
    elseif ($code -eq 13) { $null = $builder.Append('\r') }
    elseif ($code -eq 34) { $null = $builder.Append('\"') }
    elseif ($code -eq 92) { $null = $builder.Append('\\') }
    elseif ($code -lt 32) { $null = $builder.Append(('\u{0:x4}' -f $code)) }
    else { $null = $builder.Append($character) }
  }
  $null = $builder.Append('"')
  return $builder.ToString()
}

function Test-LizardPlanInteger {
  param($Value)
  return ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64])
}

function ConvertTo-LizardCanonicalJsonValue {
  param($Value)
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [bool]) { if ($Value) { return 'true' } else { return 'false' } }
  if ($Value -is [string] -or $Value -is [char]) { return ConvertTo-LizardCanonicalJsonString -Value ([string]$Value) }
  if (Test-LizardPlanInteger $Value) { return ([System.Convert]::ToString($Value, [System.Globalization.CultureInfo]::InvariantCulture)) }
  if ($Value -is [System.Collections.IDictionary]) {
    $map = @{}
    $keys = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Value.Keys) {
      if ($key -isnot [string]) { throw (New-LizardPlanException -Code 'PLAN_CANONICAL_KEY_INVALID' -Message 'Canonical JSON object keys must be strings.') }
      if ($map.ContainsKey([string]$key)) { throw (New-LizardPlanException -Code 'PLAN_CANONICAL_KEY_DUPLICATE' -Message "Duplicate canonical JSON key '$key'.") }
      $map[[string]$key] = $Value[$key]
      $keys.Add([string]$key) | Out-Null
    }
    $orderedKeys = $keys.ToArray()
    [Array]::Sort($orderedKeys, [System.StringComparer]::Ordinal)
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $orderedKeys) { $parts.Add(("{0}:{1}" -f (ConvertTo-LizardCanonicalJsonString $key), (ConvertTo-LizardCanonicalJsonValue $map[$key]))) | Out-Null }
    return '{' + (@($parts.ToArray()) -join ',') + '}'
  }
  if ($Value -is [System.Array] -or $Value -is [System.Collections.IList]) {
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($item in $Value) { $parts.Add((ConvertTo-LizardCanonicalJsonValue $item)) | Out-Null }
    return '[' + (@($parts.ToArray()) -join ',') + ']'
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $map = @{}
    foreach ($property in @($Value.PSObject.Properties)) {
      if ($map.ContainsKey([string]$property.Name)) { throw (New-LizardPlanException -Code 'PLAN_CANONICAL_KEY_DUPLICATE' -Message "Duplicate canonical JSON key '$($property.Name)'.") }
      $map[[string]$property.Name] = $property.Value
    }
    return ConvertTo-LizardCanonicalJsonValue $map
  }
  throw (New-LizardPlanException -Code 'PLAN_CANONICAL_TYPE_UNSUPPORTED' -Message ("Unsupported canonical JSON value type: {0}. Only objects, arrays, strings, integers, booleans, and null are allowed." -f $Value.GetType().FullName))
}

function ConvertTo-LizardCanonicalJson {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true, ValueFromPipeline = $true)]$InputObject)
  process { return ConvertTo-LizardCanonicalJsonValue $InputObject }
}

function Get-LizardPlanSha256 {
  [CmdletBinding(DefaultParameterSetName = 'InputObject')]
  param(
    [Parameter(Mandatory = $true, ParameterSetName = 'InputObject')]$InputObject,
    [Parameter(Mandatory = $true, ParameterSetName = 'CanonicalJson')][string]$CanonicalJson
  )
  $value = if ($PSCmdlet.ParameterSetName -eq 'CanonicalJson') { $CanonicalJson } else { ConvertTo-LizardCanonicalJson $InputObject }
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-LizardSourceGitHead {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Root)
  $resolvedRoot = Resolve-SafeRoot -Path $Root -RequireExisting
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& git -C $resolvedRoot rev-parse --verify HEAD 2>$null)
    $exitCode = [int]$LASTEXITCODE
  } catch {
    return $null
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  if ($exitCode -ne 0 -or $output.Count -eq 0) { return $null }
  $head = ([string]$output[0]).Trim().ToLowerInvariant()
  if ($head -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$') {
    throw (New-LizardPlanException -Code 'PLAN_BINDING_SOURCE_INVALID' -Message 'Git returned an invalid source HEAD identity.')
  }
  return $head
}

function Get-LizardPlanRootHash {
  param([Parameter(Mandatory = $true)][string]$TargetRoot)
  $root = ConvertTo-LizardFullPath -Path $TargetRoot
  if ((Get-LizardPathComparison) -eq [System.StringComparison]::OrdinalIgnoreCase) { $root = $root.ToLowerInvariant() }
  return Get-LizardPlanSha256 -CanonicalJson ("target-root-v1|{0}" -f $root.Replace('\', '/'))
}

function Assert-LizardPlanProperties {
  param($Document, [string[]]$Required, [string[]]$Allowed, [string]$Label)
  if ($null -eq $Document -or $Document -isnot [System.Management.Automation.PSCustomObject]) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message "$Label must be a JSON object.") }
  $names = @($Document.PSObject.Properties.Name)
  foreach ($name in $Required) { if ($names -notcontains $name) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message "$Label is missing '$name'.") } }
  foreach ($name in $names) { if ($Allowed -notcontains $name) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message "$Label contains unsupported property '$name'.") } }
}

function Test-LizardPlanTimestamp {
  param($Value, [ref]$Parsed)
  if ($Value -isnot [string]) { return $false }
  $timestamp = [DateTimeOffset]::MinValue
  $valid = [DateTimeOffset]::TryParseExact([string]$Value, 'o', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)
  if ($valid) { $Parsed.Value = $timestamp }
  return $valid
}

function Test-LizardPlanRelativePath {
  param($Value)
  if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value) -or ([string]$Value).Length -gt 1000) { return $false }
  $path = [string]$Value
  if ([System.IO.Path]::IsPathRooted($path) -or $path -match '^[A-Za-z]:' -or $path -match '[\\:\x00-\x1f]' -or $path.StartsWith('/') -or $path.EndsWith('/')) { return $false }
  foreach ($segment in @($path.Split('/'))) { if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..')) { return $false } }
  return $true
}

function ConvertTo-LizardPlanInput {
  param($InputRecord)
  if ($InputRecord -is [System.Collections.IDictionary]) { $InputRecord = [pscustomobject]$InputRecord }
  $required = @('scope', 'path', 'sha256')
  Assert-LizardPlanProperties -Document $InputRecord -Required $required -Allowed $required -Label 'Plan input'
  if ($InputRecord.scope -isnot [string] -or [string]$InputRecord.scope -notin @('layer', 'target')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_INPUT_INVALID' -Message 'Input scope must be layer or target.') }
  if (-not (Test-LizardPlanRelativePath $InputRecord.path)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_INPUT_INVALID' -Message "Input '$($InputRecord.path)' path is invalid.") }
  if ($InputRecord.sha256 -isnot [string] -or [string]$InputRecord.sha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardPlanException -Code 'PLAN_BINDING_INPUT_INVALID' -Message "Input '$($InputRecord.path)' hash is invalid.") }
  return [pscustomobject][ordered]@{ scope = [string]$InputRecord.scope; path = [string]$InputRecord.path; sha256 = [string]$InputRecord.sha256 }
}

function ConvertTo-LizardPlanTargetEntry {
  param($Entry)
  if ($Entry -is [System.Collections.IDictionary]) { $Entry = [pscustomobject]$Entry }
  $required = @('path', 'kind', 'action', 'precondition_kind', 'precondition_sha256', 'ownership', 'intended_sha256')
  Assert-LizardPlanProperties -Document $Entry -Required $required -Allowed $required -Label 'Plan target entry'
  if (-not (Test-LizardPlanRelativePath $Entry.path)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message 'Target entry path is invalid.') }
  if ($Entry.kind -isnot [string] -or [string]$Entry.kind -notin @('file', 'directory')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Target '$($Entry.path)' kind is invalid.") }
  if ($Entry.action -isnot [string] -or [string]$Entry.action -notin @('create', 'replace', 'preserve')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Target '$($Entry.path)' action is invalid.") }
  if ($Entry.precondition_kind -isnot [string] -or [string]$Entry.precondition_kind -notin @('absent', 'file', 'directory', 'other')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Target '$($Entry.path)' precondition kind is invalid.") }
  if ($Entry.ownership -isnot [string] -or [string]$Entry.ownership -notin @('unmanaged', 'layer-owned', 'user-owned', 'adopted')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Target '$($Entry.path)' ownership is invalid.") }
  foreach ($hashName in @('precondition_sha256', 'intended_sha256')) { $hash = $Entry.$hashName; if ($null -ne $hash -and ($hash -isnot [string] -or [string]$hash -notmatch '^[a-f0-9]{64}$')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Target '$($Entry.path)' $hashName is invalid.") } }
  if ([string]$Entry.precondition_kind -eq 'file' -and $null -eq $Entry.precondition_sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Existing file target '$($Entry.path)' requires a precondition hash.") }
  if ([string]$Entry.precondition_kind -ne 'file' -and $null -ne $Entry.precondition_sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Non-file target '$($Entry.path)' must not declare a precondition hash.") }
  if ([string]$Entry.kind -eq 'directory' -and $null -ne $Entry.intended_sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Directory target '$($Entry.path)' must not declare a file hash.") }
  return [pscustomobject][ordered]@{ path = [string]$Entry.path; kind = [string]$Entry.kind; action = [string]$Entry.action; precondition_kind = [string]$Entry.precondition_kind; precondition_sha256 = $Entry.precondition_sha256; ownership = [string]$Entry.ownership; intended_sha256 = $Entry.intended_sha256 }
}

function ConvertTo-LizardNestedPlanReference {
  param($NestedPlan)
  if ($null -eq $NestedPlan) { return $null }
  if ($NestedPlan -is [System.Collections.IDictionary]) { $NestedPlan = [pscustomobject]$NestedPlan }
  $names = @($NestedPlan.PSObject.Properties.Name)
  if ($names -contains 'intent') {
    Assert-LizardOperationPlanDocument -Plan $NestedPlan | Out-Null
    return [pscustomobject][ordered]@{ plan_id = [string]$NestedPlan.plan_id; operation_kind = [string]$NestedPlan.operation_kind; sha256 = Get-LizardPlanSha256 -InputObject $NestedPlan; intent_sha256 = [string]$NestedPlan.intent_sha256 }
  }
  $required = @('plan_id', 'operation_kind', 'sha256', 'intent_sha256')
  Assert-LizardPlanProperties -Document $NestedPlan -Required $required -Allowed $required -Label 'Nested plan reference'
  if ([string]$NestedPlan.plan_id -notmatch '^[a-f0-9]{32}$' -or [string]$NestedPlan.operation_kind -notin @('install', 'update') -or [string]$NestedPlan.sha256 -notmatch '^[a-f0-9]{64}$' -or [string]$NestedPlan.intent_sha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardPlanException -Code 'PLAN_BINDING_NESTED_INVALID' -Message 'Nested plan reference is invalid.') }
  return [pscustomobject][ordered]@{ plan_id = [string]$NestedPlan.plan_id; operation_kind = [string]$NestedPlan.operation_kind; sha256 = [string]$NestedPlan.sha256; intent_sha256 = [string]$NestedPlan.intent_sha256 }
}

function Get-LizardPlanIntentSha256 {
  [CmdletBinding(DefaultParameterSetName = 'Plan')]
  param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Plan')]$Plan,
    [Parameter(Mandatory = $true, ParameterSetName = 'Intent')]$Intent
  )
  $value = if ($PSCmdlet.ParameterSetName -eq 'Intent') { $Intent } else {
    if ($null -eq $Plan -or $Plan.PSObject.Properties.Name -notcontains 'intent') { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message 'Plan has no intent object.') }
    $Plan.intent
  }
  return Get-LizardPlanSha256 -InputObject $value
}

function Assert-LizardOperationPlanDocument {
  param($Plan)
  $planRequired = @('schema_version', 'plan_id', 'operation_kind', 'created_at', 'expires_at', 'intent_sha256', 'intent')
  Assert-LizardPlanProperties -Document $Plan -Required $planRequired -Allowed $planRequired -Label 'Operation plan'
  if (-not (Test-LizardPlanInteger $Plan.schema_version) -or [int64]$Plan.schema_version -ne 1) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SCHEMA_UNSUPPORTED' -Message 'Operation plan schema_version must be integer 1.') }
  if ($Plan.plan_id -isnot [string] -or [string]$Plan.plan_id -notmatch '^[a-f0-9]{32}$') { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message 'Plan ID is invalid.') }
  if ($Plan.operation_kind -isnot [string] -or [string]$Plan.operation_kind -notin @('install', 'update')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_OPERATION_INVALID' -Message 'Plan operation kind is invalid.') }
  $created = [DateTimeOffset]::MinValue; $expires = [DateTimeOffset]::MinValue
  if (-not (Test-LizardPlanTimestamp $Plan.created_at ([ref]$created)) -or -not (Test-LizardPlanTimestamp $Plan.expires_at ([ref]$expires)) -or $expires -le $created) { throw (New-LizardPlanException -Code 'PLAN_BINDING_EXPIRY_INVALID' -Message 'Plan timestamps are invalid or non-increasing.') }
  if ($Plan.intent_sha256 -isnot [string] -or [string]$Plan.intent_sha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardPlanException -Code 'PLAN_BINDING_INTENT_INVALID' -Message 'Plan intent hash is invalid.') }
  $intentRequired = @('target_root', 'target_root_hash', 'layer_root', 'layer_version', 'source_git_head', 'options', 'inputs', 'target_entries', 'nested_plan')
  Assert-LizardPlanProperties -Document $Plan.intent -Required $intentRequired -Allowed $intentRequired -Label 'Plan intent'
  if ($Plan.intent.target_root -isnot [string] -or $Plan.intent.layer_root -isnot [string] -or $Plan.intent.layer_version -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Plan.intent.layer_version)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message 'Plan roots and layer version must be strings.') }
  $targetRoot = ConvertTo-LizardFullPath ([string]$Plan.intent.target_root); $layerRoot = ConvertTo-LizardFullPath ([string]$Plan.intent.layer_root)
  if ([string]$Plan.intent.target_root -ne $targetRoot -or [string]$Plan.intent.layer_root -ne $layerRoot) { throw (New-LizardPlanException -Code 'PLAN_BINDING_ROOT_INVALID' -Message 'Plan roots must be canonical absolute paths.') }
  if ($Plan.intent.target_root_hash -isnot [string] -or [string]$Plan.intent.target_root_hash -ne (Get-LizardPlanRootHash $targetRoot)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_ROOT_MISMATCH' -Message 'Plan target root identity is invalid.') }
  if ($null -ne $Plan.intent.source_git_head -and ($Plan.intent.source_git_head -isnot [string] -or [string]$Plan.intent.source_git_head -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SOURCE_INVALID' -Message 'Plan source Git identity is invalid.') }
  if ($null -eq $Plan.intent.options -or $Plan.intent.options -isnot [System.Management.Automation.PSCustomObject] -or $Plan.intent.inputs -isnot [System.Array] -or $Plan.intent.target_entries -isnot [System.Array]) { throw (New-LizardPlanException -Code 'PLAN_BINDING_SHAPE_INVALID' -Message 'Plan options, inputs, or target entries have invalid JSON types.') }
  ConvertTo-LizardCanonicalJson $Plan.intent.options | Out-Null
  $inputIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($inputRecord in @($Plan.intent.inputs)) { $normalized = ConvertTo-LizardPlanInput $inputRecord; $inputKey = "{0}:{1}" -f $normalized.scope, $normalized.path; if (-not $inputIds.Add($inputKey)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_INPUT_INVALID' -Message "Duplicate input '$inputKey'.") } }
  $targetPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($entry in @($Plan.intent.target_entries)) { $normalized = ConvertTo-LizardPlanTargetEntry $entry; if (-not $targetPaths.Add([string]$normalized.path)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Duplicate target path '$($normalized.path)'.") } }
  ConvertTo-LizardNestedPlanReference $Plan.intent.nested_plan | Out-Null
  $actualIntent = Get-LizardPlanIntentSha256 -Intent $Plan.intent
  if ($actualIntent -ne [string]$Plan.intent_sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_INTENT_INVALID' -Message 'Plan intent hash does not match its canonical intent.') }
  return [pscustomobject]@{ created_at = $created; expires_at = $expires; target_root = $targetRoot; layer_root = $layerRoot }
}

function New-LizardOperationPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][ValidateSet('install', 'update')][string]$OperationKind,
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [Parameter(Mandatory = $true)][string]$LayerRoot,
    [Parameter(Mandatory = $true)]$Options,
    [Parameter(Mandatory = $true)][object[]]$Inputs,
    [Parameter(Mandatory = $true)][object[]]$TargetEntries,
    [AllowNull()]$NestedPlan = $null,
    [ValidateRange(1, 1440)][int]$TtlMinutes = 30,
    [AllowNull()][string]$LayerVersion,
    [AllowNull()][Alias('GitHead')][string]$SourceGitHead
  )
  $target = Resolve-SafeRoot -Path $TargetRoot -RequireExisting
  $layer = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
  if ($null -eq $Options -or ($Options -isnot [System.Management.Automation.PSCustomObject] -and $Options -isnot [System.Collections.IDictionary])) { throw (New-LizardPlanException -Code 'PLAN_BINDING_OPTIONS_INVALID' -Message 'Options must be a JSON object.') }
  $optionsCopy = ConvertFrom-LizardJson -InputObject (ConvertTo-LizardCanonicalJson $Options)
  $normalizedInputs = New-Object System.Collections.Generic.List[object]
  $inputIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($inputRecord in @($Inputs)) { $normalized = ConvertTo-LizardPlanInput $inputRecord; $inputKey = "{0}:{1}" -f $normalized.scope, $normalized.path; if (-not $inputIds.Add($inputKey)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_INPUT_INVALID' -Message "Duplicate input '$inputKey'.") }; $normalizedInputs.Add($normalized) | Out-Null }
  $normalizedTargets = New-Object System.Collections.Generic.List[object]
  $targetPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($entry in @($TargetEntries)) { $normalized = ConvertTo-LizardPlanTargetEntry $entry; if (-not $targetPaths.Add([string]$normalized.path)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TARGET_INVALID' -Message "Duplicate target path '$($normalized.path)'.") }; $normalizedTargets.Add($normalized) | Out-Null }
  $versionPath = Join-Path $layer 'VERSION'
  if ([string]::IsNullOrWhiteSpace($LayerVersion)) {
    try { $LayerVersion = (Get-SafeContent -AuthorizedRoot $layer -Path $versionPath -Raw).Trim() }
    catch { throw (New-LizardPlanException -Code 'PLAN_BINDING_LAYER_VERSION_MISSING' -Message $_.Exception.Message) }
  }
  if ([string]::IsNullOrWhiteSpace($LayerVersion)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_LAYER_VERSION_MISSING' -Message 'Layer VERSION is empty.') }
  if (-not [string]::IsNullOrWhiteSpace($SourceGitHead) -and $SourceGitHead -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$') { throw (New-LizardPlanException -Code 'PLAN_BINDING_SOURCE_INVALID' -Message 'Source Git identity must be a lowercase 40- or 64-character object ID.') }
  $created = [DateTimeOffset]::UtcNow
  $intent = [pscustomobject][ordered]@{
    target_root = $target
    target_root_hash = Get-LizardPlanRootHash $target
    layer_root = $layer
    layer_version = $LayerVersion
    source_git_head = if ([string]::IsNullOrWhiteSpace($SourceGitHead)) { $null } else { $SourceGitHead }
    options = $optionsCopy
    inputs = @($normalizedInputs.ToArray())
    target_entries = @($normalizedTargets.ToArray())
    nested_plan = ConvertTo-LizardNestedPlanReference $NestedPlan
  }
  $plan = [pscustomobject][ordered]@{
    schema_version = 1
    plan_id = [Guid]::NewGuid().ToString('N')
    operation_kind = $OperationKind
    created_at = $created.ToString('o')
    expires_at = $created.AddMinutes($TtlMinutes).ToString('o')
    intent_sha256 = Get-LizardPlanIntentSha256 -Intent $intent
    intent = $intent
  }
  Assert-LizardOperationPlanDocument $plan | Out-Null
  return $plan
}

function Write-LizardOperationPlan {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Plan,
    [Alias('ParentRoot')][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][Alias('PlanPath')][string]$Path
  )
  Assert-LizardOperationPlanDocument $Plan | Out-Null
  $fullRequested = ConvertTo-LizardFullPath -Path $Path
  $effectiveRoot = if ([string]::IsNullOrWhiteSpace($AuthorizedRoot)) { Split-Path -Parent $fullRequested } else { $AuthorizedRoot }
  $root = Resolve-SafeRoot -Path $effectiveRoot -RequireExisting
  $candidate = if ([string]::IsNullOrWhiteSpace($AuthorizedRoot)) {
    $fullRequested
  } elseif ([System.IO.Path]::IsPathRooted($Path)) {
    $Path
  } else {
    Join-Path $root $Path
  }
  $destination = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath $candidate
  $digestPath = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath ($destination + '.sha256')
  if (Test-Path -LiteralPath $destination) { throw (New-LizardPlanException -Code 'PLAN_BINDING_FILE_EXISTS' -Message "Refusing to replace existing plan: $destination") }
  if (Test-Path -LiteralPath $digestPath) { throw (New-LizardPlanException -Code 'PLAN_BINDING_FILE_EXISTS' -Message "Refusing to replace existing digest sidecar: $digestPath") }
  $canonical = ConvertTo-LizardCanonicalJson $Plan
  $digest = Get-LizardPlanSha256 -CanonicalJson $canonical
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($canonical)
  $stream = $null
  try {
    $stream = New-Object System.IO.FileStream($destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
  } catch { throw (New-LizardPlanException -Code 'PLAN_BINDING_WRITE_FAILED' -Message $_.Exception.Message) }
  finally { if ($null -ne $stream) { $stream.Dispose() } }
  $digestStream = $null
  try {
    $digestBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($digest + "`n")
    $digestStream = New-Object System.IO.FileStream($digestPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $digestStream.Write($digestBytes, 0, $digestBytes.Length)
    $digestStream.Flush($true)
  } catch { throw (New-LizardPlanException -Code 'PLAN_BINDING_WRITE_FAILED' -Message $_.Exception.Message) }
  finally { if ($null -ne $digestStream) { $digestStream.Dispose() } }
  return [pscustomobject]@{ path = $destination; sha256 = $digest; sha256_path = $digestPath }
}

function Read-LizardApprovedPlan {
  [CmdletBinding()]
  param(
    [Alias('ParentRoot')][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][Alias('PlanPath')][string]$Path,
    [Parameter(Mandatory = $true)][Alias('PlanSha256', 'ExpectedSha256')][string]$Sha256,
    [Parameter(Mandatory = $true)][Alias('ExpectedOperationKind')][ValidateSet('install', 'update')][string]$OperationKind,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow,
    [ValidateRange(1024, 16777216)][int]$MaximumBytes = 8388608
  )
  if ($Sha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardPlanException -Code 'PLAN_BINDING_DIGEST_INVALID' -Message 'Approved plan digest must be lowercase SHA-256.') }
  $fullRequested = ConvertTo-LizardFullPath -Path $Path
  $effectiveRoot = if ([string]::IsNullOrWhiteSpace($AuthorizedRoot)) { Split-Path -Parent $fullRequested } else { $AuthorizedRoot }
  $root = Resolve-SafeRoot -Path $effectiveRoot -RequireExisting
  $candidate = if ([string]::IsNullOrWhiteSpace($AuthorizedRoot)) {
    $fullRequested
  } elseif ([System.IO.Path]::IsPathRooted($Path)) {
    $Path
  } else {
    Join-Path $root $Path
  }
  $metadataBefore = Get-SafeFileMetadata -AuthorizedRoot $root -Path $candidate
  if ([int64]$metadataBefore.length -gt $MaximumBytes) { throw (New-LizardPlanException -Code 'PLAN_BINDING_TOO_LARGE' -Message "Approved plan exceeds $MaximumBytes bytes.") }
  $bytes = [System.IO.File]::ReadAllBytes([string]$metadataBefore.path)
  $metadataAfter = Get-SafeFileMetadata -AuthorizedRoot $root -Path ([string]$metadataBefore.path)
  if ([int64]$metadataBefore.length -ne [int64]$metadataAfter.length -or [string]$metadataBefore.last_write_utc -ne [string]$metadataAfter.last_write_utc) { throw (New-LizardPlanException -Code 'PLAN_BINDING_CHANGED_DURING_READ' -Message 'Approved plan changed while being read.') }
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw (New-LizardPlanException -Code 'PLAN_BINDING_NONCANONICAL' -Message 'Approved plan must be UTF-8 without BOM.') }
  try { $raw = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) }
  catch { throw (New-LizardPlanException -Code 'PLAN_BINDING_UTF8_INVALID' -Message $_.Exception.Message) }
  $computed = Get-LizardPlanSha256 -CanonicalJson $raw
  if ($computed -ne $Sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_DIGEST_MISMATCH' -Message 'Approved plan bytes do not match the supplied SHA-256.') }
  try { $plan = ConvertFrom-LizardJson -InputObject $raw }
  catch { throw (New-LizardPlanException -Code 'PLAN_BINDING_JSON_INVALID' -Message $_.Exception.Message) }
  $shape = Assert-LizardOperationPlanDocument $plan
  $canonical = ConvertTo-LizardCanonicalJson $plan
  if (-not $raw.Equals($canonical, [System.StringComparison]::Ordinal)) { throw (New-LizardPlanException -Code 'PLAN_BINDING_NONCANONICAL' -Message 'Approved plan bytes are not the unique canonical JSON representation.') }
  if ([string]$plan.operation_kind -ne $OperationKind) { throw (New-LizardPlanException -Code 'PLAN_BINDING_OPERATION_MISMATCH' -Message "Approved plan is '$($plan.operation_kind)', not '$OperationKind'.") }
  if ($shape.expires_at -le $Now.ToUniversalTime()) { throw (New-LizardPlanException -Code 'PLAN_BINDING_EXPIRED' -Message "Approved plan expired at $($plan.expires_at).") }
  return $plan
}

function Assert-LizardPlanIntentMatch {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$ApprovedPlan, [Parameter(Mandatory = $true)][Alias('CurrentPlan')]$CandidatePlan)
  Assert-LizardOperationPlanDocument $ApprovedPlan | Out-Null
  Assert-LizardOperationPlanDocument $CandidatePlan | Out-Null
  if ([string]$ApprovedPlan.operation_kind -ne [string]$CandidatePlan.operation_kind) { throw (New-LizardPlanException -Code 'PLAN_BINDING_OPERATION_MISMATCH' -Message 'Approved and candidate operation kinds differ.') }
  $approvedHash = Get-LizardPlanIntentSha256 -Plan $ApprovedPlan
  $candidateHash = Get-LizardPlanIntentSha256 -Plan $CandidatePlan
  if ($approvedHash -ne [string]$ApprovedPlan.intent_sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_APPROVED_INTENT_INVALID' -Message 'Approved plan intent declaration is invalid.') }
  if ($candidateHash -ne [string]$CandidatePlan.intent_sha256) { throw (New-LizardPlanException -Code 'PLAN_BINDING_CANDIDATE_INTENT_INVALID' -Message 'Candidate plan intent declaration is invalid.') }
  if ($approvedHash -ne $candidateHash) { throw (New-LizardPlanException -Code 'PLAN_BINDING_INTENT_MISMATCH' -Message 'Candidate intent differs from the approved intent.') }
  return $approvedHash
}

Export-ModuleMember -Function @(
  'Assert-LizardPlanIntentMatch',
  'ConvertTo-LizardCanonicalJson',
  'Get-LizardPlanIntentSha256',
  'Get-LizardPlanSha256',
  'Get-LizardSourceGitHead',
  'New-LizardOperationPlan',
  'Read-LizardApprovedPlan',
  'Write-LizardOperationPlan'
)
