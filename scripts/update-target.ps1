param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Profile,
  [string[]]$Harnesses,
  [string[]]$Packs,
  [string]$RoutingPolicy,
  [ValidateSet('inherit-current', 'inventory-routing')]
  [string]$ModelMode,
  [string]$ModelInventory,
  [string]$ModelRuntime,
  [switch]$Apply,
  [switch]$ForceManaged,
  [switch]$Json,
  [string]$PlanPath,
  [string]$OutputDir,
  [switch]$AllowTargetReportWrite,
  [switch]$AllowDowngrade,
  [switch]$HumanApproved,
  [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Host.psm1') -Force
$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$manifestPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.install.json'
$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
$versionPath = Join-Path $LayerRoot 'VERSION'

function Write-Status {
  param([string]$Message)
  if (-not $Json) { Write-Host $Message }
}

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

function Resolve-UserPath {
  param([string]$Path, [string]$Fallback)
  $candidate = if ([string]::IsNullOrWhiteSpace($Path)) { $Fallback } else { $Path }
  if ([System.IO.Path]::IsPathRooted($candidate)) { return $candidate }
  return (Join-Path (Get-Location).Path $candidate)
}

function Format-ListValue {
  param($Items)
  $itemsArray = @($Items | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($itemsArray.Count -eq 0) { return 'none' }
  return ($itemsArray -join ', ')
}

function Format-CommandLine {
  param([bool]$AsApply, [bool]$AsForce)
  $parts = New-Object System.Collections.Generic.List[string]
  $parts.Add('pwsh') | Out-Null
  $parts.Add('-NoProfile') | Out-Null
  $parts.Add('-File .\scripts\update-target.ps1') | Out-Null
  $parts.Add(('-TargetPath "{0}"' -f $TargetRoot)) | Out-Null
  if (-not [string]::IsNullOrWhiteSpace($SelectedProfile)) { $parts.Add(('-Profile {0}' -f $SelectedProfile)) | Out-Null }
  if ($SelectedHarnesses.Count -gt 0) { $parts.Add(('-Harnesses {0}' -f ($SelectedHarnesses -join ','))) | Out-Null }
  if ($SelectedPacks.Count -gt 0) { $parts.Add(('-Packs {0}' -f ($SelectedPacks -join ','))) | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($SelectedRoutingPolicy)) { $parts.Add(('-RoutingPolicy {0}' -f $SelectedRoutingPolicy)) | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($SelectedModelMode)) { $parts.Add(('-ModelMode {0}' -f $SelectedModelMode)) | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($SelectedModelInventory)) { $parts.Add(('-ModelInventory "{0}"' -f $SelectedModelInventory)) | Out-Null }
  if (-not [string]::IsNullOrWhiteSpace($SelectedModelRuntime)) { $parts.Add(('-ModelRuntime "{0}"' -f $SelectedModelRuntime)) | Out-Null }
  if ($AsApply) { $parts.Add('-Apply') | Out-Null }
  if ($AsForce) { $parts.Add('-ForceManaged') | Out-Null }
  if ($AllowDowngrade) { $parts.Add('-AllowDowngrade') | Out-Null }
  if ($HumanApproved) { $parts.Add('-HumanApproved') | Out-Null }
  return ($parts -join ' ')
}

function Add-MarkdownList {
  param($Lines, [string]$Title, $Items)
  $Lines.Add("## $Title") | Out-Null
  $Lines.Add('') | Out-Null
  $itemsArray = @($Items)
  if ($itemsArray.Count -eq 0) {
    $Lines.Add('- None') | Out-Null
  } else {
    foreach ($item in $itemsArray) { $Lines.Add(('- `{0}`' -f $item)) | Out-Null }
  }
  $Lines.Add('') | Out-Null
}

function Invoke-ManifestDiff {
  param([string]$DiffOutputDir, [switch]$Strict)
  $argsList = @($PowerShellFilePrefix) + @(
    (Join-Path $ScriptDir 'manifest-diff.ps1'),
    '-TargetPath', $TargetRoot,
    '-LayerRoot', $LayerRoot,
    '-OutputDir', $DiffOutputDir,
    '-Json'
  )
  if ($Strict) { $argsList += '-Strict' }
  $global:LASTEXITCODE = 0
  $text = & $PowerShellHost @argsList | Out-String
  if ($LASTEXITCODE -ne 0) { throw "manifest-diff.ps1 failed with exit code $LASTEXITCODE. Output: $text" }
  if ([string]::IsNullOrWhiteSpace($text)) { throw 'manifest-diff.ps1 returned no JSON output.' }
  $report = $text | ConvertFrom-Json
  if ($Strict -and [int]$report.summary.differences -gt 0) {
    throw "manifest-diff.ps1 strict check failed with $($report.summary.differences) differences. Report: $DiffOutputDir"
  }
  $report
}

function New-UpdatePlanMarkdown {
  param($DiffReport)
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add('# lizard-agent-layer update plan') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add(('- Generated: {0}' -f (Get-Date).ToUniversalTime().ToString('o'))) | Out-Null
  $lines.Add(('- Mode: `{0}`' -f $Mode)) | Out-Null
  $lines.Add(('- Target: `{0}`' -f $TargetRoot)) | Out-Null
  $lines.Add(('- Installed layer version: `{0}`' -f $InstalledVersion)) | Out-Null
  $lines.Add(('- Current layer version: `{0}`' -f $CurrentVersion)) | Out-Null
  $lines.Add(('- Version relation: `{0}`' -f $VersionRelation)) | Out-Null
  $lines.Add(('- Installed manifest schema: `{0}`' -f $InstalledManifestSchema)) | Out-Null
  $lines.Add(('- Target manifest schema after apply: `3`')) | Out-Null
  $lines.Add(('- Profile: `{0}`' -f $SelectedProfile)) | Out-Null
  $lines.Add(('- Harnesses: `{0}`' -f (Format-ListValue $SelectedHarnesses))) | Out-Null
  $lines.Add(('- Requested packs: `{0}`' -f (Format-ListValue $SelectedPacks))) | Out-Null
  $lines.Add(('- Installed expanded packs: `{0}`' -f (Format-ListValue $InstalledExpandedPacks))) | Out-Null
  $lines.Add(('- Routing policy: `{0}`' -f $SelectedRoutingPolicy)) | Out-Null
  $lines.Add(('- Model mode: `{0}`' -f $SelectedModelMode)) | Out-Null
  $lines.Add(('- Daily use: {0}' -f $(if ($SelectedModelMode -eq 'inherit-current') { 'Submit ordinary task prompts; the active IDE model completes all stages without picker changes.' } else { 'Submit ordinary task prompts; the configured automatic runtime selects models without manual picker changes.' }))) | Out-Null
  if ($SelectedModelInventory) { $lines.Add(('- Model inventory: `{0}`' -f $SelectedModelInventory)) | Out-Null }
  if ($SelectedModelRuntime) { $lines.Add(('- Model runtime: `{0}`' -f $SelectedModelRuntime)) | Out-Null }
  $lines.Add(('- Force managed files: `{0}`' -f $ForceManaged.IsPresent)) | Out-Null
  $lines.Add(('- Downgrade approved: `{0}`' -f ($AllowDowngrade -and $HumanApproved))) | Out-Null
  $lines.Add(('- Manifest diff status: `{0}`' -f $DiffReport.status)) | Out-Null
  $lines.Add(('- Manifest differences: `{0}`' -f $DiffReport.summary.differences)) | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('## Update behavior') | Out-Null
  $lines.Add('') | Out-Null
  if ($Apply) {
    $lines.Add('- This run will apply the update after writing this plan.') | Out-Null
  } else {
    $lines.Add('- Preview only. No target project files are changed by this update plan.') | Out-Null
  }
  $lines.Add('- The update reuses the installed profile, requested packs, and harnesses unless this command overrides them.') | Out-Null
  $lines.Add('- Without `-ForceManaged`, existing target files are preserved and missing/generated layer files are repaired.') | Out-Null
  $lines.Add('- With `-ForceManaged`, generated layer artifacts may be replaced from the current layer after reviewing this plan; unowned root instruction files remain merge-reviewed.') | Out-Null
  $lines.Add('- Existing project instruction files can still produce sidecar merge suggestions instead of silent edits, depending on adapter policy.') | Out-Null
  $lines.Add('- Schema v2 manifests migrate conservatively to v3; ambiguous legacy files become user-owned and are not force-refreshed.') | Out-Null
  $lines.Add('- A newer installed layer version requires both `-AllowDowngrade` and `-HumanApproved`.') | Out-Null
  $lines.Add('- After apply, manifest diff is run again in strict mode and an update-history JSONL entry is appended in `.agent/`.') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('## Commands') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('Preview:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add((Format-CommandLine -AsApply:$false -AsForce:$false)) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('Apply preserving existing files:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add((Format-CommandLine -AsApply:$true -AsForce:$false)) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('Apply and replace managed artifacts after review:') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('```powershell') | Out-Null
  $lines.Add((Format-CommandLine -AsApply:$true -AsForce:$true)) | Out-Null
  $lines.Add('```') | Out-Null
  $lines.Add('') | Out-Null
  Add-MarkdownList $lines 'Requested packs' @($SelectedPacks)
  Add-MarkdownList $lines 'Installed expanded packs' @($InstalledExpandedPacks)
  Add-MarkdownList $lines 'Harnesses' @($SelectedHarnesses)
  $lines.Add('## Manifest differences') | Out-Null
  $lines.Add('') | Out-Null
  if (@($DiffReport.differences).Count -eq 0) {
    $lines.Add('- None') | Out-Null
  } else {
    foreach ($diff in @($DiffReport.differences)) {
      $lines.Add(('- {0}: `{1}` - {2}' -f $diff.kind, $diff.value, $diff.details)) | Out-Null
    }
  }
  $lines.Add('') | Out-Null
  $lines.Add('## Affected areas') | Out-Null
  $lines.Add('') | Out-Null
  $lines.Add('- `.agent/lizard-agent-layer.install.json` records the current layer version and selected contract.') | Out-Null
  $lines.Add('- `.agent/project-profile.json` can be refreshed when packs expand the selected profile.') | Out-Null
  $lines.Add('- `.agent/skills/`, `.agent/protocols/`, and harness skill mirrors can receive new or updated generated content.') | Out-Null
  $lines.Add('- Harness instruction files or sidecars may be created, skipped, or listed for manual merge review.') | Out-Null
  $lines.Add('- `.agent/lizard-agent-layer.update-history.jsonl` records applied updates for future audits.') | Out-Null
  return ($lines -join "`n")
}

function Get-VersionRelation {
  param([string]$Installed, [string]$Current)
  if ($Installed -eq $Current) { return 'same' }
  try {
    $installedVersionObj = [Version]$Installed
    $currentVersionObj = [Version]$Current
    if ($installedVersionObj -lt $currentVersionObj) { return 'current-layer-newer' }
    if ($installedVersionObj -gt $currentVersionObj) { return 'installed-target-newer' }
  } catch {
    return 'different'
  }
  return 'different'
}

if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "Target is not installed yet. Missing install manifest: $manifestPath. Run scripts\install.ps1 first."
}
if (-not (Test-Path -LiteralPath $profilePath)) {
  throw "Target is missing installed project profile: $profilePath. Run scripts\install.ps1 first."
}
if (-not (Test-Path -LiteralPath $versionPath)) { throw "Missing layer VERSION file: $versionPath" }

$Manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$ProfileDoc = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$CurrentVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
$InstalledVersion = if ($Manifest.layer_version) { [string]$Manifest.layer_version } else { 'unknown' }
$InstalledManifestSchema = if ($null -ne $Manifest.schema_version) { try { [int]$Manifest.schema_version } catch { throw "MANIFEST_SCHEMA_INVALID: $($Manifest.schema_version)" } } else { 1 }
if ($InstalledManifestSchema -lt 2) { throw "MANIFEST_SCHEMA_UNSUPPORTED: Schema $InstalledManifestSchema is older than minimum readable schema 2." }
if ($InstalledManifestSchema -gt 3) { throw "MANIFEST_READER_TOO_OLD: Target schema $InstalledManifestSchema is newer than supported schema 3." }
if ($Manifest.minimum_reader_schema_version -and [int]$Manifest.minimum_reader_schema_version -gt 3) { throw "MANIFEST_READER_TOO_OLD: Target requires reader schema $($Manifest.minimum_reader_schema_version)." }
try { $null = [Version]$CurrentVersion } catch { throw "VERSION_FORMAT_INVALID: Current layer version '$CurrentVersion' is not a supported semantic version." }
try { $null = [Version]$InstalledVersion } catch { throw "VERSION_FORMAT_INVALID: Installed layer version '$InstalledVersion' is not a supported semantic version." }
$SelectedProfile = if (-not [string]::IsNullOrWhiteSpace($Profile)) { $Profile } elseif ($Manifest.profile) { [string]$Manifest.profile } elseif ($ProfileDoc.profile) { [string]$ProfileDoc.profile } else { 'standard' }
$SelectedHarnesses = if ($Harnesses -and $Harnesses.Count -gt 0) { Expand-ValueList $Harnesses } elseif ($Manifest.harnesses) { Expand-ValueList $Manifest.harnesses } elseif ($ProfileDoc.harnesses) { Expand-ValueList $ProfileDoc.harnesses } else { @() }
$SelectedPacks = if ($Packs -and $Packs.Count -gt 0) { Expand-ValueList $Packs } elseif ($Manifest.requested_packs) { Expand-ValueList $Manifest.requested_packs } elseif ($ProfileDoc.requestedPacks) { Expand-ValueList $ProfileDoc.requestedPacks } elseif ($Manifest.packs) { Expand-ValueList $Manifest.packs } else { @() }
$SelectedRoutingPolicy = if (-not [string]::IsNullOrWhiteSpace($RoutingPolicy)) { $RoutingPolicy.Trim() } elseif ($Manifest.routing_policy) { [string]$Manifest.routing_policy } elseif ($ProfileDoc.routingPolicy) { [string]$ProfileDoc.routingPolicy } else { 'staged-balanced' }
if ($SelectedRoutingPolicy -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid routing policy '$SelectedRoutingPolicy'." }
$SelectedModelMode = if (-not [string]::IsNullOrWhiteSpace($ModelMode)) { $ModelMode } elseif ($Manifest.model_mode) { [string]$Manifest.model_mode } elseif ($ProfileDoc.modelMode) { [string]$ProfileDoc.modelMode } else { 'inherit-current' }
$SelectedModelInventory = if (-not [string]::IsNullOrWhiteSpace($ModelInventory)) { $ModelInventory.Trim() } elseif ($Manifest.model_inventory) { [string]$Manifest.model_inventory } elseif ($ProfileDoc.modelInventory) { [string]$ProfileDoc.modelInventory } else { $null }
$SelectedModelRuntime = if (-not [string]::IsNullOrWhiteSpace($ModelRuntime)) { $ModelRuntime.Trim() } elseif ($Manifest.model_runtime) { [string]$Manifest.model_runtime } elseif ($ProfileDoc.modelRuntime) { [string]$ProfileDoc.modelRuntime } else { $null }
$InstalledExpandedPacks = if ($Manifest.packs) { Expand-ValueList $Manifest.packs } else { @() }
$SelectedHarnesses = @($SelectedHarnesses | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$SelectedPacks = @($SelectedPacks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$InstalledExpandedPacks = @($InstalledExpandedPacks | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
$VersionRelation = Get-VersionRelation -Installed $InstalledVersion -Current $CurrentVersion
$Mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
if ($Apply -and $VersionRelation -eq 'installed-target-newer' -and (-not $AllowDowngrade -or -not $HumanApproved)) {
  throw "DOWNGRADE_APPROVAL_REQUIRED: Installed version $InstalledVersion is newer than current layer $CurrentVersion. Re-run only after review with -AllowDowngrade -HumanApproved."
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$effectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\updates\$stamp")
$effectivePlanPath = Resolve-UserPath -Path $PlanPath -Fallback (Join-Path $effectiveOutputDir 'update-plan.md')
if (-not $AllowTargetReportWrite) {
  Assert-PathOutsideRoot -Path $effectiveOutputDir -ExcludedRoot $TargetRoot -Label 'OutputDir'
  Assert-PathOutsideRoot -Path $effectivePlanPath -ExcludedRoot $TargetRoot -Label 'PlanPath'
}
$effectiveOutputDir = Initialize-SafeDirectory -Path $effectiveOutputDir
$planParent = Split-Path -Parent $effectivePlanPath
if ($planParent) { $planParent = Initialize-SafeDirectory -Path $planParent }
$preDiffDir = Join-Path $effectiveOutputDir 'pre-manifest-diff'
$postDiffDir = Join-Path $effectiveOutputDir 'post-manifest-diff'
$installPlanPath = Join-Path $effectiveOutputDir 'install-plan.md'
$reportPath = Join-Path $effectiveOutputDir 'update-report.json'

$preDiff = Invoke-ManifestDiff -DiffOutputDir $preDiffDir
$updatePlan = New-UpdatePlanMarkdown -DiffReport $preDiff
Set-SafeContent -AuthorizedRoot $planParent -Path $effectivePlanPath -Value $updatePlan

$postDiff = $null
$installOutput = $null
$transactionResult = $null
$transactionOperationId = $null
if ($Apply) {
  $updateTransaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName 'update' -FailAfterMutation $TestFailAfterMutation
  $transactionOperationId = [string]$updateTransaction.operation_id
  try {
    $installArgs = @($PowerShellFilePrefix) + @(
      (Join-Path $ScriptDir 'install.ps1'),
      '-TargetPath', $TargetRoot,
      '-Profile', $SelectedProfile,
      '-WritePlan',
      '-PlanPath', $installPlanPath,
      '-Apply',
      '-JoinTransaction',
      '-TransactionId', $transactionOperationId
    )
    if ($SelectedHarnesses.Count -gt 0) { $installArgs += '-Harnesses'; $installArgs += ($SelectedHarnesses -join ',') }
    if ($SelectedPacks.Count -gt 0) { $installArgs += '-Packs'; $installArgs += ($SelectedPacks -join ',') }
    $installArgs += '-RoutingPolicy'; $installArgs += $SelectedRoutingPolicy
    $installArgs += '-ModelMode'; $installArgs += $SelectedModelMode
    if ($SelectedModelInventory) { $installArgs += '-ModelInventory'; $installArgs += $SelectedModelInventory }
    if ($SelectedModelRuntime) { $installArgs += '-ModelRuntime'; $installArgs += $SelectedModelRuntime }
    if ($ForceManaged) { $installArgs += '-ForceManaged' }
    if ($TestFailAfterMutation -gt 0) { $installArgs += '-TestFailAfterMutation'; $installArgs += [string]$TestFailAfterMutation }
    $global:LASTEXITCODE = 0
    $installOutput = & $PowerShellHost @installArgs | Out-String
    if (-not $Json) { Write-Host $installOutput }
    if ($LASTEXITCODE -ne 0) { throw "install.ps1 failed with exit code $LASTEXITCODE." }
    Join-LizardTransaction -TargetRoot $TargetRoot -OperationId $transactionOperationId | Out-Null
    $postDiff = Invoke-ManifestDiff -DiffOutputDir $postDiffDir -Strict
    $historyPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.update-history.jsonl'
    $historyEntry = [ordered]@{
      schema_version = 2
      updated_at = (Get-Date).ToUniversalTime().ToString('o')
      transaction_operation_id = $transactionOperationId
      from_version = $InstalledVersion
      to_version = $CurrentVersion
      from_manifest_schema = $InstalledManifestSchema
      to_manifest_schema = 3
      version_relation_before = $VersionRelation
      profile = $SelectedProfile
      requested_packs = @($SelectedPacks)
      harnesses = @($SelectedHarnesses)
      routing_policy = $SelectedRoutingPolicy
      model_mode = $SelectedModelMode
      model_inventory = $SelectedModelInventory
      model_runtime = $SelectedModelRuntime
      force_managed = $ForceManaged.IsPresent
      allow_downgrade = $AllowDowngrade.IsPresent
      human_approved = $HumanApproved.IsPresent
      update_plan_path = $effectivePlanPath
      install_plan_path = $installPlanPath
      pre_manifest_status = [string]$preDiff.status
      pre_manifest_differences = [int]$preDiff.summary.differences
      post_manifest_status = [string]$postDiff.status
      post_manifest_differences = [int]$postDiff.summary.differences
    }
    Add-LizardTransactionalContent -Path $historyPath -Value ($historyEntry | ConvertTo-Json -Depth 10 -Compress)
    $transactionResult = Complete-LizardTransaction
  } catch {
    $updateError = $_
    try {
      if (Test-Path -LiteralPath (Join-Path $TargetRoot '.lizard-agent-layer.lock')) {
        Join-LizardTransaction -TargetRoot $TargetRoot -OperationId $transactionOperationId | Out-Null
        Undo-LizardTransaction | Out-Null
      }
    } catch { Write-Warning "Transaction rollback requires recovery: $($_.Exception.Message)" }
    throw $updateError
  }
}

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = $Mode
  target = $TargetRoot
  layer_root = $LayerRoot
  installed_layer_version = $InstalledVersion
  current_layer_version = $CurrentVersion
  version_relation = $VersionRelation
  installed_manifest_schema = $InstalledManifestSchema
  target_manifest_schema = 3
  profile = $SelectedProfile
  harnesses = @($SelectedHarnesses)
  requested_packs = @($SelectedPacks)
  routing_policy = $SelectedRoutingPolicy
  model_mode = $SelectedModelMode
  model_inventory = $SelectedModelInventory
  model_runtime = $SelectedModelRuntime
  installed_expanded_packs = @($InstalledExpandedPacks)
  force_managed = $ForceManaged.IsPresent
  allow_downgrade = $AllowDowngrade.IsPresent
  human_approved = $HumanApproved.IsPresent
  transaction_operation_id = $transactionOperationId
  transaction = $transactionResult
  plan_path = $effectivePlanPath
  output_dir = $effectiveOutputDir
  install_plan_path = if ($Apply) { $installPlanPath } else { $null }
  pre_manifest_diff = [ordered]@{ status = [string]$preDiff.status; differences = [int]$preDiff.summary.differences; report_dir = $preDiffDir }
  post_manifest_diff = if ($postDiff) { [ordered]@{ status = [string]$postDiff.status; differences = [int]$postDiff.summary.differences; report_dir = $postDiffDir } } else { $null }
}
Set-SafeContent -AuthorizedRoot $effectiveOutputDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 10)

if ($Json) {
  $report | ConvertTo-Json -Depth 10
  exit 0
}

Write-Status "lizard-agent-layer update $Mode"
Write-Status "Target: $TargetRoot"
Write-Status "Installed layer version: $InstalledVersion"
Write-Status "Current layer version: $CurrentVersion"
Write-Status "Version relation: $VersionRelation"
Write-Status "Profile: $SelectedProfile"
Write-Status "Harnesses: $(Format-ListValue $SelectedHarnesses)"
Write-Status "Requested packs: $(Format-ListValue $SelectedPacks)"
Write-Status "Routing policy: $SelectedRoutingPolicy"
Write-Status "Model mode: $SelectedModelMode"
Write-Status "Daily use: $(if ($SelectedModelMode -eq 'inherit-current') { 'Submit normal task prompts; keep the current IDE model.' } else { 'Submit normal task prompts; the configured runtime selects models automatically.' })"
if ($SelectedModelRuntime) { Write-Status "Model runtime: $SelectedModelRuntime" }
Write-Status "Manifest diff: $($preDiff.status) ($($preDiff.summary.differences) differences)"
Write-Status "Update plan: $effectivePlanPath"
Write-Status "Report: $reportPath"
if ($Apply) {
  Write-Status "Post-update manifest diff: $($postDiff.status) ($($postDiff.summary.differences) differences)"
  Write-Status "Update history: $(Join-Path $TargetRoot '.agent\lizard-agent-layer.update-history.jsonl')"
} else {
  Write-Status "Preview only. Review the update plan, then rerun with -Apply to update the target."
}



