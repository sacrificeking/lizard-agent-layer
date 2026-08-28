param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$EnablePrivilegedFixtures
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.SafeFs.psm1') -Force

if (Test-LizardWindows) {
  Write-Host 'SKIP tests\adversarial\mount-boundary-fixtures.tests.ps1: Unix mount fixtures are not applicable on Windows.'
  return
}

$isMac = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
if ($isMac) {
  Write-Host 'SKIP tests\adversarial\mount-boundary-fixtures.tests.ps1: Linux bind-mount fixtures are not applicable on macOS.'
  return
}

if (-not $EnablePrivilegedFixtures) {
  Write-Host 'SKIP tests\adversarial\mount-boundary-fixtures.tests.ps1: pass -EnablePrivilegedFixtures on an isolated Linux runner.'
  return
}

$sudo = Get-Command sudo -ErrorAction SilentlyContinue
if ($null -eq $sudo -or [string]::IsNullOrWhiteSpace([string]$sudo.Source)) {
  throw 'MOUNT_FIXTURE_SUDO_REQUIRED: sudo is required for the explicitly enabled Linux mount fixtures.'
}

function Invoke-Sudo {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)
  $global:LASTEXITCODE = 0
  $output = & $sudo.Source '-n' @Arguments 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "MOUNT_FIXTURE_COMMAND_FAILED: sudo -n $($Arguments -join ' ')`n$output"
  }
  return $output
}

$tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd([char[]]@('/', '\'))
$fixture = Join-Path $tempRoot ("lizard-mount-boundary-{0}" -f ([Guid]::NewGuid().ToString('N')))
$authorized = Join-Path $fixture 'authorized'
$outside = Join-Path $fixture 'outside'
$bindTarget = Join-Path $authorized 'bind'
$deviceTarget = Join-Path $authorized 'device'
$bindMounted = $false
$deviceMounted = $false
$cleanupFailures = New-Object System.Collections.Generic.List[string]

New-Item -ItemType Directory -Path $bindTarget -Force | Out-Null
New-Item -ItemType Directory -Path $deviceTarget -Force | Out-Null
New-Item -ItemType Directory -Path $outside -Force | Out-Null
Set-Content -LiteralPath (Join-Path $outside 'outside-canary.txt') -Value 'outside canary' -Encoding UTF8

try {
  $ordinary = Join-Path (Join-Path $authorized 'ordinary') 'file.txt'
  $resolved = Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath $ordinary
  Assert-Equal ([System.IO.Path]::GetFullPath($ordinary)) $resolved 'Ordinary Linux descendants must remain valid.'

  $null = Invoke-Sudo -Arguments @('mount', '--bind', $outside, $bindTarget)
  $bindMounted = $true
  Assert-ThrowsCode {
    Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath (Join-Path $bindTarget 'escaped.txt') | Out-Null
  } 'SAFEFS_MOUNT_BOUNDARY' 'A same-device Linux bind mount must fail closed.'
  Assert-ThrowsCode {
    Set-SafeContent -AuthorizedRoot $authorized -Path (Join-Path $bindTarget 'escaped.txt') -Value 'must not escape'
  } 'SAFEFS_MOUNT_BOUNDARY' 'Safe writes must reject a same-device Linux bind mount.'
  Assert-False (Test-Path -LiteralPath (Join-Path $outside 'escaped.txt')) 'Rejected bind-mount writes must not reach the outside source.'

  $null = Invoke-Sudo -Arguments @('mount', '-t', 'tmpfs', '-o', 'size=1m,mode=777', 'lizard-wp01b', $deviceTarget)
  $deviceMounted = $true
  Assert-ThrowsCode {
    Resolve-SafeTargetDestination -AuthorizedRoot $authorized -DestinationPath (Join-Path $deviceTarget 'escaped.txt') | Out-Null
  } 'SAFEFS_DEVICE_BOUNDARY' 'A nested cross-device tmpfs mount must fail closed.'

  Write-Host 'PASS tests\adversarial\mount-boundary-fixtures.tests.ps1'
} finally {
  if ($deviceMounted) {
    try { $null = Invoke-Sudo -Arguments @('umount', $deviceTarget) }
    catch { $cleanupFailures.Add($_.Exception.Message) | Out-Null }
  }
  if ($bindMounted) {
    try { $null = Invoke-Sudo -Arguments @('umount', $bindTarget) }
    catch { $cleanupFailures.Add($_.Exception.Message) | Out-Null }
  }
  if ($cleanupFailures.Count -eq 0 -and (Test-Path -LiteralPath $fixture)) {
    Clear-TestDirectory -Path $fixture -AllowedRoot $tempRoot
  }
  if ($cleanupFailures.Count -gt 0) {
    throw "MOUNT_FIXTURE_CLEANUP_FAILED: $($cleanupFailures -join ' | ')"
  }
}
