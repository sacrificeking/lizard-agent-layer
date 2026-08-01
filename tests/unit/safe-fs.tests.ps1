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
  Assert-Equal ((Get-FileHash -LiteralPath $ordinaryFile -Algorithm SHA256).Hash.ToLowerInvariant()) (Get-SafeFileHash -AuthorizedRoot $authorized -Path $ordinaryFile) 'Safe hash must match the contained file SHA-256.'
  Assert-True ((Get-SafeContent -AuthorizedRoot $authorized -Path $ordinaryFile -Raw) -match 'ordinary canary') 'Safe content must read an ordinary contained file.'
  Assert-ThrowsCode { Get-SafeFileHash -AuthorizedRoot $authorized -Path (Join-Path $authorized 'missing.txt') | Out-Null } 'SAFEFS_FILE_MISSING' 'A missing safe-read source must fail with a stable code.'
  Assert-ThrowsCode { Get-SafeFileHash -AuthorizedRoot $authorized -Path $ordinaryDirectory | Out-Null } 'SAFEFS_NOT_FILE' 'A directory must not be accepted as a safe file.'

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
