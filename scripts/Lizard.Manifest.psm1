Set-StrictMode -Version 2.0

function ConvertTo-LizardArtifactPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return $Path.Replace('\', '/').TrimStart('/')
}

function Get-LizardSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-LizardStringSha256 {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) { $Value = '' }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Value)
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Get-LizardArtifactMap {
  param($Manifest)
  $comparer = if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix') { [System.StringComparer]::Ordinal } else { [System.StringComparer]::OrdinalIgnoreCase }
  $map = New-Object 'System.Collections.Generic.Dictionary[string,object]' $comparer
  if ($null -eq $Manifest -or -not ($Manifest.PSObject.Properties.Name -contains 'artifacts')) { return $map }
  foreach ($artifact in @($Manifest.artifacts)) {
    if ($null -eq $artifact -or [string]::IsNullOrWhiteSpace([string]$artifact.path)) { continue }
    $key = ConvertTo-LizardArtifactPath ([string]$artifact.path)
    if ($map.ContainsKey($key)) { throw "MANIFEST_DUPLICATE_ARTIFACT: $key" }
    $map.Add($key, $artifact)
  }
  return $map
}

function Get-LizardArtifactState {
  param(
    $Record,
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [AllowNull()][string]$ExpectedSourceHash,
    [ValidateSet('file', 'directory')][string]$Kind = 'file'
  )

  $exists = if ($Kind -eq 'directory') { Test-Path -LiteralPath $TargetPath -PathType Container } else { Test-Path -LiteralPath $TargetPath -PathType Leaf }
  if (-not $exists) { return 'missing' }
  if ($null -eq $Record) { return 'user-owned' }

  $ownership = [string]$Record.ownership
  if ($ownership -eq 'user-owned') { return 'user-owned' }
  if ($ownership -eq 'adopted') {
    if ($Kind -eq 'file' -and $Record.installed_hash -and (Get-LizardSha256 $TargetPath) -ne [string]$Record.installed_hash) { return 'locally-modified' }
    return 'adopted'
  }
  if ($ownership -ne 'layer-owned') { return 'conflict' }
  if ($Kind -eq 'directory') { return 'layer-owned' }
  if ([string]::IsNullOrWhiteSpace([string]$Record.installed_hash)) { return 'integrity-unknown' }

  $currentHash = Get-LizardSha256 $TargetPath
  if ($currentHash -ne [string]$Record.installed_hash) { return 'locally-modified' }
  if ($ExpectedSourceHash -and $Record.source_hash -and $ExpectedSourceHash -ne [string]$Record.source_hash) { return 'stale-unmodified' }
  return 'layer-owned'
}

function New-LizardArtifactRecord {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('file', 'directory')][string]$Kind,
    [ValidateSet('layer-owned', 'user-owned', 'adopted')][string]$Ownership,
    [Parameter(Mandatory = $true)][string]$State,
    [AllowNull()][string]$SourcePath,
    [AllowNull()][string]$SourceVersion,
    [AllowNull()][string]$SourceHash,
    [AllowNull()][string]$InstalledHash,
    [AllowNull()][string]$CurrentHash,
    [AllowNull()][string]$AdapterId,
    [string[]]$AdapterAliases = @(),
    [AllowNull()][string]$MirrorGroup
  )

  return [pscustomobject][ordered]@{
    path = ConvertTo-LizardArtifactPath $Path
    kind = $Kind
    ownership = $Ownership
    state = $State
    source_path = if ([string]::IsNullOrWhiteSpace($SourcePath)) { $null } else { $SourcePath }
    source_version = if ([string]::IsNullOrWhiteSpace($SourceVersion)) { $null } else { $SourceVersion }
    source_hash = if ([string]::IsNullOrWhiteSpace($SourceHash)) { $null } else { $SourceHash }
    installed_hash = if ([string]::IsNullOrWhiteSpace($InstalledHash)) { $null } else { $InstalledHash }
    current_hash = if ([string]::IsNullOrWhiteSpace($CurrentHash)) { $null } else { $CurrentHash }
    adapter_id = if ([string]::IsNullOrWhiteSpace($AdapterId)) { $null } else { $AdapterId }
    adapter_aliases = @($AdapterAliases)
    mirror_group = if ([string]::IsNullOrWhiteSpace($MirrorGroup)) { $null } else { $MirrorGroup }
  }
}

function Test-LizardArtifactPathsOverlap {
  param([string]$Left, [string]$Right)
  $a = (ConvertTo-LizardArtifactPath $Left).TrimEnd('/').ToLowerInvariant()
  $b = (ConvertTo-LizardArtifactPath $Right).TrimEnd('/').ToLowerInvariant()
  if ($a -eq $b) { return $true }
  return $a.StartsWith($b + '/', [System.StringComparison]::Ordinal) -or $b.StartsWith($a + '/', [System.StringComparison]::Ordinal)
}

function Resolve-LizardAdapterComposition {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][object[]]$Adapters)

  $instructionByPath = @{}
  $mirrors = New-Object System.Collections.Generic.List[object]
  $aliases = New-Object System.Collections.Generic.List[object]

  foreach ($entry in @($Adapters)) {
    $name = [string]$entry.name
    $manifest = $entry.manifest
    $destination = ConvertTo-LizardArtifactPath ([string]$manifest.instruction.dst)
    $hasCompatibility = $manifest.PSObject.Properties.Name -contains 'compatibility' -and $null -ne $manifest.compatibility
    $group = if ($hasCompatibility -and $manifest.compatibility.PSObject.Properties.Name -contains 'instructionGroup') { [string]$manifest.compatibility.instructionGroup } else { $null }
    $precedence = if ($hasCompatibility -and $manifest.compatibility.PSObject.Properties.Name -contains 'precedence') { [int]$manifest.compatibility.precedence } else { 0 }
    $candidate = [pscustomobject]@{
      name = $name
      manifest = $manifest
      adapter_dir = [string]$entry.adapter_dir
      destination = $destination
      compatibility_group = $group
      precedence = $precedence
      aliases = New-Object System.Collections.Generic.List[string]
    }

    $key = $destination.ToLowerInvariant()
    foreach ($existingInstruction in @($instructionByPath.Values)) {
      if ([string]$existingInstruction.destination -ne $destination -and (Test-LizardArtifactPathsOverlap -Left $destination -Right ([string]$existingInstruction.destination))) {
        throw "ADAPTER_DESTINATION_OVERLAP: '$name' instruction '$destination' overlaps '$($existingInstruction.name)' instruction '$($existingInstruction.destination)'."
      }
    }
    foreach ($existingMirror in @($mirrors.ToArray())) {
      if (Test-LizardArtifactPathsOverlap -Left $destination -Right ([string]$existingMirror.destination)) {
        throw "ADAPTER_DESTINATION_OVERLAP: '$name' instruction '$destination' overlaps '$($existingMirror.name)' mirror '$($existingMirror.destination)'."
      }
    }
    if (-not $instructionByPath.ContainsKey($key)) {
      $instructionByPath[$key] = $candidate
    } else {
      $current = $instructionByPath[$key]
      if ([string]::IsNullOrWhiteSpace($group) -or [string]::IsNullOrWhiteSpace([string]$current.compatibility_group) -or $group -ne [string]$current.compatibility_group) {
        throw "ADAPTER_DESTINATION_CONFLICT: '$name' and '$($current.name)' both target '$destination' without a shared compatibility group."
      }
      if ($precedence -eq [int]$current.precedence) {
        throw "ADAPTER_PRECEDENCE_CONFLICT: '$name' and '$($current.name)' both target '$destination' with precedence $precedence."
      }
      if ($precedence -gt [int]$current.precedence) {
        $candidate.aliases.Add([string]$current.name) | Out-Null
        foreach ($alias in @($current.aliases.ToArray())) { if (-not $candidate.aliases.Contains($alias)) { $candidate.aliases.Add($alias) | Out-Null } }
        $instructionByPath[$key] = $candidate
        $aliases.Add([pscustomobject][ordered]@{ adapter = [string]$current.name; satisfied_by = $name; destination = $destination }) | Out-Null
      } else {
        $current.aliases.Add($name) | Out-Null
        $aliases.Add([pscustomobject][ordered]@{ adapter = $name; satisfied_by = [string]$current.name; destination = $destination }) | Out-Null
      }
    }

    foreach ($mirror in @($manifest.skillMirrors)) {
      $mirrorDestination = ConvertTo-LizardArtifactPath ([string]$mirror.dst)
      foreach ($existingInstruction in @($instructionByPath.Values)) {
        if (Test-LizardArtifactPathsOverlap -Left $mirrorDestination -Right ([string]$existingInstruction.destination)) {
          throw "ADAPTER_DESTINATION_OVERLAP: '$name' mirror '$mirrorDestination' overlaps '$($existingInstruction.name)' instruction '$($existingInstruction.destination)'."
        }
      }
      foreach ($existing in @($mirrors.ToArray())) {
        if (Test-LizardArtifactPathsOverlap -Left $mirrorDestination -Right ([string]$existing.destination)) {
          throw "ADAPTER_MIRROR_CONFLICT: '$name' mirror '$mirrorDestination' overlaps '$($existing.name)' mirror '$($existing.destination)'."
        }
      }
      $mirrors.Add([pscustomobject]@{ name = $name; destination = $mirrorDestination; manifest = $manifest; adapter_dir = [string]$entry.adapter_dir }) | Out-Null
    }
  }

  return [pscustomobject]@{
    effective_instructions = @($instructionByPath.Values | Sort-Object destination)
    mirrors = @($mirrors.ToArray())
    aliases = @($aliases.ToArray())
  }
}

Export-ModuleMember -Function @(
  'Get-LizardArtifactMap', 'Get-LizardArtifactState', 'Get-LizardSha256',
  'ConvertTo-LizardArtifactPath', 'Get-LizardStringSha256', 'New-LizardArtifactRecord',
  'Resolve-LizardAdapterComposition', 'Test-LizardArtifactPathsOverlap'
)
