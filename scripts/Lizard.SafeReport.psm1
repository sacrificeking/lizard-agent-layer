$ErrorActionPreference = 'Stop'

function Get-LizardRedactionCategory {
  param([AllowEmptyString()][string]$Value)
  if ($Value -match '(?i)-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----') { return 'private-key' }
  if ($Value -match '(?i)(?:api[_-]?key|password|passwd|secret|token|authorization)\s*[:=]\s*\S+') { return 'credential' }
  if ($Value -match '(?i)\bsk-[A-Za-z0-9_-]{8,}\b') { return 'credential' }
  if ($Value -match '\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b') { return 'credential' }
  if ($Value -match '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b') { return 'personal-email' }
  if ($Value -match '(?i)(?:^|[\s"''])[A-Z]:\\[^\r\n]*') { return 'absolute-path' }
  if ($Value -match '(?:^|[\s"''])/(?:home|Users|private|var|tmp)/[^\r\n]*') { return 'absolute-path' }
  if ($Value -match '[\r\n]') { return 'multiline-text' }
  $commandPattern = '(?i)(?:^|\s)(?:pwsh|powershell|cmd(?:\.exe)?|bash|sh|' + 'c' + 'url|' + 'w' + 'get|Invoke-' + 'WebRequest|Remove-Item)(?:\s|$)'
  if ($Value -match $commandPattern) { return 'command-text' }
  if ($Value -match '[^\x00-\x7F]') { return 'non-ascii-text' }
  return $null
}

function Assert-LizardOpaqueIdentifier {
  param(
    [AllowNull()][string]$Value,
    [Parameter(Mandatory)][string]$ErrorCode,
    [int]$MaximumLength = 200,
    [switch]$AllowNull
  )
  if ([string]::IsNullOrWhiteSpace($Value)) {
    if ($AllowNull) { return }
    throw "$ErrorCode`: opaque identifier is required."
  }
  if ($Value.Length -gt $MaximumLength -or $Value -notmatch '^[A-Za-z0-9][A-Za-z0-9._/@:+-]*$' -or (Get-LizardRedactionCategory -Value $Value)) {
    throw "$ErrorCode`: value must be an opaque ASCII identifier."
  }
}

function Protect-LizardReportValue {
  param(
    $Value,
    [string]$Path,
    [System.Collections.Generic.List[string]]$RedactedPaths
  )
  if ($null -eq $Value) { return $null }
  if ($Value -is [string]) {
    $category = Get-LizardRedactionCategory -Value ([string]$Value)
    if ($category) {
      if (-not $RedactedPaths.Contains($Path)) { $RedactedPaths.Add($Path) | Out-Null }
      return "[REDACTED:$category]"
    }
    if ($Value.Length -gt 2000) {
      if (-not $RedactedPaths.Contains($Path)) { $RedactedPaths.Add($Path) | Out-Null }
      return '[REDACTED:oversized-text]'
    }
    return [string]$Value
  }
  if ($Value -is [System.Collections.IDictionary]) {
    $copy = [ordered]@{}
    foreach ($key in @($Value.Keys)) {
      $childPath = if ($Path) { "$Path.$key" } else { [string]$key }
      $copy[[string]$key] = Protect-LizardReportValue -Value $Value[$key] -Path $childPath -RedactedPaths $RedactedPaths
    }
    return $copy
  }
  if ($Value -is [System.Management.Automation.PSCustomObject]) {
    $copy = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties)) {
      $childPath = if ($Path) { "$Path.$($property.Name)" } else { [string]$property.Name }
      $copy[[string]$property.Name] = Protect-LizardReportValue -Value $property.Value -Path $childPath -RedactedPaths $RedactedPaths
    }
    return $copy
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    $items = New-Object System.Collections.Generic.List[object]
    $index = 0
    foreach ($item in $Value) {
      $items.Add((Protect-LizardReportValue -Value $item -Path "$Path[$index]" -RedactedPaths $RedactedPaths)) | Out-Null
      $index++
    }
    return , @($items.ToArray())
  }
  return $Value
}

function Protect-LizardReportDocument {
  param([Parameter(Mandatory)]$Document)
  $redactedPaths = New-Object System.Collections.Generic.List[string]
  $safe = Protect-LizardReportValue -Value $Document -Path '' -RedactedPaths $redactedPaths
  if ($safe -isnot [System.Collections.IDictionary]) { throw 'SAFE_REPORT_DOCUMENT_INVALID: report root must be an object.' }
  $safe['redaction'] = [ordered]@{
    status = if ($redactedPaths.Count -gt 0) { 'applied' } else { 'not-required' }
    fields = @($redactedPaths.ToArray() | Sort-Object -Unique)
  }
  return $safe
}

function ConvertTo-LizardSafeReportJson {
  param([Parameter(Mandatory)]$Document, [int]$Depth = 20)
  (Protect-LizardReportDocument -Document $Document) | ConvertTo-Json -Depth $Depth
}

function Protect-LizardConsoleText {
  param([AllowEmptyString()][string]$Text)
  $redactedPaths = New-Object System.Collections.Generic.List[string]
  [string](Protect-LizardReportValue -Value $Text -Path 'console' -RedactedPaths $redactedPaths)
}

Export-ModuleMember -Function Assert-LizardOpaqueIdentifier, Protect-LizardReportDocument, ConvertTo-LizardSafeReportJson, Protect-LizardConsoleText
