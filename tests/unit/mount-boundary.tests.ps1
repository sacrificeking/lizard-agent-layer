param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.MountBoundary.psm1') -Force

$mountInfo = @(
  '36 25 0:32 / / rw,relatime - ext4 /dev/root rw',
  '40 36 0:32 /outside /sandbox/allowed/bind rw,relatime - ext4 /dev/root rw,bind',
  '41 36 0:99 / /sandbox/allowed/device rw,nosuid - tmpfs tmpfs rw',
  '42 36 0:32 /space\040root /sandbox/allowed/space\040mount rw,relatime - ext4 /dev/root rw,bind',
  '43 36 0:32 /prefix /sandbox/allow rw,relatime - ext4 /dev/root rw,bind'
)

$records = @(ConvertFrom-LizardLinuxMountInfo -Lines $mountInfo)
Assert-Equal 5 $records.Count 'Every valid mountinfo record must be parsed.'
Assert-Equal '/space root' ([string]$records[3].root) 'Mountinfo root escapes must be decoded exactly once.'
Assert-Equal '/sandbox/allowed/space mount' ([string]$records[3].mount_point) 'Mountpoint escapes must be decoded exactly once.'

$ordinary = Get-LizardMountIdentity -Path '/sandbox/allowed/plain/file.txt' -MountRecords $records
Assert-Equal 36 ([int]$ordinary.mount_id) 'Ordinary descendants must resolve to the authorized filesystem mount.'
Assert-Equal '0:32' ([string]$ordinary.device) 'Ordinary descendants must retain device identity.'
Assert-Equal 36 ([int](Get-LizardMountIdentity -Path '/sandbox/allowed-prefix/file.txt' -MountRecords $records).mount_id) 'A sibling path prefix must not match a shorter mountpoint name.'

$bind = Get-LizardMountIdentity -Path '/sandbox/allowed/bind/file.txt' -MountRecords $records
Assert-Equal 40 ([int]$bind.mount_id) 'The longest matching bind-mount identity must win.'
Assert-Equal '0:32' ([string]$bind.device) 'Same-device bind mounts must remain distinguishable by mount ID.'

$allowed = Assert-LizardMountBoundary -AuthorizedRoot '/sandbox/allowed' -DestinationPath '/sandbox/allowed/plain/file.txt' -MountRecords $records -Platform Linux
Assert-Equal 36 ([int]$allowed.root_identity.mount_id) 'Ordinary paths must preserve root mount identity.'

Assert-ThrowsCode {
  Assert-LizardMountBoundary -AuthorizedRoot '/sandbox/allowed' -DestinationPath '/sandbox/allowed/bind/file.txt' -MountRecords $records -Platform Linux | Out-Null
} 'SAFEFS_MOUNT_BOUNDARY' 'A same-device bind mount below the authorized root must fail closed.'

Assert-ThrowsCode {
  Assert-LizardMountBoundary -AuthorizedRoot '/sandbox/allowed' -DestinationPath '/sandbox/allowed/device/file.txt' -MountRecords $records -Platform Linux | Out-Null
} 'SAFEFS_DEVICE_BOUNDARY' 'A cross-device mount below the authorized root must fail closed.'

$mountedRoot = Assert-LizardMountBoundary -AuthorizedRoot '/sandbox/allowed/bind' -DestinationPath '/sandbox/allowed/bind/nested/file.txt' -MountRecords $records -Platform Linux
Assert-Equal 40 ([int]$mountedRoot.root_identity.mount_id) 'The authorized root may itself be a mountpoint.'

Assert-ThrowsCode {
  Assert-LizardMountBoundary -AuthorizedRoot '/sandbox/allowed' -DestinationPath '/sandbox/allowed/plain/file.txt' -MountRecords @() -Platform Linux | Out-Null
} 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' 'Missing mount identity data must fail closed on Unix.'

Assert-ThrowsCode {
  Get-LizardMountIdentity -Path '/sandbox/allowed/plain/file.txt' -MountRecords @(
    [pscustomobject]@{ mount_id = ''; device = '0:32'; mount_point = '/' }
  ) | Out-Null
} 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' 'A selected record without a mount identity must fail closed.'

Assert-ThrowsCode {
  ConvertFrom-LizardLinuxMountInfo -Lines @('malformed mountinfo') | Out-Null
} 'SAFEFS_MOUNT_IDENTITY_UNAVAILABLE' 'Malformed mountinfo must fail closed.'

$literalEscape = @(ConvertFrom-LizardLinuxMountInfo -Lines @('50 36 0:32 /literal\134040 /sandbox/literal\134040 rw - ext4 /dev/root rw'))
Assert-Equal '/literal\040' ([string]$literalEscape[0].root) 'A literal escaped backslash must not be decoded twice.'

$macRecords = @(
  [pscustomobject]@{ mount_id = 'macos:/'; device = '100'; mount_point = '/' },
  [pscustomobject]@{ mount_id = 'macos:/Volumes/bind'; device = '100'; mount_point = '/Volumes/bind' },
  [pscustomobject]@{ mount_id = 'macos:/Volumes/device'; device = '200'; mount_point = '/Volumes/device' }
)
Assert-ThrowsCode {
  Assert-LizardMountBoundary -AuthorizedRoot '/' -DestinationPath '/Volumes/bind/file.txt' -MountRecords $macRecords -Platform MacOS | Out-Null
} 'SAFEFS_MOUNT_BOUNDARY' 'macOS same-device mounted roots must fail closed.'
Assert-ThrowsCode {
  Assert-LizardMountBoundary -AuthorizedRoot '/' -DestinationPath '/Volumes/device/file.txt' -MountRecords $macRecords -Platform MacOS | Out-Null
} 'SAFEFS_DEVICE_BOUNDARY' 'macOS cross-device mounted roots must fail closed.'

Write-Host 'PASS tests\unit\mount-boundary.tests.ps1'
