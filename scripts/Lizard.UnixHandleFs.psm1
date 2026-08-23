Set-StrictMode -Version 2.0

if (-not ('Lizard.AgentLayer.Native.UnixHandleFs' -as [type])) {
  Add-Type -Path (Join-Path $PSScriptRoot 'native/Lizard.UnixHandleFs.cs')
}

function Get-LizardUnixHandleCapability {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)

  $fullRoot = [System.IO.Path]::GetFullPath($AuthorizedRoot)
  $hostId = if ($IsMacOS) { 'macos-pwsh' } else { 'linux-pwsh' }
  $backend = if ($IsMacOS) { 'macos-openat-v1' } else { 'linux-openat-v1' }
  try {
    if ($PSVersionTable.PSVersion -lt [Version]'7.5.0') { throw 'SAFEFS_CAPABILITY_UNAVAILABLE: PowerShell 7.5 or newer is required.' }
    $identity = [Lizard.AgentLayer.Native.UnixHandleFs]::GetRootIdentity($fullRoot)
    if ([int64]$identity.MountId -eq 0) { throw 'SAFEFS_CAPABILITY_UNAVAILABLE: Native mount identity is unavailable.' }
    return [pscustomobject][ordered]@{
      schema_version = 1; host = $hostId; available = $true; assurance = 'handle-bound-no-follow'; backend = $backend
      authorized_root = $fullRoot; filesystem = $identity.MountPoint
      primitives = [ordered]@{ ancestor_handles = $true; terminal_no_follow = $true; descriptor_identity = $true; mount_identity = $true; atomic_replace = $true; atomic_create_new = $true; relative_delete = $true }
      reason_code = $null
    }
  } catch {
    return [pscustomobject][ordered]@{
      schema_version = 1; host = $hostId; available = $false; assurance = 'unavailable'; backend = 'unavailable'
      authorized_root = $fullRoot; filesystem = $null
      primitives = [ordered]@{ ancestor_handles = $false; terminal_no_follow = $false; descriptor_identity = $false; mount_identity = $false; atomic_replace = $false; atomic_create_new = $false; relative_delete = $false }
      reason_code = 'SAFEFS_HANDLE_MUTATION_UNAVAILABLE'
    }
  }
}

function Open-LizardUnixDirectoryLease {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot, [Parameter(Mandatory = $true)][string]$Destination)
  return [Lizard.AgentLayer.Native.UnixHandleFs]::OpenParent($AuthorizedRoot, $Destination)
}

function New-LizardUnixSafeDirectory {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot, [Parameter(Mandatory = $true)][string]$Path)
  [Lizard.AgentLayer.Native.UnixHandleFs]::EnsureDirectory($AuthorizedRoot, $Path)
}

function Get-LizardUnixRootIdentity {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)
  return [Lizard.AgentLayer.Native.UnixHandleFs]::GetRootIdentity($AuthorizedRoot)
}

Export-ModuleMember -Function @('Get-LizardUnixHandleCapability', 'Get-LizardUnixRootIdentity', 'New-LizardUnixSafeDirectory', 'Open-LizardUnixDirectoryLease')
