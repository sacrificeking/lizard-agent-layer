Set-StrictMode -Version 2.0

function Test-LizardWindowsHost {
  if ($PSVersionTable.PSObject.Properties.Name -contains 'Platform') { return $PSVersionTable.Platform -eq 'Win32NT' }
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
  $arguments = New-Object System.Collections.Generic.List[string]
  $arguments.Add('-NoProfile') | Out-Null
  if (Test-LizardWindowsHost) {
    $arguments.Add('-ExecutionPolicy') | Out-Null
    $arguments.Add('Bypass') | Out-Null
  }
  $arguments.Add('-File') | Out-Null
  return @($arguments.ToArray())
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
  'Get-LizardPowerShellHostPath',
  'Get-LizardHostId',
  'Test-LizardWindowsHost'
)
