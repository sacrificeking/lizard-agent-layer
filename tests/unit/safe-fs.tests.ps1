param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("safe-fs-unit-{0}" -f ([Guid]::NewGuid().ToString('N')))
$authorized = Join-Path $fixture 'authorized root'
$outside = Join-Path $fixture 'outside'
$link = Join-Path $authorized 'linked'
$fileLink = Join-Path $authorized 'linked-file.txt'
$ordinaryFile = Join-Path $authorized 'ordinary.txt'
$ordinaryDirectory = Join-Path $authorized 'ordinary-directory'
New-Item -ItemType Directory -Path $authorized -Force | Out-Null
New-Item -ItemType Directory -Path $outside -Force | Out-Null
New-Item -ItemType Directory -Path $ordinaryDirectory -Force | Out-Null
Set-Content -LiteralPath $ordinaryFile -Value 'ordinary canary' -Encoding UTF8

try {
  Assert-Equal '/private/var' (ConvertTo-LizardCanonicalTemporaryPath -Path '/var' -HostId 'macos-pwsh') 'The exact macOS /var temporary alias must canonicalize to /private/var.'
  Assert-Equal '/private/var/folders/fixture' (ConvertTo-LizardCanonicalTemporaryPath -Path '/var/folders/fixture' -HostId 'macos-pwsh') 'A macOS /var temporary descendant must canonicalize below /private/var.'
  Assert-Equal '/variant/fixture' (ConvertTo-LizardCanonicalTemporaryPath -Path '/variant/fixture' -HostId 'macos-pwsh') 'The macOS alias policy must be boundary-aware.'
  Assert-Equal '/private/var/folders/fixture' (ConvertTo-LizardCanonicalTemporaryPath -Path '/private/var/folders/fixture' -HostId 'macos-pwsh') 'An already canonical macOS temporary path must remain unchanged.'
  Assert-Equal (ConvertTo-LizardFullPath -Path '/var/folders/fixture') (ConvertTo-LizardCanonicalTemporaryPath -Path '/var/folders/fixture' -HostId 'linux-pwsh') 'Linux temporary paths must not receive the macOS alias policy.'
  Assert-Equal (ConvertTo-LizardCanonicalTemporaryPath -Path ([System.IO.Path]::GetTempPath())) (Resolve-LizardSafeTemporaryRoot) 'The current host temporary root must resolve through SafeFs using the same host canonicalization policy.'

  $nested = Join-Path $authorized 'missing\nested\file.txt'
  $resolved = Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $nested
  Assert-Equal ([System.IO.Path]::GetFullPath($nested)) $resolved 'Ordinary missing nested destinations must remain valid.'

  Assert-ThrowsCode { Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $authorized | Out-Null } 'SAFEFS_OUTSIDE_ROOT' 'Root equality must be explicit.'
  $allowedRoot = Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $authorized -AllowRoot
  Assert-Equal ([System.IO.Path]::GetFullPath($authorized)) $allowedRoot 'AllowRoot must permit exact root equality.'

  $escape = Join-Path $authorized '..\outside\escape.txt'
  Assert-ThrowsCode { Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $escape | Out-Null } 'SAFEFS_OUTSIDE_ROOT' 'Parent traversal must not escape the root.'

  New-DirectoryLink -Path $link -Target $outside
  Assert-ThrowsCode { Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath (Join-Path $link 'escaped.txt') | Out-Null } 'SAFEFS_REPARSE_POINT' 'A linked ancestor must be rejected.'
  Assert-ThrowsCode { Resolve-SafeRoot -Path $link -RequireExisting | Out-Null } 'SAFEFS_REPARSE_POINT' 'A linked authorized root must be rejected.'
  Assert-False (Test-Path -LiteralPath (Join-Path $outside 'escaped.txt')) 'Path validation must never create an escaped file.'

  $metadata = Get-SafeFileMetadata -AuthorizedRoot $authorized -Path $ordinaryFile
  Assert-Equal ([System.IO.Path]::GetFullPath($ordinaryFile)) $metadata.path 'Safe metadata must retain the validated full path.'
  Assert-True ([int64]$metadata.length -gt 0) 'Safe metadata must report the contained file length.'
  Assert-Equal 'file' ([string]$metadata.kind) 'Safe file metadata must bind the object kind.'
  $directoryMetadataBefore = Get-SafeItemMetadata -AuthorizedRoot $authorized -Path $ordinaryDirectory -Kind Directory
  Assert-Equal 'directory' ([string]$directoryMetadataBefore.kind) 'Safe directory metadata must bind the object kind.'
  Assert-False ([string]$directoryMetadataBefore.file_id -eq [string]$metadata.file_id) 'Distinct contained objects must have distinct physical identities.'
  $directoryIdentityBefore = [string]$directoryMetadataBefore.file_id
  [System.IO.Directory]::Delete($ordinaryDirectory)
  New-Item -ItemType Directory -Path $ordinaryDirectory -Force | Out-Null
  $directoryMetadataAfter = Get-SafeItemMetadata -AuthorizedRoot $authorized -Path $ordinaryDirectory -Kind Directory
  Assert-False ($directoryIdentityBefore -eq [string]$directoryMetadataAfter.file_id) 'Recreated directories must receive a different physical identity.'
  Assert-Equal ((Get-FileHash -LiteralPath $ordinaryFile -Algorithm SHA256).Hash.ToLowerInvariant()) (Get-SafeFileHash -AuthorizedRoot $authorized -Path $ordinaryFile) 'Safe hash must match the contained file SHA-256.'
  Assert-True ((Get-SafeContent -AuthorizedRoot $authorized -Path $ordinaryFile -Raw) -match 'ordinary canary') 'Safe content must read an ordinary contained file.'
  Assert-ThrowsCode { Get-SafeFileHash -AuthorizedRoot $authorized -Path (Join-Path $authorized 'missing.txt') | Out-Null } 'SAFEFS_FILE_MISSING' 'A missing safe-read source must fail with a stable code.'
  Assert-ThrowsCode { Get-SafeFileHash -AuthorizedRoot $authorized -Path $ordinaryDirectory | Out-Null } 'SAFEFS_NOT_FILE' 'A directory must not be accepted as a safe file.'

  $capability = Get-LizardSafeFsCapability -AuthorizedRoot $authorized
  Assert-True ([bool]$capability.available) 'A supported local filesystem must expose handle-bound SafeFs capability.'
  if (Test-LizardWindows) {
    Assert-Equal 'windows-handle-v1' ([string]$capability.backend) 'Windows mutations must use the handle-bound backend.'
  } else {
    Assert-True ([string]$capability.backend -in @('linux-openat-v1', 'macos-openat-v1')) 'Unix mutations must use the host-specific descriptor-relative backend.'
  }

  $identityPath = Join-Path $fixture 'identity-root'
  $identityOldPath = Join-Path $fixture 'identity-root-old'
  New-Item -ItemType Directory -Path $identityPath -Force | Out-Null
  $identityBefore = Get-LizardSafeRootIdentity -AuthorizedRoot $identityPath
  [System.IO.Directory]::Move($identityPath, $identityOldPath)
  New-Item -ItemType Directory -Path $identityPath -Force | Out-Null
  $identityAfter = Get-LizardSafeRootIdentity -AuthorizedRoot $identityPath
  Assert-Equal ([string]$identityBefore.volume_id) ([string]$identityAfter.volume_id) 'Recreated roots on the same volume must retain the volume identity.'
  Assert-False ([string]$identityBefore.file_id -eq [string]$identityAfter.file_id) 'Recreating the same root path must change its physical file identity.'

  $writeDirectory = Join-Path (Join-Path $authorized 'handle writes') 'nested'
  New-SafeDirectory -AuthorizedRoot $authorized -Path $writeDirectory | Out-Null
  Assert-True (Test-Path -LiteralPath $writeDirectory -PathType Container) 'Handle-bound directory creation must create each contained segment.'
  $initializedDirectory = Join-Path (Join-Path $fixture 'initialized') 'nested'
  Initialize-SafeDirectory -Path $initializedDirectory | Out-Null
  Assert-True (Test-Path -LiteralPath $initializedDirectory -PathType Container) 'Safe directory initialization must anchor creation at the nearest existing ancestor.'

  $writePath = Join-Path $writeDirectory 'content.txt'
  Set-SafeContent -AuthorizedRoot $authorized -Path $writePath -Value 'first'
  Add-SafeContent -AuthorizedRoot $authorized -Path $writePath -Value 'second'
  $written = Get-Content -LiteralPath $writePath -Raw
  Assert-True ($written -match 'first') 'Handle-bound set must persist initial content.'
  Assert-True ($written -match 'second') 'Handle-bound append must preserve existing content and add the new value.'

  $copySource = Join-Path $outside 'copy-source.txt'
  $copyDestination = Join-Path $writeDirectory 'copy-destination.txt'
  Set-Content -LiteralPath $copySource -Value 'copy-canary' -Encoding UTF8
  Copy-SafeItem -SourceAuthorizedRoot $outside -Source $copySource -AuthorizedRoot $authorized -Destination $copyDestination
  Assert-True ((Get-Content -LiteralPath $copyDestination -Raw) -match 'copy-canary') 'Handle-bound copy must read from an explicit source root and atomically create the contained destination.'
  Remove-SafeItem -AuthorizedRoot $authorized -Path $copyDestination -Kind File
  Assert-False (Test-Path -LiteralPath $copyDestination) 'Handle-bound file deletion must remove only the contained entry.'
  $emptyDirectory = Join-Path $writeDirectory 'empty-to-remove'
  New-SafeDirectory -AuthorizedRoot $authorized -Path $emptyDirectory | Out-Null
  Remove-SafeItem -AuthorizedRoot $authorized -Path $emptyDirectory -Kind EmptyDirectory
  Assert-False (Test-Path -LiteralPath $emptyDirectory) 'Handle-bound directory deletion must remove an empty contained directory.'
  Assert-Equal 0 @((Get-ChildItem -LiteralPath $writeDirectory -Force) | Where-Object { $_.Name -like '.lizard-stage-*' }).Count 'Successful atomic writes must not leave stage files behind.'

  if (-not (Test-LizardWindows)) {
    $outsideFile = Join-Path $outside 'source.txt'
    Set-Content -LiteralPath $outsideFile -Value 'outside canary' -Encoding UTF8
    New-Item -ItemType SymbolicLink -Path $fileLink -Target $outsideFile -Force | Out-Null
    Assert-ThrowsCode { Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $fileLink | Out-Null } 'SAFEFS_REPARSE_POINT' 'A file symlink must be rejected.'
    Assert-ThrowsCode { Get-SafeFileHash -AuthorizedRoot $authorized -Path $fileLink | Out-Null } 'SAFEFS_REPARSE_POINT' 'A linked final file must not be hashed.'
    Assert-ThrowsCode { Get-SafeContent -AuthorizedRoot $authorized -Path $fileLink -Raw | Out-Null } 'SAFEFS_REPARSE_POINT' 'A linked final file must not be read.'
  }

  Write-Host 'PASS safe-fs unit tests'
} finally {
  if (Test-Path -LiteralPath $fileLink) { [System.IO.File]::Delete($fileLink) }
  Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot -Links @($link)
}
