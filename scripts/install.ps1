param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Profile = "standard",
  [string[]]$Harnesses,
  [string[]]$Packs,
  [ValidateSet('curated', 'private-episodic', 'off')]
  [string]$MemoryMode,
  [string]$RoutingPolicy,
  [ValidateSet('inherit-current', 'inventory-routing')]
  [string]$ModelMode,
  [string]$ModelInventory,
  [string]$ModelRuntime,
  [switch]$Apply,
  [switch]$Force,
  [switch]$ForceManaged,
  [switch]$WritePlan,
  [string]$PlanPath,
  [string]$CanonicalPlanPath,
  [int]$PlanTtlMinutes = 60,
  [string]$ApprovedPlanPath,
  [string]$ApprovedPlanSha256,
  [switch]$HumanApproved,
  [switch]$RequireSignedApproval,
  [string]$ApprovalEnvelopePath,
  [string]$TrustStorePath,
  [string]$TrustStoreSha256,
  [string]$ChallengePath,
  [string]$ChallengeSha256,
  [string]$ReplayLedgerPath,
  [switch]$AllowTargetReportWrite,
  [string]$TransactionId,
  [switch]$JoinTransaction,
  [int]$TestFailAfterMutation = 0,
  [switch]$InternalPreflight,
  [switch]$InternalPlanProbe,
  [switch]$SuppressPlanReport,
  [switch]$ValidateApprovedPlanOnly
)

$ErrorActionPreference = "Stop"
$InstallScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Manifest.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Plan.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Host.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SkillPackage.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$ProfilePath = Join-Path $LayerRoot "profiles\$Profile.json"
$VersionPath = Join-Path $LayerRoot "VERSION"
$LayerVersion = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { "0.0.0-dev" }
$SkillPackageCatalog = @{}
foreach ($skillPackage in @(Assert-LizardSkillRepository -SkillsRoot (Join-Path $LayerRoot 'skills') -LayerVersion $LayerVersion)) { $SkillPackageCatalog[[string]$skillPackage.metadata.name] = $skillPackage }
$ShouldWritePlan = $WritePlan.IsPresent -or -not [string]::IsNullOrWhiteSpace($PlanPath)
$ShouldWriteCanonicalPlan = $ShouldWritePlan -or -not [string]::IsNullOrWhiteSpace($CanonicalPlanPath)
$EffectivePlanPath = $null
$EffectiveCanonicalPlanPath = $null
$PlanInsideTarget = $false
$ApprovedPlan = $null

if ($Apply) {
  if ($InternalPreflight -or $InternalPlanProbe) { throw 'PLAN_BINDING_INTERNAL_BYPASS: Internal plan switches cannot be combined with -Apply.' }
  if ([string]::IsNullOrWhiteSpace($ApprovedPlanPath) -or [string]::IsNullOrWhiteSpace($ApprovedPlanSha256) -or -not $HumanApproved) {
    throw 'PLAN_APPROVAL_REQUIRED: -Apply requires -ApprovedPlanPath, -ApprovedPlanSha256, and -HumanApproved.'
  }
  Assert-PathOutsideRoot -Path $ApprovedPlanPath -ExcludedRoot $TargetRoot -Label 'ApprovedPlanPath'
  $ApprovedPlan = Read-LizardApprovedPlan -Path $ApprovedPlanPath -ExpectedSha256 $ApprovedPlanSha256 -ExpectedOperationKind 'install'
} elseif ($ValidateApprovedPlanOnly) {
  throw 'PLAN_APPROVAL_REQUIRED: -ValidateApprovedPlanOnly requires the normal plan-bound -Apply contract.'
}

if (-not (Test-Path -LiteralPath $ProfilePath)) {
  throw "Unknown profile '$Profile'. Expected a JSON file under profiles/."
}

$ProfileDoc = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $LayerRoot -Path $ProfilePath -Raw)

function Expand-ValueList {
  param($Values)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in ([string]$value -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed -and -not $out.Contains($trimmed)) { $out.Add($trimmed) | Out-Null }
    }
  }
  @($out.ToArray())
}

function Set-DocProperty {
  param([object]$Doc, [string]$Name, $Value)
  if ($Doc.PSObject.Properties.Name -contains $Name) { $Doc.$Name = $Value }
  else { $Doc | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
}

function Merge-ArrayProperty {
  param([object]$Doc, [string]$Name, $Values)
  $list = New-Object System.Collections.Generic.List[string]
  if ($Doc.PSObject.Properties.Name -contains $Name) {
    foreach ($item in @($Doc.$Name)) { if ($item -and -not $list.Contains([string]$item)) { $list.Add([string]$item) | Out-Null } }
  }
  foreach ($item in @($Values)) { if ($item -and -not $list.Contains([string]$item)) { $list.Add([string]$item) | Out-Null } }
  Set-DocProperty $Doc $Name @($list.ToArray())
}

function Get-RiskRank {
  param([string]$Risk)
  switch ($Risk) { 'high' { 3 } 'medium' { 2 } 'low' { 1 } default { 0 } }
}

function Get-SizeRank {
  param([string]$Size)
  switch ($Size) { 'large' { 3 } 'medium' { 2 } 'small' { 1 } default { 0 } }
}

function Max-RiskLevel {
  param([string]$A, [string]$B)
  if ((Get-RiskRank $B) -gt (Get-RiskRank $A)) { $B } else { $A }
}

function Max-ProjectSize {
  param([string]$A, [string]$B)
  if ((Get-SizeRank $B) -gt (Get-SizeRank $A)) { $B } else { $A }
}

function Get-PackManifestInfo {
  param([string]$PackName)
  if ($PackName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid pack name '$PackName'." }
  $builtInPath = Join-Path $LayerRoot "packs\$PackName.json"
  if (Test-Path -LiteralPath $builtInPath) {
    return [ordered]@{ path = $builtInPath; source = 'builtin'; display = "packs/$PackName.json" }
  }
  $overlayPath = Join-Path $TargetRoot ".lizard-agent-layer\packs\$PackName.json"
  if (Test-Path -LiteralPath $overlayPath) {
    return [ordered]@{ path = $overlayPath; source = 'target-overlay'; display = ".lizard-agent-layer/packs/$PackName.json" }
  }
  throw "Unknown pack '$PackName'. Expected packs/$PackName.json or .lizard-agent-layer/packs/$PackName.json in the target."
}

function Read-PackManifest {
  param([string]$PackName)
  $info = Get-PackManifestInfo $PackName
  $packRoot = if ([string]$info.source -eq 'target-overlay') { $TargetRoot } else { $LayerRoot }
  $pack = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $packRoot -Path $info.path -Raw)
  if ($pack.name -ne $PackName) { throw "Pack manifest name '$($pack.name)' does not match '$PackName'." }
  $pack | Add-Member -NotePropertyName '_sourceKind' -NotePropertyValue $info.source -Force
  $pack | Add-Member -NotePropertyName '_sourcePath' -NotePropertyValue $info.display -Force
  $pack
}

$PackCache = @{}
function Get-Pack {
  param([string]$PackName)
  if (-not $PackCache.ContainsKey($PackName)) { $PackCache[$PackName] = Read-PackManifest $PackName }
  $PackCache[$PackName]
}

$ExpandedPackNames = New-Object System.Collections.Generic.List[string]
function Add-PackWithExtends {
  param([string]$PackName, [string[]]$Stack = @())
  if ($Stack -contains $PackName) { throw "Pack extends cycle detected: $(@($Stack + $PackName) -join ' -> ')" }
  $pack = Get-Pack $PackName
  if ($pack.PSObject.Properties.Name -contains 'extends') {
    foreach ($basePack in @(Expand-ValueList $pack.extends)) {
      Add-PackWithExtends -PackName $basePack -Stack @($Stack + $PackName)
    }
  }
  if (-not $ExpandedPackNames.Contains($PackName)) { $ExpandedPackNames.Add($PackName) | Out-Null }
}

$ModelProfileNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'model-profiles') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $model = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $LayerRoot -Path $_.FullName -Raw)
  if ($model.name) { $ModelProfileNames.Add([string]$model.name) | Out-Null }
}

function Assert-PackReferences {
  param($Pack)
  foreach ($skill in @($Pack.skills)) {
    if ($skill -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Pack $($Pack.name) references invalid skill '$skill'." }
    if (-not (Test-Path -LiteralPath (Join-Path $LayerRoot "skills\$skill\SKILL.md"))) { throw "Pack $($Pack.name) references missing skill '$skill'." }
  }
  foreach ($harness in @($Pack.harnesses)) {
    if ($harness -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Pack $($Pack.name) references invalid harness '$harness'." }
    if (-not (Test-Path -LiteralPath (Join-Path $LayerRoot "adapters\$harness\adapter.json"))) { throw "Pack $($Pack.name) references missing adapter '$harness'." }
  }
  if ($Pack.modelProfiles) {
    foreach ($prop in $Pack.modelProfiles.PSObject.Properties) {
      if (-not $ModelProfileNames.Contains([string]$prop.Value)) { throw "Pack $($Pack.name) references missing model profile '$($prop.Value)' for '$($prop.Name)'." }
    }
  }
}

$RequestedPacks = Expand-ValueList $Packs
foreach ($packName in @($RequestedPacks)) { Add-PackWithExtends -PackName $packName }
$SelectedPacks = @($ExpandedPackNames.ToArray())
$PackDocs = New-Object System.Collections.Generic.List[object]
$PackSources = New-Object System.Collections.Generic.List[object]
foreach ($packName in @($SelectedPacks)) {
  $pack = Get-Pack $packName
  Assert-PackReferences $pack
  $PackDocs.Add($pack) | Out-Null
  $packInfo = Get-PackManifestInfo $packName
  $packHash = Get-SafeFileHash -AuthorizedRoot $(if ([string]$pack._sourceKind -eq 'target-overlay') { $TargetRoot } else { $LayerRoot }) -Path ([string]$packInfo.path)
  $PackSources.Add([ordered]@{ name = [string]$pack.name; source = [string]$pack._sourceKind; path = [string]$pack._sourcePath; sha256 = $packHash; prose_trust = $(if ([string]$pack._sourceKind -eq 'target-overlay') { 'quarantined' } else { 'layer-reviewed' }) }) | Out-Null
  Merge-ArrayProperty $ProfileDoc 'stack' @($pack.stack)
  Merge-ArrayProperty $ProfileDoc 'skills' @($pack.skills)
  if ([string]$pack._sourceKind -ne 'target-overlay') { Merge-ArrayProperty $ProfileDoc 'verification' @($pack.verification) }
  Set-DocProperty $ProfileDoc 'riskLevel' (Max-RiskLevel ([string]$ProfileDoc.riskLevel) ([string]$pack.riskLevel))
  Set-DocProperty $ProfileDoc 'projectSize' (Max-ProjectSize ([string]$ProfileDoc.projectSize) ([string]$pack.projectSize))
  if ($pack.modelProfiles) {
    if (-not ($ProfileDoc.PSObject.Properties.Name -contains 'modelProfiles') -or $null -eq $ProfileDoc.modelProfiles) {
      Set-DocProperty $ProfileDoc 'modelProfiles' ([pscustomobject]@{})
    }
    foreach ($prop in $pack.modelProfiles.PSObject.Properties) {
      $ProfileDoc.modelProfiles | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
    }
  }
  if ([string]$pack._sourceKind -ne 'target-overlay' -and -not [string]::IsNullOrWhiteSpace([string]$pack.notes)) {
    $currentNotes = if ($ProfileDoc.PSObject.Properties.Name -contains 'notes') { [string]$ProfileDoc.notes } else { '' }
    $suffix = "Pack $($pack.name): $($pack.notes)"
    if ($currentNotes -and $currentNotes -notmatch [regex]::Escape($suffix)) { Set-DocProperty $ProfileDoc 'notes' ($currentNotes.TrimEnd() + "`n" + $suffix) }
    elseif (-not $currentNotes) { Set-DocProperty $ProfileDoc 'notes' $suffix }
  }
}
Set-DocProperty $ProfileDoc 'packs' @($SelectedPacks)
Set-DocProperty $ProfileDoc 'requestedPacks' @($RequestedPacks)

function Expand-HarnessList { param($Values) Expand-ValueList $Values }
$DefaultHarnesses = New-Object System.Collections.Generic.List[string]
foreach ($harness in @(Expand-HarnessList $ProfileDoc.harnesses)) {
  if ($harness -and -not $DefaultHarnesses.Contains([string]$harness)) { $DefaultHarnesses.Add([string]$harness) | Out-Null }
}
if (-not ($Harnesses -and $Harnesses.Count -gt 0)) {
  foreach ($pack in @($PackDocs.ToArray())) {
    foreach ($harness in @($pack.harnesses)) {
      if ($harness -and -not $DefaultHarnesses.Contains([string]$harness)) { $DefaultHarnesses.Add([string]$harness) | Out-Null }
    }
  }
}
$SelectedHarnesses = if ($Harnesses -and $Harnesses.Count -gt 0) { Expand-HarnessList $Harnesses } else { @($DefaultHarnesses.ToArray()) }
if (($Profile -eq "standard" -or $Profile -eq "enterprise-fullstack") -and ($null -eq $Harnesses -or $Harnesses.Count -eq 0)) {
  throw "INSTALL_HARNESSES_REQUIRED: Profile '$Profile' requires the -Harnesses parameter to be explicitly specified."
}
if ($SelectedHarnesses.Count -eq 0) { throw "No harnesses selected. Set profile.harnesses or pass -Harnesses." }

if ($Apply -and -not $ValidateApprovedPlanOnly -and -not $JoinTransaction) {
  $approvalPolicy = Get-LizardOperationApprovalPolicy `
    -OperationKind 'install' `
    -RiskLevel ([string]$ProfileDoc.riskLevel) `
    -Profile $Profile `
    -Force:$Force `
    -ForceManaged:$ForceManaged `
    -RequireSignedApproval:$RequireSignedApproval

  if ($approvalPolicy.signed_approval_required) {
    if ([string]::IsNullOrWhiteSpace($ApprovalEnvelopePath) -or [string]::IsNullOrWhiteSpace($TrustStorePath) -or [string]::IsNullOrWhiteSpace($TrustStoreSha256) -or [string]::IsNullOrWhiteSpace($ChallengePath) -or [string]::IsNullOrWhiteSpace($ChallengeSha256)) {
      throw "PLAN_SIGNED_APPROVAL_REQUIRED: Signed apply approval is mandatory for this operation ($($approvalPolicy.reason))."
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
}


function Resolve-PlanReportPath {
  if (-not [string]::IsNullOrWhiteSpace($PlanPath)) {
    if ([System.IO.Path]::IsPathRooted($PlanPath)) { return $PlanPath }
    return (Join-Path (Get-Location).Path $PlanPath)
  }
  $stamp = Get-Date -Format 'yyyyMMddHHmmss'
  return (Join-Path $LayerRoot ".tmp\install-plans\lizard-agent-layer-$Profile-$stamp.md")
}

if ($ShouldWritePlan) {
  $EffectivePlanPath = Resolve-PlanReportPath
  if (-not $AllowTargetReportWrite) { Assert-PathOutsideRoot -Path $EffectivePlanPath -ExcludedRoot $TargetRoot -Label 'PlanPath' }
  $PlanInsideTarget = Test-LizardPathWithinRoot -Path $EffectivePlanPath -AuthorizedRoot $TargetRoot
  $planParent = Split-Path -Parent $EffectivePlanPath
  if ($planParent) {
    if ($Apply -and $PlanInsideTarget) { Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $planParent | Out-Null }
    elseif (-not $Apply -and -not $SuppressPlanReport) { $planParent = Initialize-SafeDirectory -Path $planParent }
  }
}

if ($ShouldWriteCanonicalPlan) {
  if (-not [string]::IsNullOrWhiteSpace($CanonicalPlanPath)) {
    $EffectiveCanonicalPlanPath = if ([System.IO.Path]::IsPathRooted($CanonicalPlanPath)) { [System.IO.Path]::GetFullPath($CanonicalPlanPath) } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $CanonicalPlanPath)) }
  } elseif ($EffectivePlanPath) {
    $EffectiveCanonicalPlanPath = [System.IO.Path]::ChangeExtension($EffectivePlanPath, '.json')
  }
  Assert-PathOutsideRoot -Path $EffectiveCanonicalPlanPath -ExcludedRoot $TargetRoot -Label 'CanonicalPlanPath'
  if (-not $Apply) { $canonicalParent = Initialize-SafeDirectory -Path (Split-Path -Parent $EffectiveCanonicalPlanPath) }
}

function Get-CostRank {
  param([string]$Tier)
  switch ($Tier) { 'local' { 0 } 'budget' { 1 } 'balanced' { 2 } 'premium' { 3 } 'frontier' { 4 } default { 99 } }
}

function Test-ContainsAll {
  param($Available, $Required)
  foreach ($item in @($Required)) { if (@($Available) -notcontains [string]$item) { return $false } }
  return $true
}

function Get-RoleScore {
  param($Model, [string]$Role)
  if ($Model.evidence.role_scores -and $Model.evidence.role_scores.PSObject.Properties.Name -contains $Role) { return [double]$Model.evidence.role_scores.$Role }
  return -1.0
}

$EffectiveRoutingPolicy = if (-not [string]::IsNullOrWhiteSpace($RoutingPolicy)) {
  $RoutingPolicy.Trim()
} elseif ($ProfileDoc.PSObject.Properties.Name -contains 'routingPolicy' -and -not [string]::IsNullOrWhiteSpace([string]$ProfileDoc.routingPolicy)) {
  [string]$ProfileDoc.routingPolicy
} else {
  'staged-balanced'
}
if ($EffectiveRoutingPolicy -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid routing policy '$EffectiveRoutingPolicy'." }
$RoutingPolicyPath = Join-Path $LayerRoot "routing-policies\$EffectiveRoutingPolicy.json"
if (-not (Test-Path -LiteralPath $RoutingPolicyPath -PathType Leaf)) { throw "Unknown routing policy '$EffectiveRoutingPolicy'. Expected routing-policies/$EffectiveRoutingPolicy.json." }
$RoutingPolicyDoc = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $LayerRoot -Path $RoutingPolicyPath -Raw)
if ([string]$RoutingPolicyDoc.name -ne $EffectiveRoutingPolicy) { throw "Routing policy name '$($RoutingPolicyDoc.name)' does not match '$EffectiveRoutingPolicy'." }
Set-DocProperty $ProfileDoc 'routingPolicy' $EffectiveRoutingPolicy
$EffectiveModelMode = if (-not [string]::IsNullOrWhiteSpace($ModelMode)) {
  $ModelMode
} elseif ($ProfileDoc.PSObject.Properties.Name -contains 'modelMode' -and -not [string]::IsNullOrWhiteSpace([string]$ProfileDoc.modelMode)) {
  [string]$ProfileDoc.modelMode
} else {
  [string]$RoutingPolicyDoc.model_selection.default_mode
}
if ($EffectiveModelMode -notin @('inherit-current', 'inventory-routing')) { throw "Invalid model mode '$EffectiveModelMode'." }
$EffectiveModelInventory = $null
$EffectiveModelRuntime = $null
if ($EffectiveModelMode -eq 'inventory-routing') {
  $EffectiveModelInventory = if (-not [string]::IsNullOrWhiteSpace($ModelInventory)) {
    $ModelInventory.Trim()
  } elseif ($ProfileDoc.PSObject.Properties.Name -contains 'modelInventory' -and -not [string]::IsNullOrWhiteSpace([string]$ProfileDoc.modelInventory)) {
    [string]$ProfileDoc.modelInventory
  } else {
    [string]$RoutingPolicyDoc.model_selection.inventory_path
  }
  if ([System.IO.Path]::IsPathRooted($EffectiveModelInventory) -or $EffectiveModelInventory -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid model inventory path '$EffectiveModelInventory'." }
  Set-DocProperty $ProfileDoc 'modelInventory' $EffectiveModelInventory.Replace('\\', '/')
  $inventoryTargetPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $EffectiveModelInventory.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $inventoryTargetPath -PathType Leaf)) {
    Write-Output "Recommended for normal IDE use: omit '-ModelMode inventory-routing' and keep the default inherit-current mode; no model-picker changes are required."
    throw "MODEL_INVENTORY_REQUIRED: Advanced automatic routing is not configured because '$EffectiveModelInventory' is missing. Only a routing administrator or automatic runtime adapter should create this inventory."
  }
  try { $inventoryPreflight = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $inventoryTargetPath -Raw) }
  catch { throw "MODEL_INVENTORY_INVALID: $($_.Exception.Message)" }
  if (@($inventoryPreflight.models).Count -eq 0) { throw 'MODEL_INVENTORY_INVALID: inventory contains no models.' }
  $duplicateInventoryIds = @($inventoryPreflight.models | Group-Object { [string]$_.id } | Where-Object { $_.Count -gt 1 })
  if ($duplicateInventoryIds.Count -gt 0) { throw "MODEL_INVENTORY_INVALID: duplicate model id '$([string]$duplicateInventoryIds[0].Name)'." }
  $EffectiveModelRuntime = if (-not [string]::IsNullOrWhiteSpace($ModelRuntime)) {
    $ModelRuntime.Trim()
  } elseif ($ProfileDoc.PSObject.Properties.Name -contains 'modelRuntime' -and -not [string]::IsNullOrWhiteSpace([string]$ProfileDoc.modelRuntime)) {
    [string]$ProfileDoc.modelRuntime
  } else {
    [string]$RoutingPolicyDoc.model_selection.runtime_path
  }
  if ([System.IO.Path]::IsPathRooted($EffectiveModelRuntime) -or $EffectiveModelRuntime -match '(^|[\\/])\.\.([\\/]|$)') { throw "Invalid model runtime path '$EffectiveModelRuntime'." }
  Set-DocProperty $ProfileDoc 'modelRuntime' $EffectiveModelRuntime.Replace('\\', '/')
  $runtimeTargetPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $EffectiveModelRuntime.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $runtimeTargetPath -PathType Leaf)) {
    Write-Output "Recommended for normal IDE use: omit '-ModelMode inventory-routing' and keep the default inherit-current mode."
    throw "MODEL_RUNTIME_REQUIRED: Advanced automatic routing is not configured because '$EffectiveModelRuntime' is missing. Only enable Advanced mode after an automatic runtime can select and report models without user interaction."
  }
  try { $runtimePreflight = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $runtimeTargetPath -Raw) }
  catch { throw "MODEL_RUNTIME_INVALID: $($_.Exception.Message)" }
  if ([string]$runtimePreflight.status -ne 'ready') { throw 'MODEL_RUNTIME_NOT_READY: runtime status must be ready.' }
  if ([string]$runtimePreflight.selection -notin @('subagent', 'per-call')) { throw 'MODEL_RUNTIME_AUTOMATION_REQUIRED: selection must be subagent or per-call.' }
  if ($runtimePreflight.actual_model_reporting -ne $true) { throw 'MODEL_RUNTIME_REPORTING_REQUIRED: actual_model_reporting must be true.' }
  if ([string]$runtimePreflight.attestation -notin @('observed', 'attested')) { throw 'MODEL_RUNTIME_ATTESTATION_REQUIRED: attestation must be observed or attested.' }
  if ([string]::IsNullOrWhiteSpace([string]$runtimePreflight.configuration_fingerprint)) { throw 'MODEL_RUNTIME_CONFIGURATION_REQUIRED: configuration_fingerprint is required.' }
  if ([DateTimeOffset]::Parse([string]$runtimePreflight.expires_at) -le [DateTimeOffset]::UtcNow) { throw 'MODEL_RUNTIME_EXPIRED: runtime capability evidence has expired.' }
  $missingRuntimeHarnesses = @($SelectedHarnesses | Where-Object { @($runtimePreflight.harnesses) -notcontains $_ })
  if ($missingRuntimeHarnesses.Count -gt 0) { throw "MODEL_RUNTIME_HARNESS_MISMATCH: runtime does not cover selected harnesses '$($missingRuntimeHarnesses -join ', ')'." }
  $eligibleInventoryModels = @($inventoryPreflight.models | Where-Object {
    $_.available -eq $true -and $_.approved -eq $true -and [string]$_.evidence.state -eq 'calibrated' -and
    [string]$_.evidence.configuration_fingerprint -eq [string]$runtimePreflight.configuration_fingerprint -and
    $_.evidence.expires_at -and ([DateTimeOffset]::Parse([string]$_.evidence.expires_at) -gt [DateTimeOffset]::UtcNow)
  })
  if ($eligibleInventoryModels.Count -eq 0) { throw 'MODEL_INVENTORY_NO_ELIGIBLE_MODELS: at least one available, approved, non-expired calibrated model matching the runtime fingerprint is required.' }
  foreach ($route in @($RoutingPolicyDoc.routes)) {
    foreach ($routeDataClass in @($route.data_classes)) {
      $routeCovered = $false
      foreach ($role in @($route.candidate_roles) + @($route.fallback_roles)) {
        foreach ($candidate in @($eligibleInventoryModels)) {
          if (@($candidate.allowed_data_classes) -notcontains [string]$routeDataClass) { continue }
          if (-not (Test-ContainsAll -Available @($candidate.capabilities) -Required @($route.required_capabilities))) { continue }
          if ((Get-CostRank ([string]$candidate.cost_tier)) -gt (Get-CostRank ([string]$route.max_cost_tier))) { continue }
          if ((Get-RoleScore -Model $candidate -Role ([string]$role)) -lt [double]$RoutingPolicyDoc.model_selection.minimum_role_score) { continue }
          $routeCovered = $true
          break
        }
        if ($routeCovered) { break }
      }
      if (-not $routeCovered) { throw "MODEL_INVENTORY_ROUTE_GAP: route '$($route.id)' has no eligible model for data class '$routeDataClass'." }
    }
  }
} else {
  if ($ProfileDoc.PSObject.Properties.Name -contains 'modelInventory') { $ProfileDoc.PSObject.Properties.Remove('modelInventory') }
  if ($ProfileDoc.PSObject.Properties.Name -contains 'modelRuntime') { $ProfileDoc.PSObject.Properties.Remove('modelRuntime') }
}
Set-DocProperty $ProfileDoc 'modelMode' $EffectiveModelMode
$BoundRoutingModelNames = [object[]]@(if ($ProfileDoc.PSObject.Properties.Name -contains 'modelProfiles' -and $null -ne $ProfileDoc.modelProfiles) { $ProfileDoc.modelProfiles.PSObject.Properties | ForEach-Object { [string]$_.Value } | Sort-Object -Unique })
if ($BoundRoutingModelNames.Count -gt 0) { Write-Warning 'modelProfiles is deprecated; migrate target configuration to modelInventory and modelRuntime.' }
$Mode = if ($Apply) { "APPLY" } else { "PREVIEW" }
$Planned = New-Object System.Collections.Generic.List[string]
$Created = New-Object System.Collections.Generic.List[string]
$Removed = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
$MergeNeeded = New-Object System.Collections.Generic.List[string]
$MergeSuggestions = New-Object System.Collections.Generic.List[object]
$ManagedPaths = New-Object System.Collections.Generic.List[string]
$OwnedPaths = New-Object System.Collections.Generic.List[string]
$InstalledAdapters = New-Object System.Collections.Generic.List[string]
$Conflicts = New-Object System.Collections.Generic.List[string]
$RetiredArtifacts = New-Object System.Collections.Generic.List[object]
$ArtifactRecords = New-Object 'System.Collections.Generic.Dictionary[string,object]' (Get-LizardPathComparer)
$PlanTargetEntries = New-Object 'System.Collections.Generic.Dictionary[string,object]' (Get-LizardPathComparer)
$MemoryTransitionRemovals = New-Object System.Collections.Generic.List[object]
$MemoryTransitionKeys = New-Object 'System.Collections.Generic.HashSet[string]' (Get-LizardPathComparer)

function Add-UniqueListItem {
  param($List, [string]$Value)
  if (-not $List.Contains($Value)) { $List.Add($Value) | Out-Null }
}

function Normalize-RelPath {
  param([string]$Path)
  return $Path.Replace('/', '\').TrimStart('\')
}

function Assert-SafeRelativePath {
  param([string]$Path, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label path is empty." }
  $normalized = Normalize-RelPath $Path
  if ($normalized -match '(^|\\)\.\.($|\\)') { throw "$Label path contains traversal: $Path" }
  if ([System.IO.Path]::IsPathRooted($Path)) { throw "$Label path must be relative: $Path" }
  if ($Path -match '^[A-Za-z]:') { throw "$Label path must not use a drive prefix: $Path" }
  return $normalized
}

function To-RelativeDisplay {
  param([string]$Path)
  if ($Path.StartsWith($TargetRoot)) {
    return $Path.Substring($TargetRoot.Length).TrimStart("\", "/")
  }
  return $Path
}

function Assert-MemoryModeTargetPathAllowed {
  param([string]$Path)
  if ($EffectiveMemoryMode -ne 'off') { return }
  $full = [System.IO.Path]::GetFullPath($Path)
  $memoryRoot = [System.IO.Path]::GetFullPath((Join-Path $TargetRoot '.agent\memory')).TrimEnd([char[]]@('\', '/'))
  if ((Get-LizardPathComparer).Equals($full.TrimEnd([char[]]@('\', '/')), $memoryRoot) -or $full.StartsWith($memoryRoot + [System.IO.Path]::DirectorySeparatorChar, (Get-LizardPathComparison))) {
    throw 'MEMORY_MODE_OFF_WRITE_DENIED: Managed writes under .agent/memory are disabled.'
  }
}

$ExistingInstallManifestPath = Join-Path $TargetRoot ".agent\lizard-agent-layer.install.json"
$existingInstallManifest = $null
$ExistingManifestSchema = $null
if (Test-Path -LiteralPath $ExistingInstallManifestPath) {
  $existingInstallManifest = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $ExistingInstallManifestPath -Raw)
  $ExistingManifestSchema = if ($null -ne $existingInstallManifest.schema_version) { [int]$existingInstallManifest.schema_version } else { 1 }
  if ($ExistingManifestSchema -gt 4) { throw "MANIFEST_READER_TOO_OLD: Target schema $ExistingManifestSchema is newer than supported schema 4." }
  if ($ExistingManifestSchema -ge 4 -and ($existingInstallManifest.PSObject.Properties.Name -notcontains 'memory_mode' -or [string]::IsNullOrWhiteSpace([string]$existingInstallManifest.memory_mode))) {
    throw 'MEMORY_MODE_MANIFEST_INVALID: Schema-v4 manifest is missing memory_mode.'
  }
}
$ExistingArtifactMap = Get-LizardArtifactMap -Manifest $existingInstallManifest -RequireLifecycle:($ExistingManifestSchema -ge 4)
$PreviousMemoryMode = if ($null -ne $existingInstallManifest -and -not [string]::IsNullOrWhiteSpace([string]$existingInstallManifest.memory_mode)) { [string]$existingInstallManifest.memory_mode } else { $null }
$EffectiveMemoryMode = if (-not [string]::IsNullOrWhiteSpace($MemoryMode)) { $MemoryMode } elseif (-not [string]::IsNullOrWhiteSpace($PreviousMemoryMode)) { $PreviousMemoryMode } else { [string]$ProfileDoc.memoryMode }
if ($EffectiveMemoryMode -notin @('curated', 'private-episodic', 'off')) { throw "MEMORY_MODE_INVALID: Unsupported effective memory mode '$EffectiveMemoryMode'." }
$MemoryModeTransition = -not [string]::IsNullOrWhiteSpace($PreviousMemoryMode) -and $PreviousMemoryMode -ne $EffectiveMemoryMode
$MemoryTransitionName = if ($MemoryModeTransition) { "$PreviousMemoryMode->$EffectiveMemoryMode" } else { 'none' }
Set-DocProperty $ProfileDoc 'memoryMode' $EffectiveMemoryMode

$MemoryFileSpecs = New-Object System.Collections.Generic.List[object]
if ($EffectiveMemoryMode -ne 'off') {
  foreach ($spec in @(
    [pscustomobject]@{ source = 'templates\memory\personal\PREFERENCES.md'; destination = '.agent\memory\personal\PREFERENCES.md' },
    [pscustomobject]@{ source = 'templates\memory\semantic\DECISIONS.md'; destination = '.agent\memory\semantic\DECISIONS.md' },
    [pscustomobject]@{ source = 'templates\memory\semantic\LESSONS.md'; destination = '.agent\memory\semantic\LESSONS.md' },
    [pscustomobject]@{ source = 'templates\memory\working\WORKSPACE.md'; destination = '.agent\memory\working\WORKSPACE.md' }
  )) { $MemoryFileSpecs.Add($spec) | Out-Null }
}
if ($EffectiveMemoryMode -eq 'private-episodic') {
  $MemoryFileSpecs.Add([pscustomobject]@{ source = 'templates\memory\episodic\EPISODES.md'; destination = '.agent\memory\episodic\EPISODES.md' }) | Out-Null
}
$AgentGitignoreSource = if ($EffectiveMemoryMode -eq 'off') { 'templates\agent-gitignore-off' } else { 'templates\agent-gitignore' }
$ProtocolSpecs = New-Object System.Collections.Generic.List[object]
$activeProtocols = New-Object System.Collections.Generic.List[string]
$activeProtocols.Add('prompt-trust.md')
$activeProtocols.Add('permissions.md')
$activeProtocols.Add('secret-handling.md')

$effectiveSkills = @($ProfileDoc.skills)
if ($effectiveSkills -contains 'staged-execution') {
  $activeProtocols.Add('staged-execution.md')
  $activeProtocols.Add('context-hygiene.md')
}
if ($effectiveSkills -contains 'release') {
  $activeProtocols.Add('release-gates.md')
}
if ($SelectedHarnesses.Count -ge 2) {
  $activeProtocols.Add('handoff.md')
}

foreach ($protocol in $activeProtocols) {
  $ProtocolSpecs.Add([pscustomobject]@{ source = "protocols\$protocol"; destination = ".agent\protocols\$protocol" }) | Out-Null
}
$ProtocolSpecs.Add([pscustomobject]@{ source = "templates\project-context\$EffectiveMemoryMode.md"; destination = '.agent\protocols\project-context.md' }) | Out-Null
if ($EffectiveMemoryMode -eq 'curated') {
  $ProtocolSpecs.Add([pscustomobject]@{ source = 'protocols\memory-policy.md'; destination = '.agent\protocols\memory-policy.md' }) | Out-Null
} elseif ($EffectiveMemoryMode -eq 'private-episodic') {
  $ProtocolSpecs.Add([pscustomobject]@{ source = 'protocols\memory-policy-private-episodic.md'; destination = '.agent\protocols\memory-policy.md' }) | Out-Null
}

function Get-ExistingArtifactRecord {
  param([string]$RelativePath)
  $key = ConvertTo-LizardArtifactPath $RelativePath
  if ($ExistingArtifactMap.ContainsKey($key)) { return $ExistingArtifactMap[$key] }
  return $null
}

function Set-PlanTargetEntry {
  param(
    [string]$Dest,
    [ValidateSet('file', 'directory')][string]$Kind,
    [ValidateSet('create', 'replace', 'preserve', 'remove')][string]$Action,
    [AllowNull()][string]$IntendedSha256
  )
  $relative = ConvertTo-LizardArtifactPath (To-RelativeDisplay $Dest)
  $existingKind = 'absent'
  $currentSha256 = $null
  if (Test-Path -LiteralPath $Dest -PathType Leaf) {
    $existingKind = 'file'
    $currentSha256 = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $Dest
  } elseif (Test-Path -LiteralPath $Dest -PathType Container) {
    $existingKind = 'directory'
  } elseif (Test-Path -LiteralPath $Dest) {
    $existingKind = 'other'
  }
  $existing = Get-ExistingArtifactRecord $relative
  $ownership = if ($null -ne $existing -and $existing.ownership) { [string]$existing.ownership } else { 'unmanaged' }
  $entry = [pscustomobject][ordered]@{
    path = $relative
    kind = $Kind
    action = $Action
    precondition_kind = $existingKind
    precondition_sha256 = if ([string]::IsNullOrWhiteSpace($currentSha256)) { $null } else { $currentSha256 }
    ownership = $ownership
    intended_sha256 = if ([string]::IsNullOrWhiteSpace($IntendedSha256)) { $null } else { $IntendedSha256 }
  }
  if ($Action -eq 'remove') {
    if ($existingKind -ne $Kind) { throw "MEMORY_TRANSITION_CONTRACT_CONFLICT: Removal target kind mismatch for $relative." }
    if ($ownership -ne 'layer-owned') { throw "MEMORY_TRANSITION_CONTRACT_CONFLICT: Removal target is not layer-owned: $relative." }
    $entry | Add-Member -NotePropertyName precondition_identity_sha256 -NotePropertyValue (Get-LizardPlanTargetIdentitySha256 -TargetRoot $TargetRoot -Path $Dest -Kind $Kind)
  }
  $PlanTargetEntries[$relative] = $entry
}

function Test-MemoryTransitionRetirementPath {
  param([string]$RelativePath)
  $relative = (ConvertTo-LizardArtifactPath $RelativePath).TrimEnd('/')
  if ($EffectiveMemoryMode -eq 'off') {
    return $relative -eq '.agent/memory' -or $relative.StartsWith('.agent/memory/', [System.StringComparison]::OrdinalIgnoreCase) -or $relative -eq '.agent/protocols/memory-policy.md'
  }
  if ($EffectiveMemoryMode -eq 'curated') {
    return $relative -eq '.agent/memory/episodic' -or $relative.StartsWith('.agent/memory/episodic/', [System.StringComparison]::OrdinalIgnoreCase)
  }
  return $false
}

function Test-MemoryModeContractPath {
  param([string]$RelativePath, $Record)
  $relative = ConvertTo-LizardArtifactPath $RelativePath
  if ($relative -in @(
    '.agent/.gitignore', '.agent/project-profile.json', '.agent/protocols/project-context.md',
    '.agent/protocols/memory-policy.md', '.agent/protocols/permissions.md', '.agent/protocols/secret-handling.md',
    '.agent/protocols/handoff.md', '.agent/protocols/context-hygiene.md'
  )) { return $true }
  if ($null -ne $Record -and -not [string]::IsNullOrWhiteSpace([string]$Record.source_path)) {
    return ([string]$Record.source_path).Replace('\', '/').StartsWith('adapters/', [System.StringComparison]::OrdinalIgnoreCase)
  }
  return $false
}

function Get-PhysicalMemoryTransitionItems {
  $items = New-Object System.Collections.Generic.List[object]
  $roots = New-Object System.Collections.Generic.List[string]
  if ($EffectiveMemoryMode -eq 'off') {
    $roots.Add('.agent/memory') | Out-Null
    $roots.Add('.agent/protocols/memory-policy.md') | Out-Null
  } elseif ($EffectiveMemoryMode -eq 'curated') {
    $roots.Add('.agent/memory/episodic') | Out-Null
  }
  foreach ($relativeRoot in @($roots.ToArray())) {
    $absoluteRoot = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relativeRoot.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $absoluteRoot)) { continue }
    $queue = New-Object 'System.Collections.Generic.Queue[string]'
    $queue.Enqueue($absoluteRoot)
    while ($queue.Count -gt 0) {
      $absolute = $queue.Dequeue()
      $item = Get-Item -LiteralPath $absolute -Force
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "MEMORY_TRANSITION_USER_CONTENT: Link or reparse-point residue blocks memory mode '$EffectiveMemoryMode': $(To-RelativeDisplay $absolute)"
      }
      $kind = if ($item.PSIsContainer) { 'directory' } else { 'file' }
      $relative = ConvertTo-LizardArtifactPath (To-RelativeDisplay $absolute)
      $items.Add([pscustomobject]@{ path = $relative; absolute = $absolute; kind = $kind }) | Out-Null
      if ($kind -eq 'directory') {
        foreach ($child in @(Get-ChildItem -LiteralPath $absolute -Force)) { $queue.Enqueue($child.FullName) }
      }
    }
  }
  return @($items.ToArray())
}

function Assert-MemoryTransitionPhysicalSetSafe {
  param([switch]$RegisterPlan)
  $physicalItems = @(Get-PhysicalMemoryTransitionItems)
  if (-not $MemoryModeTransition -and $physicalItems.Count -gt 0) {
    $code = if ($EffectiveMemoryMode -eq 'off') { 'MEMORY_MODE_OFF_RESIDUE' } else { 'MEMORY_MODE_CURATED_RESIDUE' }
    throw "${code}: Existing content conflicts with memory mode '$EffectiveMemoryMode': $($physicalItems[0].path)"
  }
  foreach ($physical in $physicalItems) {
    $key = ConvertTo-LizardArtifactPath ([string]$physical.path)
    if (-not $ExistingArtifactMap.ContainsKey($key)) { throw "MEMORY_TRANSITION_USER_CONTENT: Unknown content blocks transition '$MemoryTransitionName': $key" }
    $record = $ExistingArtifactMap[$key]
    if ([string]$record.kind -ne [string]$physical.kind) { throw "MEMORY_TRANSITION_CONTRACT_CONFLICT: Manifest kind mismatch for $key." }
    if ([string]$record.ownership -ne 'layer-owned' -or (Get-LizardArtifactLifecycle -Record $record) -eq 'removed') {
      throw "MEMORY_TRANSITION_USER_CONTENT: Non-layer-owned or reappeared content blocks transition '$MemoryTransitionName': $key"
    }
    $state = Get-LizardArtifactState -Record $record -TargetPath ([string]$physical.absolute) -ExpectedSourceHash ([string]$record.source_hash) -Kind ([string]$physical.kind)
    if ($state -ne 'layer-owned') { throw "MEMORY_TRANSITION_MODIFIED_CONTENT: State '$state' blocks transition '$MemoryTransitionName': $key" }
    if ($RegisterPlan) {
      Set-PlanTargetEntry -Dest ([string]$physical.absolute) -Kind ([string]$physical.kind) -Action remove -IntendedSha256 $null
      $metadata = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path ([string]$physical.absolute) -Kind $(if ([string]$physical.kind -eq 'file') { 'File' } else { 'Directory' })
      $MemoryTransitionRemovals.Add([pscustomobject]@{
        path = $key
        absolute = [string]$physical.absolute
        kind = [string]$physical.kind
        sha256 = if ([string]$physical.kind -eq 'file') { Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path ([string]$physical.absolute) } else { $null }
        identity_sha256 = Get-LizardPlanTargetIdentitySha256 -Metadata $metadata
      }) | Out-Null
      $null = $MemoryTransitionKeys.Add($key)
    }
  }
  if ($MemoryModeTransition -and $RegisterPlan) {
    foreach ($key in @($ExistingArtifactMap.Keys)) {
      if (-not (Test-MemoryTransitionRetirementPath $key)) { continue }
      $null = $MemoryTransitionKeys.Add($key)
    }
  }
}

function Initialize-MemoryModeTransition {
  if ($EffectiveMemoryMode -notin @('off', 'curated')) { return }
  Assert-MemoryTransitionPhysicalSetSafe -RegisterPlan
}

function Invoke-MemoryModeTransitionRemovals {
  if (-not $Apply -or $MemoryTransitionRemovals.Count -eq 0) { return }
  Assert-MemoryTransitionPhysicalSetSafe
  $ordered = @($MemoryTransitionRemovals.ToArray() | Sort-Object @{ Expression = { if ($_.kind -eq 'file') { 0 } else { 1 } } }, @{ Expression = { -([string]$_.path).Length } }, path)
  foreach ($removal in $ordered) {
    $metadataKind = if ([string]$removal.kind -eq 'file') { 'File' } else { 'Directory' }
    $metadata = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path ([string]$removal.absolute) -Kind $metadataKind
    $identitySha256 = Get-LizardPlanTargetIdentitySha256 -Metadata $metadata
    if ($identitySha256 -ne [string]$removal.identity_sha256) { throw "PLAN_BINDING_TARGET_IDENTITY_MISMATCH: Removal target was replaced: $($removal.path)" }
    if ([string]$removal.kind -eq 'file') {
      $currentHash = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path ([string]$removal.absolute)
      if ($currentHash -ne [string]$removal.sha256) { throw "PLAN_BINDING_TARGET_MISMATCH: Removal target bytes changed: $($removal.path)" }
    }
    Remove-LizardTransactionalItem -Path ([string]$removal.absolute) -Kind $(if ([string]$removal.kind -eq 'file') { 'File' } else { 'EmptyDirectory' }) -ExpectedIdentity $metadata
    Add-UniqueListItem $Removed ([string]$removal.path)
  }
}

function Get-LayerSourcePath {
  param([string]$Source)
  $full = [System.IO.Path]::GetFullPath($Source)
  $root = $LayerRoot.TrimEnd([char[]]@('\', '/'))
  $prefix = $root + [System.IO.Path]::DirectorySeparatorChar
  if ($full.StartsWith($prefix, (Get-LizardPathComparison))) {
    return $full.Substring($prefix.Length).Replace('\', '/')
  }
  return $full
}

function Set-ArtifactRecord {
  param($Record)
  $key = ConvertTo-LizardArtifactPath ([string]$Record.path)
  $ArtifactRecords[$key] = $Record
  Add-UniqueListItem $ManagedPaths ([string]$Record.path).Replace('/', '\')
  if ([string]$Record.ownership -eq 'layer-owned') { Add-UniqueListItem $OwnedPaths ([string]$Record.path).Replace('/', '\') }
}

function Register-Artifact {
  param(
    [string]$Dest,
    [ValidateSet('file', 'directory')][string]$Kind,
    [AllowNull()][string]$SourcePath,
    [AllowNull()][string]$SourceHash,
    [AllowNull()][string]$AdapterId,
    [string[]]$AdapterAliases = @(),
    [AllowNull()][string]$MirrorGroup,
    [switch]$LayerWritten
  )
  $relative = ConvertTo-LizardArtifactPath (To-RelativeDisplay $Dest)
  $existing = Get-ExistingArtifactRecord $relative
  $currentHash = if ($Kind -eq 'file') { Get-LizardSha256 $Dest } else { $null }
  if ($LayerWritten) {
    $ownership = 'layer-owned'
    $state = 'layer-owned'
    $installedHash = $currentHash
  } elseif ($null -ne $existing) {
    $ownership = if ([string]$existing.ownership -in @('layer-owned', 'user-owned', 'adopted')) { [string]$existing.ownership } else { 'user-owned' }
    $installedHash = if ($existing.installed_hash) { [string]$existing.installed_hash } else { $null }
    $state = Get-LizardArtifactState -Record $existing -TargetPath $Dest -ExpectedSourceHash $SourceHash -Kind $Kind
  } else {
    $ownership = 'user-owned'
    $installedHash = $null
    $state = if (Test-Path -LiteralPath $Dest) { 'user-owned' } else { 'missing' }
  }
  Set-ArtifactRecord (New-LizardArtifactRecord -Path $relative -Kind $Kind -Lifecycle active -Ownership $ownership -State $state -SourcePath $SourcePath -SourceVersion $LayerVersion -SourceHash $SourceHash -InstalledHash $installedHash -CurrentHash $currentHash -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup)
}

function Register-RetiredArtifacts {
  foreach ($key in @($ExistingArtifactMap.Keys | Sort-Object)) {
    if ($ArtifactRecords.ContainsKey($key)) { continue }
    if ($MemoryTransitionKeys.Contains($key)) {
      $existing = $ExistingArtifactMap[$key]
      $record = New-LizardArtifactRecord -Path $key -Kind ([string]$existing.kind) -Lifecycle removed -Ownership ([string]$existing.ownership) -State missing `
        -SourcePath ([string]$existing.source_path) -SourceVersion ([string]$existing.source_version) -SourceHash ([string]$existing.source_hash) `
        -InstalledHash ([string]$existing.installed_hash) -CurrentHash $null -AdapterId ([string]$existing.adapter_id) `
        -AdapterAliases @($existing.adapter_aliases) -MirrorGroup ([string]$existing.mirror_group)
      Set-ArtifactRecord $record
      $RetiredArtifacts.Add([pscustomobject][ordered]@{ path = $key; lifecycle = 'removed' }) | Out-Null
      continue
    }
    if ($PlanTargetEntries.ContainsKey($key) -and [string]$PlanTargetEntries[$key].action -in @('create', 'replace')) { continue }
    $existing = $ExistingArtifactMap[$key]
    $relative = ConvertTo-LizardArtifactPath ([string]$existing.path)
    $kind = [string]$existing.kind
    if ($kind -notin @('file', 'directory')) { throw "MANIFEST_ARTIFACT_KIND_INVALID: $relative" }
    $dest = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relative.Replace('/', '\'))
    $pathExists = Test-Path -LiteralPath $dest
    $exists = if ($kind -eq 'directory') { Test-Path -LiteralPath $dest -PathType Container } else { Test-Path -LiteralPath $dest -PathType Leaf }
    if ($pathExists -and -not $exists) { throw "MANIFEST_ARTIFACT_KIND_MISMATCH: $relative expected $kind but another filesystem object exists." }
    $previousLifecycle = Get-LizardArtifactLifecycle -Record $existing
    if ($previousLifecycle -eq 'removed') {
      $lifecycle = 'removed'
      $state = if ($exists) { 'conflict' } else { 'missing' }
      if ($exists) { Add-UniqueListItem $Conflicts ("{0}: removed artifact path reappeared and remains unmanaged." -f $relative) }
    } else {
      $lifecycle = if ($exists) { 'retired-present' } else { 'retired-missing' }
      $state = if ($exists) { Get-LizardArtifactState -Record $existing -TargetPath $dest -ExpectedSourceHash ([string]$existing.source_hash) -Kind $kind } else { 'missing' }
    }
    $currentHash = if ($exists -and $kind -eq 'file') { Get-LizardSha256 $dest } else { $null }
    Set-PlanTargetEntry -Dest $dest -Kind $kind -Action preserve -IntendedSha256 $currentHash
    $record = New-LizardArtifactRecord -Path $relative -Kind $kind -Lifecycle $lifecycle -Ownership ([string]$existing.ownership) -State $state `
      -SourcePath ([string]$existing.source_path) -SourceVersion ([string]$existing.source_version) -SourceHash ([string]$existing.source_hash) `
      -InstalledHash ([string]$existing.installed_hash) -CurrentHash $currentHash -AdapterId ([string]$existing.adapter_id) `
      -AdapterAliases @($existing.adapter_aliases) -MirrorGroup ([string]$existing.mirror_group)
    Set-ArtifactRecord $record
    $RetiredArtifacts.Add([pscustomobject][ordered]@{ path = $relative; lifecycle = $lifecycle }) | Out-Null
  }
}

function Should-ReplacePath {
  param([string]$Dest, [AllowNull()][string]$ExpectedSourceHash)
  if ($Force) { return $true }
  $relative = ConvertTo-LizardArtifactPath (To-RelativeDisplay $Dest)
  $record = Get-ExistingArtifactRecord $relative
  $state = Get-LizardArtifactState -Record $record -TargetPath $Dest -ExpectedSourceHash $ExpectedSourceHash -Kind 'file'
  if ($MemoryModeTransition -and (Test-MemoryModeContractPath -RelativePath $relative -Record $record)) {
    if ($null -ne $record -and [string]$record.ownership -eq 'layer-owned' -and $state -in @('layer-owned', 'stale-unmodified')) { return $true }
    throw "MEMORY_TRANSITION_MODIFIED_CONTENT: Contract path state '$state' blocks transition '$MemoryTransitionName': $relative"
  }
  if ($relative -in @('.agent/skills/_manifest.jsonl', '.agent/skills/_index.md', '.agent/project-profile.json') -and $null -ne $record -and [string]$record.ownership -eq 'layer-owned' -and $state -in @('layer-owned', 'stale-unmodified')) {
    return $true
  }
  if (-not $ForceManaged) { return $false }
  if ($null -ne $record -and [string]$record.ownership -eq 'layer-owned' -and $state -in @('layer-owned', 'stale-unmodified')) { return $true }
  Add-UniqueListItem $Conflicts ("{0}: ForceManaged refused state '{1}' without unchanged layer-owned provenance." -f $relative, $state)
  return $false
}

function Assert-MemoryModePostcondition {
  if (-not $Apply) { return }
  if ($EffectiveMemoryMode -eq 'off') {
    foreach ($relative in @('.agent/memory', '.agent/protocols/memory-policy.md')) {
      $absolute = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relative.Replace('/', '\'))
      if (Test-Path -LiteralPath $absolute) { throw "MEMORY_MODE_OFF_RESIDUE: Physical artifact remains after transition: $relative" }
    }
    foreach ($record in @($ArtifactRecords.Values)) {
      $relative = ConvertTo-LizardArtifactPath ([string]$record.path)
      if (($relative -eq '.agent/memory' -or $relative.StartsWith('.agent/memory/', [System.StringComparison]::OrdinalIgnoreCase) -or $relative -eq '.agent/protocols/memory-policy.md') -and [string]$record.lifecycle -ne 'removed') {
        throw "MEMORY_MODE_OFF_RESIDUE: Non-removed manifest artifact remains after transition: $relative"
      }
      if ([string]$record.kind -ne 'file' -or [string]$record.lifecycle -ne 'active') { continue }
      if (-not $record.adapter_id -and -not $relative.StartsWith('.agent/protocols/', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
      $absolute = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relative.Replace('/', '\'))
      if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) { continue }
      $content = Get-SafeContent -AuthorizedRoot $TargetRoot -Path $absolute
      if ($content -match '(?i)\.agent[/\\]memory|memory[/\\](?:personal|semantic|working|episodic)') {
        throw "MEMORY_MODE_OFF_REFERENCE: Installed instruction contains an operational memory path: $relative"
      }
    }
  } elseif ($EffectiveMemoryMode -eq 'curated') {
    $episodic = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot '.agent\memory\episodic')
    if (Test-Path -LiteralPath $episodic) { throw 'MEMORY_MODE_CURATED_RESIDUE: Episodic content remains after transition.' }
  }
}
function New-MergeSuggestion {
  param([string]$Harness, [string]$InstructionPath, [string]$SidecarPath)
  $snippet = @(
    '## lizard-agent-layer',
    '',
    ('Review `{0}` before using this project with the `{1}` harness.' -f $SidecarPath, $Harness),
    'The sidecar contains reusable agent rules, skills, memory, safety, and handoff guidance installed by `lizard-agent-layer`.',
    'See `.agent/USING.md` for daily operator guidance and review rules.',
    ('Keep repository-specific rules in `{0}` authoritative; merge sidecar guidance intentionally when it fits this project.' -f $InstructionPath)
  ) -join "`n"
  return [ordered]@{
    harness = $Harness
    instruction_path = $InstructionPath
    sidecar_path = $SidecarPath
    action = "Review the sidecar and paste the suggested block into $InstructionPath when you want the harness to load lizard-agent-layer guidance."
    suggested_block = $snippet
  }
}

function Add-MergeSuggestion {
  param([string]$Harness, [string]$InstructionPath, [string]$SidecarPath)
  foreach ($item in @($MergeSuggestions.ToArray())) {
    if ($item.harness -eq $Harness -and $item.instruction_path -eq $InstructionPath -and $item.sidecar_path -eq $SidecarPath) { return }
  }
  $MergeSuggestions.Add((New-MergeSuggestion -Harness $Harness -InstructionPath $InstructionPath -SidecarPath $SidecarPath)) | Out-Null
}

function Add-MarkdownList {
  param($Lines, [string]$Title, $Items)
  $Lines.Add("## $Title") | Out-Null
  $Lines.Add("") | Out-Null
  if (@($Items).Count -eq 0) {
    $Lines.Add('- None') | Out-Null
  } else {
    foreach ($item in @($Items)) { $Lines.Add(('- `{0}`' -f $item)) | Out-Null }
  }
  $Lines.Add("") | Out-Null
}

function New-InstallPlanMarkdown {
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('# lizard-agent-layer install plan') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add(('- Generated: {0}' -f (Get-Date).ToUniversalTime().ToString('o'))) | Out-Null
  $lines.Add(('- Mode: `{0}`' -f $Mode)) | Out-Null
  $lines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
  $lines.Add(('- Layer version: `{0}`' -f $LayerVersion)) | Out-Null
  $lines.Add(('- Profile: `{0}`' -f $Profile)) | Out-Null
  $packDisplay = if ($SelectedPacks.Count -gt 0) { $SelectedPacks -join ', ' } else { 'none' }
  $lines.Add(('- Packs: `{0}`' -f $packDisplay)) | Out-Null
  $requestedPackDisplay = if ($RequestedPacks.Count -gt 0) { $RequestedPacks -join ', ' } else { 'none' }
  $lines.Add(('- Requested packs: `{0}`' -f $requestedPackDisplay)) | Out-Null
  $lines.Add(('- Risk level: `{0}`' -f $ProfileDoc.riskLevel)) | Out-Null
  $lines.Add(('- Memory mode: `{0}`' -f $ProfileDoc.memoryMode)) | Out-Null
  $lines.Add(('- Harnesses: `{0}`' -f ($SelectedHarnesses -join ', '))) | Out-Null
  $lines.Add(('- Routing policy: `{0}`' -f $EffectiveRoutingPolicy)) | Out-Null
  $lines.Add(('- Model mode: `{0}`' -f $EffectiveModelMode)) | Out-Null
  $lines.Add(('- Daily use: {0}' -f $(if ($EffectiveModelMode -eq 'inherit-current') { 'Submit ordinary task prompts; the active IDE model completes all stages without picker changes.' } else { 'Submit ordinary task prompts; the configured automatic runtime selects models without manual picker changes.' }))) | Out-Null
  if ($EffectiveModelRuntime) { $lines.Add(('- Model runtime: `{0}`' -f $EffectiveModelRuntime)) | Out-Null }
  $lines.Add('') | Out-Null
  $lines.Add('## Summary') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add(('- Planned paths: `{0}`' -f $Planned.Count)) | Out-Null
  $lines.Add(('- Created paths: `{0}`' -f $Created.Count)) | Out-Null
  $lines.Add(('- Skipped existing paths: `{0}`' -f $Skipped.Count)) | Out-Null
  $lines.Add(('- Manual merge items: `{0}`' -f $MergeNeeded.Count)) | Out-Null
  $lines.Add(('- Ownership conflicts: `{0}`' -f $Conflicts.Count)) | Out-Null
  $lines.Add(('- Retired artifacts preserved: `{0}`' -f $RetiredArtifacts.Count)) | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('## Commands') | Out-Null
  $lines.Add('') | Out-Null
  $previewArguments = New-Object System.Collections.Generic.List[string]
  foreach ($argument in @('-TargetPath', $TargetRoot, '-Profile', $Profile, '-Harnesses', ($SelectedHarnesses -join ','))) { $previewArguments.Add([string]$argument) | Out-Null }
  if ($RequestedPacks.Count -gt 0) { $previewArguments.Add('-Packs') | Out-Null; $previewArguments.Add(($RequestedPacks -join ',')) | Out-Null }
  $previewArguments.Add('-RoutingPolicy') | Out-Null; $previewArguments.Add($EffectiveRoutingPolicy) | Out-Null
  $previewArguments.Add('-ModelMode') | Out-Null; $previewArguments.Add($EffectiveModelMode) | Out-Null
  if ($EffectiveModelInventory) { $previewArguments.Add('-ModelInventory') | Out-Null; $previewArguments.Add($EffectiveModelInventory) | Out-Null }
  if ($EffectiveModelRuntime) { $previewArguments.Add('-ModelRuntime') | Out-Null; $previewArguments.Add($EffectiveModelRuntime) | Out-Null }
  $previewCommand = [string](New-LizardPowerShellFileInvocation -ScriptPath $InstallScriptPath -ArgumentList $previewArguments.ToArray() -ResolveCurrent).display
  $canonicalDisplay = if ($EffectiveCanonicalPlanPath) { $EffectiveCanonicalPlanPath } else { '<canonical-plan.json>' }
  $applyArguments = @($previewArguments.ToArray()) + @('-Apply', '-ApprovedPlanPath', $canonicalDisplay, '-ApprovedPlanSha256', '<independently-reviewed-sha256>', '-HumanApproved')
  $applyCommand = [string](New-LizardPowerShellFileInvocation -ScriptPath $InstallScriptPath -ArgumentList $applyArguments -ResolveCurrent).display
  $lines.Add('Preview:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add($previewCommand) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('Apply:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add($applyCommand) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  Add-MarkdownList $lines 'Requested packs' @($RequestedPacks)
  Add-MarkdownList $lines 'Packs' @($SelectedPacks)
  Add-MarkdownList $lines 'Skills' @($ProfileDoc.skills)
  Add-MarkdownList $lines 'Planned paths' @($Planned)
  Add-MarkdownList $lines 'Created paths' @($Created)
  Add-MarkdownList $lines 'Skipped existing paths' @($Skipped)
  Add-MarkdownList $lines 'Manual merge needed' @($MergeNeeded)
  Add-MarkdownList $lines 'Ownership conflicts' @($Conflicts)
  Add-MarkdownList $lines 'Retired artifacts preserved' @($RetiredArtifacts.ToArray() | ForEach-Object { "$($_.lifecycle):$($_.path)" })
  $lines.Add('## Merge suggestions') | Out-Null
  $lines.Add('') | Out-Null
  if ($MergeSuggestions.Count -eq 0) {
    $lines.Add('- None') | Out-Null
  } else {
    foreach ($suggestion in @($MergeSuggestions.ToArray())) {
      $lines.Add(('### {0}: {1}' -f $suggestion.harness, $suggestion.instruction_path)) | Out-Null
      $lines.Add('') | Out-Null
      $lines.Add(('- Sidecar: `{0}`' -f $suggestion.sidecar_path)) | Out-Null
      $lines.Add(('- Action: {0}' -f $suggestion.action)) | Out-Null
      $lines.Add('') | Out-Null
      $lines.Add('Suggested block:') | Out-Null
      $lines.Add('') | Out-Null
      $lines.Add('```markdown') | Out-Null
      $lines.Add($suggestion.suggested_block) | Out-Null
      $lines.Add('```') | Out-Null
      $lines.Add('') | Out-Null
    }
  }
  return ($lines -join "`n")
}

function Write-PlanReport {
  if (-not $ShouldWritePlan -or $SuppressPlanReport) { return }
  $markdown = New-InstallPlanMarkdown
  if ($Apply -and $PlanInsideTarget) {
    New-LizardTransactionalDirectory -Path $planParent | Out-Null
    Set-LizardTransactionalContent -Path $EffectivePlanPath -Value $markdown
  } else {
    if (-not (Test-Path -LiteralPath $planParent)) { $script:planParent = Initialize-SafeDirectory -Path $planParent }
    Set-SafeContent -AuthorizedRoot $planParent -Path $EffectivePlanPath -Value $markdown
  }
}

function Get-InstallPlanInputs {
  $inputs = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([System.StringComparer]::OrdinalIgnoreCase)
  function Add-InputFile {
    param([string]$Scope, [string]$Root, [string]$Path, [string]$DisplayPath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $display = $DisplayPath.Replace('\', '/')
    $key = "$Scope`:$display"
    $inputs[$key] = [pscustomobject][ordered]@{
      scope = $Scope
      path = $display
      sha256 = Get-SafeFileHash -AuthorizedRoot $Root -Path $Path
    }
  }
  function Add-LayerTree {
    param([string]$RelativeRoot)
    $absoluteRoot = Join-Path $LayerRoot $RelativeRoot
    if (-not (Test-Path -LiteralPath $absoluteRoot -PathType Container)) { return }
    Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
      $relative = $_.FullName.Substring($LayerRoot.Length).TrimStart([char[]]@('\', '/'))
      Add-InputFile -Scope layer -Root $LayerRoot -Path $_.FullName -DisplayPath $relative
    }
  }

  foreach ($relative in @(
    'VERSION', 'scripts\install.ps1', 'scripts\Lizard.Plan.psm1', 'scripts\Lizard.SafeFs.psm1',
    'scripts\Lizard.Manifest.psm1', 'scripts\Lizard.Transaction.psm1'
  )) {
    Add-InputFile -Scope layer -Root $LayerRoot -Path (Join-Path $LayerRoot $relative) -DisplayPath $relative
  }
  Add-InputFile -Scope layer -Root $LayerRoot -Path $ProfilePath -DisplayPath ("profiles/{0}.json" -f $Profile)
  foreach ($packName in @($SelectedPacks)) {
    $packInfo = Get-PackManifestInfo $packName
    if ([string]$packInfo.source -eq 'target-overlay') {
      Add-InputFile -Scope target -Root $TargetRoot -Path ([string]$packInfo.path) -DisplayPath ([string]$packInfo.display)
    } else {
      Add-InputFile -Scope layer -Root $LayerRoot -Path ([string]$packInfo.path) -DisplayPath ([string]$packInfo.display)
    }
  }
  foreach ($adapterName in @($SelectedHarnesses)) { Add-LayerTree -RelativeRoot ("adapters\{0}" -f $adapterName) }
  foreach ($skillName in @($ProfileDoc.skills)) { Add-LayerTree -RelativeRoot ("skills\{0}" -f $skillName) }
  Add-InputFile -Scope layer -Root $LayerRoot -Path (Join-Path $LayerRoot $AgentGitignoreSource) -DisplayPath $AgentGitignoreSource
  Add-InputFile -Scope layer -Root $LayerRoot -Path (Join-Path $LayerRoot 'templates\operator-card.md') -DisplayPath 'templates/operator-card.md'
  foreach ($spec in @($MemoryFileSpecs.ToArray())) {
    Add-InputFile -Scope layer -Root $LayerRoot -Path (Join-Path $LayerRoot ([string]$spec.source)) -DisplayPath ([string]$spec.source)
  }
  foreach ($spec in @($ProtocolSpecs.ToArray())) {
    Add-InputFile -Scope layer -Root $LayerRoot -Path (Join-Path $LayerRoot ([string]$spec.source)) -DisplayPath ([string]$spec.source)
  }
  Add-InputFile -Scope layer -Root $LayerRoot -Path $RoutingPolicyPath -DisplayPath ("routing-policies/{0}.json" -f $EffectiveRoutingPolicy)
  foreach ($modelName in @($BoundRoutingModelNames)) {
    Add-InputFile -Scope layer -Root $LayerRoot -Path (Join-Path $LayerRoot "model-profiles\$modelName.json") -DisplayPath "model-profiles/$modelName.json"
  }
  if ($EffectiveModelInventory) {
    Add-InputFile -Scope target -Root $TargetRoot -Path $inventoryTargetPath -DisplayPath $EffectiveModelInventory
  }
  if ($EffectiveModelRuntime) {
    Add-InputFile -Scope target -Root $TargetRoot -Path $runtimeTargetPath -DisplayPath $EffectiveModelRuntime
  }
  return @($inputs.Values | Sort-Object scope, path)
}

function Get-InstallInvocationOptions {
  return [ordered]@{
    profile = $Profile
    risk_level = [string]$ProfileDoc.riskLevel
    harnesses = @($SelectedHarnesses | Sort-Object -Unique)
    requested_packs = @($RequestedPacks | Sort-Object -Unique)
    expanded_packs = @($SelectedPacks)
    memory_mode = $EffectiveMemoryMode
    previous_memory_mode = $PreviousMemoryMode
    memory_transition = $MemoryTransitionName
    routing_policy = $EffectiveRoutingPolicy
    model_mode = $EffectiveModelMode
    model_inventory = $EffectiveModelInventory
    model_runtime = $EffectiveModelRuntime
    force = $Force.IsPresent
    force_managed = $ForceManaged.IsPresent
    write_plan = $ShouldWritePlan
    plan_path = $EffectivePlanPath
    allow_target_report_write = $AllowTargetReportWrite.IsPresent
    plan_ttl_minutes = $PlanTtlMinutes
    test_fail_after_mutation = $TestFailAfterMutation
  }
}

function Get-InstallPlanOptions {
  $options = Get-InstallInvocationOptions
  $options['retired_artifacts'] = @($RetiredArtifacts.ToArray() | Sort-Object path | ForEach-Object {
    [ordered]@{ path = [string]$_.path; lifecycle = [string]$_.lifecycle }
  })
  $options['removed_memory_artifacts'] = @($MemoryTransitionRemovals.ToArray() | Sort-Object path | ForEach-Object { [string]$_.path })
  return $options
}

function New-CurrentInstallOperationPlan {
  $gitHead = Get-LizardSourceGitHead -Root $LayerRoot
  return New-LizardOperationPlan -OperationKind install -TargetRoot $TargetRoot -LayerRoot $LayerRoot `
    -Options (Get-InstallPlanOptions) -Inputs (Get-InstallPlanInputs) `
    -TargetEntries @($PlanTargetEntries.Values | Sort-Object path) -NestedPlan $null `
    -TtlMinutes $PlanTtlMinutes -LayerVersion $LayerVersion -GitHead $gitHead
}

function Write-CanonicalInstallPlan {
  if (-not $ShouldWriteCanonicalPlan) { return $null }
  $plan = New-CurrentInstallOperationPlan
  Write-LizardOperationPlan -Plan $plan -Path $EffectiveCanonicalPlanPath | Out-Null
  return $plan
}

function Ensure-Dir {
  param([string]$Path, [AllowNull()][string]$AdapterId, [string[]]$AdapterAliases = @(), [AllowNull()][string]$MirrorGroup)
  Assert-MemoryModeTargetPathAllowed -Path $Path
  $candidatePath = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/'))
  if ((Get-LizardPathComparer).Equals($candidatePath, $TargetRoot.TrimEnd([char[]]@('\', '/')))) { return }
  $Path = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $Path
  $parent = Split-Path -Parent $Path
  if (-not (Get-LizardPathComparer).Equals($parent, $TargetRoot)) {
    Ensure-Dir -Path $parent -AdapterId $null -AdapterAliases @() -MirrorGroup $null
  }
  $label = To-RelativeDisplay $Path
  $artifactKey = ConvertTo-LizardArtifactPath $label
  if ($ArtifactRecords.ContainsKey($artifactKey)) { return }
  Add-UniqueListItem $ManagedPaths $label
  if (Test-Path -LiteralPath $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "DESTINATION_TYPE_CONFLICT: Expected directory but found file: $label" }
    Set-PlanTargetEntry -Dest $Path -Kind directory -Action preserve -IntendedSha256 $null
    Add-UniqueListItem $Skipped $label
    Register-Artifact -Dest $Path -Kind directory -SourcePath $null -SourceHash $null -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup
    return
  }
  Set-PlanTargetEntry -Dest $Path -Kind directory -Action create -IntendedSha256 $null
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    New-LizardTransactionalDirectory -Path $Path | Out-Null
    Add-UniqueListItem $Created $label
    Register-Artifact -Dest $Path -Kind directory -SourcePath $null -SourceHash $null -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup -LayerWritten
  }
}

function Copy-IfMissing {
  param([string]$Source, [string]$Dest, [AllowNull()][string]$AdapterId, [string[]]$AdapterAliases = @(), [AllowNull()][string]$MirrorGroup)
  if (-not (Test-Path -LiteralPath $Source)) { throw "Missing source file: $Source" }
  Assert-MemoryModeTargetPathAllowed -Path $Dest
  $Dest = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $Dest
  $sourceHash = Get-LizardSha256 $Source
  $sourcePath = Get-LayerSourcePath $Source
  $label = To-RelativeDisplay $Dest
  Add-UniqueListItem $ManagedPaths $label
  $parent = Split-Path -Parent $Dest
  Ensure-Dir -Path $parent -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup
  $destExists = Test-Path -LiteralPath $Dest
  $shouldReplace = if ($destExists) { Should-ReplacePath -Dest $Dest -ExpectedSourceHash $sourceHash } else { $false }
  if ($destExists -and -not $shouldReplace) {
    Set-PlanTargetEntry -Dest $Dest -Kind file -Action preserve -IntendedSha256 $sourceHash
    Add-UniqueListItem $Skipped $label
    Register-Artifact -Dest $Dest -Kind file -SourcePath $sourcePath -SourceHash $sourceHash -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup
    return
  }
  Set-PlanTargetEntry -Dest $Dest -Kind file -Action $(if ($destExists) { 'replace' } else { 'create' }) -IntendedSha256 $sourceHash
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    Copy-LizardTransactionalFile -SourceAuthorizedRoot $LayerRoot -Source $Source -Destination $Dest -Force:$shouldReplace
    Add-UniqueListItem $Created $label
    Register-Artifact -Dest $Dest -Kind file -SourcePath $sourcePath -SourceHash $sourceHash -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup -LayerWritten
  }
}

function Copy-SkillPackage {
  param([string]$SkillName, [string]$DestRoot, [AllowNull()][string]$AdapterId, [string[]]$AdapterAliases = @())
  if ($SkillName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid skill name '$SkillName'." }
  if (-not $SkillPackageCatalog.ContainsKey($SkillName)) { throw "Missing validated skill package metadata: $SkillName" }
  $sourceDir = Join-Path $LayerRoot "skills\$SkillName"
  $sourceSkill = Join-Path $sourceDir 'SKILL.md'
  if (-not (Test-Path -LiteralPath $sourceSkill)) { throw "Missing skill package: $SkillName" }
  $destSkillDir = Join-Path $DestRoot $SkillName
  Ensure-Dir -Path $destSkillDir -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup ("skill:{0}:directory" -f $SkillName)
  Get-ChildItem -LiteralPath $sourceDir -Recurse -Directory | Sort-Object @{ Expression = { $_.FullName.Length } }, FullName | ForEach-Object {
    $relative = $_.FullName.Substring($sourceDir.Length).TrimStart([char[]]@('\', '/'))
    $mirrorGroup = "skill:{0}:directory:{1}" -f $SkillName, $relative.Replace('\', '/')
    Ensure-Dir -Path (Join-Path $destSkillDir $relative) -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $mirrorGroup
  }
  Get-ChildItem -LiteralPath $sourceDir -Recurse -File | Sort-Object FullName | ForEach-Object {
    $relative = $_.FullName.Substring($sourceDir.Length).TrimStart([char[]]@('\', '/'))
    $mirrorGroup = "skill:{0}:{1}" -f $SkillName, $relative.Replace('\', '/')
    Copy-IfMissing -Source $_.FullName -Dest (Join-Path $destSkillDir $relative) -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $mirrorGroup
  }
}
function Write-IfMissing {
  param([string]$Dest, [string]$Content, [string]$SourcePath = 'generated:content', [AllowNull()][string]$AdapterId, [string[]]$AdapterAliases = @(), [AllowNull()][string]$MirrorGroup)
  Assert-MemoryModeTargetPathAllowed -Path $Dest
  $Dest = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath $Dest
  $sourceHash = Get-LizardStringSha256 $Content
  $label = To-RelativeDisplay $Dest
  Add-UniqueListItem $ManagedPaths $label
  $parent = Split-Path -Parent $Dest
  Ensure-Dir -Path $parent -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup
  $destExists = Test-Path -LiteralPath $Dest
  $shouldReplace = if ($destExists) { Should-ReplacePath -Dest $Dest -ExpectedSourceHash $sourceHash } else { $false }
  if ($destExists -and -not $shouldReplace) {
    Set-PlanTargetEntry -Dest $Dest -Kind file -Action preserve -IntendedSha256 $sourceHash
    Add-UniqueListItem $Skipped $label
    Register-Artifact -Dest $Dest -Kind file -SourcePath $SourcePath -SourceHash $sourceHash -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup
    return
  }
  Set-PlanTargetEntry -Dest $Dest -Kind file -Action $(if ($destExists) { 'replace' } else { 'create' }) -IntendedSha256 $sourceHash
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    Set-LizardTransactionalContent -Path $Dest -Value $Content
    Add-UniqueListItem $Created $label
    Register-Artifact -Dest $Dest -Kind file -SourcePath $SourcePath -SourceHash $sourceHash -AdapterId $AdapterId -AdapterAliases $AdapterAliases -MirrorGroup $MirrorGroup -LayerWritten
  }
}

function Copy-InstructionFile {
  param($Adapter, [string]$AdapterDir, [string]$AdapterName, [string[]]$AdapterAliases = @())
  $instruction = $Adapter.instruction
  $srcRel = Assert-SafeRelativePath $instruction.src "adapter instruction src"
  $dstRel = Assert-SafeRelativePath $instruction.dst "adapter instruction dst"
  $src = Join-Path $AdapterDir $srcRel
  $dst = Join-Path $TargetRoot $dstRel
  $policy = if ($instruction.mergePolicy) { $instruction.mergePolicy } else { 'sidecar-if-exists' }

  $sourceHash = Get-LizardSha256 $src
  $shouldReplaceInstruction = if (Test-Path -LiteralPath $dst) { Should-ReplacePath -Dest $dst -ExpectedSourceHash $sourceHash } else { $false }
  if ((Test-Path -LiteralPath $dst) -and -not $shouldReplaceInstruction -and $policy -ne 'overwrite') {
    if ((Get-LizardSha256 $dst) -eq $sourceHash) {
      Set-PlanTargetEntry -Dest $dst -Kind file -Action preserve -IntendedSha256 $sourceHash
      Register-Artifact -Dest $dst -Kind file -SourcePath (Get-LayerSourcePath $src) -SourceHash $sourceHash -AdapterId $AdapterName -AdapterAliases $AdapterAliases -MirrorGroup ("adapter-instruction:{0}" -f (ConvertTo-LizardArtifactPath $dstRel))
      return $true
    }
    $existing = Get-Content -LiteralPath $dst -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'lizard-agent-layer') {
      Set-PlanTargetEntry -Dest $dst -Kind file -Action preserve -IntendedSha256 $sourceHash
      Add-UniqueListItem $Skipped $dstRel
      Add-UniqueListItem $ManagedPaths $dstRel
      Register-Artifact -Dest $dst -Kind file -SourcePath (Get-LayerSourcePath $src) -SourceHash $sourceHash -AdapterId $AdapterName -AdapterAliases $AdapterAliases -MirrorGroup ("adapter-instruction:{0}" -f (ConvertTo-LizardArtifactPath $dstRel))
      return $false
    }
    if ($policy -eq 'sidecar-if-exists') {
      $sidecarRel = if ($instruction.sidecar) { Assert-SafeRelativePath $instruction.sidecar "adapter instruction sidecar" } else { "$dstRel.lizard-agent-layer" }
      $sidecarPath = Join-Path $TargetRoot $sidecarRel
      Copy-IfMissing -Source $src -Dest $sidecarPath -AdapterId $AdapterName -AdapterAliases $AdapterAliases -MirrorGroup ("adapter-instruction:{0}" -f (ConvertTo-LizardArtifactPath $dstRel))
      Add-UniqueListItem $MergeNeeded "$dstRel exists; review $sidecarRel and merge intentionally."
      Add-MergeSuggestion -Harness $AdapterName -InstructionPath $dstRel -SidecarPath $sidecarRel
      if (-not $Apply) { return $true }
      return ((Get-LizardSha256 $sidecarPath) -eq $sourceHash)
    }
    Add-UniqueListItem $Skipped $dstRel
    Set-PlanTargetEntry -Dest $dst -Kind file -Action preserve -IntendedSha256 $sourceHash
    Register-Artifact -Dest $dst -Kind file -SourcePath (Get-LayerSourcePath $src) -SourceHash $sourceHash -AdapterId $AdapterName -AdapterAliases $AdapterAliases -MirrorGroup ("adapter-instruction:{0}" -f (ConvertTo-LizardArtifactPath $dstRel))
    return $false
  }

  Copy-IfMissing -Source $src -Dest $dst -AdapterId $AdapterName -AdapterAliases $AdapterAliases -MirrorGroup ("adapter-instruction:{0}" -f (ConvertTo-LizardArtifactPath $dstRel))
  if (-not $Apply) { return $true }
  return ((Get-LizardSha256 $dst) -eq $sourceHash)
}

function Install-Adapter {
  param([string]$AdapterName)
  $entry = $AdapterDocMap[$AdapterName]
  $adapter = $entry.manifest
  $adapterDir = [string]$entry.adapter_dir
  if ($EffectiveInstructionMap.ContainsKey($AdapterName)) {
    $effective = $EffectiveInstructionMap[$AdapterName]
    $adapterAliases = @($effective.aliases.ToArray())
    $identityInstalled = Copy-InstructionFile -Adapter $adapter -AdapterDir $adapterDir -AdapterName $AdapterName -AdapterAliases $adapterAliases
    if ($identityInstalled) { Add-UniqueListItem $InstalledAdapters $AdapterName }
  }

  foreach ($mirror in @($adapter.skillMirrors)) {
    $mirrorRel = Assert-SafeRelativePath $mirror.dst "skill mirror dst"
    Ensure-Dir -Path (Join-Path $TargetRoot $mirrorRel) -AdapterId $AdapterName -MirrorGroup ("adapter-mirror:{0}" -f (ConvertTo-LizardArtifactPath $mirrorRel))
    foreach ($skill in @($ProfileDoc.skills)) {
      Copy-SkillPackage -SkillName $skill -DestRoot (Join-Path $TargetRoot $mirrorRel) -AdapterId $AdapterName
    }
  }
}

function Write-InstallManifest {
  $manifestPath = Join-Path $TargetRoot ".agent\lizard-agent-layer.install.json"
  $label = To-RelativeDisplay $manifestPath
  Add-UniqueListItem $ManagedPaths $label
  $manifestExists = Test-Path -LiteralPath $manifestPath
  Set-PlanTargetEntry -Dest $manifestPath -Kind file -Action $(if ($manifestExists) { 'replace' } else { 'create' }) -IntendedSha256 $null
  $doc = New-Object System.Collections.Specialized.OrderedDictionary
  $doc['schema_version'] = 4
  $doc['layer'] = "lizard-agent-layer"
  $doc['layer_version'] = $LayerVersion
  $doc['minimum_reader_schema_version'] = 4
  $doc['writer_schema_version'] = 4
  if ($ExistingManifestSchema -and $ExistingManifestSchema -lt 4) { $doc['migrated_from_schema_version'] = $ExistingManifestSchema }
  $doc['profile'] = $Profile
  $doc['requested_packs'] = @($RequestedPacks)
  $doc['pack_sources'] = @($PackSources.ToArray())
  $doc['packs'] = @($SelectedPacks)
  $doc['installed_at'] = (Get-Date).ToUniversalTime().ToString("o")
  $doc['target_root'] = $TargetRoot
  $doc['memory_mode'] = $ProfileDoc.memoryMode
  $doc['risk_level'] = $ProfileDoc.riskLevel
  $doc['harnesses'] = @($SelectedHarnesses)
  $doc['model_profiles'] = if ($ProfileDoc.PSObject.Properties.Name -contains 'modelProfiles' -and $null -ne $ProfileDoc.modelProfiles) { $ProfileDoc.modelProfiles } else { [pscustomobject]@{} }
  $doc['model_mode'] = $EffectiveModelMode
  $doc['model_inventory'] = if ($EffectiveModelInventory) { $EffectiveModelInventory.Replace('\\', '/') } else { $null }
  $doc['model_runtime'] = if ($EffectiveModelRuntime) { $EffectiveModelRuntime.Replace('\\', '/') } else { $null }
  $doc['routing_policy'] = $EffectiveRoutingPolicy
  $doc['routing_models'] = [object[]]@($BoundRoutingModelNames)
  $doc['skills'] = @($ProfileDoc.skills)
  $doc['adapters'] = @($InstalledAdapters.ToArray())
  $doc['adapter_aliases'] = @($AdapterComposition.aliases)
  $doc['artifacts'] = @($ArtifactRecords.Values | Sort-Object path)
  $doc['managed_paths'] = @($ManagedPaths.ToArray())
  $doc['owned_paths'] = @($OwnedPaths.ToArray())
  $doc['merge_needed'] = @($MergeNeeded.ToArray())
  $doc['merge_suggestions'] = @($MergeSuggestions.ToArray())
  $doc['conflicts'] = @($Conflicts.ToArray())
  if ($Apply -and $null -ne $ApprovedPlan) {
    $doc['applied_plan_id'] = [string]$ApprovedPlan.plan_id
    $doc['applied_plan_sha256'] = $ApprovedPlanSha256.ToLowerInvariant()
  }
  if ($Apply -and $null -ne $TransactionContext) { $doc['transaction_operation_id'] = [string]$TransactionContext.operation_id }
  if ($Apply) {
    Set-LizardTransactionalContent -Path $manifestPath -Value ($doc | ConvertTo-Json -Depth 10)
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  } else {
    Add-UniqueListItem $Planned $label
  }
}

$AdapterEntries = New-Object System.Collections.Generic.List[object]
$AdapterDocMap = @{}
foreach ($adapterName in $SelectedHarnesses) {
  if ($adapterName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid adapter name '$adapterName'." }
  $adapterDir = Join-Path $LayerRoot "adapters\$adapterName"
  $adapterManifestPath = Join-Path $adapterDir 'adapter.json'
  if (-not (Test-Path -LiteralPath $adapterManifestPath)) { throw "Missing adapter manifest for '$adapterName': $adapterManifestPath" }
  $adapter = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $LayerRoot -Path $adapterManifestPath -Raw)
  if ($adapter.name -ne $adapterName) { throw "Adapter manifest name '$($adapter.name)' does not match folder '$adapterName'." }
  $entry = [pscustomobject]@{ name = $adapterName; manifest = $adapter; adapter_dir = $adapterDir }
  $AdapterEntries.Add($entry) | Out-Null
  $AdapterDocMap[$adapterName] = $entry
}
$AdapterComposition = Resolve-LizardAdapterComposition -Adapters @($AdapterEntries.ToArray())
$EffectiveInstructionMap = @{}
foreach ($effective in @($AdapterComposition.effective_instructions)) { $EffectiveInstructionMap[[string]$effective.name] = $effective }

function Assert-ApprovedInstallPlanCurrent {
  if (-not $Apply) { return }
  if ([string]$ApprovedPlan.intent.target_root -ne $TargetRoot -or [string]$ApprovedPlan.intent.layer_root -ne $LayerRoot) {
    throw 'PLAN_BINDING_ROOT_MISMATCH: Approved target or layer root differs from the current invocation.'
  }
  if ([string]$ApprovedPlan.intent.layer_version -ne $LayerVersion) {
    throw 'PLAN_BINDING_SOURCE_MISMATCH: Approved layer version differs from the current layer.'
  }
  $currentGitHead = Get-LizardSourceGitHead -Root $LayerRoot
  if ([string]$ApprovedPlan.intent.source_git_head -ne [string]$currentGitHead) {
    throw 'PLAN_BINDING_SOURCE_MISMATCH: Approved source Git HEAD differs from the current layer.'
  }
  $currentInvocationOptions = Get-InstallInvocationOptions
  $approvedInvocationOptions = [ordered]@{}
  foreach ($key in @($currentInvocationOptions.Keys)) {
    if ($ApprovedPlan.intent.options.PSObject.Properties.Name -notcontains $key) { throw "PLAN_BINDING_OPTIONS_MISMATCH: Approved plan lacks option '$key'." }
    $approvedInvocationOptions[$key] = $ApprovedPlan.intent.options.$key
  }
  $approvedOptions = ConvertTo-LizardCanonicalJson $approvedInvocationOptions
  $currentOptions = ConvertTo-LizardCanonicalJson $currentInvocationOptions
  if (-not $approvedOptions.Equals($currentOptions, [System.StringComparison]::Ordinal)) {
    throw 'PLAN_BINDING_OPTIONS_MISMATCH: Current install options differ from the approved plan.'
  }
  Assert-ApprovedInstallCriticalBindingsCurrent
  $candidatePlan = Get-CurrentInstallProbePlan
  Assert-LizardPlanIntentMatch -ApprovedPlan $ApprovedPlan -CurrentPlan $candidatePlan | Out-Null
}

function Get-CurrentInstallProbePlan {
  $probeRoot = Initialize-SafeDirectory -Path (Join-Path $LayerRoot '.tmp\plan-probes')
  $probePath = Join-Path $probeRoot ("lizard-install-plan-probe-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
  $probeDigestPath = "$probePath.sha256"
  $hostPath = Get-LizardPowerShellHostPath
  $invokeArgs = @((Get-LizardPowerShellFilePrefix) + @(
    $InstallScriptPath,
    '-TargetPath', $TargetRoot,
    '-Profile', $Profile,
    '-Harnesses', ($SelectedHarnesses -join ','),
    '-CanonicalPlanPath', $probePath,
    '-PlanTtlMinutes', [string]$PlanTtlMinutes,
    '-TestFailAfterMutation', [string]$TestFailAfterMutation,
    '-InternalPlanProbe',
    '-SuppressPlanReport'
  ))
  if (-not [string]::IsNullOrWhiteSpace($MemoryMode)) { $invokeArgs += @('-MemoryMode', $EffectiveMemoryMode) }
  if ($RequestedPacks.Count -gt 0) { $invokeArgs += @('-Packs', ($RequestedPacks -join ',')) }
  if (-not [string]::IsNullOrWhiteSpace($RoutingPolicy)) { $invokeArgs += @('-RoutingPolicy', $RoutingPolicy) }
  if (-not [string]::IsNullOrWhiteSpace($ModelMode)) { $invokeArgs += @('-ModelMode', $ModelMode) }
  if (-not [string]::IsNullOrWhiteSpace($ModelInventory)) { $invokeArgs += @('-ModelInventory', $ModelInventory) }
  if (-not [string]::IsNullOrWhiteSpace($ModelRuntime)) { $invokeArgs += @('-ModelRuntime', $ModelRuntime) }
  if ($Force) { $invokeArgs += '-Force' }
  if ($ForceManaged) { $invokeArgs += '-ForceManaged' }
  if ($ShouldWritePlan) {
    $invokeArgs += @('-WritePlan', '-PlanPath', $EffectivePlanPath)
  }
  if ($AllowTargetReportWrite) { $invokeArgs += '-AllowTargetReportWrite' }

  try {
    $global:LASTEXITCODE = 0
    $previousErrorAction = $ErrorActionPreference
    try {
      $ErrorActionPreference = 'Continue'
      $probeOutput = & $hostPath @invokeArgs 2>&1 | Out-String
      $probeExitCode = [int]$LASTEXITCODE
    } finally {
      $ErrorActionPreference = $previousErrorAction
    }
    if ($probeExitCode -ne 0) { throw "PLAN_BINDING_PROBE_FAILED: Candidate plan probe failed: $probeOutput" }
    if (-not (Test-Path -LiteralPath $probePath -PathType Leaf)) { throw 'PLAN_BINDING_PROBE_FAILED: Candidate plan probe produced no plan.' }
    $probeSha256 = Get-SafeFileHash -AuthorizedRoot $probeRoot -Path $probePath
    return Read-LizardApprovedPlan -Path $probePath -ExpectedSha256 $probeSha256 -ExpectedOperationKind install
  } finally {
    if (Test-Path -LiteralPath $probePath -PathType Leaf) { Remove-SafeItem -AuthorizedRoot $probeRoot -Path $probePath -Kind File }
    if (Test-Path -LiteralPath $probeDigestPath -PathType Leaf) { Remove-SafeItem -AuthorizedRoot $probeRoot -Path $probeDigestPath -Kind File }
  }
}

function Assert-ApprovedInstallCriticalBindingsCurrent {
  if (-not $Apply) { return }
  foreach ($inputRecord in @($ApprovedPlan.intent.inputs)) {
    $root = if ([string]$inputRecord.scope -eq 'target') { $TargetRoot } else { $LayerRoot }
    $path = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $root ([string]$inputRecord.path).Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "PLAN_BINDING_INPUT_MISMATCH: Bound input is missing: $($inputRecord.scope):$($inputRecord.path)" }
    $currentHash = Get-SafeFileHash -AuthorizedRoot $root -Path $path
    if ($currentHash -ne [string]$inputRecord.sha256) { throw "PLAN_BINDING_INPUT_MISMATCH: Bound input changed: $($inputRecord.scope):$($inputRecord.path)" }
  }
  foreach ($entry in @($ApprovedPlan.intent.target_entries)) {
    $path = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot ([string]$entry.path).Replace('/', '\'))
    $kind = if (Test-Path -LiteralPath $path -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $path -PathType Container) { 'directory' } elseif (Test-Path -LiteralPath $path) { 'other' } else { 'absent' }
    if ($kind -ne [string]$entry.precondition_kind) { throw "PLAN_BINDING_TARGET_MISMATCH: Target kind changed: $($entry.path)" }
    if ($kind -eq 'file') {
      $currentHash = Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $path
      if ($currentHash -ne [string]$entry.precondition_sha256) { throw "PLAN_BINDING_TARGET_MISMATCH: Target bytes changed: $($entry.path)" }
    }
    if ([string]$entry.action -eq 'remove') {
      $currentIdentity = Get-LizardPlanTargetIdentitySha256 -TargetRoot $TargetRoot -Path $path -Kind ([string]$entry.kind)
      if ($currentIdentity -ne [string]$entry.precondition_identity_sha256) { throw "PLAN_BINDING_TARGET_IDENTITY_MISMATCH: Target identity changed: $($entry.path)" }
    }
  }
}

Initialize-MemoryModeTransition
if ($Apply) { Assert-ApprovedInstallPlanCurrent }
if ($ValidateApprovedPlanOnly) {
  Write-Host "Approved install plan is current: $($ApprovedPlan.plan_id)"
  return
}

$TransactionContext = $null
$OwnsTransaction = $false
if ($Apply) {
  if ($JoinTransaction) {
    if ([string]::IsNullOrWhiteSpace($TransactionId)) { throw 'TRANSACTION_ID_REQUIRED: -JoinTransaction requires -TransactionId.' }
    $TransactionContext = Join-LizardTransaction -TargetRoot $TargetRoot -OperationId $TransactionId -FailAfterMutation $TestFailAfterMutation
  } else {
    if (-not [string]::IsNullOrWhiteSpace($TransactionId)) { throw 'TRANSACTION_JOIN_REQUIRED: -TransactionId requires -JoinTransaction.' }
    $TransactionContext = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName 'install' -FailAfterMutation $TestFailAfterMutation
    $OwnsTransaction = $true
  }
}

try {

Write-Host "lizard-agent-layer $Mode"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $Profile"
$packDisplay = if ($SelectedPacks.Count -gt 0) { $SelectedPacks -join ', ' } else { 'none' }
Write-Host "Packs: $packDisplay"
$requestedPackDisplay = if ($RequestedPacks.Count -gt 0) { $RequestedPacks -join ', ' } else { 'none' }
Write-Host "Requested packs: $requestedPackDisplay"
Write-Host "Harnesses: $($SelectedHarnesses -join ', ')"
Write-Host "Memory mode: $EffectiveMemoryMode"
Write-Host "Routing policy: $EffectiveRoutingPolicy"
Write-Host "Model mode: $EffectiveModelMode"
Write-Host "Daily use: $(if ($EffectiveModelMode -eq 'inherit-current') { 'Submit normal task prompts; keep the current IDE model.' } else { 'Submit normal task prompts; the configured runtime selects models automatically.' })"
if ($EffectiveModelRuntime) { Write-Host "Model runtime: $EffectiveModelRuntime" }
Write-Host "Version: $LayerVersion"
if ($ShouldWritePlan) { Write-Host "Plan report: $EffectivePlanPath" }
Write-Host ""

Invoke-MemoryModeTransitionRemovals
Ensure-Dir (Join-Path $TargetRoot ".agent")
Ensure-Dir (Join-Path $TargetRoot ".agent\protocols")
Ensure-Dir (Join-Path $TargetRoot ".agent\skills")
Ensure-Dir (Join-Path $TargetRoot ".agent\routing")
Ensure-Dir (Join-Path $TargetRoot ".agent\routing\receipts")
Ensure-Dir (Join-Path $TargetRoot ".agent\routing\receipts\decisions")
Ensure-Dir (Join-Path $TargetRoot ".agent\routing\receipts\executions")

Copy-IfMissing (Join-Path $LayerRoot $AgentGitignoreSource) (Join-Path $TargetRoot ".agent\.gitignore")
Copy-IfMissing (Join-Path $LayerRoot 'templates\operator-card.md') (Join-Path $TargetRoot ".agent\USING.md")
if ($SelectedPacks.Count -gt 0 -or -not [string]::IsNullOrWhiteSpace($MemoryMode) -or $null -ne $existingInstallManifest -or -not [string]::IsNullOrWhiteSpace($RoutingPolicy) -or -not [string]::IsNullOrWhiteSpace($ModelMode) -or -not [string]::IsNullOrWhiteSpace($ModelInventory) -or -not [string]::IsNullOrWhiteSpace($ModelRuntime)) {
  Write-IfMissing -Dest (Join-Path $TargetRoot ".agent\project-profile.json") -Content ($ProfileDoc | ConvertTo-Json -Depth 10) -SourcePath 'generated:project-profile'
} else {
  Copy-IfMissing $ProfilePath (Join-Path $TargetRoot ".agent\project-profile.json")
}
foreach ($spec in @($MemoryFileSpecs.ToArray())) {
  Copy-IfMissing (Join-Path $LayerRoot ([string]$spec.source)) (Join-Path $TargetRoot ([string]$spec.destination))
}

foreach ($spec in @($ProtocolSpecs.ToArray())) {
  Copy-IfMissing (Join-Path $LayerRoot ([string]$spec.source)) (Join-Path $TargetRoot ([string]$spec.destination))
}

Copy-IfMissing $RoutingPolicyPath (Join-Path $TargetRoot ".agent\routing\policy.json")
$RoutingModelNames = [object[]]@($BoundRoutingModelNames)
if ($RoutingModelNames.Count -gt 0) { Ensure-Dir (Join-Path $TargetRoot ".agent\routing\models") }
foreach ($modelName in $RoutingModelNames) {
  if ($modelName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid model profile name '$modelName' in routing bindings." }
  $modelSource = Join-Path $LayerRoot "model-profiles\$modelName.json"
  if (-not (Test-Path -LiteralPath $modelSource -PathType Leaf)) { throw "Missing routing model profile '$modelName'." }
  Copy-IfMissing $modelSource (Join-Path $TargetRoot ".agent\routing\models\$modelName.json")
}

$indexLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add("# Skill Index") | Out-Null
$indexLines.Add("") | Out-Null
$manifestLines = New-Object System.Collections.Generic.List[string]

foreach ($skill in $ProfileDoc.skills) {
  $source = Join-Path $LayerRoot "skills\$skill\SKILL.md"
  if (-not (Test-Path -LiteralPath $source)) {
    Write-Warning "Profile references missing skill '$skill'."
    continue
  }
  Copy-SkillPackage -SkillName $skill -DestRoot (Join-Path $TargetRoot ".agent\skills")
  $indexLines.Add("## $skill") | Out-Null
  $indexLines.Add(('Source: `.agent/skills/{0}/SKILL.md`' -f $skill)) | Out-Null
  $indexLines.Add("") | Out-Null
  $skillPackage = $SkillPackageCatalog[[string]$skill]
  $manifest = [ordered]@{
    schema_version = 1
    name = $skill
    version = [string]$skillPackage.metadata.version
    status = 'active'
    source = ".agent/skills/$skill/SKILL.md"
    metadata = ".agent/skills/$skill/skill.json"
    metadata_sha256 = (Get-LizardSha256 $skillPackage.metadata_path)
    dependencies = @($skillPackage.metadata.dependencies)
    permissions = $skillPackage.metadata.permissions
  }
  $manifestLines.Add(($manifest | ConvertTo-Json -Compress)) | Out-Null
}

Write-IfMissing -Dest (Join-Path $TargetRoot ".agent\skills\_index.md") -Content ($indexLines -join "`n") -SourcePath 'generated:skill-index'
Write-IfMissing -Dest (Join-Path $TargetRoot ".agent\skills\_manifest.jsonl") -Content ($manifestLines -join "`n") -SourcePath 'generated:skill-manifest'

foreach ($adapterName in $SelectedHarnesses) {
  Install-Adapter $adapterName
}

Register-RetiredArtifacts
Assert-MemoryModePostcondition
Write-InstallManifest
Write-PlanReport
if (-not $Apply) { $null = Write-CanonicalInstallPlan }

if ($Apply -and $OwnsTransaction) {
  $TransactionResult = Complete-LizardTransaction
  Write-Host "Transaction: $($TransactionResult.operation_id) ($($TransactionResult.mutation_count) mutations committed)"
}

Write-Host "Summary"
Write-Host "Planned: $($Planned.Count)"
foreach ($item in $Planned) { Write-Host "  + $item" }
Write-Host "Created: $($Created.Count)"
foreach ($item in $Created) { Write-Host "  + $item" }
Write-Host "Removed: $($Removed.Count)"
foreach ($item in $Removed) { Write-Host "  - $item" }
Write-Host "Skipped existing: $($Skipped.Count)"
foreach ($item in $Skipped) { Write-Host "  ~ $item" }
if ($MergeNeeded.Count -gt 0) {
  Write-Host "Manual merge needed:"
  foreach ($item in $MergeNeeded) { Write-Host "  ! $item" }
}
if ($MergeSuggestions.Count -gt 0) {
  Write-Host "Merge suggestions: $($MergeSuggestions.Count)"
  foreach ($item in @($MergeSuggestions.ToArray())) { Write-Host "  ? $($item.harness): add pointer in $($item.instruction_path) for $($item.sidecar_path)" }
}
if ($ShouldWritePlan) {
  Write-Host ""
  Write-Host "Plan report written: $EffectivePlanPath"
}
if (-not $Apply) {
  Write-Host ""
  Write-Host "Preview only. Re-run with -Apply to write files."
}
if (-not $Apply -and $ShouldWriteCanonicalPlan) {
  Write-Host "Canonical approval plan: $EffectiveCanonicalPlanPath"
  Write-Host "Digest sidecar (convenience only): ${EffectiveCanonicalPlanPath}.sha256"
}
if ($Conflicts.Count -gt 0) {
  Write-Host "Ownership conflicts:"
  foreach ($item in $Conflicts) { Write-Host "  ! $item" }
}
} catch {
  $installError = $_
  if ($Apply -and $null -ne $TransactionContext) {
    try { Undo-LizardTransaction | Out-Null }
    catch { Write-Warning "Transaction rollback requires recovery: $($_.Exception.Message)" }
  }
  throw $installError
}
