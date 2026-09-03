param(
  [string]$TargetPath = (Get-Location).Path,
  [ValidateSet('managed-only', 'complete', 'export-then-complete')][string]$Scope = 'managed-only',
  [switch]$Apply,
  [string]$PlanPath,
  [string]$CanonicalPlanPath,
  [string]$ReceiptPath,
  [string]$ApprovedPlanPath,
  [string]$ApprovedPlanSha256,
  [ValidateSet('summary', 'digest', 'signed')]
  [string]$PlanApprovalMode = 'summary',
  [switch]$HumanApproved,
  [switch]$RequireSignedApproval,
  [string]$ApprovalEnvelopePath,
  [string]$TrustStorePath,
  [string]$TrustStoreSha256,
  [string]$ChallengePath,
  [string]$ChallengeSha256,
  [string]$ReplayLedgerPath,
  [switch]$ConfirmModifiedLayerOwnedPurge,
  [string]$ExportPath,
  [string[]]$ExportRelativePaths,
  [switch]$ConfirmExportMayContainSensitiveData,
  [ValidateRange(1, 1440)][int]$PlanTtlMinutes = 60,
  [ValidateRange(0, 1000000)][int]$TestFailAfterMutation = 0,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Manifest.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Plan.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force

$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$VersionPath = Join-Path $LayerRoot 'VERSION'
$LayerVersion = (Get-SafeContent -AuthorizedRoot $LayerRoot -Path $VersionPath -Raw).Trim()
$ManifestRelativePath = '.agent/lizard-agent-layer.install.json'
$ManifestPath = Join-Path $TargetRoot ($ManifestRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))

function Expand-UninstallValueList {
  param($Values)
  $expanded = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in @(([string]$value).Split(','))) {
      $trimmed = $part.Trim()
      if (-not [string]::IsNullOrWhiteSpace($trimmed) -and -not $expanded.Contains($trimmed)) { $expanded.Add($trimmed) | Out-Null }
    }
  }
  return @($expanded.ToArray())
}
$ExportRelativePaths = @(Expand-UninstallValueList $ExportRelativePaths)

$ApprovedPlan = $null
if ($Apply) {
  if ([string]::IsNullOrWhiteSpace($ApprovedPlanPath) -or -not $HumanApproved) {
    throw 'PLAN_APPROVAL_REQUIRED: Uninstall -Apply requires -ApprovedPlanPath and -HumanApproved.'
  }
  if ($PlanApprovalMode -eq 'digest' -and [string]::IsNullOrWhiteSpace($ApprovedPlanSha256)) {
    throw 'PLAN_APPROVAL_REQUIRED: -PlanApprovalMode digest requires -ApprovedPlanSha256.'
  }
  Assert-PathOutsideRoot -Path $ApprovedPlanPath -ExcludedRoot $TargetRoot -Label 'ApprovedPlanPath'
  $ApprovedPlan = Read-LizardApprovedPlan -Path $ApprovedPlanPath -Sha256 $ApprovedPlanSha256 -ExpectedOperationKind uninstall
  if ([string]::IsNullOrWhiteSpace($ApprovedPlanSha256)) {
    $planFull = ConvertTo-LizardFullPath -Path $ApprovedPlanPath
    $planDir = Split-Path -Parent $planFull
    $planSafeRoot = Resolve-SafeRoot -Path $planDir -RequireExisting
    $ApprovedPlanSha256 = Get-SafeFileHash -AuthorizedRoot $planSafeRoot -Path $planFull
  }
  $manifestRisk = if ($ApprovedPlan.intent.risk_level) { [string]$ApprovedPlan.intent.risk_level } else { 'medium' }
  $approvalPolicy = Get-LizardOperationApprovalPolicy `
    -OperationKind 'uninstall' `
    -RiskLevel $manifestRisk `
    -Scope $Scope `
    -ApprovalMode $PlanApprovalMode `
    -RequireSignedApproval:$RequireSignedApproval

  if ($approvalPolicy.signed_approval_required) {
    if ([string]::IsNullOrWhiteSpace($ApprovalEnvelopePath) -or [string]::IsNullOrWhiteSpace($TrustStorePath) -or [string]::IsNullOrWhiteSpace($TrustStoreSha256) -or [string]::IsNullOrWhiteSpace($ChallengePath) -or [string]::IsNullOrWhiteSpace($ChallengeSha256)) {
      throw "PLAN_SIGNED_APPROVAL_REQUIRED: Signed apply approval is mandatory for this operation ($($approvalPolicy.reason)). Use scripts/new-approval.ps1 to generate approval materials."
    }
    if ([string]::IsNullOrWhiteSpace($ReplayLedgerPath)) {
      throw 'PLAN_REPLAY_LEDGER_REQUIRED: A replay ledger path is mandatory for signed apply approval verification.'
    }
    Assert-LizardPlanApprovalSignature `
      -ApprovedPlan $ApprovedPlan `
      -PlanSha256 $ApprovedPlanSha256 `
      -ApprovalEnvelopePath $ApprovalEnvelopePath `
      -TrustStorePath $TrustStorePath `
      -TrustStoreSha256 $TrustStoreSha256 `
      -ChallengePath $ChallengePath `
      -ChallengeSha256 $ChallengeSha256 `
      -ReplayLedgerPath $ReplayLedgerPath `
      -TargetRoot $TargetRoot | Out-Null
  }
  if ([string]$ApprovedPlan.intent.options.scope -ne $Scope) { throw 'PLAN_BINDING_OPTIONS_MISMATCH: Approved uninstall scope differs from the current invocation.' }
  if ([bool]$ApprovedPlan.intent.options.confirm_modified_layer_owned_purge -ne $ConfirmModifiedLayerOwnedPurge.IsPresent) { throw 'PLAN_BINDING_OPTIONS_MISMATCH: Modified-content purge confirmation differs from the approved plan.' }
  if ([bool]$ApprovedPlan.intent.options.confirm_export_may_contain_sensitive_data -ne $ConfirmExportMayContainSensitiveData.IsPresent) { throw 'PLAN_BINDING_OPTIONS_MISMATCH: Export sensitivity confirmation differs from the approved plan.' }
  if ([int]$ApprovedPlan.intent.options.test_fail_after_mutation -ne $TestFailAfterMutation) { throw 'PLAN_BINDING_OPTIONS_MISMATCH: Transaction fault-injection option differs from the approved plan.' }
  $PlanPath = [string]$ApprovedPlan.intent.options.plan_path
  $CanonicalPlanPath = [string]$ApprovedPlan.intent.options.canonical_plan_path
  $ReceiptPath = [string]$ApprovedPlan.intent.options.receipt_path
  $ExportPath = [string]$ApprovedPlan.intent.options.export_path
  $ExportRelativePaths = @($ApprovedPlan.intent.options.export_relative_paths)
  $PlanTtlMinutes = [int]$ApprovedPlan.intent.options.plan_ttl_minutes
}
if ($Scope -in @('complete', 'export-then-complete') -and -not $ConfirmModifiedLayerOwnedPurge) {
  throw 'UNINSTALL_SENSITIVE_PURGE_CONFIRMATION_REQUIRED: Complete scope requires -ConfirmModifiedLayerOwnedPurge in preview and apply.'
}
if ($Scope -eq 'export-then-complete') {
  if (-not $ConfirmExportMayContainSensitiveData) { throw 'UNINSTALL_EXPORT_CONFIRMATION_REQUIRED: Export requires -ConfirmExportMayContainSensitiveData in preview and apply.' }
  if ([string]::IsNullOrWhiteSpace($ExportPath) -or $ExportRelativePaths.Count -eq 0) { throw 'UNINSTALL_EXPORT_SELECTION_REQUIRED: Export requires -ExportPath and at least one exact -ExportRelativePaths value.' }
}

function Assert-UninstallProperties {
  param($Document, [string[]]$Required, [string[]]$Allowed, [string]$Label)
  if ($null -eq $Document -or $Document -isnot [System.Management.Automation.PSCustomObject]) { throw "UNINSTALL_MANIFEST_INVALID: $Label must be a JSON object." }
  $names = @($Document.PSObject.Properties.Name)
  foreach ($name in $Required) { if ($names -notcontains $name) { throw "UNINSTALL_MANIFEST_INVALID: $Label is missing '$name'." } }
  foreach ($name in $names) { if ($Allowed -notcontains $name) { throw "UNINSTALL_MANIFEST_INVALID: $Label contains unsupported property '$name'." } }
}

function Assert-UninstallRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -gt 1000 -or [System.IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or $Path -match '[\\:\x00-\x1f]' -or $Path.StartsWith('/') -or $Path.EndsWith('/')) {
    throw "UNINSTALL_ARTIFACT_PATH_INVALID: Unsafe artifact path '$Path'."
  }
  foreach ($segment in @($Path.Split('/'))) {
    if ([string]::IsNullOrWhiteSpace($segment) -or $segment -in @('.', '..')) { throw "UNINSTALL_ARTIFACT_PATH_INVALID: Unsafe artifact path '$Path'." }
  }
}

function Assert-UninstallHashOrNull {
  param($Value, [string]$Label)
  if ($null -ne $Value -and ($Value -isnot [string] -or [string]$Value -notmatch '^[a-f0-9]{64}$')) { throw "UNINSTALL_MANIFEST_INVALID: $Label must be null or lowercase SHA-256." }
}

function Read-UninstallManifest {
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $null }
  $metadata = Get-SafeFileMetadata -AuthorizedRoot $TargetRoot -Path $ManifestPath
  if ([int64]$metadata.length -gt 8388608) { throw 'UNINSTALL_MANIFEST_TOO_LARGE: Install manifest exceeds 8 MiB.' }
  try { $manifest = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $ManifestPath -Raw) }
  catch { throw "UNINSTALL_MANIFEST_INVALID: $($_.Exception.Message)" }
  $required = @('schema_version', 'layer', 'layer_version', 'minimum_reader_schema_version', 'writer_schema_version', 'profile', 'memory_mode', 'harnesses', 'artifacts')
  $allowed = @('schema_version', 'layer', 'layer_version', 'minimum_reader_schema_version', 'writer_schema_version', 'migrated_from_schema_version', 'profile', 'requested_packs', 'pack_sources', 'packs', 'installed_at', 'target_root', 'memory_mode', 'risk_level', 'harnesses', 'model_profiles', 'model_mode', 'model_inventory', 'model_runtime', 'routing_policy', 'routing_models', 'skills', 'adapters', 'adapter_aliases', 'artifacts', 'managed_paths', 'owned_paths', 'merge_needed', 'merge_suggestions', 'conflicts', 'transaction_operation_id', 'applied_plan_id', 'applied_plan_sha256')
  $schemaV = if ($manifest.schema_version -is [ValueType]) { [int64]$manifest.schema_version } else { -1 }
  $minReaderV = if ($manifest.minimum_reader_schema_version -is [ValueType]) { [int64]$manifest.minimum_reader_schema_version } else { -1 }
  $writerV = if ($manifest.writer_schema_version -is [ValueType]) { [int64]$manifest.writer_schema_version } else { -1 }
  if ($schemaV -ne 4 -or $minReaderV -ne 4 -or $writerV -ne 4) { throw 'UNINSTALL_MANIFEST_SCHEMA_UNSUPPORTED: Uninstall requires an exact schema-v4 manifest.' }
  if ([string]$manifest.layer -ne 'lizard-agent-layer') { throw 'UNINSTALL_MANIFEST_INVALID: Manifest layer identity is invalid.' }
  if ([string]$manifest.memory_mode -notin @('curated', 'private-episodic', 'off')) { throw 'UNINSTALL_MANIFEST_INVALID: Manifest memory_mode is invalid.' }
  if ($manifest.artifacts -isnot [System.Array]) { throw 'UNINSTALL_MANIFEST_INVALID: Manifest artifacts must be a JSON array.' }
  if ($manifest.PSObject.Properties.Name -contains 'target_root' -and -not [string]::IsNullOrWhiteSpace([string]$manifest.target_root)) {
    $manifestRoot = ConvertTo-LizardFullPath -Path ([string]$manifest.target_root)
    if (-not $manifestRoot.Equals($TargetRoot, (Get-LizardPathComparison))) { throw 'UNINSTALL_MANIFEST_ROOT_MISMATCH: Manifest target root differs from the current target.' }
  }
  $artifactRequired = @('path', 'kind', 'lifecycle', 'ownership', 'state', 'source_version', 'adapter_aliases')
  $artifactAllowed = @('path', 'kind', 'lifecycle', 'ownership', 'state', 'source_path', 'source_version', 'source_hash', 'installed_hash', 'current_hash', 'adapter_id', 'adapter_aliases', 'mirror_group')
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' (Get-LizardPathComparer)
  foreach ($artifact in @($manifest.artifacts)) {
    Assert-UninstallProperties -Document $artifact -Required $artifactRequired -Allowed $artifactAllowed -Label 'Manifest artifact'
    $relative = [string]$artifact.path
    Assert-UninstallRelativePath -Path $relative
    if (-not $seen.Add($relative)) { throw "UNINSTALL_MANIFEST_DUPLICATE_ARTIFACT: $relative" }
    if ([string]$artifact.kind -notin @('file', 'directory')) { throw "UNINSTALL_MANIFEST_INVALID: Artifact '$relative' has an invalid kind." }
    if ([string]$artifact.lifecycle -notin @('active', 'retired-present', 'retired-missing', 'removed')) { throw "UNINSTALL_MANIFEST_INVALID: Artifact '$relative' has an invalid lifecycle." }
    if ([string]$artifact.ownership -notin @('layer-owned', 'user-owned', 'adopted')) { throw "UNINSTALL_MANIFEST_INVALID: Artifact '$relative' has invalid ownership." }
    if ([string]$artifact.state -notin @('layer-owned', 'user-owned', 'adopted', 'locally-modified', 'stale-unmodified', 'missing', 'conflict', 'integrity-unknown')) { throw "UNINSTALL_MANIFEST_INVALID: Artifact '$relative' has an invalid state." }
    foreach ($hashName in @('source_hash', 'installed_hash', 'current_hash')) {
      if ($artifact.PSObject.Properties.Name -contains $hashName) { Assert-UninstallHashOrNull -Value $artifact.$hashName -Label "Artifact '$relative' $hashName" }
    }
  }
  return $manifest
}

function Get-UninstallPlanInput {
  param([string]$ScopeName, [string]$Root, [string]$Path, [string]$DisplayPath)
  return [pscustomobject][ordered]@{ scope = $ScopeName; path = $DisplayPath.Replace('\\', '/'); sha256 = Get-SafeFileHash -AuthorizedRoot $Root -Path $Path }
}

function New-PreserveEntry {
  param([string]$Path, [string]$Kind, [string]$Ownership, [string]$PreconditionKind, [AllowNull()][string]$Hash)
  $normalizedHash = if ([string]::IsNullOrWhiteSpace($Hash)) { $null } else { $Hash }
  return [pscustomobject][ordered]@{ path = $Path; kind = $Kind; action = 'preserve'; precondition_kind = $PreconditionKind; precondition_sha256 = $normalizedHash; ownership = $Ownership; intended_sha256 = $null }
}

function New-RemoveEntry {
  param([string]$Path, [string]$Kind, [AllowNull()][string]$Hash)
  $absolute = Join-Path $TargetRoot ($Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
  $normalizedHash = if ([string]::IsNullOrWhiteSpace($Hash)) { $null } else { $Hash }
  return [pscustomobject][ordered]@{
    path = $Path
    kind = $Kind
    action = 'remove'
    precondition_kind = $Kind
    precondition_sha256 = $normalizedHash
    precondition_identity_sha256 = Get-LizardPlanTargetIdentitySha256 -TargetRoot $TargetRoot -Path $absolute -Kind $Kind
    ownership = 'layer-owned'
    intended_sha256 = $null
  }
}

function New-ReplaceEntry {
  param([string]$Path, [string]$PreconditionHash, [string]$IntendedHash)
  return [pscustomobject][ordered]@{ path = $Path; kind = 'file'; action = 'replace'; precondition_kind = 'file'; precondition_sha256 = $PreconditionHash; ownership = 'layer-owned'; intended_sha256 = $IntendedHash }
}

function Get-UninstallCurrentPrecondition {
  param([string]$Path, [string]$ExpectedKind)
  $absolute = Join-Path $TargetRoot ($Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
  if (-not (Test-Path -LiteralPath $absolute)) { return [pscustomobject]@{ kind = 'absent'; sha256 = $null; identity_sha256 = $null; metadata = $null } }
  $kind = if (Test-Path -LiteralPath $absolute -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $absolute -PathType Container) { 'directory' } else { 'other' }
  if ($kind -eq 'other') { return [pscustomobject]@{ kind = 'other'; sha256 = $null; identity_sha256 = $null; metadata = $null } }
  $metadataKind = if ($kind -eq 'file') { 'File' } else { 'Directory' }
  $metadata = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $absolute -Kind $metadataKind
  $hash = if ($kind -eq 'file') { Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $absolute } else { $null }
  $identity = if ($kind -eq $ExpectedKind) { Get-LizardPlanTargetIdentitySha256 -Metadata $metadata } else { $null }
  return [pscustomobject]@{ kind = $kind; sha256 = $hash; identity_sha256 = $identity; metadata = $metadata }
}

function Assert-UninstallTargetEntryCurrent {
  param($Entry, [switch]$RequireIdentity)
  $current = Get-UninstallCurrentPrecondition -Path ([string]$Entry.path) -ExpectedKind ([string]$Entry.kind)
  if ([string]$current.kind -ne [string]$Entry.precondition_kind) { throw "UNINSTALL_TARGET_KIND_MISMATCH: $($Entry.path) expected $($Entry.precondition_kind), found $($current.kind)." }
  if ([string]$current.sha256 -ne [string]$Entry.precondition_sha256) { throw "UNINSTALL_TARGET_HASH_MISMATCH: $($Entry.path) changed after approval." }
  if ($RequireIdentity -and [string]$current.identity_sha256 -ne [string]$Entry.precondition_identity_sha256) { throw "UNINSTALL_TARGET_IDENTITY_MISMATCH: $($Entry.path) was replaced after approval." }
  return $current
}

function Assert-UninstallInputsCurrent {
  param($Plan)
  foreach ($input in @($Plan.intent.inputs)) {
    $root = if ([string]$input.scope -eq 'layer') { $LayerRoot } else { $TargetRoot }
    $absolute = Join-Path $root (([string]$input.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $current = Get-SafeFileHash -AuthorizedRoot $root -Path $absolute
    if ($current -ne [string]$input.sha256) { throw "UNINSTALL_INPUT_MISMATCH: $($input.scope):$($input.path) changed after approval." }
  }
}

$Manifest = Read-UninstallManifest
$Candidates = New-Object System.Collections.Generic.List[object]
$Preserved = New-Object System.Collections.Generic.List[object]
$Warnings = New-Object System.Collections.Generic.List[string]
$ResidualManifestBytes = $null

if ($null -ne $Manifest) {
  foreach ($artifact in @($Manifest.artifacts | Sort-Object path)) {
    $relative = [string]$artifact.path
    if ($relative -eq $ManifestRelativePath) { throw 'UNINSTALL_MANIFEST_INVALID: The install manifest must not self-assert an artifact record.' }
    $kind = [string]$artifact.kind
    $absolute = Join-Path $TargetRoot ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $exists = Test-Path -LiteralPath $absolute
    if (-not $exists -and [string]$artifact.lifecycle -eq 'removed') { continue }
    if (-not $exists) {
      $Candidates.Add((New-PreserveEntry -Path $relative -Kind $kind -Ownership ([string]$artifact.ownership) -PreconditionKind absent -Hash $null)) | Out-Null
      $Preserved.Add([pscustomobject]@{ path = $relative; reason = 'missing' }) | Out-Null
      continue
    }
    if ([string]$artifact.lifecycle -eq 'removed') {
      $currentKind = if (Test-Path -LiteralPath $absolute -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $absolute -PathType Container) { 'directory' } else { 'other' }
      $hash = if ($currentKind -eq 'file') { Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $absolute } else { $null }
      $Candidates.Add((New-PreserveEntry -Path $relative -Kind $kind -Ownership ([string]$artifact.ownership) -PreconditionKind $currentKind -Hash $hash)) | Out-Null
      $Preserved.Add([pscustomobject]@{ path = $relative; reason = 'removed-path-reappeared' }) | Out-Null
      $Warnings.Add("Removed artifact path reappeared and remains unmanaged: $relative") | Out-Null
      continue
    }
    $metadataKind = if ($kind -eq 'file') { 'File' } else { 'Directory' }
    try { $null = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $absolute -Kind $metadataKind }
    catch { throw "UNINSTALL_ARTIFACT_UNSAFE: ${relative}: $($_.Exception.Message)" }
    if ([string]$artifact.ownership -ne 'layer-owned') {
      $hash = if ($kind -eq 'file') { Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $absolute } else { $null }
      $Candidates.Add((New-PreserveEntry -Path $relative -Kind $kind -Ownership ([string]$artifact.ownership) -PreconditionKind $kind -Hash $hash)) | Out-Null
      $Preserved.Add([pscustomobject]@{ path = $relative; reason = [string]$artifact.ownership }) | Out-Null
      continue
    }
    if ($kind -eq 'file') {
      $currentHash = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $absolute
      if ([string]::IsNullOrWhiteSpace([string]$artifact.installed_hash) -or $currentHash -ne [string]$artifact.installed_hash) {
        if ($Scope -in @('complete', 'export-then-complete')) {
          $Candidates.Add((New-RemoveEntry -Path $relative -Kind file -Hash $currentHash)) | Out-Null
          continue
        }
        $Candidates.Add((New-PreserveEntry -Path $relative -Kind file -Ownership layer-owned -PreconditionKind file -Hash $currentHash)) | Out-Null
        $Preserved.Add([pscustomobject]@{ path = $relative; reason = 'locally-modified-or-integrity-unknown' }) | Out-Null
      } else {
        $Candidates.Add((New-RemoveEntry -Path $relative -Kind file -Hash $currentHash)) | Out-Null
      }
    } elseif ([string]$artifact.state -eq 'layer-owned' -or $Scope -in @('complete', 'export-then-complete')) {
      $Candidates.Add((New-RemoveEntry -Path $relative -Kind directory -Hash $null)) | Out-Null
    } else {
      $Candidates.Add((New-PreserveEntry -Path $relative -Kind directory -Ownership layer-owned -PreconditionKind directory -Hash $null)) | Out-Null
      $Preserved.Add([pscustomobject]@{ path = $relative; reason = "directory-state-$($artifact.state)" }) | Out-Null
    }
  }

  $preservedPaths = @($Preserved.ToArray() | ForEach-Object { [string]$_.path })
  for ($index = 0; $index -lt $Candidates.Count; $index++) {
    $entry = $Candidates[$index]
    if ([string]$entry.kind -ne 'directory' -or [string]$entry.action -ne 'remove') { continue }
    $prefix = ([string]$entry.path).TrimEnd('/') + '/'
    if (@($preservedPaths | Where-Object { $_.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
      $Candidates[$index] = New-PreserveEntry -Path ([string]$entry.path) -Kind directory -Ownership layer-owned -PreconditionKind directory -Hash $null
      $Preserved.Add([pscustomobject]@{ path = [string]$entry.path; reason = 'contains-preserved-artifact' }) | Out-Null
    }
  }

  $manifestHash = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $ManifestPath
  if ($Preserved.Count -eq 0) {
    $Candidates.Add((New-RemoveEntry -Path $ManifestRelativePath -Kind file -Hash $manifestHash)) | Out-Null
  } else {
    $residual = ConvertFrom-LizardJson -InputObject (ConvertTo-LizardCanonicalJson $Manifest)
    $removedPaths = @($Candidates.ToArray() | Where-Object { $_.action -eq 'remove' } | ForEach-Object { [string]$_.path })
    foreach ($record in @($residual.artifacts)) {
      if ($removedPaths -notcontains [string]$record.path) { continue }
      $record.lifecycle = 'removed'
      $record.state = 'missing'
      if ($record.PSObject.Properties.Name -contains 'current_hash') { $record.current_hash = $null }
      else { $record | Add-Member -NotePropertyName current_hash -NotePropertyValue $null }
    }
    $residualCanonical = ConvertTo-LizardCanonicalJson $residual
    $ResidualManifestBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($residualCanonical)
    $residualHash = Get-LizardPlanSha256 -CanonicalJson $residualCanonical
    $Candidates.Add((New-ReplaceEntry -Path $ManifestRelativePath -PreconditionHash $manifestHash -IntendedHash $residualHash)) | Out-Null
  }
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$defaultBase = Join-Path $LayerRoot ('.tmp/uninstall-plans/lizard-agent-layer-{0}-{1}' -f (Split-Path -Leaf $TargetRoot), $stamp)
$EffectivePlanPath = if ([string]::IsNullOrWhiteSpace($PlanPath)) { $defaultBase + '.md' } elseif ([System.IO.Path]::IsPathRooted($PlanPath)) { [System.IO.Path]::GetFullPath($PlanPath) } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $PlanPath)) }
$EffectiveCanonicalPlanPath = if ([string]::IsNullOrWhiteSpace($CanonicalPlanPath)) { [System.IO.Path]::ChangeExtension($EffectivePlanPath, '.json') } elseif ([System.IO.Path]::IsPathRooted($CanonicalPlanPath)) { [System.IO.Path]::GetFullPath($CanonicalPlanPath) } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $CanonicalPlanPath)) }
$EffectiveReceiptPath = if ([string]::IsNullOrWhiteSpace($ReceiptPath)) { [System.IO.Path]::ChangeExtension($EffectivePlanPath, '.receipt.json') } elseif ([System.IO.Path]::IsPathRooted($ReceiptPath)) { [System.IO.Path]::GetFullPath($ReceiptPath) } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ReceiptPath)) }
Assert-PathOutsideRoot -Path $EffectivePlanPath -ExcludedRoot $TargetRoot -Label 'PlanPath'
Assert-PathOutsideRoot -Path $EffectiveCanonicalPlanPath -ExcludedRoot $TargetRoot -Label 'CanonicalPlanPath'
Assert-PathOutsideRoot -Path $EffectiveReceiptPath -ExcludedRoot $TargetRoot -Label 'ReceiptPath'
$EffectiveExportPath = $null
$ExportRootHash = $null
if ($Scope -eq 'export-then-complete') {
  $EffectiveExportPath = if ([System.IO.Path]::IsPathRooted($ExportPath)) { [System.IO.Path]::GetFullPath($ExportPath) } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $ExportPath)) }
  Assert-PathOutsideRoot -Path $EffectiveExportPath -ExcludedRoot $TargetRoot -Label 'ExportPath'
  $EffectiveExportPath = Resolve-SafeRoot -Path $EffectiveExportPath -RequireExisting
  $ExportRootHash = Get-LizardPlanRootHash -TargetRoot $EffectiveExportPath
  foreach ($relative in @($ExportRelativePaths)) {
    Assert-UninstallRelativePath -Path $relative
    $artifact = @($Manifest.artifacts | Where-Object { [string]$_.path -eq $relative })
    if ($artifact.Count -ne 1 -or [string]$artifact[0].kind -ne 'file') { throw "UNINSTALL_EXPORT_SELECTION_INVALID: Export path '$relative' must identify exactly one manifest file artifact." }
    $source = Join-Path $TargetRoot ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw "UNINSTALL_EXPORT_SOURCE_MISSING: $relative" }
    Get-SafeFileMetadata -AuthorizedRoot $TargetRoot -Path $source | Out-Null
  }
}
if (-not $Apply) {
  $planParent = Initialize-SafeDirectory -Path (Split-Path -Parent $EffectivePlanPath)
  $canonicalParent = Initialize-SafeDirectory -Path (Split-Path -Parent $EffectiveCanonicalPlanPath)
}

$Inputs = New-Object System.Collections.Generic.List[object]
foreach ($relative in @('VERSION', 'scripts/uninstall.ps1', 'scripts/Lizard.Json.psm1', 'scripts/Lizard.SafeFs.psm1', 'scripts/Lizard.Manifest.psm1', 'scripts/Lizard.Plan.psm1', 'scripts/Lizard.Transaction.psm1')) {
  $Inputs.Add((Get-UninstallPlanInput -ScopeName layer -Root $LayerRoot -Path (Join-Path $LayerRoot ($relative.Replace('/', '/'))) -DisplayPath $relative)) | Out-Null
}
if ($null -ne $Manifest) { $Inputs.Add((Get-UninstallPlanInput -ScopeName target -Root $TargetRoot -Path $ManifestPath -DisplayPath $ManifestRelativePath)) | Out-Null }

$Options = [pscustomobject][ordered]@{
  scope = $Scope
  installation_present = ($null -ne $Manifest)
  memory_mode = if ($null -ne $Manifest) { [string]$Manifest.memory_mode } else { $null }
  plan_path = $EffectivePlanPath
  canonical_plan_path = $EffectiveCanonicalPlanPath
  receipt_path = $EffectiveReceiptPath
  plan_ttl_minutes = $PlanTtlMinutes
  confirm_modified_layer_owned_purge = $ConfirmModifiedLayerOwnedPurge.IsPresent
  export_path = $EffectiveExportPath
  export_relative_paths = @($ExportRelativePaths | Sort-Object -Unique)
  export_root_hash = $ExportRootHash
  confirm_export_may_contain_sensitive_data = $ConfirmExportMayContainSensitiveData.IsPresent
  test_fail_after_mutation = $TestFailAfterMutation
}
$OperationPlan = New-LizardOperationPlan -OperationKind uninstall -TargetRoot $TargetRoot -LayerRoot $LayerRoot -Options $Options -Inputs @($Inputs.ToArray() | Sort-Object scope, path) -TargetEntries @($Candidates.ToArray() | Sort-Object path) -TtlMinutes $PlanTtlMinutes -LayerVersion $LayerVersion -GitHead (Get-LizardSourceGitHead -Root $LayerRoot)

if ($Apply) {
  Assert-LizardPlanIntentMatch -ApprovedPlan $ApprovedPlan -CandidatePlan $OperationPlan | Out-Null
  $exported = New-Object System.Collections.Generic.List[object]
  if ($Scope -eq 'export-then-complete') {
    if ((Get-LizardPlanRootHash -TargetRoot $EffectiveExportPath) -ne [string]$ApprovedPlan.intent.options.export_root_hash) { throw 'UNINSTALL_EXPORT_ROOT_MISMATCH: Export root identity changed after approval.' }
    foreach ($relative in @($ExportRelativePaths | Sort-Object -Unique)) {
      $source = Join-Path $TargetRoot ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
      $destination = Join-Path $EffectiveExportPath ($relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
      $destinationParent = Split-Path -Parent $destination
      New-SafeDirectory -AuthorizedRoot $EffectiveExportPath -Path $destinationParent | Out-Null
      if (Test-Path -LiteralPath $destination) { throw "UNINSTALL_EXPORT_DESTINATION_EXISTS: Refusing to replace export path '$relative'." }
      $sourceHash = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $source
      Copy-SafeItem -SourceAuthorizedRoot $TargetRoot -Source $source -AuthorizedRoot $EffectiveExportPath -Destination $destination
      $exportHash = Get-SafeFileHash -AuthorizedRoot $EffectiveExportPath -Path $destination
      if ($exportHash -ne $sourceHash) { throw "UNINSTALL_EXPORT_HASH_MISMATCH: $relative" }
      $exported.Add([pscustomobject][ordered]@{ path = $relative; sha256 = $exportHash }) | Out-Null
    }
  }
  $transaction = $null
  $transactionResult = $null
  try {
    $transaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName 'uninstall' -FailAfterMutation $TestFailAfterMutation
    Assert-UninstallInputsCurrent -Plan $ApprovedPlan
    foreach ($entry in @($ApprovedPlan.intent.target_entries)) { Assert-UninstallTargetEntryCurrent -Entry $entry -RequireIdentity:([string]$entry.action -eq 'remove') | Out-Null }

    $removeFiles = @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' -and $_.kind -eq 'file' -and $_.path -ne $ManifestRelativePath } | Sort-Object path)
    $removeManifest = @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' -and $_.path -eq $ManifestRelativePath })
    $removeDirectories = @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' -and $_.kind -eq 'directory' } | Sort-Object @{ Expression = { @(([string]$_.path).Split('/')).Count }; Descending = $true }, path)
    foreach ($entry in @($removeFiles + $removeManifest + $removeDirectories)) {
      $current = Assert-UninstallTargetEntryCurrent -Entry $entry -RequireIdentity
      $absolute = Join-Path $TargetRoot (([string]$entry.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
      $deleteKind = if ([string]$entry.kind -eq 'file') { 'File' } else { 'EmptyDirectory' }
      Remove-LizardTransactionalItem -Path $absolute -Kind $deleteKind -ExpectedIdentity $current.metadata
    }
    foreach ($entry in @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'replace' })) {
      Assert-UninstallTargetEntryCurrent -Entry $entry | Out-Null
      if ([string]$entry.path -ne $ManifestRelativePath -or $null -eq $ResidualManifestBytes) { throw "UNINSTALL_REPLACEMENT_UNSUPPORTED: $($entry.path)" }
      Set-LizardTransactionalBytes -Path $ManifestPath -Bytes $ResidualManifestBytes
      if ((Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $ManifestPath) -ne [string]$entry.intended_sha256) { throw 'UNINSTALL_RESIDUAL_MANIFEST_HASH_MISMATCH: Residual manifest bytes differ from the approved plan.' }
    }

    foreach ($entry in @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' })) {
      $absolute = Join-Path $TargetRoot (([string]$entry.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
      if (Test-Path -LiteralPath $absolute) { throw "UNINSTALL_FINAL_REMOVAL_FAILED: $($entry.path) remains present." }
    }
    foreach ($entry in @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'preserve' })) { Assert-UninstallTargetEntryCurrent -Entry $entry | Out-Null }
    $transactionResult = Complete-LizardTransaction
  } catch {
    $primary = $_
    if ($null -ne $transaction) {
      try { Undo-LizardTransaction | Out-Null } catch { throw "UNINSTALL_ROLLBACK_FAILED: $($primary.Exception.Message); rollback: $($_.Exception.Message)" }
    }
    throw $primary
  }

  $receiptParent = Initialize-SafeDirectory -Path (Split-Path -Parent $EffectiveReceiptPath)
  $receipt = [pscustomobject][ordered]@{
    schema_version = 1
    status = if ($null -eq $Manifest) { 'no-op' } elseif (@($ApprovedPlan.intent.target_entries | Where-Object { $_.action -in @('preserve', 'replace') }).Count -gt 0) { 'partial' } else { 'completed' }
    completed_at = (Get-Date).ToUniversalTime().ToString('o')
    target_root_hash = [string]$ApprovedPlan.intent.target_root_hash
    scope = $Scope
    memory_mode = if ($null -ne $Manifest) { [string]$Manifest.memory_mode } else { $null }
    plan_id = [string]$ApprovedPlan.plan_id
    plan_sha256 = $ApprovedPlanSha256.ToLowerInvariant()
    transaction_operation_id = [string]$transactionResult.operation_id
    removed = @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' } | ForEach-Object { [pscustomobject][ordered]@{ path = [string]$_.path; kind = [string]$_.kind; precondition_sha256 = $_.precondition_sha256; precondition_identity_sha256 = [string]$_.precondition_identity_sha256 } })
    preserved = @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'preserve' } | ForEach-Object { [pscustomobject][ordered]@{ path = [string]$_.path; kind = [string]$_.kind; precondition_sha256 = $_.precondition_sha256 } })
    exported = @($exported.ToArray())
    unresolved_residue = @($ApprovedPlan.intent.target_entries | Where-Object { $_.action -eq 'preserve' } | ForEach-Object { [string]$_.path } | Sort-Object -Unique)
    final_manifest_present = (Test-Path -LiteralPath $ManifestPath)
  }
  Set-SafeContent -AuthorizedRoot $receiptParent -Path $EffectiveReceiptPath -Value ($receipt | ConvertTo-Json -Depth 10)
  if ($Json) { $receipt | ConvertTo-Json -Depth 10 } else {
    Write-Host "Uninstall $($receipt.status): $(@($receipt.removed).Count) removed, $(@($receipt.preserved).Count) preserved"
    Write-Host "Receipt: $EffectiveReceiptPath"
  }
  exit 0
}

$writeResult = Write-LizardOperationPlan -Plan $OperationPlan -Path $EffectiveCanonicalPlanPath

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('# lizard-agent-layer Uninstall Plan') | Out-Null
$lines.Add('') | Out-Null
$lines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
$lines.Add(('- Scope: `{0}`' -f $Scope)) | Out-Null
$lines.Add(('- Plan ID: `{0}`' -f $OperationPlan.plan_id)) | Out-Null
$lines.Add(('- Canonical SHA-256: `{0}`' -f $writeResult.sha256)) | Out-Null
$lines.Add(('- Installation manifest present: `{0}`' -f ($null -ne $Manifest))) | Out-Null
$lines.Add('') | Out-Null
$lines.Add('| Path | Kind | Action | Ownership | Precondition SHA-256 |') | Out-Null
$lines.Add('| --- | --- | --- | --- | --- |') | Out-Null
foreach ($entry in @($OperationPlan.intent.target_entries)) { $lines.Add(('| `{0}` | {1} | {2} | {3} | {4} |' -f $entry.path, $entry.kind, $entry.action, $entry.ownership, $entry.precondition_sha256)) | Out-Null }
$lines.Add('') | Out-Null
$lines.Add('## Preserved') | Out-Null
$lines.Add('') | Out-Null
if ($Preserved.Count -eq 0) { $lines.Add('- None.') | Out-Null } else { foreach ($entry in @($Preserved.ToArray() | Sort-Object path, reason)) { $lines.Add(('- `{0}`: {1}' -f $entry.path, $entry.reason)) | Out-Null } }
$lines.Add('') | Out-Null
$lines.Add('## Warnings') | Out-Null
$lines.Add('') | Out-Null
if ($Warnings.Count -eq 0) { $lines.Add('- None.') | Out-Null } else { foreach ($warning in @($Warnings.ToArray())) { $lines.Add("- $warning") | Out-Null } }
$lines.Add('') | Out-Null
$lines.Add('No target content was changed. Apply requires the canonical plan path, its independently supplied SHA-256, and explicit human approval.') | Out-Null
Set-SafeContent -AuthorizedRoot $planParent -Path $EffectivePlanPath -Value ($lines -join "`n")

$result = [pscustomobject][ordered]@{
  status = 'preview'
  target = $TargetRoot
  scope = $Scope
  installation_present = ($null -ne $Manifest)
  plan_path = $EffectivePlanPath
  canonical_plan_path = $writeResult.path
  canonical_plan_sha256 = $writeResult.sha256
  receipt_path = $EffectiveReceiptPath
  remove_count = @($OperationPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' }).Count
  preserve_count = @($OperationPlan.intent.target_entries | Where-Object { $_.action -eq 'preserve' }).Count
  warnings = @($Warnings.ToArray())
}
if ($Json) { $result | ConvertTo-Json -Depth 8 } else {
  Write-Host "Uninstall preview: $($result.remove_count) remove, $($result.preserve_count) preserve"
  Write-Host "Plan: $($result.plan_path)"
  Write-Host "Canonical plan: $($result.canonical_plan_path)"
  Write-Host "SHA-256: $($result.canonical_plan_sha256)"
}
