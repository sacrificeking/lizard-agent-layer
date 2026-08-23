Set-StrictMode -Version 2.0

if (-not ('Lizard.AgentLayer.Native.WindowsHandleFs' -as [type])) {
  Add-Type -Path (Join-Path $PSScriptRoot 'native\Lizard.WindowsHandleFs.cs')
}

function Get-LizardWindowsHandleCapability {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)

  $fullRoot = [System.IO.Path]::GetFullPath($AuthorizedRoot)
  $fileSystem = $null
  try {
    $driveRoot = [System.IO.Path]::GetPathRoot($fullRoot)
    if ([string]::IsNullOrWhiteSpace($driveRoot) -or $driveRoot.StartsWith('\\')) {
      throw 'SAFEFS_HANDLE_MUTATION_UNAVAILABLE: UNC and non-drive paths are not supported.'
    }
    $drive = New-Object System.IO.DriveInfo $driveRoot
    $fileSystem = [string]$drive.DriveFormat
    if ($fileSystem -notin @('NTFS', 'ReFS')) {
      throw ("SAFEFS_HANDLE_MUTATION_UNAVAILABLE: Filesystem '{0}' is not supported by windows-handle-v1." -f $fileSystem)
    }

    $probeDestination = Join-Path $fullRoot '.lizard-capability-probe'
    $lease = [Lizard.AgentLayer.Native.WindowsHandleFs]::OpenParent($fullRoot, $probeDestination)
    $lease.Dispose()
    return [pscustomobject][ordered]@{
      schema_version = 1
      host = if ([string]$PSVersionTable.PSEdition -eq 'Desktop') { 'windows-powershell-5.1' } else { 'windows-pwsh' }
      available = $true
      assurance = 'handle-bound-no-follow'
      backend = 'windows-handle-v1'
      authorized_root = $fullRoot
      filesystem = $fileSystem
      primitives = [ordered]@{
        ancestor_handles = $true
        terminal_no_follow = $true
        descriptor_identity = $true
        mount_identity = $true
        atomic_replace = $true
        atomic_create_new = $true
        relative_delete = $true
      }
      reason_code = $null
    }
  } catch {
    return [pscustomobject][ordered]@{
      schema_version = 1
      host = if ([string]$PSVersionTable.PSEdition -eq 'Desktop') { 'windows-powershell-5.1' } else { 'windows-pwsh' }
      available = $false
      assurance = 'unavailable'
      backend = 'unavailable'
      authorized_root = $fullRoot
      filesystem = $fileSystem
      primitives = [ordered]@{
        ancestor_handles = $false
        terminal_no_follow = $false
        descriptor_identity = $false
        mount_identity = $false
        atomic_replace = $false
        atomic_create_new = $false
        relative_delete = $false
      }
      reason_code = 'SAFEFS_HANDLE_MUTATION_UNAVAILABLE'
    }
  }
}

function Open-LizardWindowsDirectoryLease {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Destination
  )
  return [Lizard.AgentLayer.Native.WindowsHandleFs]::OpenParent($AuthorizedRoot, $Destination)
}

function Get-LizardWindowsRootIdentity {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$AuthorizedRoot)
  return [Lizard.AgentLayer.Native.WindowsHandleFs]::GetRootIdentity([System.IO.Path]::GetFullPath($AuthorizedRoot))
}

function New-LizardWindowsSafeDirectory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$AuthorizedRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )
  [Lizard.AgentLayer.Native.WindowsHandleFs]::EnsureDirectory($AuthorizedRoot, $Path)
}

Export-ModuleMember -Function @(
  'Get-LizardWindowsHandleCapability',
  'Get-LizardWindowsRootIdentity',
  'New-LizardWindowsSafeDirectory',
  'Open-LizardWindowsDirectoryLease'
)
