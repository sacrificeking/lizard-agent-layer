param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Manifest.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SkillPackage.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]
$Ok = New-Object System.Collections.Generic.List[string]

function Add-Ok { param([string]$Message) $Ok.Add($Message) | Out-Null }
function Add-Warn { param([string]$Message) $Warnings.Add($Message) | Out-Null }
function Add-Fail { param([string]$Message) $Failures.Add($Message) | Out-Null }
function Check-File {
  param([string]$Relative, [switch]$Required)
  $path = Join-Path $TargetRoot $Relative
  if (Test-Path -LiteralPath $path) { Add-Ok "$Relative exists"; return $true }
  if ($Required) { Add-Fail "$Relative missing" } else { Add-Warn "$Relative missing" }
  return $false
}
function Normalize-RelPath { param([string]$Path) return $Path.Replace('/', '\').TrimStart('\') }
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

Write-Host "lizard-agent-layer doctor"
Write-Host "Target: $TargetRoot"
Write-Host ""

$transactionStore = Join-Path $TargetRoot '.lizard-agent-layer-transactions'
try {
  $transactionInfo = Get-LizardTransactionRecoveryInfo -TargetRoot $TargetRoot
  if ($null -eq $transactionInfo) {
    if (Test-Path -LiteralPath $transactionStore) { Add-Fail 'TRANSACTION_ORPHAN_METADATA: transaction metadata exists without a lock.' }
    else { Add-Ok 'transaction control metadata is clean' }
  } elseif ([string]$transactionInfo.journal_state -eq 'active') {
    $ownerLive = $false
    try { $ownerLive = $null -ne (Get-Process -Id ([int]$transactionInfo.lock.owner_pid) -ErrorAction Stop) } catch { $ownerLive = $false }
    if ($ownerLive) { Add-Fail "TRANSACTION_ACTIVE: operation $($transactionInfo.lock.operation_id) is active; do not run another writer." }
    else { Add-Fail "TRANSACTION_RECOVERY_REQUIRED: operation $($transactionInfo.lock.operation_id) has a stale active journal." }
  } elseif ([string]$transactionInfo.journal_state -eq 'recovery-required') {
    Add-Fail "TRANSACTION_RECOVERY_REQUIRED: operation $($transactionInfo.lock.operation_id) requires retry-safe rollback."
  } else {
    Add-Fail "TRANSACTION_CLEANUP_REQUIRED: operation $($transactionInfo.lock.operation_id) is $($transactionInfo.journal_state) and requires metadata cleanup."
  }
} catch {
  Add-Fail "TRANSACTION_EVIDENCE_INVALID: $($_.Exception.Message)"
}

$profilePath = Join-Path $TargetRoot '.agent\project-profile.json'
$manifestPath = Join-Path $TargetRoot '.agent\lizard-agent-layer.install.json'
$profile = $null
$manifest = $null
$harnesses = @()
$manifestSchema = 0

Check-File '.agent\project-profile.json' -Required | Out-Null
if (Test-Path -LiteralPath $profilePath) {
  try { $profile = Get-Content -LiteralPath $profilePath -Raw | ConvertFrom-Json; Add-Ok "profile loaded: $($profile.profile)" }
  catch { Add-Fail "project-profile.json is invalid JSON: $($_.Exception.Message)" }
}

if (Test-Path -LiteralPath $manifestPath) {
  try {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifestSchema = if ($null -ne $manifest.schema_version) { [int]$manifest.schema_version } else { 1 }
    if ($manifestSchema -gt 4) { Add-Fail "install manifest schema $manifestSchema is newer than supported schema 4." }
    elseif ($manifestSchema -lt 3) { Add-Warn "install manifest schema $manifestSchema has unknown content integrity; migrate to schema 4." }
    elseif ($manifestSchema -lt 4) { Add-Warn "install manifest schema $manifestSchema has no continuous artifact lifecycle; migrate to schema 4." }
    else { Add-Ok "install manifest loaded: $($manifest.layer_version), schema 4" }
  }
  catch { Add-Fail "install manifest is invalid JSON: $($_.Exception.Message)" }
} else {
  Add-Warn '.agent\lizard-agent-layer.install.json missing; target may be preview-only or pre-manifest install.'
}

if ($null -ne $manifest -and $manifest.harnesses) { $harnesses = @($manifest.harnesses) }
elseif ($null -ne $profile -and $profile.harnesses) { $harnesses = @($profile.harnesses) }

$profileMemoryMode = if ($null -ne $profile -and $profile.PSObject.Properties.Name -contains 'memoryMode') { [string]$profile.memoryMode } else { $null }
$manifestMemoryMode = if ($null -ne $manifest -and $manifest.PSObject.Properties.Name -contains 'memory_mode') { [string]$manifest.memory_mode } else { $null }
$effectiveMemoryMode = if (-not [string]::IsNullOrWhiteSpace($manifestMemoryMode)) { $manifestMemoryMode } else { $profileMemoryMode }
if ($effectiveMemoryMode -notin @('curated', 'private-episodic', 'off')) { Add-Fail "MEMORY_MODE_MANIFEST_INVALID: unsupported or missing mode '$effectiveMemoryMode'." }
elseif (-not [string]::IsNullOrWhiteSpace($profileMemoryMode) -and $profileMemoryMode -ne $effectiveMemoryMode) { Add-Fail "MEMORY_MODE_MISMATCH: profile '$profileMemoryMode' differs from manifest '$effectiveMemoryMode'." }
else { Add-Ok "memory mode: $effectiveMemoryMode" }

if ($null -ne $manifest -and $manifestSchema -ge 3 -and $manifestSchema -le 4) {
  try { $null = Get-LizardArtifactMap -Manifest $manifest -RequireLifecycle:($manifestSchema -ge 4) }
  catch { Add-Fail $_.Exception.Message }
  foreach ($artifact in @($manifest.artifacts)) {
    $relative = ConvertTo-LizardArtifactPath ([string]$artifact.path)
    try { $artifactPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relative.Replace('/', '\')) }
    catch { Add-Fail "unsafe artifact path ${relative}: $($_.Exception.Message)"; continue }
    try { $lifecycle = Get-LizardArtifactLifecycle -Record $artifact }
    catch { Add-Fail $_.Exception.Message; continue }
    $pathExists = Test-Path -LiteralPath $artifactPath
    $artifactExists = if ([string]$artifact.kind -eq 'directory') { Test-Path -LiteralPath $artifactPath -PathType Container } else { Test-Path -LiteralPath $artifactPath -PathType Leaf }
    if ($lifecycle -in @('retired-missing', 'removed')) {
      if ($pathExists) { Add-Fail "artifact lifecycle expects absence but path exists: $relative ($lifecycle)" }
      continue
    }
    if ($lifecycle -eq 'retired-present') {
      if (-not $artifactExists) { Add-Fail "retired artifact is missing: $relative"; continue }
      if ([string]$artifact.kind -eq 'file') {
        if ([string]::IsNullOrWhiteSpace([string]$artifact.current_hash)) { Add-Fail "retired artifact has no current hash: $relative" }
        elseif ((Get-LizardSha256 $artifactPath) -ne [string]$artifact.current_hash) { Add-Fail "retired artifact changed after retirement: $relative" }
      }
      continue
    }
    if ([string]$artifact.kind -eq 'directory') {
      if (-not (Test-Path -LiteralPath $artifactPath -PathType Container)) { Add-Fail "artifact directory missing: $relative" }
      continue
    }
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) { Add-Fail "artifact file missing: $relative"; continue }
    if ([string]$artifact.ownership -in @('layer-owned', 'adopted')) {
      if ([string]::IsNullOrWhiteSpace([string]$artifact.installed_hash)) { Add-Fail "owned artifact has no installed hash: $relative" }
      else {
        $currentHash = Get-LizardSha256 $artifactPath
        if ($currentHash -ne [string]$artifact.installed_hash) { Add-Fail "artifact content modified: $relative" }
      }
    }
  }
}

$expectedFiles = New-Object System.Collections.Generic.List[string]
$expectedFiles.Add('.agent\.gitignore')
$expectedFiles.Add('.agent\protocols\permissions.md')
$expectedFiles.Add('.agent\protocols\project-context.md')
$expectedFiles.Add('.agent\protocols\secret-handling.md')
$expectedFiles.Add('.agent\routing\policy.json')
$expectedFiles.Add('.agent\skills\_index.md')
$expectedFiles.Add('.agent\skills\_manifest.jsonl')

if ($manifest) {
  if ($manifest.skills -contains 'staged-execution') {
    $expectedFiles.Add('.agent\protocols\staged-execution.md')
    $expectedFiles.Add('.agent\protocols\context-hygiene.md')
  }
  if ($manifest.skills -contains 'release') {
    $expectedFiles.Add('.agent\protocols\release-gates.md')
  }
  if ($manifest.harnesses -and $manifest.harnesses.Count -ge 2) {
    $expectedFiles.Add('.agent\protocols\handoff.md')
  }
}

foreach ($file in $expectedFiles) {
  Check-File $file -Required | Out-Null
}

$skillManifestPath = Join-Path $TargetRoot '.agent\skills\_manifest.jsonl'
if (Test-Path -LiteralPath $skillManifestPath -PathType Leaf) {
  try {
    $skillRecords = @{}
    $skillLines = @((Get-SafeContent -AuthorizedRoot $TargetRoot -Path $skillManifestPath -Raw -MaximumBytes 4194304) -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    foreach ($line in $skillLines) {
      $record = $line | ConvertFrom-Json
      $required = @('schema_version', 'name', 'version', 'status', 'source', 'metadata', 'metadata_sha256', 'dependencies', 'permissions')
      $names = @($record.PSObject.Properties.Name)
      foreach ($name in $required) { if ($names -notcontains $name) { throw "skill manifest record is missing '$name'." } }
      foreach ($name in $names) { if ($required -notcontains $name) { throw "skill manifest record contains unsupported '$name'." } }
      if ([int64]$record.schema_version -ne 1 -or [string]$record.status -ne 'active' -or $skillRecords.ContainsKey([string]$record.name)) { throw "skill manifest record '$($record.name)' has invalid schema, status, or duplicate name." }
      $package = Read-LizardSkillPackage -SkillsRoot (Join-Path $TargetRoot '.agent\skills') -Name ([string]$record.name) -LayerVersion ([string]$manifest.layer_version)
      if ([string]$record.version -ne [string]$package.metadata.version -or [string]$record.source -ne ".agent/skills/$($record.name)/SKILL.md" -or [string]$record.metadata -ne ".agent/skills/$($record.name)/skill.json") { throw "skill manifest record '$($record.name)' does not match its installed package." }
      $actualMetadataHash = (Get-FileHash -LiteralPath $package.metadata_path -Algorithm SHA256).Hash.ToLowerInvariant()
      if ([string]$record.metadata_sha256 -ne $actualMetadataHash) { throw "skill manifest metadata hash differs for '$($record.name)'." }
      $skillRecords[[string]$record.name] = [pscustomobject]@{ record = $record; package = $package }
    }
    foreach ($name in @($skillRecords.Keys)) {
      foreach ($dependency in @($skillRecords[$name].package.metadata.dependencies)) {
        if (-not $skillRecords.ContainsKey([string]$dependency.name)) {
          if ($dependency.optional) { continue }
          throw "installed skill '$name' requires missing skill '$($dependency.name)'."
        }
        if (-not (Test-LizardSkillVersionRequirement -Actual ([string]$skillRecords[[string]$dependency.name].package.metadata.version) -Requirement ([string]$dependency.version))) { throw "installed skill '$name' dependency '$($dependency.name)' has an incompatible version." }
      }
      foreach ($conflict in @($skillRecords[$name].package.metadata.conflicts)) { if ($skillRecords.ContainsKey([string]$conflict)) { throw "installed skill '$name' conflicts with '$conflict'." } }
    }
    Add-Ok "validated versioned skill manifest: $($skillRecords.Count) package(s)"
  } catch { Add-Fail "SKILL_MANIFEST_INVALID: $($_.Exception.Message)" }
}

$memoryRoot = Join-Path $TargetRoot '.agent\memory'
if ($effectiveMemoryMode -eq 'off') {
  if (Test-Path -LiteralPath $memoryRoot) { Add-Fail 'MEMORY_MODE_OFF_RESIDUE: .agent/memory exists while persistence is off.' }
  else { Add-Ok 'memory namespace absent for off mode' }
  if (Test-Path -LiteralPath (Join-Path $TargetRoot '.agent\protocols\memory-policy.md')) { Add-Fail 'MEMORY_MODE_OFF_RESIDUE: memory-policy.md remains installed.' }
  if ($null -ne $manifest) {
    foreach ($artifact in @($manifest.artifacts)) {
      $artifactPath = [string]$artifact.path
      if (($artifactPath -eq '.agent/memory' -or $artifactPath.StartsWith('.agent/memory/')) -and [string]$artifact.lifecycle -ne 'removed') {
        Add-Fail "MEMORY_MODE_OFF_RESIDUE: non-removed manifest artifact remains: $artifactPath"
      }
    }
  }
  $instructionPaths = New-Object 'System.Collections.Generic.HashSet[string]' (Get-LizardPathComparer)
  foreach ($relative in @('.agent/protocols/permissions.md', '.agent/protocols/project-context.md', '.agent/protocols/handoff.md', '.agent/protocols/context-hygiene.md')) { $null = $instructionPaths.Add($relative) }
  if ($null -ne $manifest) {
    foreach ($artifact in @($manifest.artifacts)) {
      $relative = ConvertTo-LizardArtifactPath ([string]$artifact.path)
      if ([string]$artifact.kind -eq 'file' -and [string]$artifact.lifecycle -eq 'active' -and ($artifact.adapter_id -or $relative.StartsWith('.agent/protocols/', [System.StringComparison]::OrdinalIgnoreCase))) { $null = $instructionPaths.Add($relative) }
    }
  }
  foreach ($relative in @($instructionPaths | Sort-Object)) {
    $path = Join-Path $TargetRoot $relative.Replace('/', '\')
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
    $content = Get-SafeContent -AuthorizedRoot $TargetRoot -Path $path -Raw
    if ($content -match '(?i)\.agent[/\\]memory|memory[/\\](?:personal|semantic|working|episodic)|working-memory') { Add-Fail "MEMORY_MODE_OFF_REFERENCE: $relative contains an operational memory path." }
  }
} elseif ($effectiveMemoryMode -in @('curated', 'private-episodic')) {
  foreach ($relative in @('personal\PREFERENCES.md', 'semantic\DECISIONS.md', 'semantic\LESSONS.md', 'working\WORKSPACE.md')) {
    Check-File ('.agent\memory\' + $relative) -Required | Out-Null
  }
  Check-File '.agent\protocols\memory-policy.md' -Required | Out-Null
  if ($effectiveMemoryMode -eq 'private-episodic') {
    Check-File '.agent\memory\episodic\EPISODES.md' -Required | Out-Null
    $ignorePath = Join-Path $TargetRoot '.agent\.gitignore'
    if ((Test-Path -LiteralPath $ignorePath -PathType Leaf) -and (Get-Content -LiteralPath $ignorePath -Raw) -notmatch '(?m)^memory/episodic/\*\*$') { Add-Fail 'MEMORY_MODE_PRIVATE_IGNORE_MISSING: episodic content is not ignored recursively.' }
  } elseif (Test-Path -LiteralPath (Join-Path $memoryRoot 'episodic')) {
    Add-Fail 'MEMORY_MODE_CURATED_RESIDUE: episodic content exists in curated mode.'
  }
}

$routingPolicy = $null
if ($null -ne $profile) {
  if ([string]::IsNullOrWhiteSpace([string]$profile.routingPolicy)) { Add-Fail 'project profile has no routingPolicy.' }
  else {
    $routingPolicyPath = Join-Path $TargetRoot '.agent\routing\policy.json'
    if (Test-Path -LiteralPath $routingPolicyPath -PathType Leaf) {
      try {
        $routingPolicy = Get-Content -LiteralPath $routingPolicyPath -Raw | ConvertFrom-Json
        if ([string]$routingPolicy.name -ne [string]$profile.routingPolicy) { Add-Fail "routing policy '$($routingPolicy.name)' does not match profile '$($profile.routingPolicy)'." }
        else { Add-Ok "routing policy loaded: $($routingPolicy.name)" }
        $regulatedPolicy = if ($routingPolicy.PSObject.Properties.Name -contains 'regulated_data') { $routingPolicy.regulated_data } else { $null }
        if (
          $null -eq $regulatedPolicy -or
          [string]$regulatedPolicy.default_decision -ne 'human-review' -or
          $regulatedPolicy.organization_approval_required -ne $true -or
          $regulatedPolicy.require_inventory_identity -ne $true -or
          $regulatedPolicy.approval_must_be_outside_target -ne $true
        ) {
          Add-Fail 'REGULATED_POLICY_INVALID: regulated data must default to human review and require external organization approval plus inventory identity.'
        } else {
          Add-Ok 'regulated-data policy defaults to human review with external organization approval required.'
        }
      } catch { Add-Fail "routing policy is invalid JSON: $($_.Exception.Message)" }
    }
  }
  $modelMode = if ($profile.PSObject.Properties.Name -contains 'modelMode') { [string]$profile.modelMode } else { 'inherit-current' }
  if ($modelMode -eq 'inherit-current') {
    Add-Ok 'model mode inherit-current: no model picker change is required.'
  } elseif ($modelMode -eq 'inventory-routing') {
    $inventoryRelative = if ($profile.PSObject.Properties.Name -contains 'modelInventory' -and -not [string]::IsNullOrWhiteSpace([string]$profile.modelInventory)) { [string]$profile.modelInventory } else { '.agent/routing/inventory.json' }
    $runtimeRelative = if ($profile.PSObject.Properties.Name -contains 'modelRuntime' -and -not [string]::IsNullOrWhiteSpace([string]$profile.modelRuntime)) { [string]$profile.modelRuntime } else { '.agent/routing/runtime.json' }
    try {
      $inventoryPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $inventoryRelative.Replace('/', '\'))
      $runtimePath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $runtimeRelative.Replace('/', '\'))
      if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) { throw "inventory-routing requires $inventoryRelative." }
      if (-not (Test-Path -LiteralPath $runtimePath -PathType Leaf)) { throw "inventory-routing requires $runtimeRelative." }
      $runtime = Get-Content -LiteralPath $runtimePath -Raw | ConvertFrom-Json
      if ([string]$runtime.status -ne 'ready') { Add-Fail 'routing runtime status is not ready.' }
      if ([string]$runtime.selection -notin @('subagent', 'per-call')) { Add-Fail 'routing runtime lacks automatic selection.' }
      if ($runtime.actual_model_reporting -ne $true) { Add-Fail 'routing runtime cannot report actual model identity.' }
      if ([string]$runtime.attestation -notin @('observed', 'attested')) { Add-Fail 'routing runtime attestation is insufficient.' }
      if ([string]::IsNullOrWhiteSpace([string]$runtime.configuration_fingerprint)) { Add-Fail 'routing runtime configuration fingerprint is missing.' }
      if ([DateTimeOffset]::Parse([string]$runtime.expires_at) -le [DateTimeOffset]::UtcNow) { Add-Fail 'routing runtime capability evidence has expired.' }
      $missingHarnesses = @($harnesses | Where-Object { @($runtime.harnesses) -notcontains $_ })
      if ($missingHarnesses.Count -gt 0) { Add-Fail "routing runtime does not cover installed harnesses: $($missingHarnesses -join ', ')." }
      else { Add-Ok "automatic runtime $($runtime.executor_id): $($runtime.selection), harnesses $($harnesses -join ', ')" }

      $inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
      $duplicateIds = @($inventory.models | Group-Object { [string]$_.id } | Where-Object { $_.Count -gt 1 })
      if ($duplicateIds.Count -gt 0) { Add-Fail "model inventory contains duplicate id '$([string]$duplicateIds[0].Name)'." }
      $eligible = @($inventory.models | Where-Object {
        $_.available -eq $true -and $_.approved -eq $true -and [string]$_.evidence.state -eq 'calibrated' -and
        [string]$_.evidence.configuration_fingerprint -eq [string]$runtime.configuration_fingerprint -and
        $_.evidence.expires_at -and ([DateTimeOffset]::Parse([string]$_.evidence.expires_at) -gt [DateTimeOffset]::UtcNow)
      })
      if ($eligible.Count -eq 0) { Add-Fail 'model inventory has no available, approved, non-expired calibrated model matching the runtime fingerprint.' }
      else { Add-Ok "eligible calibrated inventory models: $($eligible.Count)" }

      if ($null -ne $routingPolicy) {
        foreach ($route in @($routingPolicy.routes)) {
          $missingDataClasses = New-Object System.Collections.Generic.List[string]
          foreach ($routeDataClass in @($route.data_classes)) {
            $covered = $false
            foreach ($role in @($route.candidate_roles) + @($route.fallback_roles)) {
              foreach ($candidate in @($eligible)) {
                if (@($candidate.allowed_data_classes) -notcontains [string]$routeDataClass) { continue }
                if (-not (Test-ContainsAll -Available @($candidate.capabilities) -Required @($route.required_capabilities))) { continue }
                if ((Get-CostRank ([string]$candidate.cost_tier)) -gt (Get-CostRank ([string]$route.max_cost_tier))) { continue }
                if ((Get-RoleScore -Model $candidate -Role ([string]$role)) -lt [double]$routingPolicy.model_selection.minimum_role_score) { continue }
                $covered = $true
                break
              }
              if ($covered) { break }
            }
            if (-not $covered) { $missingDataClasses.Add([string]$routeDataClass) | Out-Null }
          }
          if ($missingDataClasses.Count -gt 0) { Add-Fail "route readiness $($route.id) missing data classes: $($missingDataClasses -join ', ')." }
          else { Add-Ok "route readiness: $($route.id)" }
        }
      }
    } catch { Add-Fail "inventory routing readiness is invalid: $($_.Exception.Message)" }
  } else {
    Add-Fail "unsupported modelMode '$modelMode'."
  }
  $boundModelProfiles = if ($profile.PSObject.Properties.Name -contains 'modelProfiles' -and $null -ne $profile.modelProfiles) { @($profile.modelProfiles.PSObject.Properties | ForEach-Object { [string]$_.Value } | Sort-Object -Unique) } else { @() }
  if ($boundModelProfiles.Count -gt 0) { Add-Ok 'legacy modelProfiles bindings are readable but deprecated; migrate to modelInventory and modelRuntime.' }
  foreach ($modelProfile in $boundModelProfiles) {
    Check-File ".agent\routing\models\$modelProfile.json" -Required | Out-Null
  }
  $activeSkills = if ($null -ne $manifest -and $manifestSchema -ge 4) { @($manifest.skills) } else { @($profile.skills) }
  foreach ($skill in $activeSkills) {
    Check-File ".agent\skills\$skill\SKILL.md" -Required | Out-Null
  }
  $skillsLocalDir = Join-Path $TargetRoot '.agent\skills-local'
  if (Test-Path -LiteralPath $skillsLocalDir -PathType Container) {
    $localSkillDirs = @(Get-ChildItem -LiteralPath $skillsLocalDir -Directory -ErrorAction SilentlyContinue)
    foreach ($localDir in $localSkillDirs) {
      $localSkillFile = Join-Path $localDir.FullName 'SKILL.md'
      if (Test-Path -LiteralPath $localSkillFile -PathType Leaf) {
        Add-Ok "target-owned local skill '$($localDir.Name)' present (user-managed, not hash-bound to catalog)"
      }
    }
  }
}

foreach ($harness in $harnesses) {
  $layerAdapterPath = Join-Path $LayerRoot "adapters\$harness\adapter.json"
  if (-not (Test-Path -LiteralPath $layerAdapterPath)) {
    Add-Warn "Adapter '$harness' is installed in manifest/profile, but this doctor cannot find its local adapter manifest."
    continue
  }
  $adapter = Get-Content -LiteralPath $layerAdapterPath -Raw | ConvertFrom-Json
  $dst = Normalize-RelPath $adapter.instruction.dst
  $sidecar = if ($adapter.instruction.sidecar) { Normalize-RelPath $adapter.instruction.sidecar } else { "$dst.lizard-agent-layer" }
  $dstPath = Join-Path $TargetRoot $dst
  $sidecarPath = Join-Path $TargetRoot $sidecar
  if ($manifestSchema -ge 3 -and $manifestSchema -le 4) {
    $effectiveAdapter = [string]$harness
    $alias = @($manifest.adapter_aliases | Where-Object { [string]$_.adapter -eq [string]$harness } | Select-Object -First 1)
    if ($alias.Count -gt 0) { $effectiveAdapter = [string]$alias[0].satisfied_by }
    $identityArtifacts = @($manifest.artifacts | Where-Object { (Get-LizardArtifactLifecycle -Record $_) -eq 'active' -and [string]$_.adapter_id -eq $effectiveAdapter -and [string]$_.mirror_group -like 'adapter-instruction:*' })
    $identityValid = $false
    foreach ($identity in $identityArtifacts) {
      $identityPath = Join-Path $TargetRoot ([string]$identity.path).Replace('/', '\')
      if ((Test-Path -LiteralPath $identityPath -PathType Leaf) -and (Get-LizardSha256 $identityPath) -eq [string]$identity.source_hash) { $identityValid = $true; break }
    }
    if ($identityValid) {
      if ($effectiveAdapter -eq [string]$harness) { Add-Ok "$harness exact adapter identity verified" }
      else { Add-Ok "$harness satisfied by compatible adapter $effectiveAdapter" }
    } else { Add-Fail "$harness exact adapter identity is missing or modified" }
  } elseif (Test-Path -LiteralPath $dstPath) {
    $content = Get-Content -LiteralPath $dstPath -Raw
    if ($content -match 'lizard-agent-layer') { Add-Ok "$harness instruction wired at $dst" }
    elseif (Test-Path -LiteralPath $sidecarPath) { Add-Warn "$harness instruction $dst exists but is not wired; sidecar $sidecar exists." }
    else { Add-Warn "$harness instruction $dst exists but is not wired and no sidecar exists." }
  } elseif (Test-Path -LiteralPath $sidecarPath) {
    Add-Warn "$harness has only sidecar $sidecar; merge intentionally."
  } else {
    Add-Fail "$harness instruction missing: $dst"
  }

  foreach ($mirror in @($adapter.skillMirrors)) {
    $mirrorRel = Normalize-RelPath $mirror.dst
    Check-File $mirrorRel -Required | Out-Null
    if ($null -ne $profile) {
      $activeMirrorSkills = if ($null -ne $manifest -and $manifestSchema -ge 4) { @($manifest.skills) } else { @($profile.skills) }
      foreach ($skill in $activeMirrorSkills) {
        Check-File "$mirrorRel\$skill\SKILL.md" -Required | Out-Null
      }
    }
  }
}

foreach ($line in $Ok) { Write-Host "  OK   $line" }
foreach ($line in $Warnings) { Write-Host "  WARN $line" }
foreach ($line in $Failures) { Write-Host "  FAIL $line" }

if ($Failures.Count -gt 0 -or ($Strict -and $Warnings.Count -gt 0)) { exit 1 }
Write-Host "Doctor completed. Failures=$($Failures.Count) Warnings=$($Warnings.Count)"
