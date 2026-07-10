Set-StrictMode -Version 2.0

function Get-LizardPathComparison {
  if ($PSVersionTable.PSObject.Properties.Name -contains 'Platform' -and $PSVersionTable.Platform -eq 'Unix') {
    return [System.StringComparison]::Ordinal
  }
  return [System.StringComparison]::OrdinalIgnoreCase
}

function Get-LizardPathComparer {
  if ($PSVersionTable.PSObject.Properties.Name -contains 'Platform' -and $PSVersionTable.Platform -eq 'Unix') {
    return [System.StringComparer]::Ordinal
  }
  return [System.StringComparer]::OrdinalIgnoreCase
}

function New-LizardSafeFsException {
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

function ConvertTo-LizardFullPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [string]$BasePath = (Get-Location).Path
  )

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_EMPTY_PATH' -Message 'A filesystem path is required.' -Path $Path)
  }

  $full = if ([System.IO.Path]::IsPathRooted($Path)) {
    [System.IO.Path]::GetFullPath($Path)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
  }

  $pathRoot = [System.IO.Path]::GetPathRoot($full)
  if ($full.Length -gt $pathRoot.Length) {
    return $full.TrimEnd([char[]]@([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar))
  }
  return $full
}

function Test-LizardPathWithinRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [switch]$AllowRoot
  )

  $fullPath = ConvertTo-LizardFullPath -Path $Path
  $fullRoot = ConvertTo-LizardFullPath -Path $AuthorizedRoot
  $comparison = Get-LizardPathComparison

  if ($fullPath.Equals($fullRoot, $comparison)) { return $AllowRoot.IsPresent }
  $prefix = $fullRoot + [System.IO.Path]::DirectorySeparatorChar
  return $fullPath.StartsWith($prefix, $comparison)
}

function Get-LizardExistingItem {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    return Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  } catch [System.Management.Automation.ItemNotFoundException] {
    return $null
  }
}

function Test-LizardReparsePoint {
  param([Parameter(Mandatory = $true)]$Item)

  if (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $true }
  if ($Item.PSObject.Properties.Name -contains 'LinkType' -and -not [string]::IsNullOrWhiteSpace([string]$Item.LinkType)) { return $true }
  return $false
}

function Get-LizardAncestorPaths {
  param([Parameter(Mandatory = $true)][string]$Path)

  $paths = New-Object System.Collections.Generic.List[string]
  $current = ConvertTo-LizardFullPath -Path $Path
  while ($true) {
    $paths.Add($current) | Out-Null
    $parent = [System.IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
    $current = $parent
  }
  return @($paths.ToArray())
}

function Assert-NoReparsePointEscape {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  $fullRoot = ConvertTo-LizardFullPath -Path $AuthorizedRoot
  $fullDestination = ConvertTo-LizardFullPath -Path $DestinationPath
  $checked = New-Object System.Collections.Generic.HashSet[string] (Get-LizardPathComparer)

  foreach ($candidate in @((Get-LizardAncestorPaths -Path $fullRoot) + (Get-LizardAncestorPaths -Path $fullDestination))) {
    if (-not $checked.Add($candidate)) { continue }
    $item = Get-LizardExistingItem -Path $candidate
    if ($null -ne $item -and (Test-LizardReparsePoint -Item $item)) {
      throw (New-LizardSafeFsException -Code 'SAFEFS_REPARSE_POINT' -Message ("Linked path component is not allowed: {0}" -f $candidate) -Path $fullDestination -AuthorizedRoot $fullRoot)
    }
  }

  return [pscustomobject]@{
    authorized_root = $fullRoot
    destination = $fullDestination
    reparse_points = @()
  }
}

function Resolve-SafeTargetDestination {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [switch]$AllowRoot
  )

  $fullRoot = ConvertTo-LizardFullPath -Path $AuthorizedRoot
  $fullDestination = ConvertTo-LizardFullPath -Path $DestinationPath
  if (-not (Test-LizardPathWithinRoot -Path $fullDestination -AuthorizedRoot $fullRoot -AllowRoot:$AllowRoot)) {
    $reason = if ($fullDestination -eq $fullRoot) { 'Destination equality with the authorized root is not allowed.' } else { 'Destination escapes the authorized root.' }
    throw (New-LizardSafeFsException -Code 'SAFEFS_OUTSIDE_ROOT' -Message ("{0} Root: {1}; destination: {2}" -f $reason, $fullRoot, $fullDestination) -Path $fullDestination -AuthorizedRoot $fullRoot)
  }

  Assert-NoReparsePointEscape -AuthorizedRoot $fullRoot -DestinationPath $fullDestination | Out-Null
  return $fullDestination
}

function Resolve-SafeRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$RequireExisting
  )

  $fullPath = ConvertTo-LizardFullPath -Path $Path
  if ($RequireExisting -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_ROOT_MISSING' -Message ("Authorized root does not exist as a directory: {0}" -f $fullPath) -Path $fullPath -AuthorizedRoot $fullPath)
  }
  Assert-NoReparsePointEscape -AuthorizedRoot $fullPath -DestinationPath $fullPath | Out-Null
  return $fullPath
}

function Assert-PathOutsideRoot {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$ExcludedRoot,
    [string]$Label = 'Output path'
  )

  if (Test-LizardPathWithinRoot -Path $Path -AuthorizedRoot $ExcludedRoot -AllowRoot) {
    $fullPath = ConvertTo-LizardFullPath -Path $Path
    $fullRoot = ConvertTo-LizardFullPath -Path $ExcludedRoot
    throw (New-LizardSafeFsException -Code 'SAFEFS_FORBIDDEN_ROOT' -Message ("{0} must remain outside target root. Root: {1}; path: {2}" -f $Label, $fullRoot, $fullPath) -Path $fullPath -AuthorizedRoot $fullRoot)
  }
}

function Initialize-SafeDirectory {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = Resolve-SafeRoot -Path $Path
  if (-not (Test-Path -LiteralPath $fullPath)) {
    Assert-NoReparsePointEscape -AuthorizedRoot $fullPath -DestinationPath $fullPath | Out-Null
    New-Item -ItemType Directory -Path $fullPath -Force | Out-Null
  }
  Resolve-SafeRoot -Path $fullPath -RequireExisting | Out-Null
  return $fullPath
}

function New-SafeDirectory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$AllowRoot
  )

  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Path -AllowRoot:$AllowRoot
  if (-not (Test-Path -LiteralPath $safePath)) {
    $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $safePath -AllowRoot:$AllowRoot
    New-Item -ItemType Directory -Path $safePath -Force | Out-Null
  }
  return $safePath
}

function Set-SafeContent {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowNull()][object]$Value,
    [string]$Encoding = 'UTF8'
  )

  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Path
  Set-Content -LiteralPath $safePath -Value $Value -Encoding $Encoding
}

function Add-SafeContent {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowNull()][object]$Value,
    [string]$Encoding = 'UTF8'
  )

  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Path
  Add-Content -LiteralPath $safePath -Value $Value -Encoding $Encoding
}

function Copy-SafeItem {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [switch]$Force
  )

  $safeDestination = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Destination
  Copy-Item -LiteralPath $Source -Destination $safeDestination -Force:$Force
}

Export-ModuleMember -Function @(
  'Add-SafeContent',
  'Assert-NoReparsePointEscape',
  'Assert-PathOutsideRoot',
  'ConvertTo-LizardFullPath',
  'Copy-SafeItem',
  'Initialize-SafeDirectory',
  'New-SafeDirectory',
  'Resolve-SafeRoot',
  'Resolve-SafeTargetDestination',
  'Set-SafeContent',
  'Test-LizardPathWithinRoot'
)
