param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$Profile = "standard",
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
$Mode = if ($Apply) { "APPLY" } else { "PREVIEW" }
$Planned = New-Object System.Collections.Generic.List[string]
$Created = New-Object System.Collections.Generic.List[string]
$Skipped = New-Object System.Collections.Generic.List[string]
$MergeNeeded = New-Object System.Collections.Generic.List[string]
$ManagedPaths = New-Object System.Collections.Generic.List[string]
$OwnedPaths = New-Object System.Collections.Generic.List[string]

function Add-UniqueListItem {
  param($List, [string]$Value)
  if (-not $List.Contains($Value)) { $List.Add($Value) | Out-Null }
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

function Write-InstallManifest {
  $manifestPath = Join-Path $TargetRoot ".agent\lizard-agent-layer.install.json"
  $label = To-RelativeDisplay $manifestPath
  Add-UniqueListItem $ManagedPaths $label
  $doc = [ordered]@{
    schema_version = 1
    layer = "lizard-agent-layer"
    layer_version = $LayerVersion
    profile = $Profile
    installed_at = (Get-Date).ToUniversalTime().ToString("o")
    target_root = $TargetRoot
    memory_mode = $ProfileDoc.memoryMode
    risk_level = $ProfileDoc.riskLevel
    harnesses = @($ProfileDoc.harnesses)
    skills = @($ProfileDoc.skills)
    managed_paths = @($ManagedPaths)
    owned_paths = @($OwnedPaths)
    merge_needed = @($MergeNeeded)
  }
  if ($Apply) {
    $doc | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Add-UniqueListItem $Created $label
    Add-UniqueListItem $OwnedPaths $label
  } else {
    Add-UniqueListItem $Planned $label
  }
}

Write-Host "lizard-agent-layer $Mode"
Write-Host "Target: $TargetRoot"
Write-Host "Profile: $Profile"
Write-Host "Version: $LayerVersion"
Write-Host ""

Ensure-Dir (Join-Path $TargetRoot ".agent")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\personal")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\semantic")
Ensure-Dir (Join-Path $TargetRoot ".agent\memory\working")
Ensure-Dir (Join-Path $TargetRoot ".agent\protocols")
Ensure-Dir (Join-Path $TargetRoot ".agent\skills")
Ensure-Dir (Join-Path $TargetRoot ".agents\skills")

Copy-IfMissing (Join-Path $LayerRoot "templates\agent-gitignore") (Join-Path $TargetRoot ".agent\.gitignore")
Copy-IfMissing $ProfilePath (Join-Path $TargetRoot ".agent\project-profile.json")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\personal\PREFERENCES.md") (Join-Path $TargetRoot ".agent\memory\personal\PREFERENCES.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\semantic\DECISIONS.md") (Join-Path $TargetRoot ".agent\memory\semantic\DECISIONS.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\semantic\LESSONS.md") (Join-Path $TargetRoot ".agent\memory\semantic\LESSONS.md")
Copy-IfMissing (Join-Path $LayerRoot "templates\memory\working\WORKSPACE.md") (Join-Path $TargetRoot ".agent\memory\working\WORKSPACE.md")

foreach ($protocol in @("permissions.md", "memory-policy.md", "secret-handling.md", "release-gates.md")) {
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
  Copy-IfMissing $source (Join-Path $TargetRoot ".agents\skills\$skill\SKILL.md")
  $indexLines.Add("## $skill") | Out-Null
  $indexLines.Add(('Source: `.agent/skills/{0}/SKILL.md`' -f $skill)) | Out-Null
  $indexLines.Add("") | Out-Null
  $manifest = [ordered]@{ name = $skill; source = ".agent/skills/$skill/SKILL.md" }
  $manifestLines.Add(($manifest | ConvertTo-Json -Compress)) | Out-Null
}

Write-IfMissing (Join-Path $TargetRoot ".agent\skills\_index.md") ($indexLines -join "`n")
Write-IfMissing (Join-Path $TargetRoot ".agent\skills\_manifest.jsonl") ($manifestLines -join "`n")

$adapterSource = Join-Path $LayerRoot "adapters\codex\AGENTS.lizard.md"
$rootAgents = Join-Path $TargetRoot "AGENTS.md"
if ((Test-Path -LiteralPath $rootAgents) -and -not $Force) {
  $existingAgents = Get-Content -LiteralPath $rootAgents -Raw -ErrorAction SilentlyContinue
  if ($existingAgents -match "lizard-agent-layer") {
    Add-UniqueListItem $Skipped "AGENTS.md"
    Add-UniqueListItem $ManagedPaths "AGENTS.md"
  } else {
    Copy-IfMissing $adapterSource (Join-Path $TargetRoot "AGENTS.lizard-agent-layer.md")
    Add-UniqueListItem $MergeNeeded "AGENTS.md exists; review AGENTS.lizard-agent-layer.md and merge intentionally."
  }
} else {
  Copy-IfMissing $adapterSource $rootAgents
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
