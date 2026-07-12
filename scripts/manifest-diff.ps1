param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$OutputDir,
  [switch]$Json,
  [switch]$Strict,
  [switch]$AllowTargetReportWrite
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Manifest.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $LayerRoot '.tmp\manifest-diff' }
if (-not $AllowTargetReportWrite) { Assert-PathOutsideRoot -Path $OutputDir -ExcludedRoot $TargetRoot -Label 'OutputDir' }
$OutputDir = Initialize-SafeDirectory -Path $OutputDir

$manifestPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.install.json'
$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Missing install manifest: $manifestPath" }
if (-not (Test-Path -LiteralPath $profilePath)) { throw "Missing installed project profile: $profilePath" }

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
function Add-Unique {
  param($List, [string]$Value)
  if ($Value -and -not $List.Contains($Value)) { $List.Add($Value) | Out-Null }
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
    foreach ($item in @($Doc.$Name)) { Add-Unique $list ([string]$item) }
  }
  foreach ($item in @($Values)) { Add-Unique $list ([string]$item) }
  Set-DocProperty $Doc $Name @($list.ToArray())
}
function Get-RiskRank { param([string]$Risk) switch ($Risk) { 'high' { 3 } 'medium' { 2 } 'low' { 1 } default { 0 } } }
function Get-SizeRank { param([string]$Size) switch ($Size) { 'large' { 3 } 'medium' { 2 } 'small' { 1 } default { 0 } } }
function Max-RiskLevel { param([string]$A, [string]$B) if ((Get-RiskRank $B) -gt (Get-RiskRank $A)) { $B } else { $A } }
function Max-ProjectSize { param([string]$A, [string]$B) if ((Get-SizeRank $B) -gt (Get-SizeRank $A)) { $B } else { $A } }

function Get-PackManifestInfo {
  param([string]$PackName)
  if ($PackName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid pack name '$PackName'." }
  $builtInPath = Join-Path $LayerRoot "packs\$PackName.json"
  if (Test-Path -LiteralPath $builtInPath) { return [ordered]@{ path = $builtInPath; source = 'builtin'; display = "packs/$PackName.json" } }
  $overlayPath = Join-Path $TargetRoot ".lizard-agent-layer\packs\$PackName.json"
  if (Test-Path -LiteralPath $overlayPath) { return [ordered]@{ path = $overlayPath; source = 'target-overlay'; display = ".lizard-agent-layer/packs/$PackName.json" } }
  throw "Unknown pack '$PackName'."
}
$PackCache = @{}
function Get-Pack {
  param([string]$PackName)
  if (-not $PackCache.ContainsKey($PackName)) {
    $info = Get-PackManifestInfo $PackName
    $pack = Get-Content -LiteralPath $info.path -Raw | ConvertFrom-Json
    if ($pack.name -ne $PackName) { throw "Pack manifest name '$($pack.name)' does not match '$PackName'." }
    $pack | Add-Member -NotePropertyName '_sourceKind' -NotePropertyValue $info.source -Force
    $pack | Add-Member -NotePropertyName '_sourcePath' -NotePropertyValue $info.display -Force
    $PackCache[$PackName] = $pack
  }
  $PackCache[$PackName]
}
$ExpandedPackNames = New-Object System.Collections.Generic.List[string]
function Add-PackWithExtends {
  param([string]$PackName, [string[]]$Stack = @())
  if ($Stack -contains $PackName) { throw "Pack extends cycle detected: $(@($Stack + $PackName) -join ' -> ')" }
  $pack = Get-Pack $PackName
  if ($pack.PSObject.Properties.Name -contains 'extends') {
    foreach ($basePack in @(Expand-ValueList $pack.extends)) { Add-PackWithExtends -PackName $basePack -Stack @($Stack + $PackName) }
  }
  Add-Unique $ExpandedPackNames $PackName
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$manifestSchema = if ($null -ne $manifest.schema_version) { [int]$manifest.schema_version } else { 1 }
if ($manifestSchema -gt 3) { throw "MANIFEST_READER_TOO_OLD: Target schema $manifestSchema is newer than supported schema 3." }
$legacyIntegrityUnknown = $manifestSchema -lt 3
$installedProfile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json
$profileName = if ($manifest.profile) { [string]$manifest.profile } elseif ($installedProfile.profile) { [string]$installedProfile.profile } else { 'standard' }
$baseProfilePath = Join-Path $LayerRoot "profiles\$profileName.json"
if (-not (Test-Path -LiteralPath $baseProfilePath)) { throw "Missing layer profile for installed profile '$profileName'." }
$expectedProfile = Get-Content -LiteralPath $baseProfilePath -Raw | ConvertFrom-Json

$requestedPacks = if ($manifest.requested_packs) { Expand-ValueList $manifest.requested_packs } elseif ($manifest.packs) { Expand-ValueList $manifest.packs } else { @() }
foreach ($packName in @($requestedPacks)) { Add-PackWithExtends -PackName $packName }
$expectedPacks = @($ExpandedPackNames.ToArray())
$packSources = New-Object System.Collections.Generic.List[object]
foreach ($packName in @($expectedPacks)) {
  $pack = Get-Pack $packName
  $packSources.Add([ordered]@{ name = [string]$pack.name; source = [string]$pack._sourceKind; path = [string]$pack._sourcePath }) | Out-Null
  Merge-ArrayProperty $expectedProfile 'stack' @($pack.stack)
  Merge-ArrayProperty $expectedProfile 'skills' @($pack.skills)
  Merge-ArrayProperty $expectedProfile 'harnesses' @($pack.harnesses)
  Merge-ArrayProperty $expectedProfile 'verification' @($pack.verification)
  Set-DocProperty $expectedProfile 'riskLevel' (Max-RiskLevel ([string]$expectedProfile.riskLevel) ([string]$pack.riskLevel))
  Set-DocProperty $expectedProfile 'projectSize' (Max-ProjectSize ([string]$expectedProfile.projectSize) ([string]$pack.projectSize))
}

$differences = New-Object System.Collections.Generic.List[object]
function Add-Diff { param([string]$Kind, [string]$Value, [string]$Details) $differences.Add([ordered]@{ kind = $Kind; value = $Value; details = $Details }) | Out-Null }
function Compare-List {
  param([string]$Kind, [string[]]$Expected, [string[]]$Actual)
  foreach ($item in @($Expected)) { if ($item -and ($Actual -notcontains $item)) { Add-Diff "missing-$Kind" $item "Expected but not installed." } }
  foreach ($item in @($Actual)) { if ($item -and ($Expected -notcontains $item)) { Add-Diff "unexpected-$Kind" $item "Installed but not expected from current profile and packs." } }
}

$currentLayerVersion = if (Test-Path -LiteralPath (Join-Path $LayerRoot 'VERSION')) { (Get-Content -LiteralPath (Join-Path $LayerRoot 'VERSION') -Raw).Trim() } else { '0.0.0-dev' }
if ([string]$manifest.layer_version -ne $currentLayerVersion) { Add-Diff 'layer-version' ([string]$manifest.layer_version) "Current layer version is $currentLayerVersion." }
if ([string]$manifest.risk_level -ne [string]$expectedProfile.riskLevel) { Add-Diff 'risk-level' ([string]$manifest.risk_level) "Expected $($expectedProfile.riskLevel)." }

Compare-List -Kind 'pack' -Expected @($expectedPacks) -Actual @($manifest.packs)
Compare-List -Kind 'skill' -Expected @($expectedProfile.skills) -Actual @($manifest.skills)
if ($legacyIntegrityUnknown) { Add-Diff 'integrity-unknown' "schema-$manifestSchema" 'Legacy manifests do not contain per-artifact ownership and content identity.' }

$effectiveAdapters = @($manifest.adapters)
$adapterAliases = @($manifest.adapter_aliases)
foreach ($harness in @($manifest.harnesses)) {
  $covered = $effectiveAdapters -contains [string]$harness
  if (-not $covered) {
    $covered = @($adapterAliases | Where-Object { [string]$_.adapter -eq [string]$harness -and $effectiveAdapters -contains [string]$_.satisfied_by }).Count -gt 0
  }
  if (-not $covered) { Add-Diff 'missing-adapter-identity' ([string]$harness) 'Selected harness has no effective adapter or declared compatibility alias.' }
}

$mirrorHashes = @{}
if (-not $legacyIntegrityUnknown) {
  try { $artifactMap = Get-LizardArtifactMap -Manifest $manifest }
  catch { Add-Diff 'invalid-artifact-index' 'artifacts' $_.Exception.Message; $artifactMap = $null }

  if ($artifactMap) {
    foreach ($managedPath in @($manifest.managed_paths)) {
      $managedRelative = ConvertTo-LizardArtifactPath ([string]$managedPath)
      if ([string]::IsNullOrWhiteSpace($managedRelative) -or $managedRelative -eq '.agent/lizard-agent-layer.install.json') { continue }
      if (-not $artifactMap.ContainsKey($managedRelative)) { Add-Diff 'artifact-identity-missing' $managedRelative 'Managed path has no manifest v3 artifact identity.' }
    }
    foreach ($ownedPath in @($manifest.owned_paths)) {
      $ownedRelative = ConvertTo-LizardArtifactPath ([string]$ownedPath)
      if ([string]::IsNullOrWhiteSpace($ownedRelative) -or $ownedRelative -eq '.agent/lizard-agent-layer.install.json') { continue }
      if (-not $artifactMap.ContainsKey($ownedRelative)) { Add-Diff 'owned-artifact-missing' $ownedRelative 'Owned path has no manifest v3 artifact identity.'; continue }
      if ([string]$artifactMap[$ownedRelative].ownership -ne 'layer-owned') { Add-Diff 'ownership-index-mismatch' $ownedRelative ("owned_paths claims layer ownership, artifact records '{0}'." -f $artifactMap[$ownedRelative].ownership) }
    }
    foreach ($artifact in @($manifest.artifacts)) {
      $relative = ConvertTo-LizardArtifactPath ([string]$artifact.path)
      if ([string]::IsNullOrWhiteSpace($relative)) { Add-Diff 'invalid-artifact-path' '<empty>' 'Artifact path is empty.'; continue }
      try { $targetArtifactPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)) }
      catch { Add-Diff 'unsafe-artifact-path' $relative $_.Exception.Message; continue }

      $kind = [string]$artifact.kind
      $exists = if ($kind -eq 'directory') { Test-Path -LiteralPath $targetArtifactPath -PathType Container } else { Test-Path -LiteralPath $targetArtifactPath -PathType Leaf }
      if (-not $exists) { Add-Diff 'missing-artifact' $relative "Manifest v3 $kind is missing."; continue }
      if ($kind -eq 'directory') { continue }
      if ($kind -ne 'file') { Add-Diff 'invalid-artifact-kind' $relative "Unsupported kind '$kind'."; continue }

      $currentHash = Get-LizardSha256 $targetArtifactPath
      if ([string]$artifact.ownership -in @('layer-owned', 'adopted')) {
        if ([string]::IsNullOrWhiteSpace([string]$artifact.installed_hash)) {
          Add-Diff 'integrity-unknown' $relative 'Owned artifact has no installed hash.'
        } elseif ($currentHash -ne [string]$artifact.installed_hash) {
          Add-Diff 'content-modified' $relative ("Expected installed hash {0}, actual {1}." -f $artifact.installed_hash, $currentHash)
        }
      }

      $sourcePathValue = [string]$artifact.source_path
      if (-not [string]::IsNullOrWhiteSpace($sourcePathValue) -and -not $sourcePathValue.StartsWith('generated:', [System.StringComparison]::OrdinalIgnoreCase)) {
        try {
          if ($sourcePathValue.StartsWith('.lizard-agent-layer/', [System.StringComparison]::OrdinalIgnoreCase)) {
            $sourceFullPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $sourcePathValue.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
          } else {
            $sourceFullPath = Resolve-SafeTargetDestination -AuthorizedRoot $LayerRoot -DestinationPath (Join-Path $LayerRoot $sourcePathValue.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
          }
          if (-not (Test-Path -LiteralPath $sourceFullPath -PathType Leaf)) { Add-Diff 'missing-source' $relative "Source file is missing: $sourcePathValue" }
          else {
            $currentSourceHash = Get-LizardSha256 $sourceFullPath
            if ($currentSourceHash -ne [string]$artifact.source_hash) { Add-Diff 'source-drift' $relative ("Recorded source hash {0}, current source hash {1}." -f $artifact.source_hash, $currentSourceHash) }
          }
        } catch { Add-Diff 'unsafe-source-path' $relative $_.Exception.Message }
      }

      if (-not [string]::IsNullOrWhiteSpace([string]$artifact.mirror_group) -and [string]$artifact.ownership -eq 'layer-owned') {
        $group = [string]$artifact.mirror_group
        if (-not $mirrorHashes.ContainsKey($group)) { $mirrorHashes[$group] = New-Object System.Collections.Generic.List[object] }
        $mirrorHashes[$group].Add([pscustomobject]@{ path = $relative; hash = $currentHash }) | Out-Null
      }
    }
  }

  foreach ($group in @($mirrorHashes.Keys)) {
    $rows = @($mirrorHashes[$group].ToArray())
    $hashes = @($rows | ForEach-Object { $_.hash } | Select-Object -Unique)
    if ($hashes.Count -gt 1) { Add-Diff 'mirror-mismatch' $group ("Mirror paths differ: {0}" -f (($rows | ForEach-Object { $_.path }) -join ', ')) }
  }

  foreach ($adapterId in $effectiveAdapters) {
    $identityArtifacts = @($manifest.artifacts | Where-Object { [string]$_.adapter_id -eq [string]$adapterId -and [string]$_.mirror_group -like 'adapter-instruction:*' })
    $identityValid = $false
    foreach ($identity in $identityArtifacts) {
      $identityPath = Join-Path $TargetRoot ([string]$identity.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
      if ((Test-Path -LiteralPath $identityPath -PathType Leaf) -and (Get-LizardSha256 $identityPath) -eq [string]$identity.source_hash) { $identityValid = $true; break }
    }
    if (-not $identityValid) { Add-Diff 'adapter-identity-mismatch' ([string]$adapterId) 'No installed instruction or sidecar matches the exact adapter source hash.' }
  }
}

foreach ($skill in @($expectedProfile.skills)) {
  $skillPath = Join-Path $TargetRoot ".agent\skills\$skill\SKILL.md"
  if (-not (Test-Path -LiteralPath $skillPath)) { Add-Diff 'missing-skill-file' $skill ".agent/skills/$skill/SKILL.md is missing." }
}
foreach ($managedPath in @($manifest.managed_paths)) {
  if ([string]::IsNullOrWhiteSpace([string]$managedPath)) { continue }
  $fullPath = Join-Path $TargetRoot ([string]$managedPath)
  if (-not (Test-Path -LiteralPath $fullPath)) { Add-Diff 'missing-managed-path' ([string]$managedPath) 'Path is listed in install manifest but missing on disk.' }
}

$status = if ($differences.Count -eq 0) { 'pass' } elseif ($legacyIntegrityUnknown) { 'integrity-unknown' } else { 'drift' }
$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  target = $TargetRoot
  layer_root = $LayerRoot
  status = $status
  strict = $Strict.IsPresent
  manifest_schema_version = $manifestSchema
  installed = [ordered]@{ layer_version = [string]$manifest.layer_version; profile = $profileName; packs = @($manifest.packs); requested_packs = @($requestedPacks); risk_level = [string]$manifest.risk_level; skills = @($manifest.skills); harnesses = @($manifest.harnesses) }
  expected = [ordered]@{ layer_version = $currentLayerVersion; profile = $profileName; packs = @($expectedPacks); requested_packs = @($requestedPacks); risk_level = [string]$expectedProfile.riskLevel; skills = @($expectedProfile.skills); harnesses = @($manifest.harnesses); pack_sources = @($packSources.ToArray()) }
  summary = [ordered]@{ differences = $differences.Count }
  differences = @($differences.ToArray())
}

$jsonPath = Join-Path $OutputDir 'manifest-diff.json'
$mdPath = Join-Path $OutputDir 'manifest-diff.md'
Set-SafeContent -AuthorizedRoot $OutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 10)
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# lizard-agent-layer manifest diff') | Out-Null
$md.Add('') | Out-Null
$md.Add("Status: $status") | Out-Null
$md.Add("Target: $TargetRoot") | Out-Null
$md.Add("Installed layer version: $($manifest.layer_version)") | Out-Null
$md.Add("Current layer version: $currentLayerVersion") | Out-Null
$md.Add("Differences: $($differences.Count)") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Differences') | Out-Null
$md.Add('') | Out-Null
if ($differences.Count -eq 0) { $md.Add('- None') | Out-Null }
else { foreach ($diff in @($differences.ToArray())) { $md.Add("- $($diff.kind): `$($diff.value)` - $($diff.details)") | Out-Null } }
Set-SafeContent -AuthorizedRoot $OutputDir -Path $mdPath -Value $md

if ($Json) {
  $report | ConvertTo-Json -Depth 10
  if ($Strict -and $differences.Count -gt 0) { exit 1 }
  exit 0
}
Write-Host "Manifest diff: $status"
Write-Host "Differences: $($differences.Count)"
Write-Host "Report: $jsonPath"
Write-Host "Markdown: $mdPath"
if ($Strict -and $differences.Count -gt 0) { exit 1 }
