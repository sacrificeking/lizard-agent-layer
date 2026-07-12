param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Manifest.psm1') -Force
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
$adapterEntries = New-Object System.Collections.Generic.List[object]
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
  if ($adapter.compatibility) {
    if (-not (Is-HyphenName ([string]$adapter.compatibility.instructionGroup))) { Fail "Adapter $name has invalid compatibility instructionGroup." }
    try { $precedence = [int]$adapter.compatibility.precedence; if ($precedence -lt 0) { throw 'negative' } }
    catch { Fail "Adapter $name has invalid compatibility precedence '$($adapter.compatibility.precedence)'." }
  }
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
  $adapterEntries.Add([pscustomobject]@{ name = $name; manifest = $adapter; adapter_dir = $_.FullName }) | Out-Null
}

try { $null = Resolve-LizardAdapterComposition -Adapters @($adapterEntries.ToArray()) }
catch { Fail $_.Exception.Message }

$packNames = New-Object System.Collections.Generic.HashSet[string]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'packs') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object { $packNames.Add([System.IO.Path]::GetFileNameWithoutExtension($_.Name)) | Out-Null }

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
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'packs') -Filter '*.json' -File -ErrorAction SilentlyContinue | ForEach-Object {
  $pack = Read-JsonFile $_.FullName
  if ($null -eq $pack) { return }
  $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
  foreach ($field in @('name', 'description', 'riskLevel', 'projectSize', 'skills')) {
    if (-not ($pack.PSObject.Properties.Name -contains $field)) { Fail "Pack $($_.Name) missing '$field'." }
  }
  if ($pack.name -ne $expectedName) { Fail "Pack $($_.Name) manifest name '$($pack.name)' does not match filename." }
  if ($pack.name -and -not (Is-HyphenName $pack.name)) { Fail "Pack $($_.Name) has invalid name '$($pack.name)'." }
  if ($pack.riskLevel -and $pack.riskLevel -notin @('low', 'medium', 'high')) { Fail "Pack $($_.Name) has invalid riskLevel '$($pack.riskLevel)'." }
  if ($pack.projectSize -and $pack.projectSize -notin @('small', 'medium', 'large')) { Fail "Pack $($_.Name) has invalid projectSize '$($pack.projectSize)'." }
  if ($pack.PSObject.Properties.Name -contains 'extends') {
    foreach ($basePack in @(($pack.extends | ForEach-Object { [string]$_ }) -split ',')) {
      $basePack = $basePack.Trim()
      if ($basePack -and -not $packNames.Contains($basePack)) { Fail "Pack $($_.Name) references missing extended pack '$basePack'." }
    }
  }  foreach ($skill in @($pack.skills)) {
    if (-not (Is-HyphenName $skill)) { Fail "Pack $($_.Name) references invalid skill name '$skill'."; continue }
    $skillPath = Join-Path $LayerRoot "skills\$skill\SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) { Fail "Pack $($_.Name) references missing skill '$skill'." }
  }
  foreach ($harness in @($pack.harnesses)) {
    if (-not $adapterNames.Contains($harness)) { Fail "Pack $($_.Name) references missing adapter '$harness'." }
  }
  if ($pack.modelProfiles) {
    foreach ($prop in $pack.modelProfiles.PSObject.Properties) {
      if (-not $modelNames.Contains([string]$prop.Value)) { Fail "Pack $($_.Name) references missing model profile '$($prop.Value)' for '$($prop.Name)'." }
    }
  }
}
$loopRegistryPath = Join-Path $LayerRoot 'loops\registry.json'
$loopRegistry = Read-JsonFile $loopRegistryPath
$loopNames = New-Object System.Collections.Generic.HashSet[string]
if ($null -ne $loopRegistry) {
  if (-not ($loopRegistry.PSObject.Properties.Name -contains 'schema_version')) { Fail 'Loop registry missing schema_version.' }
  if (-not ($loopRegistry.PSObject.Properties.Name -contains 'patterns')) { Fail 'Loop registry missing patterns.' }
  foreach ($entry in @($loopRegistry.patterns)) {
    foreach ($field in @('name', 'file', 'readinessLevel', 'riskLevel', 'description')) {
      if (-not ($entry.PSObject.Properties.Name -contains $field)) { Fail "Loop registry entry missing '$field'." }
    }
    if ($entry.name -and -not (Is-HyphenName ([string]$entry.name))) { Fail "Loop registry has invalid pattern name '$($entry.name)'." }
    if ($entry.readinessLevel -and $entry.readinessLevel -notin @('L0', 'L1', 'L2', 'L3')) { Fail "Loop registry entry $($entry.name) has invalid readinessLevel '$($entry.readinessLevel)'." }
    if ($entry.riskLevel -and $entry.riskLevel -notin @('low', 'medium', 'high')) { Fail "Loop registry entry $($entry.name) has invalid riskLevel '$($entry.riskLevel)'." }
    if ($entry.file -and -not (Is-SafeRelativePath ([string]$entry.file))) { Fail "Loop registry entry $($entry.name) has unsafe file path '$($entry.file)'." }
    elseif ($entry.file -and -not (Test-Path -LiteralPath (Join-Path $LayerRoot ([string]$entry.file).Replace('/', '\')))) { Fail "Loop registry entry $($entry.name) references missing file '$($entry.file)'." }
    if ($entry.name) { $loopNames.Add([string]$entry.name) | Out-Null }
  }
}

Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'loops') -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'registry.json' } | ForEach-Object {
  $loop = Read-JsonFile $_.FullName
  if ($null -eq $loop) { return }
  $expectedName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
  foreach ($field in @('name', 'description', 'readinessLevel', 'riskLevel', 'cadence', 'stateFile', 'budgetFile', 'runLogFile', 'constraintsFile', 'runtimeBudgetFile', 'runtimeStateFile', 'runtimeEventsFile', 'runtimeLeaseFile', 'skills', 'allowedActions', 'humanGates')) {
    if (-not ($loop.PSObject.Properties.Name -contains $field)) { Fail "Loop $($_.Name) missing '$field'." }
  }
  if ($loop.name -ne $expectedName) { Fail "Loop $($_.Name) manifest name '$($loop.name)' does not match filename." }
  if ($loop.name -and -not (Is-HyphenName $loop.name)) { Fail "Loop $($_.Name) has invalid name '$($loop.name)'." }
  if ($loop.readinessLevel -and $loop.readinessLevel -notin @('L0', 'L1', 'L2', 'L3')) { Fail "Loop $($_.Name) has invalid readinessLevel '$($loop.readinessLevel)'." }
  if ($loop.riskLevel -and $loop.riskLevel -notin @('low', 'medium', 'high')) { Fail "Loop $($_.Name) has invalid riskLevel '$($loop.riskLevel)'." }
  if (-not $loopNames.Contains([string]$loop.name)) { Fail "Loop $($_.Name) is not listed in loops/registry.json." }
  if ($loop.cadence) {
    foreach ($field in @('recommended', 'minimum', 'notes')) {
      if (-not ($loop.cadence.PSObject.Properties.Name -contains $field)) { Fail "Loop $($_.Name) cadence missing '$field'." }
    }
  }
  foreach ($pathField in @('stateFile', 'budgetFile', 'runLogFile', 'constraintsFile', 'runtimeBudgetFile', 'runtimeStateFile', 'runtimeEventsFile', 'runtimeLeaseFile')) {
    $pathValue = [string]$loop.$pathField
    if (-not (Is-SafeRelativePath $pathValue)) { Fail "Loop $($_.Name) $pathField is unsafe: $pathValue" }
    elseif ($pathValue.Replace('/', '\') -notmatch '^\.agent\\loops\\') { Warn "Loop $($_.Name) $pathField is outside .agent/loops: $pathValue" }
  }
  foreach ($pathField in @('worktreePolicyFile', 'assistedPlanFile', 'verifierFile')) {
    if ($loop.PSObject.Properties.Name -contains $pathField) {
      $pathValue = [string]$loop.$pathField
      if (-not (Is-SafeRelativePath $pathValue)) { Fail "Loop $($_.Name) $pathField is unsafe: $pathValue" }
      elseif ($pathValue.Replace('/', '\') -notmatch '^\.agent\\loops\\') { Warn "Loop $($_.Name) $pathField is outside .agent/loops: $pathValue" }
    }
  }
  foreach ($skill in @($loop.skills)) {
    if (-not (Is-HyphenName ([string]$skill))) { Fail "Loop $($_.Name) references invalid skill name '$skill'."; continue }
    $skillPath = Join-Path $LayerRoot "skills\$skill\SKILL.md"
    if (-not (Test-Path -LiteralPath $skillPath)) { Fail "Loop $($_.Name) references missing skill '$skill'." }
  }
  if (@($loop.allowedActions).Count -lt 1) { Fail "Loop $($_.Name) has no allowedActions." }
  if (@($loop.humanGates).Count -lt 1) { Fail "Loop $($_.Name) has no humanGates." }
  if ($loop.readinessLevel -eq 'L2') {
    foreach ($field in @('worktreePolicyFile', 'assistedPlanFile', 'verifierFile')) {
      if (-not ($loop.PSObject.Properties.Name -contains $field)) { Fail "L2 loop $($_.Name) missing '$field'." }
    }
    foreach ($requiredSkill in @('worktree-isolation', 'minimal-fix', 'loop-verifier')) {
      if (@($loop.skills) -notcontains $requiredSkill) { Fail "L2 loop $($_.Name) missing required skill '$requiredSkill'." }
    }
    foreach ($requiredGate in @('human_approval_before_worktree_apply', 'human_review_before_merge', 'verifier_required_before_done')) {
      if (@($loop.humanGates) -notcontains $requiredGate) { Fail "L2 loop $($_.Name) missing required gate '$requiredGate'." }
    }
    if (@($loop.deniedActions) -notcontains 'auto-merge') { Fail "L2 loop $($_.Name) must deny auto-merge." }
  }
  if ($loop.modelStrategy) {
    foreach ($bucket in @('cheap', 'strong')) {
      if (-not ($loop.modelStrategy.PSObject.Properties.Name -contains $bucket)) { Warn "Loop $($_.Name) modelStrategy missing '$bucket' bucket." }
    }
  }
}
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\lizard-agent-layer.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\adapter.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\install-manifest.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\model-profile.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\quality-registry.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\maturity-levels.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\pack.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\loop.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\loop-registry.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\manifest-migrations.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\risk-signals.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\drift-baseline.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\verifier-evidence.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\worktree-lifecycle.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\merge-suggestions-report.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\behavioral-readiness.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\skill-evidence.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\focused-test-report.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\contracts.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\contract-change.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'schemas\contract-check-report.schema.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'registry\quality-rubric.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'registry\maturity-levels.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'registry\risk-signals.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'registry\behavioral-readiness.json')
$null = Read-JsonFile (Join-Path $LayerRoot 'registry\contracts.json')
$migrationRegistry = Read-JsonFile (Join-Path $LayerRoot 'registry\manifest-migrations.json')
if ($migrationRegistry) {
  if ([int]$migrationRegistry.currentSchemaVersion -ne 3) { Fail 'Manifest migration registry currentSchemaVersion must be 3.' }
  if ([int]$migrationRegistry.minimumReadableSchemaVersion -ne 2 -or [int]$migrationRegistry.maximumReadableSchemaVersion -ne 3) { Fail 'Manifest migration reader range must be 2 through 3.' }
  $v2Migration = @($migrationRegistry.migrations | Where-Object { [int]$_.from -eq 2 -and [int]$_.to -eq 3 })
  if ($v2Migration.Count -ne 1 -or [string]$v2Migration[0].ambiguousOwnership -ne 'user-owned') { Fail 'Manifest migration registry must define one conservative v2-to-v3 migration.' }
}

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

foreach ($script in @('install.ps1', 'validate.ps1', 'doctor.ps1', 'sync-manifest.ps1', 'upgrade.ps1', 'matrix.ps1', 'analyze-target.ps1', 'merge-suggestions.ps1', 'ci.ps1', 'contract-check.ps1', 'score-layer.ps1', 'drift-check.ps1', 'pack-report.ps1', 'manifest-diff.ps1', 'update-target.ps1', 'transaction-recover.ps1', 'loop-init.ps1', 'loop-audit.ps1', 'loop-report.ps1', 'loop-sync.ps1', 'loop-cost.ps1', 'loop-worktree.ps1', 'loop-verify.ps1', 'loop-worktree-cleanup.ps1')) {
  $path = Join-Path $LayerRoot "scripts\$script"
  if (-not (Test-Path -LiteralPath $path)) { Fail "Missing script $script."; continue }
  try { $null = [scriptblock]::Create((Get-Content -LiteralPath $path -Raw)) }
  catch { Fail "PowerShell parse failure in ${script}: $($_.Exception.Message)" }
}

foreach ($relative in @('scripts\Lizard.SafeFs.psm1', 'scripts\Lizard.Manifest.psm1', 'scripts\Lizard.Host.psm1', 'scripts\Lizard.Transaction.psm1', 'scripts\Lizard.LoopEvidence.psm1', 'scripts\Lizard.QualityEvidence.psm1', 'tests\TestHelpers.psm1', 'tests\run-focused.ps1', 'tests\unit\safe-fs.tests.ps1', 'tests\unit\host.tests.ps1', 'tests\integration\manifest-v3.tests.ps1', 'tests\integration\transaction.tests.ps1', 'tests\adversarial\install-containment.tests.ps1', 'tests\adversarial\report-privacy.tests.ps1', 'tests\adversarial\quality-evidence.tests.ps1', 'tests\adversarial\contract-governance.tests.ps1', 'tests\adversarial\version-gates.tests.ps1', 'tests\adversarial\loop-evidence.tests.ps1')) {
  $path = Join-Path $LayerRoot $relative
  if (-not (Test-Path -LiteralPath $path)) { Fail "Missing safety artifact $relative."; continue }
  try { $null = [scriptblock]::Create((Get-Content -LiteralPath $path -Raw)) }
  catch { Fail "PowerShell parse failure in ${relative}: $($_.Exception.Message)" }
}

$schemaValidator = Join-Path $LayerRoot 'tools\schema-validator\validate.mjs'
$ajvPackage = Join-Path $LayerRoot 'node_modules\ajv\package.json'
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) {
  Fail 'SCHEMA_VALIDATOR_NODE_MISSING: Node.js 22 or newer is required for executable schema validation.'
} elseif (-not (Test-Path -LiteralPath $ajvPackage -PathType Leaf)) {
  Fail 'SCHEMA_VALIDATOR_DEPENDENCY_MISSING: Run npm ci before validation.'
} elseif (-not (Test-Path -LiteralPath $schemaValidator -PathType Leaf)) {
  Fail 'Missing tools/schema-validator/validate.mjs.'
} else {
  $schemaOutput = & $nodeCommand.Source $schemaValidator --root $LayerRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { Fail "Executable JSON Schema validation failed: $schemaOutput" }
  elseif ($schemaOutput) { Write-Host $schemaOutput.Trim() }
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
