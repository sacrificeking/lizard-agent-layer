param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$OutputDir,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $LayerRoot '.tmp\packs' }
$OutputDir = Initialize-SafeDirectory -Path $OutputDir

$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]
function Fail { param([string]$Message) $Failures.Add($Message) | Out-Null }
function Warn { param([string]$Message) $Warnings.Add($Message) | Out-Null }
function Is-HyphenName { param([string]$Name) $Name -match '^[a-z0-9][a-z0-9-]{0,62}$' }
function Read-JsonFile {
  param([string]$Path)
  try { Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
  catch { Fail "Invalid JSON: $Path ($($_.Exception.Message))"; $null }
}
function Get-RelativePath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $resolved.Substring($LayerRoot.Length).TrimStart('\').Replace('\', '/')
}

$skillNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'skills') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $skillNames.Add($_.Name) | Out-Null }
$adapterNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'adapters') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $adapterNames.Add($_.Name) | Out-Null }
$packNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'packs') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $packNames.Add([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) | Out-Null }

$modelNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'model-profiles') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $model = Read-JsonFile $_.FullName
  if ($model -and $model.name) { $modelNames.Add([string]$model.name) | Out-Null }
}

$packs = New-Object System.Collections.Generic.List[object]
$packRoot = Join-Path $LayerRoot 'packs'
if (-not (Test-Path -LiteralPath $packRoot)) { Fail 'Missing packs directory.' }
else {
  Get-ChildItem -LiteralPath $packRoot -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
    $pack = Read-JsonFile $_.FullName
    if ($null -eq $pack) { return }
    $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    foreach ($field in @('name', 'description', 'riskLevel', 'projectSize', 'skills')) {
      if (-not ($pack.PSObject.Properties.Name -contains $field)) { Fail "Pack $($_.Name) missing '$field'." }
    }
    if ($pack.name -ne $expectedName) { Fail "Pack $($_.Name) name '$($pack.name)' does not match file '$expectedName'." }
    if (-not (Is-HyphenName ([string]$pack.name))) { Fail "Pack $($_.Name) has invalid name '$($pack.name)'." }
    if ($pack.riskLevel -and $pack.riskLevel -notin @('low', 'medium', 'high')) { Fail "Pack $($pack.name) has invalid riskLevel '$($pack.riskLevel)'." }
    if ($pack.projectSize -and $pack.projectSize -notin @('small', 'medium', 'large')) { Fail "Pack $($pack.name) has invalid projectSize '$($pack.projectSize)'." }
    if ($pack.PSObject.Properties.Name -contains 'extends') {
      foreach ($basePack in @(($pack.extends | ForEach-Object { [string]$_ }) -split ',')) {
        $basePack = $basePack.Trim()
        if ($basePack -and -not $packNames.Contains($basePack)) { Fail "Pack $($pack.name) extends missing pack '$basePack'." }
      }
    }    foreach ($skill in @($pack.skills)) {
      if (-not $skillNames.Contains([string]$skill)) { Fail "Pack $($pack.name) references missing skill '$skill'." }
    }
    foreach ($harness in @($pack.harnesses)) {
      if (-not $adapterNames.Contains([string]$harness)) { Fail "Pack $($pack.name) references missing adapter '$harness'." }
    }
    if ($pack.modelProfiles) {
      foreach ($prop in $pack.modelProfiles.PSObject.Properties) {
        if (-not $modelNames.Contains([string]$prop.Value)) { Fail "Pack $($pack.name) references missing model profile '$($prop.Value)' for '$($prop.Name)'." }
      }
    }
    if (@($pack.skills).Count -eq 0) { Fail "Pack $($pack.name) has no skills." }
    if (@($pack.verification).Count -eq 0 -and $pack.riskLevel -ne 'low') { Warn "Pack $($pack.name) has no verification guidance." }
    $packs.Add([ordered]@{
      name = [string]$pack.name
      path = Get-RelativePath $_.FullName
      riskLevel = [string]$pack.riskLevel
      projectSize = [string]$pack.projectSize
      stack = @($pack.stack)
      harnesses = @($pack.harnesses)
      skills = @($pack.skills)
      verification = @($pack.verification)
      recommendedForSignals = @($pack.recommendedForSignals)
      notes = [string]$pack.notes
    }) | Out-Null
  }
}

$uniqueSkills = New-Object System.Collections.Generic.HashSet[string]
foreach ($pack in @($packs.ToArray())) { foreach ($skill in @($pack.skills)) { $uniqueSkills.Add([string]$skill) | Out-Null } }

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  layer_root = $LayerRoot
  status = if ($Failures.Count -eq 0) { 'pass' } else { 'fail' }
  summary = [ordered]@{ packs = $packs.Count; unique_skills = $uniqueSkills.Count; failures = $Failures.Count; warnings = $Warnings.Count }
  packs = @($packs.ToArray())
  failures = @($Failures.ToArray())
  warnings = @($Warnings.ToArray())
}
$jsonPath = Join-Path $OutputDir 'pack-report.json'
$mdPath = Join-Path $OutputDir 'pack-report.md'
Set-SafeContent -AuthorizedRoot $OutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 10)

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Lizard Agent Layer Pack Report') | Out-Null
$md.Add('') | Out-Null
$md.Add("Generated: $($report.generated_at)") | Out-Null
$md.Add("Status: $($report.status)") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Summary') | Out-Null
$md.Add('') | Out-Null
$md.Add("- Packs: $($report.summary.packs)") | Out-Null
$md.Add("- Unique skills: $($report.summary.unique_skills)") | Out-Null
$md.Add("- Failures: $($report.summary.failures)") | Out-Null
$md.Add("- Warnings: $($report.summary.warnings)") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Packs') | Out-Null
$md.Add('') | Out-Null
$md.Add('| Name | Risk | Size | Skills | Harnesses |') | Out-Null
$md.Add('| --- | --- | --- | --- | --- |') | Out-Null
foreach ($pack in @($packs.ToArray())) { $md.Add("| $($pack.name) | $($pack.riskLevel) | $($pack.projectSize) | $(@($pack.skills) -join ', ') | $(@($pack.harnesses) -join ', ') |") | Out-Null }
$md.Add('') | Out-Null
if ($Failures.Count -gt 0) {
  $md.Add('## Failures') | Out-Null
  $md.Add('') | Out-Null
  foreach ($failure in @($Failures.ToArray())) { $md.Add("- $failure") | Out-Null }
  $md.Add('') | Out-Null
}
if ($Warnings.Count -gt 0) {
  $md.Add('## Warnings') | Out-Null
  $md.Add('') | Out-Null
  foreach ($warning in @($Warnings.ToArray())) { $md.Add("- $warning") | Out-Null }
  $md.Add('') | Out-Null
}
Set-SafeContent -AuthorizedRoot $OutputDir -Path $mdPath -Value $md

Write-Host "Pack report: $($report.status)"
Write-Host "Packs: $($report.summary.packs), unique skills: $($report.summary.unique_skills), failures: $($report.summary.failures), warnings: $($report.summary.warnings)"
Write-Host "Report: $jsonPath"
Write-Host "Markdown: $mdPath"
if ($Failures.Count -gt 0) { foreach ($failure in @($Failures.ToArray())) { Write-Host "FAIL $failure" } }
if ($Strict -and $Failures.Count -gt 0) { exit 1 }
