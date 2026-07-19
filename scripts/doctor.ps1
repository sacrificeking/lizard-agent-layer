param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Manifest.psm1') -Force
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
    if ($manifestSchema -gt 3) { Add-Fail "install manifest schema $manifestSchema is newer than supported schema 3." }
    elseif ($manifestSchema -lt 3) { Add-Warn "install manifest schema $manifestSchema has unknown content integrity; migrate to schema 3." }
    else { Add-Ok "install manifest loaded: $($manifest.layer_version), schema 3" }
  }
  catch { Add-Fail "install manifest is invalid JSON: $($_.Exception.Message)" }
} else {
  Add-Warn '.agent\lizard-agent-layer.install.json missing; target may be preview-only or pre-manifest install.'
}

if ($null -ne $manifest -and $manifest.harnesses) { $harnesses = @($manifest.harnesses) }
elseif ($null -ne $profile -and $profile.harnesses) { $harnesses = @($profile.harnesses) }

if ($null -ne $manifest -and $manifestSchema -eq 3) {
  try { $null = Get-LizardArtifactMap -Manifest $manifest }
  catch { Add-Fail $_.Exception.Message }
  foreach ($artifact in @($manifest.artifacts)) {
    $relative = ConvertTo-LizardArtifactPath ([string]$artifact.path)
    try { $artifactPath = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot $relative.Replace('/', '\')) }
    catch { Add-Fail "unsafe artifact path ${relative}: $($_.Exception.Message)"; continue }
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

foreach ($file in @(
  '.agent\.gitignore',
  '.agent\memory\personal\PREFERENCES.md',
  '.agent\memory\semantic\DECISIONS.md',
  '.agent\memory\semantic\LESSONS.md',
  '.agent\memory\working\WORKSPACE.md',
  '.agent\protocols\permissions.md',
  '.agent\protocols\memory-policy.md',
  '.agent\protocols\secret-handling.md',
  '.agent\protocols\release-gates.md',
  '.agent\protocols\handoff.md',
  '.agent\protocols\staged-execution.md',
  '.agent\protocols\context-hygiene.md',
  '.agent\routing\policy.json',
  '.agent\skills\_index.md',
  '.agent\skills\_manifest.jsonl'
)) {
  Check-File $file -Required | Out-Null
}

if ($null -ne $profile) {
  if ([string]::IsNullOrWhiteSpace([string]$profile.routingPolicy)) { Add-Fail 'project profile has no routingPolicy.' }
  else {
    $routingPolicyPath = Join-Path $TargetRoot '.agent\routing\policy.json'
    if (Test-Path -LiteralPath $routingPolicyPath -PathType Leaf) {
      try {
        $routingPolicy = Get-Content -LiteralPath $routingPolicyPath -Raw | ConvertFrom-Json
        if ([string]$routingPolicy.name -ne [string]$profile.routingPolicy) { Add-Fail "routing policy '$($routingPolicy.name)' does not match profile '$($profile.routingPolicy)'." }
        else { Add-Ok "routing policy loaded: $($routingPolicy.name)" }
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
  foreach ($skill in @($profile.skills)) {
    Check-File ".agent\skills\$skill\SKILL.md" -Required | Out-Null
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
  if ($manifestSchema -eq 3) {
    $effectiveAdapter = [string]$harness
    $alias = @($manifest.adapter_aliases | Where-Object { [string]$_.adapter -eq [string]$harness } | Select-Object -First 1)
    if ($alias.Count -gt 0) { $effectiveAdapter = [string]$alias[0].satisfied_by }
    $identityArtifacts = @($manifest.artifacts | Where-Object { [string]$_.adapter_id -eq $effectiveAdapter -and [string]$_.mirror_group -like 'adapter-instruction:*' })
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
      foreach ($skill in @($profile.skills)) {
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
