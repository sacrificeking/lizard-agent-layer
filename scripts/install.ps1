param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Profile = "standard",
  [string[]]$Harnesses,
  [switch]$Apply,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$ProfilePath = Join-Path $LayerRoot "profiles\$Profile.json"
$VersionPath = Join-Path $LayerRoot "VERSION"
$LayerVersion = if (Test-Path -LiteralPath $VersionPath) { (Get-Content -LiteralPath $VersionPath -Raw).Trim() } else { "0.0.0-dev" }

if (-not (Test-Path -LiteralPath $ProfilePath)) {
  throw "Unknown profile '$Profile'. Expected a JSON file under profiles/."
}

$ProfileDoc = Get-Content -LiteralPath $ProfilePath -Raw | ConvertFrom-Json
function Expand-HarnessList {
  param($Values)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in ([string]$value -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed -and -not $out.Contains($trimmed)) { $out.Add($trimmed) | Out-Null }
    }
  }
  return @($out)
}
$SelectedHarnesses = if ($Harnesses -and $Harnesses.Count -gt 0) { Expand-HarnessList $Harnesses } else { Expand-HarnessList $ProfileDoc.harnesses }
if ($SelectedHarnesses.Count -eq 0) { throw "No harnesses selected. Set profile.harnesses or pass -Harnesses." }

$Mode = if ($Apply) { "APPLY" } else { "PREVIEW" }
$Planned = New-Object System.Collections.Generic.List[string]
$Created = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
$MergeNeeded = New-Object System.Collections.Generic.List[string]
$ManagedPaths = New-Object System.Collections.Generic.List[string]
$OwnedPaths = New-Object System.Collections.Generic.List[string]
$InstalledAdapters = New-Object System.Collections.Generic.List[string]

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

function Ensure-Dir {
  param([string]$Path)
  $label = To-RelativeDisplay $Path
  Add-UniqueListItem $ManagedPaths $label
  if (Test-Path -LiteralPath $Path) {
    Add-UniqueListItem $Skipped $label
    return
  }
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    New-Item -ItemType Directory -Path $Path | Out-Null
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  }
}

function Copy-IfMissing {
  param([string]$Source, [string]$Dest)
  if (-not (Test-Path -LiteralPath $Source)) { throw "Missing source file: $Source" }
  $label = To-RelativeDisplay $Dest
  Add-UniqueListItem $ManagedPaths $label
  $parent = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $parent)) {
    if ($Apply) { New-Item -ItemType Directory -Path $parent | Out-Null }
  }
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) {
    Add-UniqueListItem $Skipped $label
    return
  }
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    Copy-Item -LiteralPath $Source -Destination $Dest -Force:$Force
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  }
}

function Write-IfMissing {
  param([string]$Dest, [string]$Content)
  $label = To-RelativeDisplay $Dest
  Add-UniqueListItem $ManagedPaths $label
  $parent = Split-Path -Parent $Dest
  if (-not (Test-Path -LiteralPath $parent)) {
    if ($Apply) { New-Item -ItemType Directory -Path $parent | Out-Null }
  }
  if ((Test-Path -LiteralPath $Dest) -and -not $Force) {
    Add-UniqueListItem $Skipped $label
    return
  }
  Add-UniqueListItem $Planned $label
  if ($Apply) {
    Set-Content -LiteralPath $Dest -Value $Content -Encoding UTF8
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  }
}

function Copy-InstructionFile {
  param($Adapter, [string]$AdapterDir)
  $instruction = $Adapter.instruction
  $srcRel = Assert-SafeRelativePath $instruction.src "adapter instruction src"
  $dstRel = Assert-SafeRelativePath $instruction.dst "adapter instruction dst"
  $src = Join-Path $AdapterDir $srcRel
  $dst = Join-Path $TargetRoot $dstRel
  $policy = if ($instruction.mergePolicy) { $instruction.mergePolicy } else { 'sidecar-if-exists' }

  if ((Test-Path -LiteralPath $dst) -and -not $Force -and $policy -ne 'overwrite') {
    $existing = Get-Content -LiteralPath $dst -Raw -ErrorAction SilentlyContinue
    if ($existing -match 'lizard-agent-layer') {
      Add-UniqueListItem $Skipped $dstRel
      Add-UniqueListItem $ManagedPaths $dstRel
      return
    }
    if ($policy -eq 'sidecar-if-exists') {
      $sidecarRel = if ($instruction.sidecar) { Assert-SafeRelativePath $instruction.sidecar "adapter instruction sidecar" } else { "$dstRel.lizard-agent-layer" }
      Copy-IfMissing $src (Join-Path $TargetRoot $sidecarRel)
      Add-UniqueListItem $MergeNeeded "$dstRel exists; review $sidecarRel and merge intentionally."
      return
    }
    Add-UniqueListItem $Skipped $dstRel
    return
  }

  Copy-IfMissing $src $dst
}

function Install-Adapter {
  param([string]$AdapterName)
  if ($AdapterName -notmatch '^[a-z0-9][a-z0-9-]{0,62}$') { throw "Invalid adapter name '$AdapterName'." }
  $adapterDir = Join-Path $LayerRoot "adapters\$AdapterName"
  $adapterManifestPath = Join-Path $adapterDir 'adapter.json'
  if (-not (Test-Path -LiteralPath $adapterManifestPath)) { throw "Missing adapter manifest for '$AdapterName': $adapterManifestPath" }
  $adapter = Get-Content -LiteralPath $adapterManifestPath -Raw | ConvertFrom-Json
  if ($adapter.name -ne $AdapterName) { throw "Adapter manifest name '$($adapter.name)' does not match folder '$AdapterName'." }

  Add-UniqueListItem $InstalledAdapters $AdapterName
  Copy-InstructionFile $adapter $adapterDir

  foreach ($mirror in @($adapter.skillMirrors)) {
    $mirrorRel = Assert-SafeRelativePath $mirror.dst "skill mirror dst"
    Ensure-Dir (Join-Path $TargetRoot $mirrorRel)
    foreach ($skill in @($ProfileDoc.skills)) {
      $source = Join-Path $LayerRoot "skills\$skill\SKILL.md"
      Copy-IfMissing $source (Join-Path $TargetRoot "$mirrorRel\$skill\SKILL.md")
    }
  }
}

function Write-InstallManifest {
  $manifestPath = Join-Path $TargetRoot ".agent\lizard-agent-layer.install.json"
  $label = To-RelativeDisplay $manifestPath
  Add-UniqueListItem $ManagedPaths $label
  $doc = [ordered]@{
    schema_version = 2
    layer = "lizard-agent-layer"
    layer_version = $LayerVersion
    profile = $Profile
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
    target_root = $TargetRoot
    memory_mode = $ProfileDoc.memoryMode
    risk_level = $ProfileDoc.riskLevel
    harnesses = @($SelectedHarnesses)
    model_profiles = $ProfileDoc.modelProfiles
    skills = @($ProfileDoc.skills)
    adapters = @($InstalledAdapters)
    managed_paths = @($ManagedPaths)
    owned_paths = @($OwnedPaths)
    merge_needed = @($MergeNeeded)
  }
  if ($Apply) {
    $doc | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  } else {
    Add-UniqueListItem $Planned $label
  }
}

Write-Host "lizard-agent-layer $Mode"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $Profile"
Write-Host "Harnesses: $($SelectedHarnesses -join ', ')"
Write-Host "Version: $LayerVersion"
Write-Host ""

Ensure-Dir (Join-Path $TargetRoot ".agent")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\personal")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\semantic")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\working")
Ensure-Dir (Join-Path $TargetRoot ".agent\protocols")
Ensure-Dir (Join-Path $TargetRoot ".agent\skills")

Copy-IfMissing (Join-Path $LayerRoot "templates\agent-gitignore") (Join-Path $TargetRoot ".agent\.gitignore")
Copy-IfMissing $ProfilePath (Join-Path $TargetRoot ".agent\project-profile.json")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\personal\PREFERENCES.md") (Join-Path $TargetRoot ".agent\memory\personal\PREFERENCES.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\semantic\DECISIONS.md") (Join-Path $TargetRoot ".agent\memory\semantic\DECISIONS.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\semantic\LESSONS.md") (Join-Path $TargetRoot ".agent\memory\semantic\LESSONS.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\working\WORKSPACE.md") (Join-Path $TargetRoot ".agent\memory\working\WORKSPACE.md")

foreach ($protocol in @("permissions.md", "memory-policy.md", "secret-handling.md", "release-gates.md", "handoff.md")) {
  Copy-IfMissing (Join-Path $LayerRoot "protocols\$protocol") (Join-Path $TargetRoot ".agent\protocols\$protocol")
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
  Copy-IfMissing $source (Join-Path $TargetRoot ".agent\skills\$skill\SKILL.md")
  $indexLines.Add("## $skill") | Out-Null
  $indexLines.Add(('Source: `.agent/skills/{0}/SKILL.md`' -f $skill)) | Out-Null
  $indexLines.Add("") | Out-Null
  $manifest = [ordered]@{ name = $skill; source = ".agent/skills/$skill/SKILL.md" }
  $manifestLines.Add(($manifest | ConvertTo-Json -Compress)) | Out-Null
}

Write-IfMissing (Join-Path $TargetRoot ".agent\skills\_index.md") ($indexLines -join "`n")
Write-IfMissing (Join-Path $TargetRoot ".agent\skills\_manifest.jsonl") ($manifestLines -join "`n")

foreach ($adapterName in $SelectedHarnesses) {
  Install-Adapter $adapterName
}

Write-InstallManifest

Write-Host "Summary"
Write-Host "Planned: $($Planned.Count)"
foreach ($item in $Planned) { Write-Host "  + $item" }
Write-Host "Created: $($Created.Count)"
foreach ($item in $Created) { Write-Host "  + $item" }
Write-Host "Skipped existing: $($Skipped.Count)"
foreach ($item in $Skipped) { Write-Host "  ~ $item" }
if ($MergeNeeded.Count -gt 0) {
  Write-Host "Manual merge needed:"
  foreach ($item in $MergeNeeded) { Write-Host "  ! $item" }
}
if (-not $Apply) {
  Write-Host ""
  Write-Host "Preview only. Re-run with -Apply to write files."
}
