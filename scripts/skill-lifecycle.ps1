[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$TargetRoot,
  [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9][a-z0-9-]{0,62}$')][string]$SkillName,
  [ValidateSet('Validate', 'Install', 'Update', 'Migrate', 'Disable', 'Recover', 'Remove')][string]$Action = 'Validate',
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$CanonicalPlanPath,
  [switch]$Apply,
  [string]$ApprovedPlanPath,
  [string]$ApprovedPlanSha256,
  [switch]$HumanApproved,
  [ValidateRange(1, 1440)][int]$PlanTtlMinutes = 30,
  [ValidateRange(0, 10000)][int]$FailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$TargetRoot = (Resolve-Path -LiteralPath $TargetRoot).Path

Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Json.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Plan.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Transaction.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SkillPackage.psm1') -Force

function New-SkillLifecycleException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['skill_lifecycle_code'] = $Code
  return $exception
}

function ConvertTo-RelativePath {
  param([string]$Root, [string]$Path)
  $relative = $Path.Substring($Root.TrimEnd([char[]]@('\', '/')).Length).TrimStart([char[]]@('\', '/'))
  return $relative.Replace('\', '/')
}

function Get-SkillTree {
  param([string]$AuthorizedRoot, [string]$PackageRoot)
  $authorized = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $candidate = ConvertTo-LizardFullPath -Path $PackageRoot
  if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { return [pscustomobject]@{ files = @(); directories = @() } }
  $root = if ($candidate.Equals($authorized, (Get-LizardPathComparison))) { $authorized } else { Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $candidate }
  $files = New-Object System.Collections.Generic.List[object]
  $directories = New-Object System.Collections.Generic.List[string]
  $queue = New-Object System.Collections.Generic.Queue[string]
  $queue.Enqueue($root)
  while ($queue.Count -gt 0) {
    $directory = $queue.Dequeue()
    foreach ($entry in @(Get-SafeDirectoryEntries -AuthorizedRoot $AuthorizedRoot -Path $directory)) {
      $relative = ConvertTo-RelativePath -Root $root -Path $entry.path
      if ($entry.kind -eq 'directory') {
        $directories.Add($relative) | Out-Null
        $queue.Enqueue([string]$entry.path)
      } else {
        $files.Add([pscustomobject][ordered]@{
          path = $relative
          full_path = [string]$entry.path
          sha256 = Get-SafeFileHash -AuthorizedRoot $authorized -Path $entry.path
        }) | Out-Null
      }
    }
  }
  $fileByPath = @{}
  $filePaths = [string[]]@($files.ToArray() | ForEach-Object { $fileByPath[[string]$_.path] = $_; [string]$_.path })
  [Array]::Sort($filePaths, [System.StringComparer]::Ordinal)
  $fileArray = [object[]]@($filePaths | ForEach-Object { $fileByPath[$_] })
  $directoryArray = @($directories.ToArray())
  [Array]::Sort($directoryArray, [System.StringComparer]::Ordinal)
  return [pscustomobject]@{ files = $fileArray; directories = $directoryArray }
}

function Assert-StateDocument {
  param($State, [string]$ExpectedName)
  $required = @('schema_version', 'name', 'version', 'status', 'files', 'directories', 'previous_version')
  if ($null -eq $State -or $State -isnot [System.Management.Automation.PSCustomObject]) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' 'State must be a JSON object.') }
  $names = @($State.PSObject.Properties.Name)
  foreach ($name in $required) { if ($names -notcontains $name) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' "State is missing '$name'.") } }
  foreach ($name in $names) { if ($required -notcontains $name) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' "State contains unsupported property '$name'.") } }
  if ([int64]$State.schema_version -ne 1 -or [string]$State.name -ne $ExpectedName -or [string]$State.status -notin @('active', 'disabled', 'removed')) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' 'State schema, name, or status is invalid.') }
  $null = ConvertTo-LizardSkillVersion ([string]$State.version) 'State version'
  if ($null -ne $State.previous_version) { $null = ConvertTo-LizardSkillVersion ([string]$State.previous_version) 'Previous state version' }
  if ($State.files -isnot [System.Array] -or $State.directories -isnot [System.Array]) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' 'State files and directories must be arrays.') }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($file in @($State.files)) {
    if ($file -isnot [System.Management.Automation.PSCustomObject] -or @($file.PSObject.Properties.Name).Count -ne 2 -or @($file.PSObject.Properties.Name) -notcontains 'path' -or @($file.PSObject.Properties.Name) -notcontains 'sha256') { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' 'State file record is invalid.') }
    if ([string]$file.path -notmatch '^(?!/)(?!.*(?:^|/)\.\.?(?:/|$))[^\\:\x00-\x1f]+$' -or [string]$file.sha256 -notmatch '^[a-f0-9]{64}$' -or -not $seen.Add([string]$file.path)) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' 'State file path or hash is invalid or duplicated.') }
  }
  foreach ($directory in @($State.directories)) {
    if ($directory -isnot [string] -or [string]$directory -notmatch '^(?!/)(?!.*(?:^|/)\.\.?(?:/|$))[^\\:\x00-\x1f]+$' -or -not $seen.Add("dir:$directory")) { throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' 'State directory is invalid or duplicated.') }
  }
  return $State
}

function Read-State {
  param([string]$Path, [switch]$Optional)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    if ($Optional) { return $null }
    throw (New-SkillLifecycleException 'SKILL_STATE_MISSING' "Lifecycle state is missing: $Path")
  }
  try { $state = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $Path -Raw -MaximumBytes 1048576) }
  catch { if ($_.Exception.Data['skill_lifecycle_code']) { throw }; throw (New-SkillLifecycleException 'SKILL_STATE_INVALID' $_.Exception.Message) }
  return Assert-StateDocument -State $state -ExpectedName $SkillName
}

function Convert-TreeToStateFiles {
  param($Tree)
  return [object[]]@($Tree.files | ForEach-Object { [pscustomobject][ordered]@{ path = [string]$_.path; sha256 = [string]$_.sha256 } })
}

function New-StateDocument {
  param([string]$Version, [string]$Status, $Tree, [AllowNull()]$PreviousVersion)
  $stateFiles = [object[]]@()
  $stateDirectories = [string[]]@()
  if ($Status -ne 'removed') {
    $stateFiles = [object[]]@(Convert-TreeToStateFiles $Tree)
    $stateDirectories = [string[]]@($Tree.directories)
  }
  return [pscustomobject][ordered]@{
    schema_version = 1
    name = $SkillName
    version = $Version
    status = $Status
    files = $stateFiles
    directories = $stateDirectories
    previous_version = $PreviousVersion
  }
}

function Assert-TreeMatchesState {
  param($Tree, $State)
  $actualFiles = @($Tree.files)
  $expectedFiles = @($State.files)
  if ($actualFiles.Count -ne $expectedFiles.Count) { throw (New-SkillLifecycleException 'SKILL_PACKAGE_MODIFIED' 'Installed file set differs from recorded ownership state.') }
  for ($i = 0; $i -lt $expectedFiles.Count; $i++) {
    if ([string]$actualFiles[$i].path -ne [string]$expectedFiles[$i].path -or [string]$actualFiles[$i].sha256 -ne [string]$expectedFiles[$i].sha256) { throw (New-SkillLifecycleException 'SKILL_PACKAGE_MODIFIED' "Installed file '$($expectedFiles[$i].path)' changed or was replaced.") }
  }
  $actualDirectories = [string[]]@($Tree.directories)
  $expectedDirectories = [string[]]@($State.directories)
  if ($actualDirectories.Count -ne $expectedDirectories.Count) { throw (New-SkillLifecycleException 'SKILL_PACKAGE_MODIFIED' 'Installed directory set differs from recorded ownership state.') }
  for ($i = 0; $i -lt $expectedDirectories.Count; $i++) { if ($actualDirectories[$i] -ne $expectedDirectories[$i]) { throw (New-SkillLifecycleException 'SKILL_PACKAGE_MODIFIED' "Installed directory '$($expectedDirectories[$i])' changed.") } }
}

function Get-OtherState {
  param([string]$Name)
  $path = Join-Path $TargetRoot ".agent\skill-lifecycle\$Name.json"
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  try {
    $state = ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $path -Raw -MaximumBytes 1048576)
    return Assert-StateDocument -State $state -ExpectedName $Name
  } catch { throw (New-SkillLifecycleException 'SKILL_DEPENDENCY_STATE_INVALID' "State for '$Name' is invalid: $($_.Exception.Message)") }
}

function Assert-DependenciesAndConflicts {
  param($Metadata)
  foreach ($dependency in @($Metadata.dependencies)) {
    $state = Get-OtherState ([string]$dependency.name)
    if ($null -eq $state -or [string]$state.status -ne 'active') {
      if ($dependency.optional) { continue }
      throw (New-SkillLifecycleException 'SKILL_DEPENDENCY_NOT_ACTIVE' "Required skill '$($dependency.name)' is not active.")
    }
    if (-not (Test-LizardSkillVersionRequirement -Actual ([string]$state.version) -Requirement ([string]$dependency.version))) { throw (New-SkillLifecycleException 'SKILL_DEPENDENCY_VERSION' "Installed '$($dependency.name)' does not satisfy '$($dependency.version)'.") }
  }
  foreach ($conflict in @($Metadata.conflicts)) {
    $state = Get-OtherState ([string]$conflict)
    if ($null -ne $state -and [string]$state.status -eq 'active') { throw (New-SkillLifecycleException 'SKILL_CONFLICT_ACTIVE' "Conflicting skill '$conflict' is active.") }
  }
}

function Get-TargetEntry {
  param([string]$Path, [string]$Kind, [AllowNull()]$IntendedHash, [string]$Ownership = 'layer-owned', [string]$ActionOverride)
  $exists = Test-Path -LiteralPath $Path
  $preKind = if (-not $exists) { 'absent' } elseif (Test-Path -LiteralPath $Path -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $Path -PathType Container) { 'directory' } else { 'other' }
  $preHash = if ($preKind -eq 'file') { Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $Path } else { $null }
  $action = if (-not [string]::IsNullOrWhiteSpace($ActionOverride)) { $ActionOverride } elseif (-not $exists) { 'create' } elseif ($Kind -eq 'directory' -and $preKind -eq 'directory') { 'preserve' } elseif ($Kind -eq 'file' -and $preKind -eq 'file' -and $preHash -eq $IntendedHash) { 'preserve' } else { 'replace' }
  $relative = ConvertTo-RelativePath -Root $TargetRoot -Path $Path
  $entry = [pscustomobject][ordered]@{ path = $relative; kind = $Kind; action = $action; precondition_kind = $preKind; precondition_sha256 = $preHash }
  if ($action -eq 'remove') {
    $metadataKind = if ($Kind -eq 'file') { 'File' } else { 'Directory' }
    $metadata = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $Path -Kind $metadataKind
    $entry | Add-Member -NotePropertyName precondition_identity_sha256 -NotePropertyValue (Get-LizardPlanTargetIdentitySha256 -Metadata $metadata)
  }
  $entry | Add-Member -NotePropertyName ownership -NotePropertyValue $Ownership
  $entry | Add-Member -NotePropertyName intended_sha256 -NotePropertyValue $IntendedHash
  return $entry
}

function Add-RequiredDirectoryEntries {
  param($Entries, [string[]]$Paths)
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
  foreach ($existing in $Entries) { $null = $seen.Add([string]$existing.path) }
  foreach ($path in $Paths) {
    $relative = ConvertTo-RelativePath -Root $TargetRoot -Path $path
    if ($seen.Add($relative)) { $Entries.Add((Get-TargetEntry -Path $path -Kind directory -IntendedHash $null -Ownership layer-owned)) | Out-Null }
  }
}

function Assert-PostLockPlanBinding {
  param($Plan)
  if ((Get-LizardPlanRootHash -TargetRoot $TargetRoot) -ne [string]$Plan.intent.target_root_hash) { throw (New-SkillLifecycleException 'SKILL_PLAN_DRIFT' 'Target root identity changed after approval.') }
  foreach ($inputRecord in @($Plan.intent.inputs)) {
    if ([string]$inputRecord.scope -ne 'layer') { throw (New-SkillLifecycleException 'SKILL_PLAN_DRIFT' 'Skill lifecycle accepts layer inputs only.') }
    $inputPath = Resolve-SafeTargetDestination -AuthorizedRoot $LayerRoot -DestinationPath (Join-Path $LayerRoot ([string]$inputRecord.path).Replace('/', '\'))
    if ((Get-SafeFileHash -AuthorizedRoot $LayerRoot -Path $inputPath) -ne [string]$inputRecord.sha256) { throw (New-SkillLifecycleException 'SKILL_PLAN_DRIFT' "Source input '$($inputRecord.path)' changed after approval.") }
  }
  foreach ($targetEntry in @($Plan.intent.target_entries)) {
    $path = Resolve-SafeTargetDestination -AuthorizedRoot $TargetRoot -DestinationPath (Join-Path $TargetRoot ([string]$targetEntry.path).Replace('/', '\'))
    $exists = Test-Path -LiteralPath $path
    $kind = if (-not $exists) { 'absent' } elseif (Test-Path -LiteralPath $path -PathType Leaf) { 'file' } elseif (Test-Path -LiteralPath $path -PathType Container) { 'directory' } else { 'other' }
    if ($kind -ne [string]$targetEntry.precondition_kind) { throw (New-SkillLifecycleException 'SKILL_PLAN_DRIFT' "Target '$($targetEntry.path)' kind changed after approval.") }
    if ($kind -eq 'file' -and (Get-SafeFileHash -AuthorizedRoot $TargetRoot -Path $path) -ne [string]$targetEntry.precondition_sha256) { throw (New-SkillLifecycleException 'SKILL_PLAN_DRIFT' "Target '$($targetEntry.path)' content changed after approval.") }
    if ([string]$targetEntry.action -eq 'remove') {
      $metadataKind = if ($kind -eq 'file') { 'File' } else { 'Directory' }
      $identity = Get-LizardPlanTargetIdentitySha256 -Metadata (Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $path -Kind $metadataKind)
      if ($identity -ne [string]$targetEntry.precondition_identity_sha256) { throw (New-SkillLifecycleException 'SKILL_PLAN_DRIFT' "Target '$($targetEntry.path)' identity changed after approval.") }
    }
  }
}

$skillsRoot = Join-Path $LayerRoot 'skills'
$layerVersion = (Get-SafeContent -AuthorizedRoot $LayerRoot -Path (Join-Path $LayerRoot 'VERSION') -Raw -MaximumBytes 1024).Trim()
$package = Read-LizardSkillPackage -SkillsRoot $skillsRoot -Name $SkillName -LayerVersion $layerVersion
$null = Assert-LizardSkillRepository -SkillsRoot $skillsRoot -LayerVersion $layerVersion

if ($Action -eq 'Validate') {
  Write-Output ([pscustomobject]@{ name = $SkillName; version = [string]$package.metadata.version; status = 'valid'; metadata = $package.metadata_path })
  return
}

$packagePath = Join-Path $TargetRoot ".agent\skills\$SkillName"
$statePath = Join-Path $TargetRoot ".agent\skill-lifecycle\$SkillName.json"
$state = Read-State -Path $statePath -Optional
$sourceTree = Get-SkillTree -AuthorizedRoot $package.root -PackageRoot $package.root
$targetTree = Get-SkillTree -AuthorizedRoot $TargetRoot -PackageRoot $packagePath
$sourceVersion = [string]$package.metadata.version

switch ($Action) {
  'Install' {
    if (Test-Path -LiteralPath $packagePath) { throw (New-SkillLifecycleException 'SKILL_INSTALL_TARGET_EXISTS' 'Refusing to adopt or overwrite an existing skill directory.') }
    if ($null -ne $state -and [string]$state.status -ne 'removed') { throw (New-SkillLifecycleException 'SKILL_INSTALL_STATE_CONFLICT' "Existing lifecycle state is '$($state.status)'.") }
    Assert-DependenciesAndConflicts $package.metadata
  }
  'Update' {
    if ($null -eq $state -or [string]$state.status -ne 'active') { throw (New-SkillLifecycleException 'SKILL_UPDATE_STATE_INVALID' 'Update requires an active managed skill.') }
    Assert-TreeMatchesState $targetTree $state
    if ((ConvertTo-LizardSkillVersion $sourceVersion) -lt (ConvertTo-LizardSkillVersion ([string]$state.version))) { throw (New-SkillLifecycleException 'SKILL_UPDATE_DOWNGRADE' 'Update refuses a package downgrade.') }
    Assert-DependenciesAndConflicts $package.metadata
  }
  'Migrate' {
    if ($null -eq $state -or [string]$state.status -ne 'active') { throw (New-SkillLifecycleException 'SKILL_MIGRATION_STATE_INVALID' 'Migration requires an active managed skill.') }
    Assert-TreeMatchesState $targetTree $state
    if (@($package.metadata.migration.from_versions) -notcontains [string]$state.version) { throw (New-SkillLifecycleException 'SKILL_MIGRATION_UNDECLARED' "Migration from '$($state.version)' is not declared.") }
    if ((ConvertTo-LizardSkillVersion $sourceVersion) -le (ConvertTo-LizardSkillVersion ([string]$state.version))) { throw (New-SkillLifecycleException 'SKILL_MIGRATION_VERSION_INVALID' 'Migration requires a newer source package version.') }
    Assert-DependenciesAndConflicts $package.metadata
  }
  'Disable' {
    if ($null -eq $state -or [string]$state.status -ne 'active') { throw (New-SkillLifecycleException 'SKILL_DISABLE_STATE_INVALID' 'Disable requires an active managed skill.') }
    Assert-TreeMatchesState $targetTree $state
  }
  'Recover' {
    if ($null -eq $state -or [string]$state.status -ne 'disabled') { throw (New-SkillLifecycleException 'SKILL_RECOVERY_STATE_INVALID' 'Recovery requires disabled lifecycle state.') }
    if (Test-Path -LiteralPath $packagePath) { throw (New-SkillLifecycleException 'SKILL_RECOVERY_TARGET_EXISTS' 'Recovery refuses an existing skill directory.') }
    if ([string]$state.version -ne $sourceVersion) { throw (New-SkillLifecycleException 'SKILL_RECOVERY_SOURCE_MISMATCH' 'Recovery requires the exact recorded package version.') }
    Assert-TreeMatchesState $sourceTree $state
    Assert-DependenciesAndConflicts $package.metadata
  }
  'Remove' {
    if ($null -eq $state -or [string]$state.status -notin @('active', 'disabled')) { throw (New-SkillLifecycleException 'SKILL_REMOVE_STATE_INVALID' 'Remove requires active or disabled managed state.') }
    if ([string]$state.status -eq 'active') { Assert-TreeMatchesState $targetTree $state }
    elseif (Test-Path -LiteralPath $packagePath) { throw (New-SkillLifecycleException 'SKILL_REMOVE_TARGET_CONFLICT' 'Disabled state must not have a skill directory.') }
  }
}

$writesPackage = $Action -in @('Install', 'Update', 'Migrate', 'Recover')
$removesPackage = $Action -in @('Disable', 'Remove') -and $null -ne $state -and [string]$state.status -eq 'active'
$nextState = switch ($Action) {
  'Disable' { New-StateDocument -Version ([string]$state.version) -Status disabled -Tree $targetTree -PreviousVersion $state.previous_version }
  'Remove' { New-StateDocument -Version ([string]$state.version) -Status removed -Tree $targetTree -PreviousVersion $state.previous_version }
  'Migrate' { New-StateDocument -Version $sourceVersion -Status active -Tree $sourceTree -PreviousVersion ([string]$state.version) }
  default { New-StateDocument -Version $sourceVersion -Status active -Tree $sourceTree -PreviousVersion $null }
}
$stateJson = ConvertTo-LizardCanonicalJson $nextState
$stateHash = Get-LizardPlanSha256 -CanonicalJson $stateJson
$entries = New-Object System.Collections.Generic.List[object]
$inputs = New-Object System.Collections.Generic.List[object]

foreach ($file in @($sourceTree.files)) {
  $inputs.Add([pscustomobject][ordered]@{ scope = 'layer'; path = "skills/$SkillName/$($file.path)"; sha256 = [string]$file.sha256 }) | Out-Null
}
if ($writesPackage) {
  $requiredDirectories = New-Object System.Collections.Generic.List[string]
  foreach ($path in @((Join-Path $TargetRoot '.agent'), (Join-Path $TargetRoot '.agent\skills'), $packagePath, (Join-Path $TargetRoot '.agent\skill-lifecycle'))) { $requiredDirectories.Add($path) | Out-Null }
  foreach ($relative in @($sourceTree.directories)) { $requiredDirectories.Add((Join-Path $packagePath $relative.Replace('/', '\'))) | Out-Null }
  Add-RequiredDirectoryEntries -Entries $entries -Paths @($requiredDirectories.ToArray())
  foreach ($file in @($sourceTree.files)) { $entries.Add((Get-TargetEntry -Path (Join-Path $packagePath $file.path.Replace('/', '\')) -Kind file -IntendedHash ([string]$file.sha256) -Ownership layer-owned)) | Out-Null }
} elseif ($removesPackage) {
  foreach ($file in @($targetTree.files)) { $entries.Add((Get-TargetEntry -Path $file.full_path -Kind file -IntendedHash $null -Ownership layer-owned -ActionOverride remove)) | Out-Null }
  $directoryPaths = @($targetTree.directories | ForEach-Object { Join-Path $packagePath $_.Replace('/', '\') }) + @($packagePath)
  $directoryPaths = @($directoryPaths | Sort-Object { $_.Length } -Descending)
  foreach ($path in $directoryPaths) { $entries.Add((Get-TargetEntry -Path $path -Kind directory -IntendedHash $null -Ownership layer-owned -ActionOverride remove)) | Out-Null }
}
Add-RequiredDirectoryEntries -Entries $entries -Paths @((Join-Path $TargetRoot '.agent'), (Join-Path $TargetRoot '.agent\skill-lifecycle'))
$entries.Add((Get-TargetEntry -Path $statePath -Kind file -IntendedHash $stateHash -Ownership layer-owned)) | Out-Null

$options = [pscustomobject][ordered]@{
  action = $Action.ToLowerInvariant()
  skill = $SkillName
  package_version = $sourceVersion
  previous_status = if ($null -eq $state) { 'absent' } else { [string]$state.status }
  previous_version = if ($null -eq $state) { $null } else { [string]$state.version }
}
$candidatePlan = New-LizardOperationPlan -OperationKind skill-lifecycle -TargetRoot $TargetRoot -LayerRoot $LayerRoot -Options $options -Inputs @($inputs.ToArray()) -TargetEntries @($entries.ToArray()) -TtlMinutes $PlanTtlMinutes

if (-not $Apply) {
  if ([string]::IsNullOrWhiteSpace($CanonicalPlanPath)) {
    $planRoot = Join-Path $LayerRoot '.tmp\skill-plans'
    if (-not (Test-Path -LiteralPath $planRoot)) { New-SafeDirectory -AuthorizedRoot $LayerRoot -Path $planRoot | Out-Null }
    $CanonicalPlanPath = Join-Path $planRoot ("{0}-{1}-{2}.json" -f $SkillName, $Action.ToLowerInvariant(), ([Guid]::NewGuid().ToString('N')))
  }
  $written = Write-LizardOperationPlan -Plan $candidatePlan -AuthorizedRoot $LayerRoot -Path $CanonicalPlanPath
  Write-Output ([pscustomobject]@{ mode = 'preview'; action = $Action.ToLowerInvariant(); skill = $SkillName; plan_path = $written.path; plan_sha256 = $written.sha256; target_mutations = @($entries | Where-Object { $_.action -ne 'preserve' }).Count })
  return
}

if (-not $HumanApproved -or [string]::IsNullOrWhiteSpace($ApprovedPlanPath) -or [string]::IsNullOrWhiteSpace($ApprovedPlanSha256)) { throw (New-SkillLifecycleException 'SKILL_APPROVAL_REQUIRED' 'Apply requires HumanApproved, ApprovedPlanPath, and independently supplied ApprovedPlanSha256.') }
$approved = Read-LizardApprovedPlan -AuthorizedRoot $LayerRoot -Path $ApprovedPlanPath -Sha256 $ApprovedPlanSha256 -OperationKind skill-lifecycle
$null = Assert-LizardPlanIntentMatch -ApprovedPlan $approved -CandidatePlan $candidatePlan

$transaction = Start-LizardTransaction -TargetRoot $TargetRoot -OperationName ("skill-{0}-{1}" -f $Action.ToLowerInvariant(), $SkillName) -FailAfterMutation $FailAfterMutation
try {
  Assert-PostLockPlanBinding -Plan $candidatePlan
  $entryByPath = @{}
  foreach ($plannedEntry in @($candidatePlan.intent.target_entries)) { $entryByPath[[string]$plannedEntry.path] = $plannedEntry }
  if ($writesPackage) {
    New-LizardTransactionalDirectory -Path $packagePath | Out-Null
    foreach ($directory in @($sourceTree.directories)) { New-LizardTransactionalDirectory -Path (Join-Path $packagePath $directory.Replace('/', '\')) | Out-Null }
    foreach ($file in @($sourceTree.files)) {
      $destination = Join-Path $packagePath $file.path.Replace('/', '\')
      $relativeDestination = ConvertTo-RelativePath -Root $TargetRoot -Path $destination
      if ([string]$entryByPath[$relativeDestination].action -eq 'preserve') { continue }
      $force = Test-Path -LiteralPath $destination -PathType Leaf
      Copy-LizardTransactionalFile -SourceAuthorizedRoot $package.root -Source $file.full_path -Destination $destination -Force:$force
    }
  } elseif ($removesPackage) {
    foreach ($file in @($targetTree.files)) {
      $identity = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $file.full_path -Kind File
      Remove-LizardTransactionalItem -Path $file.full_path -Kind File -ExpectedIdentity $identity
    }
    $directoryPaths = @($targetTree.directories | ForEach-Object { Join-Path $packagePath $_.Replace('/', '\') }) + @($packagePath)
    $directoryPaths = @($directoryPaths | Sort-Object { $_.Length } -Descending)
    foreach ($directory in $directoryPaths) {
      $identity = Get-SafeItemMetadata -AuthorizedRoot $TargetRoot -Path $directory -Kind Directory
      Remove-LizardTransactionalItem -Path $directory -Kind EmptyDirectory -ExpectedIdentity $identity
    }
  }
  $relativeStatePath = ConvertTo-RelativePath -Root $TargetRoot -Path $statePath
  if ([string]$entryByPath[$relativeStatePath].action -ne 'preserve') { Set-LizardTransactionalBytes -Path $statePath -Bytes ((New-Object System.Text.UTF8Encoding($false)).GetBytes($stateJson)) }
  $result = Complete-LizardTransaction
} catch {
  $originalFailure = $_
  try { Undo-LizardTransaction | Out-Null }
  catch { throw (New-SkillLifecycleException 'SKILL_ROLLBACK_FAILED' "Original failure: $($originalFailure.Exception.Message) Rollback failure: $($_.Exception.Message)") }
  throw $originalFailure
}

[pscustomobject]@{ mode = 'apply'; action = $Action.ToLowerInvariant(); skill = $SkillName; version = [string]$nextState.version; status = [string]$nextState.status; transaction_id = $result.operation_id; mutations = $result.mutation_count }
