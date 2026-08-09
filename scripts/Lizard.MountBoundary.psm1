Set-StrictMode -Version 2.0

function New-LizardMountBoundaryException {
  param(
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Message,
    [AllowNull()][string]$Path,
    [AllowNull()][string]$AuthorizedRoot
  )

  $exception = New-Object System.UnauthorizedAccessException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['safe_fs_code'] = $Code
  if ($Path) { $exception.Data['path'] = $Path }
  if ($AuthorizedRoot) { $exception.Data['authorized_root'] = $AuthorizedRoot }
  return $exception
}

function Get-LizardMountPlatform {
  param([ValidateSet('Auto', 'Windows', 'Linux', 'MacOS')][string]$Platform = 'Auto')

  if ($Platform -ne 'Auto') { return $Platform }
  if (-not $PSVersionTable.ContainsKey('Platform') -or $PSVersionTable['Platform'] -ne 'Unix') { return 'Windows' }
  $isMac = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
  if ($isMac) { return 'MacOS' }
  return 'Linux'
}

function ConvertTo-LizardUnixPath {
  param([Parameter(Mandatory = $true)][string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not $Path.StartsWith('/', [System.StringComparison]::Ordinal)) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("Unix mount identity requires an absolute path: {0}" -f $Path) -Path $Path)
  }
  $normalized = $Path
  while ($normalized.Contains('//')) { $normalized = $normalized.Replace('//', '/') }
  if ($normalized.Length -gt 1) { $normalized = $normalized.TrimEnd('/') }
  return $normalized
}

function ConvertFrom-LizardMountInfoPath {
  param([Parameter(Mandatory = $true)][string]$Value)

  $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
    param([System.Text.RegularExpressions.Match]$match)
    switch ($match.Groups[1].Value) {
      '040' { return ' ' }
      '011' { return "`t" }
      '012' { return "`n" }
      '134' { return '\' }
      default { return $match.Value }
    }
  }
  return [regex]::Replace($Value, '\\(040|011|012|134)', $evaluator)
}

function ConvertFrom-LizardLinuxMountInfo {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Lines)

  $records = New-Object System.Collections.Generic.List[object]
  foreach ($rawLine in @($Lines)) {
    $line = [string]$rawLine
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $separator = $line.IndexOf(' - ', [System.StringComparison]::Ordinal)
    if ($separator -lt 0) {
      throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("Malformed Linux mountinfo record: {0}" -f $line))
    }
    $left = $line.Substring(0, $separator)
    $right = $line.Substring($separator + 3)
    $fields = @($left -split '\s+')
    $filesystemFields = @($right -split '\s+')
    $mountId = 0
    $parentId = 0
    if ($fields.Count -lt 6 -or $filesystemFields.Count -lt 3 -or
        -not [int]::TryParse([string]$fields[0], [ref]$mountId) -or
        -not [int]::TryParse([string]$fields[1], [ref]$parentId) -or
        [string]$fields[2] -notmatch '^[0-9]+:[0-9]+$') {
      throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("Malformed Linux mountinfo fields: {0}" -f $line))
    }
    $records.Add([pscustomobject][ordered]@{
      mount_id = $mountId
      parent_id = $parentId
      device = [string]$fields[2]
      root = ConvertFrom-LizardMountInfoPath ([string]$fields[3])
      mount_point = ConvertFrom-LizardMountInfoPath ([string]$fields[4])
      filesystem = [string]$filesystemFields[0]
      source = ConvertFrom-LizardMountInfoPath ([string]$filesystemFields[1])
    }) | Out-Null
  }
  if ($records.Count -eq 0) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message 'Linux mountinfo contains no usable records.')
  }
  return @($records.ToArray())
}

function Get-LizardMacDeviceId {
  param([Parameter(Mandatory = $true)][string]$Path)

  $statPath = if (Test-Path -LiteralPath '/usr/bin/stat' -PathType Leaf) { '/usr/bin/stat' } elseif (Test-Path -LiteralPath '/bin/stat' -PathType Leaf) { '/bin/stat' } else { $null }
  if ([string]::IsNullOrWhiteSpace($statPath)) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message 'macOS stat executable is unavailable.' -Path $Path)
  }
  $global:LASTEXITCODE = 0
  $output = & $statPath '-f' '%d' $Path 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("macOS device identity failed for {0}: {1}" -f $Path, $output.Trim()) -Path $Path)
  }
  $device = $output.Trim()
  if ($device -notmatch '^[0-9]+$') {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("macOS returned an invalid device identity for {0}." -f $Path) -Path $Path)
  }
  return $device
}

function Get-LizardRuntimeMountRecords {
  param([ValidateSet('Linux', 'MacOS')][string]$Platform)

  if ($Platform -eq 'Linux') {
    $mountInfoPath = '/proc/self/mountinfo'
    if (-not [System.IO.File]::Exists($mountInfoPath)) {
      throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message 'Linux /proc/self/mountinfo is unavailable.')
    }
    return @(ConvertFrom-LizardLinuxMountInfo -Lines ([System.IO.File]::ReadAllLines($mountInfoPath)))
  }

  $records = New-Object System.Collections.Generic.List[object]
  foreach ($drive in @([System.IO.DriveInfo]::GetDrives())) {
    try {
      $mountPoint = ConvertTo-LizardUnixPath ([string]$drive.Name)
      $records.Add([pscustomobject][ordered]@{
        mount_id = "macos:$mountPoint"
        parent_id = $null
        device = Get-LizardMacDeviceId -Path $mountPoint
        root = '/'
        mount_point = $mountPoint
        filesystem = [string]$drive.DriveFormat
        source = [string]$drive.VolumeLabel
      }) | Out-Null
    } catch {
      throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("macOS mount identity is incomplete for {0}: {1}" -f $drive.Name, $_.Exception.Message) -Path ([string]$drive.Name))
    }
  }
  if ($records.Count -eq 0) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message 'macOS mount enumeration produced no usable records.')
  }
  return @($records.ToArray())
}

function Get-LizardMountIdentity {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MountRecords
  )

  $normalizedPath = ConvertTo-LizardUnixPath -Path $Path
  $best = $null
  $bestLength = -1
  foreach ($record in @($MountRecords)) {
    if ($null -eq $record -or
        $record.PSObject.Properties.Name -notcontains 'mount_id' -or
        $record.PSObject.Properties.Name -notcontains 'device' -or
        $record.PSObject.Properties.Name -notcontains 'mount_point') { continue }
    try { $mountPoint = ConvertTo-LizardUnixPath -Path ([string]$record.mount_point) }
    catch { continue }
    $matches = $normalizedPath.Equals($mountPoint, [System.StringComparison]::Ordinal) -or
      $mountPoint -eq '/' -or
      $normalizedPath.StartsWith($mountPoint + '/', [System.StringComparison]::Ordinal)
    if ($matches -and $mountPoint.Length -ge $bestLength) {
      $best = $record
      $bestLength = $mountPoint.Length
    }
  }
  if ($null -eq $best -or
      [string]::IsNullOrWhiteSpace([string]$best.mount_id) -or
      [string]::IsNullOrWhiteSpace([string]$best.device)) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("No mount identity covers path: {0}" -f $normalizedPath) -Path $normalizedPath)
  }
  return $best
}

function Get-LizardUnixPathComponents {
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  $root = ConvertTo-LizardUnixPath -Path $AuthorizedRoot
  $destination = ConvertTo-LizardUnixPath -Path $DestinationPath
  if (-not $destination.Equals($root, [System.StringComparison]::Ordinal) -and
      -not $destination.StartsWith($(if ($root -eq '/') { '/' } else { $root + '/' }), [System.StringComparison]::Ordinal)) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message ("Destination is outside the mount-identity root. Root: {0}; destination: {1}" -f $root, $destination) -Path $destination -AuthorizedRoot $root)
  }

  $components = New-Object System.Collections.Generic.List[string]
  $components.Add($root) | Out-Null
  if ($destination.Equals($root, [System.StringComparison]::Ordinal)) { return @($components.ToArray()) }
  $relative = if ($root -eq '/') { $destination.TrimStart('/') } else { $destination.Substring($root.Length).TrimStart('/') }
  $current = $root
  foreach ($segment in @($relative -split '/')) {
    if ([string]::IsNullOrWhiteSpace($segment)) { continue }
    $current = if ($current -eq '/') { '/' + $segment } else { $current + '/' + $segment }
    $components.Add($current) | Out-Null
  }
  return @($components.ToArray())
}

function Assert-LizardMountBoundary {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [AllowEmptyCollection()][object[]]$MountRecords,
    [ValidateSet('Auto', 'Windows', 'Linux', 'MacOS')][string]$Platform = 'Auto'
  )

  $effectivePlatform = Get-LizardMountPlatform -Platform $Platform
  if ($effectivePlatform -eq 'Windows') {
    return [pscustomobject][ordered]@{ platform = 'Windows'; root_identity = $null; checked_paths = @() }
  }

  $records = @()
  if ($PSBoundParameters.ContainsKey('MountRecords')) { $records = @($MountRecords) }
  else { $records = @(Get-LizardRuntimeMountRecords -Platform $effectivePlatform) }
  if ($records.Count -eq 0) {
    throw (New-LizardMountBoundaryException -Code 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' -Message 'Unix mount identity data is empty.' -Path $DestinationPath -AuthorizedRoot $AuthorizedRoot)
  }
  $components = @(Get-LizardUnixPathComponents -AuthorizedRoot $AuthorizedRoot -DestinationPath $DestinationPath)
  $rootIdentity = Get-LizardMountIdentity -Path $components[0] -MountRecords $records
  foreach ($component in $components) {
    $identity = Get-LizardMountIdentity -Path $component -MountRecords $records
    if ([string]$identity.mount_id -ne [string]$rootIdentity.mount_id) {
      $code = if ([string]$identity.device -ne [string]$rootIdentity.device) { 'SAFEFS_DEVICE_BOUNDARY' } else { 'SAFEFS_MOUNT_BOUNDARY' }
      throw (New-LizardMountBoundaryException -Code $code -Message ("Path crosses a nested Unix mount. Root mount: {0} ({1}); nested mount: {2} ({3}); path: {4}" -f $rootIdentity.mount_id, $rootIdentity.device, $identity.mount_id, $identity.device, $component) -Path $component -AuthorizedRoot $AuthorizedRoot)
    }
  }

  return [pscustomobject][ordered]@{
    platform = $effectivePlatform
    root_identity = $rootIdentity
    checked_paths = $components
  }
}

Export-ModuleMember -Function @(
  'Assert-LizardMountBoundary',
  'ConvertFrom-LizardLinuxMountInfo',
  'Get-LizardMountIdentity'
)
