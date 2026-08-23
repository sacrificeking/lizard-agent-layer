Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')

function New-LizardSkillPackageException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['skill_package_code'] = $Code
  return $exception
}

function Assert-LizardSkillObject {
  param($Value, [string[]]$Required, [string[]]$Allowed, [string]$Label)
  if ($null -eq $Value -or $Value -isnot [System.Management.Automation.PSCustomObject]) {
    throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' "$Label must be a JSON object.")
  }
  $names = @($Value.PSObject.Properties.Name)
  foreach ($name in $Required) {
    if ($names -notcontains $name) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' "$Label is missing '$name'.") }
  }
  foreach ($name in $names) {
    if ($Allowed -notcontains $name) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' "$Label contains unsupported property '$name'.") }
  }
}

function Test-LizardSkillName {
  param($Value)
  return ($Value -is [string] -and [string]$Value -match '^[a-z0-9][a-z0-9-]{0,62}$')
}

function ConvertTo-LizardSkillVersion {
  param($Value, [string]$Label = 'version')
  if ($Value -isnot [string] -or [string]$Value -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw (New-LizardSkillPackageException 'SKILL_PACKAGE_VERSION_INVALID' "$Label must be a stable semantic version.")
  }
  return [version]([string]$Value)
}

function Test-LizardSkillVersionRequirement {
  param([string]$Actual, [string]$Requirement)
  $actualVersion = ConvertTo-LizardSkillVersion $Actual 'Actual dependency version'
  $minimum = $Requirement.StartsWith('>=')
  $requiredText = if ($minimum) { $Requirement.Substring(2) } else { $Requirement }
  $requiredVersion = ConvertTo-LizardSkillVersion $requiredText 'Dependency requirement'
  if ($minimum) { return $actualVersion -ge $requiredVersion }
  return $actualVersion -eq $requiredVersion
}

function Assert-LizardSkillStringArray {
  param($Value, [string]$Label, [string[]]$Allowed = @(), [switch]$Names, [switch]$AllowEmpty)
  if ($Value -isnot [System.Array]) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' "$Label must be a JSON array.") }
  if (-not $AllowEmpty -and @($Value).Count -eq 0) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' "$Label must not be empty.") }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($item in @($Value)) {
    if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$item)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' "$Label contains a non-string or empty item.") }
    if ($Names -and -not (Test-LizardSkillName $item)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_NAME_INVALID' "$Label contains invalid name '$item'.") }
    if ($Allowed.Count -gt 0 -and $Allowed -notcontains [string]$item) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_VALUE_INVALID' "$Label contains unsupported value '$item'.") }
    if (-not $seen.Add([string]$item)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DUPLICATE' "$Label contains duplicate '$item'.") }
  }
}

function Assert-LizardSkillPackageDocument {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)]$Document, [string]$ExpectedName, [string]$LayerVersion)

  $rootFields = @('schema_version', 'name', 'version', 'lifecycle_state', 'compatibility', 'dependencies', 'permissions', 'provenance', 'conflicts', 'migration', 'disablement', 'recovery', 'removal')
  Assert-LizardSkillObject $Document $rootFields $rootFields 'Skill package'
  if ($Document.schema_version -isnot [byte] -and $Document.schema_version -isnot [int16] -and $Document.schema_version -isnot [int32] -and $Document.schema_version -isnot [int64]) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SCHEMA_UNSUPPORTED' 'schema_version must be integer 1.') }
  if ([int64]$Document.schema_version -ne 1) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SCHEMA_UNSUPPORTED' 'schema_version must be integer 1.') }
  if (-not (Test-LizardSkillName $Document.name)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_NAME_INVALID' 'Package name is invalid.') }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedName) -and [string]$Document.name -ne $ExpectedName) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_NAME_MISMATCH' "Package '$($Document.name)' does not match folder '$ExpectedName'.") }
  $null = ConvertTo-LizardSkillVersion $Document.version
  if ($Document.lifecycle_state -isnot [string] -or [string]$Document.lifecycle_state -ne 'active') { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_STATE_INVALID' 'Source lifecycle_state must be active.') }

  Assert-LizardSkillObject $Document.compatibility @('minimum_layer_version', 'hosts', 'harnesses') @('minimum_layer_version', 'hosts', 'harnesses') 'compatibility'
  $minimumLayer = ConvertTo-LizardSkillVersion $Document.compatibility.minimum_layer_version 'minimum_layer_version'
  if (-not [string]::IsNullOrWhiteSpace($LayerVersion) -and (ConvertTo-LizardSkillVersion $LayerVersion 'Layer version') -lt $minimumLayer) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_LAYER_INCOMPATIBLE' "Package requires layer $minimumLayer or newer.") }
  Assert-LizardSkillStringArray $Document.compatibility.hosts 'compatibility.hosts' @('windows-powershell-5.1', 'windows-powershell-7', 'linux-powershell-7', 'macos-powershell-7')
  Assert-LizardSkillStringArray $Document.compatibility.harnesses 'compatibility.harnesses' -Names

  if ($Document.dependencies -isnot [System.Array]) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_SHAPE_INVALID' 'dependencies must be a JSON array.') }
  $dependencyNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($dependency in @($Document.dependencies)) {
    Assert-LizardSkillObject $dependency @('name', 'version', 'optional') @('name', 'version', 'optional') 'dependency'
    if (-not (Test-LizardSkillName $dependency.name) -or [string]$dependency.name -eq [string]$Document.name) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DEPENDENCY_INVALID' 'Dependency name is invalid or self-referential.') }
    if (-not $dependencyNames.Add([string]$dependency.name)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DUPLICATE' "Duplicate dependency '$($dependency.name)'.") }
    if ($dependency.version -isnot [string] -or [string]$dependency.version -notmatch '^(?:>=)?(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$') { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DEPENDENCY_INVALID' "Dependency '$($dependency.name)' has invalid version requirement.") }
    if ($dependency.optional -isnot [bool]) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DEPENDENCY_INVALID' "Dependency '$($dependency.name)' optional must be boolean.") }
  }

  Assert-LizardSkillObject $Document.permissions @('filesystem', 'network', 'process', 'secrets') @('filesystem', 'network', 'process', 'secrets') 'permissions'
  $permissionSets = @{
    filesystem = @('denied', 'read-only', 'workspace-scoped', 'approval-required'); network = @('denied', 'approval-required')
    process = @('denied', 'bounded', 'approval-required'); secrets = @('denied', 'approval-required')
  }
  foreach ($name in @('filesystem', 'network', 'process', 'secrets')) {
    if ($Document.permissions.$name -isnot [string] -or $permissionSets[$name] -notcontains [string]$Document.permissions.$name) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_PERMISSION_INVALID' "Permission '$name' is invalid.") }
  }

  Assert-LizardSkillObject $Document.provenance @('owner', 'source_path', 'reviewed_at', 'review_record') @('owner', 'source_path', 'reviewed_at', 'review_record') 'provenance'
  if ([string]::IsNullOrWhiteSpace([string]$Document.provenance.owner) -or [string]::IsNullOrWhiteSpace([string]$Document.provenance.review_record)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_PROVENANCE_INVALID' 'Provenance owner and review_record are required.') }
  if ([string]$Document.provenance.source_path -ne "skills/$($Document.name)") { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_PROVENANCE_INVALID' 'Provenance source_path must match the package folder.') }
  $reviewed = [DateTime]::MinValue
  if ($Document.provenance.reviewed_at -isnot [string] -or -not [DateTime]::TryParseExact([string]$Document.provenance.reviewed_at, 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$reviewed)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_PROVENANCE_INVALID' 'reviewed_at must be an ISO date.') }

  Assert-LizardSkillStringArray $Document.conflicts 'conflicts' -Names -AllowEmpty
  if (@($Document.conflicts) -contains [string]$Document.name) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_CONFLICT_INVALID' 'A package cannot conflict with itself.') }
  foreach ($conflict in @($Document.conflicts)) { if ($dependencyNames.Contains([string]$conflict)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_CONFLICT_INVALID' "'$conflict' cannot be both dependency and conflict.") } }

  Assert-LizardSkillObject $Document.migration @('from_versions', 'strategy') @('from_versions', 'strategy') 'migration'
  Assert-LizardSkillStringArray $Document.migration.from_versions 'migration.from_versions' -AllowEmpty
  foreach ($version in @($Document.migration.from_versions)) { $null = ConvertTo-LizardSkillVersion $version 'migration.from_versions item' }
  if ([string]$Document.migration.strategy -ne 'replace-unchanged-managed-files') { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_LIFECYCLE_INVALID' 'Migration strategy is unsupported.') }
  Assert-LizardSkillObject $Document.disablement @('strategy', 'preserve_user_content') @('strategy', 'preserve_user_content') 'disablement'
  if ([string]$Document.disablement.strategy -ne 'remove-unchanged-managed-files' -or $Document.disablement.preserve_user_content -ne $true) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_LIFECYCLE_INVALID' 'Disablement must remove only unchanged managed files and preserve user content.') }
  Assert-LizardSkillObject $Document.recovery @('strategy', 'verification') @('strategy', 'verification') 'recovery'
  if ([string]$Document.recovery.strategy -ne 'reinstall-exact-reviewed-package' -or [string]$Document.recovery.verification -ne 'sha256') { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_LIFECYCLE_INVALID' 'Recovery contract is unsupported.') }
  Assert-LizardSkillObject $Document.removal @('strategy', 'ownership') @('strategy', 'ownership') 'removal'
  if ([string]$Document.removal.strategy -ne 'remove-unchanged-managed-files' -or [string]$Document.removal.ownership -ne 'layer-owned-only') { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_LIFECYCLE_INVALID' 'Removal contract is unsupported.') }
  return $Document
}

function Read-LizardSkillPackage {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$SkillsRoot, [Parameter(Mandatory = $true)][string]$Name, [string]$LayerVersion)
  if (-not (Test-LizardSkillName $Name)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_NAME_INVALID' "Invalid skill name '$Name'.") }
  $root = Resolve-SafeRoot -Path $SkillsRoot -RequireExisting
  $packageRoot = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $root $Name)
  if (-not (Test-Path -LiteralPath $packageRoot -PathType Container)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_MISSING' "Skill package '$Name' is missing.") }
  $skillPath = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $packageRoot 'SKILL.md')
  $metadataPath = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath (Join-Path $packageRoot 'skill.json')
  if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_INSTRUCTIONS_MISSING' "Skill '$Name' is missing SKILL.md.") }
  if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_METADATA_MISSING' "Skill '$Name' is missing skill.json.") }
  try { $document = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $root -Path $metadataPath -Raw -MaximumBytes 1048576) }
  catch { if ($_.Exception.Data['skill_package_code']) { throw }; throw (New-LizardSkillPackageException 'SKILL_PACKAGE_JSON_INVALID' $_.Exception.Message) }
  $null = Assert-LizardSkillPackageDocument -Document $document -ExpectedName $Name -LayerVersion $LayerVersion
  return [pscustomobject]@{ root = $packageRoot; instructions_path = $skillPath; metadata_path = $metadataPath; metadata = $document }
}

function Assert-LizardSkillRepository {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$SkillsRoot, [Parameter(Mandatory = $true)][string]$LayerVersion)
  $root = Resolve-SafeRoot -Path $SkillsRoot -RequireExisting
  $packages = @{}
  foreach ($entry in @(Get-SafeDirectoryEntries -AuthorizedRoot $root -Path $root)) {
    if ($entry.kind -ne 'directory') { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_ROOT_INVALID' "Unexpected file '$($entry.name)' in skills root.") }
    $package = Read-LizardSkillPackage -SkillsRoot $root -Name $entry.name -LayerVersion $LayerVersion
    $packages[$entry.name] = $package
  }
  foreach ($name in @($packages.Keys)) {
    $metadata = $packages[$name].metadata
    foreach ($dependency in @($metadata.dependencies)) {
      if (-not $packages.ContainsKey([string]$dependency.name)) {
        if ($dependency.optional) { continue }
        throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DEPENDENCY_MISSING' "'$name' requires missing package '$($dependency.name)'.")
      }
      if (-not (Test-LizardSkillVersionRequirement -Actual ([string]$packages[[string]$dependency.name].metadata.version) -Requirement ([string]$dependency.version))) { throw (New-LizardSkillPackageException 'SKILL_PACKAGE_DEPENDENCY_VERSION' "'$name' dependency '$($dependency.name)' does not satisfy '$($dependency.version)'.") }
    }
  }
  return @($packages.Values)
}

Export-ModuleMember -Function @(
  'Assert-LizardSkillPackageDocument',
  'Assert-LizardSkillRepository',
  'ConvertTo-LizardSkillVersion',
  'Read-LizardSkillPackage',
  'Test-LizardSkillVersionRequirement'
)
