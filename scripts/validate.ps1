param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = "Stop"
$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]

function Fail { param([string]$Message) $Failures.Add($Message) | Out-Null }
function Warn { param([string]$Message) $Warnings.Add($Message) | Out-Null }
function Is-HyphenName { param([string]$Name) return $Name -match '^[a-z0-9][a-z0-9-]{0,62}$' }
function Is-SafeRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
  if ([System.IO.Path]::IsPathRooted($Path)) { return $false }
  if ($Path -match '^[A-Za-z]:') { return $false }
  $normalized = $Path.Replace('/', '\')
  if ($normalized -match '(^|\\)\.\.($|\\)') { return $false }
  return $true
}

function Read-JsonFile {
  param([string]$Path)
  try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
  catch { Fail "Invalid JSON: $Path ($($_.Exception.Message))"; return $null }
}

if (-not (Test-Path -LiteralPath (Join-Path $LayerRoot 'VERSION'))) { Fail 'Missing VERSION file.' }
if (-not (Test-Path -LiteralPath (Join-Path $LayerRoot 'README.md'))) { Fail 'Missing README.md.' }
if (-not (Test-Path -LiteralPath (Join-Path $LayerRoot 'LICENSE'))) { Warn 'Missing LICENSE file.' }

$adapterNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'adapters') -Directory | ForEach-Object {
  $name = $_.Name
  if (-not (Is-HyphenName $name)) { Fail "Invalid adapter folder name '$name'." }
  $manifestPath = Join-Path $_.FullName 'adapter.json'
  if (-not (Test-Path -LiteralPath $manifestPath)) { Fail "Adapter '$name' missing adapter.json."; return }
  $adapter = Read-JsonFile $manifestPath
  if ($null -eq $adapter) { return }
  $adapterNames.Add($name) | Out-Null
  foreach ($field in @('name', 'description', 'instruction', 'skillMirrors')) {
    if (-not ($adapter.PSObject.Properties.Name -contains $field)) { Fail "Adapter $name missing '$field'." }
  }
  if ($adapter.name -ne $name) { Fail "Adapter $name manifest name '$($adapter.name)' does not match folder." }
  if (-not $adapter.instruction.src -or -not $adapter.instruction.dst) { Fail "Adapter $name instruction requires src and dst." }
  foreach ($pathField in @('src', 'dst', 'sidecar')) {
    if ($adapter.instruction.PSObject.Properties.Name -contains $pathField) {
      $pathValue = $adapter.instruction.$pathField
      if ($pathValue -and -not (Is-SafeRelativePath $pathValue)) { Fail "Adapter $name instruction $pathField is unsafe: $pathValue" }
    }
  }
  $srcPath = Join-Path $_.FullName ($adapter.instruction.src.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $srcPath)) { Fail "Adapter $name instruction source missing: $($adapter.instruction.src)" }
  foreach ($mirror in @($adapter.skillMirrors)) {
    if (-not $mirror.dst) { Fail "Adapter $name has skill mirror without dst." }
    elseif (-not (Is-SafeRelativePath $mirror.dst)) { Fail "Adapter $name skill mirror dst is unsafe: $($mirror.dst)" }
  }
}

$modelNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'model-profiles') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $model = Read-JsonFile $_.FullName
  if ($null -eq $model) { return }
  foreach ($field in @('name', 'provider', 'bestFor', 'limits')) {
    if (-not ($model.PSObject.Properties.Name -contains $field)) { Fail "Model profile $($_.Name) missing '$field'." }
  }
  if ($model.name) { $modelNames.Add($model.name) | Out-Null }
}

Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'profiles') -Filter '*.json' -File | ForEach-Object {
  $profile = Read-JsonFile $_.FullName
  if ($null -eq $profile) { return }
  foreach ($field in @('profile', 'riskLevel', 'memoryMode', 'harnesses', 'skills')) {
    if (-not ($profile.PSObject.Properties.Name -contains $field)) { Fail "Profile $($_.Name) missing '$field'." }
  }
  if ($profile.riskLevel -and $profile.riskLevel -notin @('low', 'medium', 'high')) { Fail "Profile $($_.Name) has invalid riskLevel '$($profile.riskLevel)'." }
  if ($profile.memoryMode -and $profile.memoryMode -notin @('curated', 'private-episodic', 'off')) { Fail "Profile $($_.Name) has invalid memoryMode '$($profile.memoryMode)'." }
  foreach ($harness in @($profile.harnesses)) {
    if (-not $adapterNames.Contains($harness)) { Fail "Profile $($_.Name) references missing adapter '$harness'." }
  }
  foreach ($skill in @($profile.skills)) {
    if (-not (Is-HyphenName $skill)) { Fail "Profile $($_.Name) references invalid skill name '$skill'." }
    $skillPath = Join-Path $LayerRoot "skills\$skill\SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) { Fail "Profile $($_.Name) references missing skill '$skill'." }
  }
  if ($profile.modelProfiles) {
    foreach ($prop in $profile.modelProfiles.PSObject.Properties) {
      if (-not $modelNames.Contains([string]$prop.Value)) { Fail "Profile $($_.Name) references missing model profile '$($prop.Value)' for '$($prop.Name)'." }
    }
  }
}

Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'examples') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $example = Read-JsonFile $_.FullName
  if ($null -eq $example) { return }
  foreach ($harness in @($example.harnesses)) {
    if (-not $adapterNames.Contains($harness)) { Fail "Example $($_.Name) references missing adapter '$harness'." }
  }
}
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\lizard-agent-layer.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\adapter.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\model-profile.schema.json')

Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'skills') -Directory | ForEach-Object {
  $folderName = $_.Name
  if (-not (Is-HyphenName $folderName)) { Fail "Invalid skill folder name '$folderName'." }
  $skillPath = Join-Path $_.FullName 'SKILL.md'
  if (-not (Test-Path -LiteralPath $skillPath)) { Fail "Skill '$folderName' missing SKILL.md."; return }
  $lines = Get-Content -LiteralPath $skillPath
  if ($lines.Count -lt 5 -or $lines[0] -ne '---') { Fail "Skill '$folderName' missing frontmatter."; return }
  $end = -1
  for ($i = 1; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -eq '---') { $end = $i; break }
  }
  if ($end -lt 0) { Fail "Skill '$folderName' has unterminated frontmatter."; return }
  $frontmatter = $lines[1..($end - 1)]
  $keys = @()
  $values = @{}
  foreach ($line in $frontmatter) {
    if ($line.Trim() -eq '') { continue }
    if ($line -notmatch '^([A-Za-z0-9_-]+):\s*(.*)$') { Fail "Skill '$folderName' has unsupported frontmatter line: $line"; continue }
    $key = $Matches[1]
    $value = $Matches[2].Trim()
    $keys += $key
    $values[$key] = $value
  }
  foreach ($required in @('name', 'description')) {
    if (-not ($keys -contains $required)) { Fail "Skill '$folderName' missing frontmatter key '$required'." }
  }
  foreach ($key in $keys) {
    if ($key -notin @('name', 'description')) { Fail "Skill '$folderName' has non-Codex frontmatter key '$key'." }
  }
  if ($values['name'] -ne $folderName) { Fail "Skill '$folderName' frontmatter name '$($values['name'])' does not match folder." }
  if ([string]::IsNullOrWhiteSpace($values['description'])) { Fail "Skill '$folderName' has empty description." }
}

foreach ($script in @('install.ps1', 'validate.ps1', 'doctor.ps1', 'sync-manifest.ps1', 'upgrade.ps1', 'matrix.ps1', 'analyze-target.ps1')) {
  $path = Join-Path $LayerRoot "scripts\$script"
  if (-not (Test-Path -LiteralPath $path)) { Fail "Missing script $script."; continue }
  try { $null = [scriptblock]::Create((Get-Content -LiteralPath $path -Raw)) }
  catch { Fail "PowerShell parse failure in ${script}: $($_.Exception.Message)" }
}

if ($Warnings.Count -gt 0) {
  Write-Host 'Warnings:'
  foreach ($warning in $Warnings) { Write-Host "  WARN $warning" }
}

if ($Failures.Count -gt 0) {
  Write-Host 'Validation failed:'
  foreach ($failure in $Failures) { Write-Host "  FAIL $failure" }
  exit 1
}

Write-Host 'lizard-agent-layer validation passed.'
