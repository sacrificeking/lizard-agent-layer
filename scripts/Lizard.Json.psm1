Set-StrictMode -Version 2.0

function New-LizardJsonException {
  param(
    [Parameter(Mandatory = $true)][string]$Code,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['json_code'] = $Code
  return $exception
}

function ConvertFrom-LizardJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)][AllowEmptyString()][string]$InputObject
  )

  process {
    $command = Get-Command -Name ConvertFrom-Json -Module Microsoft.PowerShell.Utility -ErrorAction Stop
    $supportsDateKind = $command.Parameters.ContainsKey('DateKind')
    if (-not $supportsDateKind -and [string]$PSVersionTable.PSEdition -ne 'Desktop') {
      throw (New-LizardJsonException -Code 'LIZARD_JSON_DATE_POLICY_UNSUPPORTED' -Message 'PowerShell Core must provide ConvertFrom-Json -DateKind String so JSON timestamps retain their declared string type. Use PowerShell 7.5 or newer.')
    }

    try {
      if ($supportsDateKind) {
        return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject -DateKind String
      }
      return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject
    } catch {
      throw (New-LizardJsonException -Code 'LIZARD_JSON_INVALID' -Message $_.Exception.Message)
    }
  }
}

Export-ModuleMember -Function 'ConvertFrom-LizardJson'
