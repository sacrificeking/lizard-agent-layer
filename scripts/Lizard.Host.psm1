Set-StrictMode -Version 2.0

function Test-LizardWindowsHost {
  if ($PSVersionTable.ContainsKey('Platform')) { return $PSVersionTable['Platform'] -eq 'Win32NT' }
  return $true
}

function Get-LizardPowerShellHostPath {
  $process = Get-Process -Id $PID
  if ($process.Path -and (Test-Path -LiteralPath $process.Path -PathType Leaf)) { return $process.Path }
  $fallback = if (Test-LizardWindowsHost) { 'powershell.exe' } else { 'pwsh' }
  $command = Get-Command $fallback -ErrorAction SilentlyContinue
  if ($command -and $command.Source) { return $command.Source }
  throw "POWERSHELL_HOST_NOT_FOUND: Unable to resolve the current PowerShell executable."
}

function Get-LizardPowerShellFilePrefix {
  param(
    [ValidateSet('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')]
    [string]$HostId = (Get-LizardHostId)
  )
  $arguments = New-Object System.Collections.Generic.List[string]
  $arguments.Add('-NoProfile') | Out-Null
  if ($HostId -in @('windows-powershell-5.1', 'windows-pwsh')) {
    $arguments.Add('-ExecutionPolicy') | Out-Null
    $arguments.Add('Bypass') | Out-Null
  }
  $arguments.Add('-File') | Out-Null
  return @($arguments.ToArray())
}

function Get-LizardPowerShellCommandName {
  param(
    [ValidateSet('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')]
    [string]$HostId = (Get-LizardHostId),
    [switch]$ResolveCurrent
  )
  if ($ResolveCurrent -and $HostId -eq (Get-LizardHostId)) { return Get-LizardPowerShellHostPath }
  if ($HostId -eq 'windows-powershell-5.1') { return 'powershell.exe' }
  return 'pwsh'
}

function ConvertTo-LizardCommandDisplay {
  param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [string[]]$ArgumentList = @(),
    [ValidateSet('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')]
    [string]$HostId = (Get-LizardHostId)
  )
  function Quote-LizardDisplayArgument {
    param([string]$Value)
    if ($Value -match '^[A-Za-z0-9_./:\\,=+-]+$') { return $Value }
    return '"' + $Value.Replace('"', '`"') + '"'
  }
  return ((Quote-LizardDisplayArgument $Executable) + ' ' + ((@($ArgumentList) | ForEach-Object { Quote-LizardDisplayArgument ([string]$_) }) -join ' ')).Trim()
}

function New-LizardPowerShellFileInvocation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [string[]]$ArgumentList = @(),
    [ValidateSet('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')]
    [string]$HostId = (Get-LizardHostId),
    [switch]$ResolveCurrent
  )
  $executable = Get-LizardPowerShellCommandName -HostId $HostId -ResolveCurrent:$ResolveCurrent
  $argv = @((Get-LizardPowerShellFilePrefix -HostId $HostId) + @($ScriptPath) + @($ArgumentList))
  return [pscustomobject][ordered]@{
    host_id = $HostId
    executable = $executable
    argv = $argv
    display = ConvertTo-LizardCommandDisplay -Executable $executable -ArgumentList $argv -HostId $HostId
  }
}

function Get-LizardHostId {
  if (Test-LizardWindowsHost) {
    if ($PSVersionTable.PSEdition -eq 'Desktop') { return 'windows-powershell-5.1' }
    return 'windows-pwsh'
  }
  $isMac = Get-Variable -Name IsMacOS -ValueOnly -ErrorAction SilentlyContinue
  if ($isMac) { return 'macos-pwsh' }
  return 'linux-pwsh'
}

Export-ModuleMember -Function @(
  'Get-LizardPowerShellFilePrefix',
  'Get-LizardPowerShellCommandName',
  'Get-LizardPowerShellHostPath',
  'Get-LizardHostId',
  'ConvertTo-LizardCommandDisplay',
  'New-LizardPowerShellFileInvocation',
  'Test-LizardWindowsHost'
)
