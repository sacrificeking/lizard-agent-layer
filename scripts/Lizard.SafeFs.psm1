Set-StrictMode -Version 2.0
Import-Module (Join-Path $PSScriptRoot 'Lizard.MountBoundary.psm1') -Force

function Test-LizardSafeFsWindows {
  return -not ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix')
}

if (Test-LizardSafeFsWindows) {
  Import-Module (Join-Path $PSScriptRoot 'Lizard.WindowsHandleFs.psm1') -Force
} else {
  Import-Module (Join-Path $PSScriptRoot 'Lizard.UnixHandleFs.psm1') -Force
}

$script:LizardSafeFsTestHooks = @{}

function Set-LizardSafeFsTestHook {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('after-parent-handle-acquired', 'after-directory-identity-acquired')][string]$Event,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )
  if ([string]$env:LIZARD_SAFEFS_TESTING -ne '1') {
    throw 'SAFEFS_TEST_HOOK_DISABLED: SafeFs synchronization hooks are available only when LIZARD_SAFEFS_TESTING=1.'
  }
  $script:LizardSafeFsTestHooks[$Event] = $Action
}

function Clear-LizardSafeFsTestHooks {
  $script:LizardSafeFsTestHooks.Clear()
}

function Invoke-LizardSafeFsTestHook {
  param([Parameter(Mandatory = $true)][string]$Event, [AllowNull()]$Context)
  if ([string]$env:LIZARD_SAFEFS_TESTING -ne '1') { return }
  if ($script:LizardSafeFsTestHooks.ContainsKey($Event)) {
    & $script:LizardSafeFsTestHooks[$Event] $Context
  }
}

function ConvertTo-LizardSafeContentBytes {
  param(
    [AllowNull()][object]$Value,
    [Parameter(Mandatory = $true)][string]$Encoding,
    [switch]$NoPreamble
  )

  $normalized = $Encoding.ToUpperInvariant()
  $emitUtf8Bom = ([string]$PSVersionTable.PSEdition -eq 'Desktop') -and -not $NoPreamble
  $encoder = switch ($normalized) {
    'UTF8' { New-Object System.Text.UTF8Encoding($emitUtf8Bom); break }
    'UTF-8' { New-Object System.Text.UTF8Encoding($emitUtf8Bom); break }
    'UNICODE' { New-Object System.Text.UnicodeEncoding($false, (-not $NoPreamble)); break }
    'BIGENDIANUNICODE' { New-Object System.Text.UnicodeEncoding($true, (-not $NoPreamble)); break }
    'ASCII' { [System.Text.Encoding]::ASCII; break }
    default { [System.Text.Encoding]::GetEncoding($Encoding) }
  }

  $body = [byte[]]@()
  if ($null -ne $Value) {
    $lines = @($Value | ForEach-Object { if ($null -eq $_) { '' } else { [string]$_ } })
    $text = ($lines -join [Environment]::NewLine) + [Environment]::NewLine
    $body = $encoder.GetBytes($text)
  }
  $preamble = [byte[]]@()
  if (-not $NoPreamble) { $preamble = $encoder.GetPreamble() }
  $bytes = New-Object byte[] ($preamble.Length + $body.Length)
  if ($preamble.Length -gt 0) { [Array]::Copy($preamble, 0, $bytes, 0, $preamble.Length) }
  if ($body.Length -gt 0) { [Array]::Copy($body, 0, $bytes, $preamble.Length, $body.Length) }
  return ,$bytes
}

function ConvertFrom-LizardSafeContentBytes {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Bytes,
    [Parameter(Mandatory = $true)][string]$Encoding,
    [switch]$Raw
  )

  $encoder = switch ($Encoding.ToUpperInvariant()) {
    'UTF8' { New-Object System.Text.UTF8Encoding($false, $true); break }
    'UTF-8' { New-Object System.Text.UTF8Encoding($false, $true); break }
    'UNICODE' { [System.Text.Encoding]::Unicode; break }
    'BIGENDIANUNICODE' { [System.Text.Encoding]::BigEndianUnicode; break }
    'ASCII' { [System.Text.Encoding]::ASCII; break }
    default { [System.Text.Encoding]::GetEncoding($Encoding) }
  }
  $stream = New-Object System.IO.MemoryStream (,$Bytes)
  $reader = New-Object System.IO.StreamReader($stream, $encoder, $true)
  try { $text = $reader.ReadToEnd() }
  finally { $reader.Dispose(); $stream.Dispose() }
  if ($Raw) { return $text }

  $lines = @($text -split "`r`n|`n|`r")
  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
    if ($lines.Count -eq 1) { return @() }
    return @($lines[0..($lines.Count - 2)])
  }
  return $lines
}

function Open-LizardSafeDirectoryLease {
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot, [Parameter(Mandatory = $true)][string]$Destination)
  if (Test-LizardSafeFsWindows) { return Open-LizardWindowsDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $Destination }
  return Open-LizardUnixDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $Destination
}

function Read-LizardHandleSafeFile {
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$MetadataOnly,
    [ValidateRange(1, 2147483647)][int64]$MaximumBytes = 2147483647
  )

  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $AuthorizedRoot | Out-Null
  $lease = Open-LizardSafeDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $Path
  try {
    Invoke-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Context ([pscustomobject]@{ authorized_root = $AuthorizedRoot; path = $Path; operation = 'read' })
    if ($MetadataOnly) { return $lease.GetExistingMetadata() }
    $bytes = $lease.ReadExisting($MaximumBytes)
    return ,$bytes
  } finally {
    if ($null -ne $lease) { $lease.Dispose() }
  }
}

function Get-SafeBytes {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateRange(1, 2147483647)][int64]$MaximumBytes = 67108864
  )

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $Path
  return ,(Read-LizardHandleSafeFile -AuthorizedRoot $fullRoot -Path $safePath -MaximumBytes $MaximumBytes)
}

function Get-LizardPathComparison {
  if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix') {
    return [System.StringComparison]::Ordinal
  }
  return [System.StringComparison]::OrdinalIgnoreCase
}

function Get-LizardPathComparer {
  if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix') {
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

function Get-LizardSafeFsHostId {
  if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix') {
    $isMac = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
    if ($isMac) { return 'macos-pwsh' }
    return 'linux-pwsh'
  }
  if ([string]$PSVersionTable.PSEdition -eq 'Desktop') { return 'windows-powershell-5.1' }
  return 'windows-pwsh'
}

function ConvertTo-LizardCanonicalTemporaryPath {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')]
    [string]$HostId = (Get-LizardSafeFsHostId)
  )

  $isRuntimeUnix = $PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix'
  $fullPath = if ($HostId -eq 'macos-pwsh' -and -not $isRuntimeUnix -and $Path.StartsWith('/', [System.StringComparison]::Ordinal)) {
    if ($Path.Length -gt 1) { $Path.TrimEnd('/') } else { $Path }
  } else {
    ConvertTo-LizardFullPath -Path $Path
  }

  if ($HostId -eq 'macos-pwsh' -and ($fullPath -eq '/var' -or $fullPath.StartsWith('/var/', [System.StringComparison]::Ordinal))) {
    return '/private' + $fullPath
  }
  return $fullPath
}

function Resolve-LizardSafeTemporaryRoot {
  [CmdletBinding()]
  param(
    [string]$Path = [System.IO.Path]::GetTempPath(),
    [ValidateSet('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')]
    [string]$HostId = (Get-LizardSafeFsHostId)
  )

  $canonicalPath = ConvertTo-LizardCanonicalTemporaryPath -Path $Path -HostId $HostId
  return Resolve-SafeRoot -Path $canonicalPath -RequireExisting
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
  if ($Item.PSObject.Properties.Name -contains 'LinkTarget' -and -not [string]::IsNullOrWhiteSpace([string]$Item.LinkTarget)) { return $true }
  if ($Item.PSObject.Properties.Name -contains 'Target' -and -not [string]::IsNullOrWhiteSpace([string]$Item.Target)) { return $true }
  if ($PSVersionTable.ContainsKey('Platform') -and $PSVersionTable['Platform'] -eq 'Unix') {
    try { if ($null -ne [System.IO.Directory]::ResolveLinkTarget([string]$Item.FullName, $false)) { return $true } } catch {}
    try { if ($null -ne [System.IO.File]::ResolveLinkTarget([string]$Item.FullName, $false)) { return $true } } catch {}
  }
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
  Assert-LizardMountBoundary -AuthorizedRoot $fullRoot -DestinationPath $fullDestination | Out-Null
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
  Assert-LizardMountBoundary -AuthorizedRoot $fullPath -DestinationPath $fullPath | Out-Null
  return $fullPath
}

function Get-LizardSafeFileSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $Path
  $item = Get-LizardExistingItem -Path $safePath
  if ($null -eq $item) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_FILE_MISSING' -Message ("File does not exist: {0}" -f $safePath) -Path $safePath -AuthorizedRoot $fullRoot)
  }
  if (Test-LizardReparsePoint -Item $item) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_REPARSE_POINT' -Message ("Linked terminal file is not allowed: {0}" -f $safePath) -Path $safePath -AuthorizedRoot $fullRoot)
  }
  if ($item.PSIsContainer) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_NOT_FILE' -Message ("Expected a file, but found a directory: {0}" -f $safePath) -Path $safePath -AuthorizedRoot $fullRoot)
  }

  return [pscustomobject]@{
    authorized_root = $fullRoot
    path = $safePath
    length = [int64]$item.Length
    last_write_utc_ticks = [int64]$item.LastWriteTimeUtc.Ticks
  }
}

function Assert-LizardSafeFileUnchanged {
  param(
    [Parameter(Mandatory = $true)]$Before,
    [Parameter(Mandatory = $true)]$After
  )

  if (-not ([string]$Before.path).Equals([string]$After.path, (Get-LizardPathComparison)) -or
      [int64]$Before.length -ne [int64]$After.length -or
      [int64]$Before.last_write_utc_ticks -ne [int64]$After.last_write_utc_ticks) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_CHANGED_DURING_READ' -Message ("File identity changed while it was being read: {0}" -f $Before.path) -Path ([string]$Before.path) -AuthorizedRoot ([string]$Before.authorized_root))
  }
}

function Get-SafeFileMetadata {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )

  return Get-SafeItemMetadata -AuthorizedRoot $AuthorizedRoot -Path $Path -Kind File
}

function Get-SafeItemMetadata {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][ValidateSet('File', 'Directory')][string]$Kind
  )

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $Path
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $fullRoot | Out-Null
  $lease = Open-LizardSafeDirectoryLease -AuthorizedRoot $fullRoot -Destination $safePath
  try {
    Invoke-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Context ([pscustomobject]@{ authorized_root = $fullRoot; path = $safePath; operation = 'metadata' })
    $metadata = if ($Kind -eq 'File') { $lease.GetExistingMetadata() } else { $lease.GetExistingDirectoryMetadata() }
  } finally {
    if ($null -ne $lease) { $lease.Dispose() }
  }
  $volumeId = if ($metadata.PSObject.Properties.Name -contains 'VolumeSerial') { ([uint64]$metadata.VolumeSerial).ToString('x') } else { ([uint64]$metadata.Device).ToString('x') }
  $fileId = if ($metadata.PSObject.Properties.Name -contains 'FileId') { [uint64]$metadata.FileId } else { [uint64]$metadata.Inode }
  $mountId = if ($metadata.PSObject.Properties.Name -contains 'MountId') { ([int64]$metadata.MountId).ToString([System.Globalization.CultureInfo]::InvariantCulture) } else { $volumeId }
  $capability = Get-LizardSafeFsCapability -AuthorizedRoot $fullRoot
  return [pscustomobject]@{
    backend = [string]$capability.backend
    path = $safePath
    kind = $Kind.ToLowerInvariant()
    length = [int64]$metadata.Length
    last_write_utc = ([DateTime]::new([int64]$metadata.LastWriteUtcTicks, [DateTimeKind]::Utc)).ToString('o')
    volume_id = $volumeId
    mount_id = $mountId
    file_id = $fileId.ToString('x16')
  }
}

function Get-SafeFileHash {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [ValidateSet('SHA256')][string]$Algorithm = 'SHA256'
  )

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $Path
  $bytes = Read-LizardHandleSafeFile -AuthorizedRoot $fullRoot -Path $safePath
  $hasher = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($hasher.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $hasher.Dispose() }
}

function Get-SafeContent {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [switch]$Raw,
    [string]$Encoding = 'UTF8',
    [ValidateRange(1, 2147483647)][int64]$MaximumBytes = 67108864
  )

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $Path
  $bytes = Read-LizardHandleSafeFile -AuthorizedRoot $fullRoot -Path $safePath -MaximumBytes $MaximumBytes
  return ConvertFrom-LizardSafeContentBytes -Bytes $bytes -Encoding $Encoding -Raw:$Raw
}

function Get-LizardSafeDirectoryIdentity {
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $comparison = Get-LizardPathComparison
  if ($Path.Equals($AuthorizedRoot, $comparison)) {
    $identity = Get-LizardSafeRootIdentity -AuthorizedRoot $AuthorizedRoot
    return [pscustomobject]@{ volume_id = [string]$identity.volume_id; mount_id = [string]$identity.volume_id; file_id = [string]$identity.file_id }
  }
  return Get-SafeItemMetadata -AuthorizedRoot $AuthorizedRoot -Path $Path -Kind Directory
}

function Assert-LizardSafeDirectoryIdentityEqual {
  param([Parameter(Mandatory = $true)]$Before, [Parameter(Mandatory = $true)]$After, [Parameter(Mandatory = $true)][string]$Path)
  if ([string]$Before.volume_id -ne [string]$After.volume_id -or
      [string]$Before.mount_id -ne [string]$After.mount_id -or
      [string]$Before.file_id -ne [string]$After.file_id) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_CHANGED_DURING_ENUMERATION' -Message ("Directory identity changed while entries were enumerated: {0}" -f $Path) -Path $Path -AuthorizedRoot $Path)
  }
}

function Get-SafeDirectoryEntries {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $comparison = Get-LizardPathComparison
  $fullPath = ConvertTo-LizardFullPath -Path $Path
  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $fullPath -AllowRoot:($fullPath.Equals($fullRoot, $comparison))
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $fullRoot | Out-Null
  $before = Get-LizardSafeDirectoryIdentity -AuthorizedRoot $fullRoot -Path $safePath
  Invoke-LizardSafeFsTestHook -Event 'after-directory-identity-acquired' -Context ([pscustomobject]@{ authorized_root = $fullRoot; path = $safePath; operation = 'enumerate' })

  try { $rawEntries = @(Get-ChildItem -LiteralPath $safePath -Force -ErrorAction Stop) }
  catch { throw (New-LizardSafeFsException -Code 'SAFEFS_DIRECTORY_ENUMERATION_FAILED' -Message $_.Exception.Message -Path $safePath -AuthorizedRoot $fullRoot) }

  $after = Get-LizardSafeDirectoryIdentity -AuthorizedRoot $fullRoot -Path $safePath
  Assert-LizardSafeDirectoryIdentityEqual -Before $before -After $after -Path $safePath

  $names = New-Object System.Collections.Generic.List[string]
  $byName = @{}
  foreach ($entry in $rawEntries) {
    $name = [string]$entry.Name
    if ([string]::IsNullOrWhiteSpace($name) -or $name -in @('.', '..') -or $name.IndexOfAny([char[]]@('\', '/', [char]0)) -ge 0) {
      throw (New-LizardSafeFsException -Code 'SAFEFS_INVALID_SEGMENT' -Message ("Invalid directory entry name: {0}" -f $name) -Path $safePath -AuthorizedRoot $fullRoot)
    }
    if ($byName.ContainsKey($name)) {
      throw (New-LizardSafeFsException -Code 'SAFEFS_DUPLICATE_ENTRY' -Message ("Duplicate directory entry name: {0}" -f $name) -Path $safePath -AuthorizedRoot $fullRoot)
    }
    $names.Add($name) | Out-Null
    $byName[$name] = $entry
  }
  $names.Sort([System.StringComparer]::Ordinal)

  $result = New-Object System.Collections.Generic.List[object]
  foreach ($name in $names) {
    $entry = $byName[$name]
    $entryPath = Join-Path $safePath $name
    $resolved = Resolve-SafeTargetDestination -AuthorizedRoot $fullRoot -DestinationPath $entryPath
    $kind = if ($entry.PSIsContainer) { 'Directory' } else { 'File' }
    $metadata = Get-SafeItemMetadata -AuthorizedRoot $fullRoot -Path $resolved -Kind $kind
    $result.Add([pscustomobject][ordered]@{
      name = $name
      path = $resolved
      kind = $kind.ToLowerInvariant()
      volume_id = [string]$metadata.volume_id
      mount_id = [string]$metadata.mount_id
      file_id = [string]$metadata.file_id
    }) | Out-Null
  }

  $final = Get-LizardSafeDirectoryIdentity -AuthorizedRoot $fullRoot -Path $safePath
  Assert-LizardSafeDirectoryIdentityEqual -Before $before -After $final -Path $safePath
  return @($result.ToArray())
}

function Get-LizardSafeFsCapability {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  if (Test-LizardSafeFsWindows) {
    return Get-LizardWindowsHandleCapability -AuthorizedRoot $fullRoot
  }
  return Get-LizardUnixHandleCapability -AuthorizedRoot $fullRoot
}

function Assert-LizardSafeFsMutationCapability {
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)
  $capability = Get-LizardSafeFsCapability -AuthorizedRoot $AuthorizedRoot
  if (-not [bool]$capability.available) {
    throw (New-LizardSafeFsException -Code 'SAFEFS_HANDLE_MUTATION_UNAVAILABLE' -Message ("Handle-bound mutation is unavailable for {0}." -f $capability.authorized_root) -Path ([string]$capability.authorized_root) -AuthorizedRoot ([string]$capability.authorized_root))
  }
  return $capability
}

function Get-LizardSafeRootIdentity {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)

  $fullRoot = Resolve-SafeRoot -Path $AuthorizedRoot -RequireExisting
  $capability = Assert-LizardSafeFsMutationCapability -AuthorizedRoot $fullRoot
  $native = if (Test-LizardSafeFsWindows) { Get-LizardWindowsRootIdentity -AuthorizedRoot $fullRoot } else { Get-LizardUnixRootIdentity -AuthorizedRoot $fullRoot }
  $volumeId = if ($native.PSObject.Properties.Name -contains 'VolumeSerial') { ([uint64]$native.VolumeSerial).ToString('x') } else { ([uint64]$native.Device).ToString('x') }
  $fileId = if ($native.PSObject.Properties.Name -contains 'FileId') { [uint64]$native.FileId } else { [uint64]$native.Inode }
  return [pscustomobject][ordered]@{
    schema_version = 1
    backend = [string]$capability.backend
    authorized_root = $fullRoot
    volume_id = $volumeId
    file_id = $fileId.ToString('x16')
  }
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
    $existingAncestor = [System.IO.Path]::GetDirectoryName($fullPath)
    while (-not [string]::IsNullOrWhiteSpace($existingAncestor) -and -not (Test-Path -LiteralPath $existingAncestor -PathType Container)) {
      $parent = [System.IO.Path]::GetDirectoryName($existingAncestor)
      if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $existingAncestor) { break }
      $existingAncestor = $parent
    }
    if ([string]::IsNullOrWhiteSpace($existingAncestor) -or -not (Test-Path -LiteralPath $existingAncestor -PathType Container)) {
      throw (New-LizardSafeFsException -Code 'SAFEFS_ROOT_MISSING' -Message ("No existing authorized ancestor can create directory: {0}" -f $fullPath) -Path $fullPath -AuthorizedRoot $fullPath)
    }
    $ancestorRoot = Resolve-SafeRoot -Path $existingAncestor -RequireExisting
    New-SafeDirectory -AuthorizedRoot $ancestorRoot -Path $fullPath | Out-Null
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
    Assert-LizardSafeFsMutationCapability -AuthorizedRoot $AuthorizedRoot | Out-Null
    if (Test-LizardSafeFsWindows) {
      New-LizardWindowsSafeDirectory -AuthorizedRoot $AuthorizedRoot -Path $safePath
    } else {
      New-LizardUnixSafeDirectory -AuthorizedRoot $AuthorizedRoot -Path $safePath
    }
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
  $bytes = ConvertTo-LizardSafeContentBytes -Value $Value -Encoding $Encoding
  Set-SafeBytes -AuthorizedRoot $AuthorizedRoot -Path $safePath -Bytes $bytes
}

function Set-SafeBytes {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][byte[]]$Bytes,
    [switch]$CreateNew
  )

  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Path
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $AuthorizedRoot | Out-Null
  $lease = Open-LizardSafeDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $safePath
  try {
    Invoke-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Context ([pscustomobject]@{ authorized_root = $AuthorizedRoot; path = $safePath; operation = 'write' })
    try { $lease.WriteAtomic($Bytes, (-not $CreateNew)) }
    catch {
      if ($CreateNew -and (Test-Path -LiteralPath $safePath)) {
        throw (New-LizardSafeFsException -Code 'SAFEFS_DESTINATION_EXISTS' -Message ("Create-new destination already exists: {0}" -f $safePath) -Path $safePath -AuthorizedRoot $AuthorizedRoot)
      }
      throw
    }
  } finally {
    if ($null -ne $lease) { $lease.Dispose() }
  }
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
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $AuthorizedRoot | Out-Null
  $lease = Open-LizardSafeDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $safePath
  try {
    Invoke-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Context ([pscustomobject]@{ authorized_root = $AuthorizedRoot; path = $safePath })
    try { $existing = $lease.ReadExisting(2147483647) }
    catch { if ($_.Exception.Message -match 'SAFEFS_FILE_MISSING') { $existing = [byte[]]@() } else { throw } }
    $appended = ConvertTo-LizardSafeContentBytes -Value $Value -Encoding $Encoding -NoPreamble
    $bytes = New-Object byte[] ($existing.Length + $appended.Length)
    if ($existing.Length -gt 0) { [Array]::Copy($existing, 0, $bytes, 0, $existing.Length) }
    if ($appended.Length -gt 0) { [Array]::Copy($appended, 0, $bytes, $existing.Length, $appended.Length) }
    $lease.WriteAtomic($bytes, $true)
  } finally {
    if ($null -ne $lease) { $lease.Dispose() }
  }
}

function Copy-SafeItem {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$SourceAuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination,
    [switch]$Force
  )

  $fullSourceRoot = Resolve-SafeRoot -Path $SourceAuthorizedRoot -RequireExisting
  $safeSource = Resolve-SafeTargetDestination -AuthorizedRoot $fullSourceRoot -DestinationPath $Source
  $safeDestination = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Destination
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $fullSourceRoot | Out-Null
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $AuthorizedRoot | Out-Null
  $bytes = Read-LizardHandleSafeFile -AuthorizedRoot $fullSourceRoot -Path $safeSource
  $lease = Open-LizardSafeDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $safeDestination
  try {
    Invoke-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Context ([pscustomobject]@{ authorized_root = $AuthorizedRoot; path = $safeDestination; operation = 'copy-destination' })
    $lease.WriteAtomic($bytes, [bool]$Force)
  } finally {
    if ($null -ne $lease) { $lease.Dispose() }
  }
}

function Remove-SafeItem {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][ValidateSet('File', 'EmptyDirectory')][string]$Kind,
    [AllowNull()]$ExpectedIdentity
  )

  $safePath = Resolve-SafeTargetDestination -AuthorizedRoot $AuthorizedRoot -DestinationPath $Path
  Assert-LizardSafeFsMutationCapability -AuthorizedRoot $AuthorizedRoot | Out-Null
  $lease = Open-LizardSafeDirectoryLease -AuthorizedRoot $AuthorizedRoot -Destination $safePath
  try {
    Invoke-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Context ([pscustomobject]@{ authorized_root = $AuthorizedRoot; path = $safePath; operation = 'delete' })
    if ($null -eq $ExpectedIdentity) {
      if ($Kind -eq 'File') { $lease.RemoveFile() } else { $lease.RemoveEmptyDirectory() }
    } else {
      foreach ($name in @('volume_id', 'mount_id', 'file_id')) {
        if ($ExpectedIdentity.PSObject.Properties.Name -notcontains $name -or [string]::IsNullOrWhiteSpace([string]$ExpectedIdentity.$name)) { throw (New-LizardSafeFsException -Code 'SAFEFS_IDENTITY_INVALID' -Message "Expected removal identity lacks '$name'." -Path $safePath -AuthorizedRoot $AuthorizedRoot) }
      }
      if (Test-LizardSafeFsWindows) {
        if ($Kind -eq 'File') { $lease.RemoveFileChecked([string]$ExpectedIdentity.volume_id, [string]$ExpectedIdentity.file_id) }
        else { $lease.RemoveEmptyDirectoryChecked([string]$ExpectedIdentity.volume_id, [string]$ExpectedIdentity.file_id) }
      } else {
        if ($Kind -eq 'File') { $lease.RemoveFileChecked([string]$ExpectedIdentity.volume_id, [string]$ExpectedIdentity.file_id, [string]$ExpectedIdentity.mount_id) }
        else { $lease.RemoveEmptyDirectoryChecked([string]$ExpectedIdentity.volume_id, [string]$ExpectedIdentity.file_id, [string]$ExpectedIdentity.mount_id) }
      }
    }
  } finally {
    if ($null -ne $lease) { $lease.Dispose() }
  }
}

Export-ModuleMember -Function @(
  'Add-SafeContent',
  'Assert-NoReparsePointEscape',
  'Assert-PathOutsideRoot',
  'ConvertTo-LizardCanonicalTemporaryPath',
  'ConvertTo-LizardFullPath',
  'Copy-SafeItem',
  'Get-SafeBytes',
  'Get-LizardSafeFsCapability',
  'Get-LizardSafeRootIdentity',
  'Get-SafeContent',
  'Get-SafeDirectoryEntries',
  'Get-SafeFileHash',
  'Get-SafeFileMetadata',
  'Get-SafeItemMetadata',
  'Get-LizardPathComparer',
  'Get-LizardPathComparison',
  'Initialize-SafeDirectory',
  'New-SafeDirectory',
  'Resolve-SafeRoot',
  'Resolve-LizardSafeTemporaryRoot',
  'Resolve-SafeTargetDestination',
  'Remove-SafeItem',
  'Set-SafeBytes',
  'Set-SafeContent',
  'Test-LizardPathWithinRoot'
)
