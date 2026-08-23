param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$previousSafeFsTesting = [Environment]::GetEnvironmentVariable('LIZARD_SAFEFS_TESTING', 'Process')
[Environment]::SetEnvironmentVariable('LIZARD_SAFEFS_TESTING', '1', 'Process')
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("handle-bound-mutation-{0}" -f ([Guid]::NewGuid().ToString('N')))
$authorized = Join-Path $fixture 'authorized'
$outside = Join-Path $fixture 'outside'
$raceParent = Join-Path $authorized 'race-parent'
$movedRaceParent = Join-Path $authorized 'race-parent-original'
$readParent = Join-Path $authorized 'read-parent'
$movedReadParent = Join-Path $authorized 'read-parent-original'
$copyParent = Join-Path $authorized 'copy-parent'
$movedCopyParent = Join-Path $authorized 'copy-parent-original'
$deleteParent = Join-Path $authorized 'delete-parent'
$movedDeleteParent = Join-Path $authorized 'delete-parent-original'
New-Item -ItemType Directory -Path $authorized -Force | Out-Null
New-Item -ItemType Directory -Path $outside -Force | Out-Null

function New-TestHardLink {
  param([string]$Path, [string]$Target)
  New-Item -ItemType HardLink -Path $Path -Target $Target -Force | Out-Null
}

try {
  $outsideCanary = Join-Path $outside 'hardlink-canary.txt'
  $insideHardLink = Join-Path $authorized 'hardlink-target.txt'
  Set-Content -LiteralPath $outsideCanary -Value 'outside-canary' -Encoding UTF8
  New-TestHardLink -Path $insideHardLink -Target $outsideCanary

  $hardLinkRejected = $false
  try {
    Set-SafeContent -AuthorizedRoot $authorized -Path $insideHardLink -Value 'contained-replacement'
  } catch {
    if ($_.Exception.Message -notmatch 'SAFEFS_REPARSE_POINT') { throw }
    $hardLinkRejected = $true
  }

  Assert-True ((Get-Content -LiteralPath $outsideCanary -Raw) -match 'outside-canary') 'Set-SafeContent must reject the hard link or replace only its contained directory entry; it must never modify the outside inode.'
  if (-not $hardLinkRejected) {
    Assert-True ((Get-Content -LiteralPath $insideHardLink -Raw) -match 'contained-replacement') 'An accepted contained hard-link destination must be replaced atomically.'
  }

  $capabilityCommand = Get-Command Get-LizardSafeFsCapability -ErrorAction SilentlyContinue
  Assert-True ($null -ne $capabilityCommand) 'SafeFs must expose an executable host capability contract.'
  $capability = Get-LizardSafeFsCapability -AuthorizedRoot $authorized
  Assert-True ([bool]$capability.available) 'A supported local test filesystem must provide handle-bound mutation capability.'
  Assert-Equal 'handle-bound-no-follow' ([string]$capability.assurance) 'Available capability must claim only the handle-bound no-follow assurance level.'
  foreach ($primitive in @('ancestor_handles', 'terminal_no_follow', 'descriptor_identity', 'mount_identity', 'atomic_replace', 'atomic_create_new', 'relative_delete')) {
    Assert-True ([bool]$capability.primitives.$primitive) "Available capability must prove primitive '$primitive'."
  }

  $safeFsModule = Get-Module Lizard.SafeFs
  $hasPrivateTestHook = & $safeFsModule { [bool](Get-Command Set-LizardSafeFsTestHook -ErrorAction SilentlyContinue) }
  Assert-True $hasPrivateTestHook 'SafeFs adversarial tests require a private, test-gated synchronization hook.'

  New-Item -ItemType Directory -Path $raceParent -Force | Out-Null
  $raceState = [hashtable]::Synchronized(@{ invoked = $false; swapped = $false })
  $raceAction = {
    param($Context)
    $raceState.invoked = $true
    try {
      [System.IO.Directory]::Move($raceParent, $movedRaceParent)
      New-DirectoryLink -Path $raceParent -Target $outside
      $raceState.swapped = $true
    } catch [System.IO.IOException] {
      $raceState.swapped = $false
    } catch [System.UnauthorizedAccessException] {
      $raceState.swapped = $false
    }
  }.GetNewClosure()

  & $safeFsModule { param($Action) Set-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Action $Action } $raceAction
  try {
    Set-SafeContent -AuthorizedRoot $authorized -Path (Join-Path $raceParent 'race.txt') -Value 'contained-race-write'
  } finally {
    & $safeFsModule { Clear-LizardSafeFsTestHooks }
  }

  Assert-True ([bool]$raceState.invoked) 'The deterministic race barrier must execute after the destination parent handle is acquired.'
  Assert-False (Test-Path -LiteralPath (Join-Path $outside 'race.txt')) 'An ancestor swap after parent acquisition must never redirect a write outside the authorized root.'
  Assert-Equal 0 @((Get-ChildItem -LiteralPath $outside -Force) | Where-Object { $_.Name -like '.lizard-stage-*' }).Count 'A synchronized ancestor swap must never create even a temporary stage file outside the authorized root.'
  $originalRacePath = Join-Path $raceParent 'race.txt'
  $renamedRacePath = Join-Path $movedRaceParent 'race.txt'
  Assert-True ((Test-Path -LiteralPath $originalRacePath -PathType Leaf) -or (Test-Path -LiteralPath $renamedRacePath -PathType Leaf)) 'The mutation must remain bound to the originally acquired contained parent.'

  New-Item -ItemType Directory -Path $readParent -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $readParent 'evidence.txt') -Value 'inside-evidence' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $outside 'evidence.txt') -Value 'outside-secret!' -Encoding UTF8
  $readRaceState = [hashtable]::Synchronized(@{ invoked = $false; swapped = $false })
  $readRaceAction = {
    param($Context)
    $readRaceState.invoked = $true
    try {
      [System.IO.Directory]::Move($readParent, $movedReadParent)
      New-DirectoryLink -Path $readParent -Target $outside
      $readRaceState.swapped = $true
    } catch [System.IO.IOException] {
      $readRaceState.swapped = $false
    } catch [System.UnauthorizedAccessException] {
      $readRaceState.swapped = $false
    }
  }.GetNewClosure()

  & $safeFsModule { param($Action) Set-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Action $Action } $readRaceAction
  try {
    $protectedRead = Get-SafeContent -AuthorizedRoot $authorized -Path (Join-Path $readParent 'evidence.txt') -Raw
  } finally {
    & $safeFsModule { Clear-LizardSafeFsTestHooks }
  }
  Assert-True ([bool]$readRaceState.invoked) 'The deterministic read barrier must execute after the source parent handle is acquired.'
  Assert-True ($protectedRead -match 'inside-evidence') 'A protected read must remain bound to the originally acquired contained parent.'
  Assert-False ($protectedRead -match 'outside-secret') 'A synchronized ancestor swap must never redirect a protected read outside the authorized root.'

  New-Item -ItemType Directory -Path $copyParent -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $copyParent 'source.txt') -Value 'inside-copy' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $outside 'source.txt') -Value 'outside-copy-secret' -Encoding UTF8
  $copyRaceAction = {
    param($Context)
    if ([string]$Context.path -ne (Join-Path $copyParent 'source.txt')) { return }
    try {
      [System.IO.Directory]::Move($copyParent, $movedCopyParent)
      New-DirectoryLink -Path $copyParent -Target $outside
    } catch [System.IO.IOException] { }
      catch [System.UnauthorizedAccessException] { }
  }.GetNewClosure()
  & $safeFsModule { param($Action) Set-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Action $Action } $copyRaceAction
  try {
    $copyRaceDestination = Join-Path $authorized 'copy-race-result.txt'
    Copy-SafeItem -SourceAuthorizedRoot $authorized -Source (Join-Path $copyParent 'source.txt') -AuthorizedRoot $authorized -Destination $copyRaceDestination
  } finally {
    & $safeFsModule { Clear-LizardSafeFsTestHooks }
  }
  $copyRaceContent = Get-Content -LiteralPath $copyRaceDestination -Raw
  Assert-True ($copyRaceContent -match 'inside-copy') 'A copy source must remain bound to its originally acquired contained parent.'
  Assert-False ($copyRaceContent -match 'outside-copy-secret') 'A source ancestor swap must never redirect copy input outside the authorized root.'

  New-Item -ItemType Directory -Path $deleteParent -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $deleteParent 'remove.txt') -Value 'contained-delete' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $outside 'remove.txt') -Value 'outside-delete-canary' -Encoding UTF8
  $deleteRaceState = [hashtable]::Synchronized(@{ invoked = $false; swapped = $false })
  $deleteRaceAction = {
    param($Context)
    $deleteRaceState.invoked = $true
    try {
      [System.IO.Directory]::Move($deleteParent, $movedDeleteParent)
      New-DirectoryLink -Path $deleteParent -Target $outside
      $deleteRaceState.swapped = $true
    } catch [System.IO.IOException] { }
      catch [System.UnauthorizedAccessException] { }
  }.GetNewClosure()
  & $safeFsModule { param($Action) Set-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Action $Action } $deleteRaceAction
  try {
    Remove-SafeItem -AuthorizedRoot $authorized -Path (Join-Path $deleteParent 'remove.txt') -Kind File
  } finally {
    & $safeFsModule { Clear-LizardSafeFsTestHooks }
  }
  Assert-True ([bool]$deleteRaceState.invoked) 'The deterministic delete barrier must execute after the destination parent handle is acquired.'
  $originalDeletePath = if ($deleteRaceState.swapped) { Join-Path $movedDeleteParent 'remove.txt' } else { Join-Path $deleteParent 'remove.txt' }
  Assert-False (Test-Path -LiteralPath $originalDeletePath) 'Handle-bound deletion must remove the entry from the originally acquired contained parent.'
  Assert-True ((Get-Content -LiteralPath (Join-Path $outside 'remove.txt') -Raw) -match 'outside-delete-canary') 'A delete ancestor swap must not remove or modify the outside canary.'

  $terminalParent = Join-Path $authorized 'terminal-delete'
  $terminalPath = Join-Path $terminalParent 'planned.txt'
  $terminalOriginal = Join-Path $terminalParent 'planned-original.txt'
  $terminalReplacement = Join-Path $terminalParent 'replacement.txt'
  New-Item -ItemType Directory -Path $terminalParent -Force | Out-Null
  Set-Content -LiteralPath $terminalPath -Value 'planned-terminal-canary' -Encoding UTF8
  Set-Content -LiteralPath $terminalReplacement -Value 'replacement-terminal-canary' -Encoding UTF8
  $expectedTerminalIdentity = Get-SafeItemMetadata -AuthorizedRoot $authorized -Path $terminalPath -Kind File
  $terminalSwapAction = {
    param($Context)
    if ([string]$Context.operation -ne 'delete') { return }
    [System.IO.File]::Move($terminalPath, $terminalOriginal)
    [System.IO.File]::Move($terminalReplacement, $terminalPath)
  }.GetNewClosure()
  & $safeFsModule { param($Action) Set-LizardSafeFsTestHook -Event 'after-parent-handle-acquired' -Action $Action } $terminalSwapAction
  try {
    Assert-ThrowsCode { Remove-SafeItem -AuthorizedRoot $authorized -Path $terminalPath -Kind File -ExpectedIdentity $expectedTerminalIdentity } 'SAFEFS_IDENTITY_MISMATCH' 'Checked deletion must reject a synchronized terminal replacement.'
  } finally {
    & $safeFsModule { Clear-LizardSafeFsTestHooks }
  }
  Assert-True ((Get-Content -LiteralPath $terminalPath -Raw) -match 'replacement-terminal-canary') 'Identity mismatch must preserve the raced replacement entry.'
  Assert-True ((Get-Content -LiteralPath $terminalOriginal -Raw) -match 'planned-terminal-canary') 'Identity mismatch must not delete the originally approved object after it moved.'

  Write-Host 'PASS handle-bound mutation behavior; validating capability schema.'
  $capabilityPath = Join-Path $fixture 'capability.json'
  $capability | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $capabilityPath -Encoding UTF8
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/safe-fs-capability.schema.json' -InstancePath $capabilityPath -Message 'Safe filesystem capability must satisfy its executable schema.'

  Write-Host 'PASS tests\adversarial\handle-bound-mutation.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $raceParent) {
    $raceItem = Get-Item -LiteralPath $raceParent -Force
    if ($raceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Remove-DirectoryLink -Path $raceParent }
  }
  if (Test-Path -LiteralPath $readParent) {
    $readItem = Get-Item -LiteralPath $readParent -Force
    if ($readItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Remove-DirectoryLink -Path $readParent }
  }
  foreach ($linkedParent in @($copyParent, $deleteParent)) {
    if (Test-Path -LiteralPath $linkedParent) {
      $linkedItem = Get-Item -LiteralPath $linkedParent -Force
      if ($linkedItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Remove-DirectoryLink -Path $linkedParent }
    }
  }
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
  [Environment]::SetEnvironmentVariable('LIZARD_SAFEFS_TESTING', $previousSafeFsTesting, 'Process')
}
