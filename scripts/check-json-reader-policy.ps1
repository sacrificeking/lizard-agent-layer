[CmdletBinding()]
param(
  [string]$LayerRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path

$exemptFiles = New-Object System.Collections.Generic.HashSet[string]
# The canonical wrapper itself is exempt
$exemptFiles.Add((Join-Path $LayerRoot 'scripts/Lizard.Json.psm1')) | Out-Null
# This policy linter itself
$exemptFiles.Add((Join-Path $LayerRoot 'scripts/check-json-reader-policy.ps1')) | Out-Null
# Unit tests testing the policy linter or ConvertFrom-LizardJson internals
$exemptFiles.Add((Join-Path $LayerRoot 'tests/unit/json-reader-policy.tests.ps1')) | Out-Null
$exemptFiles.Add((Join-Path $LayerRoot 'tests/unit/json.tests.ps1')) | Out-Null

$scanDirs = @('scripts', 'tests')
$violations = New-Object System.Collections.Generic.List[object]

foreach ($dir in $scanDirs) {
  $dirPath = Join-Path $LayerRoot $dir
  if (-not (Test-Path -LiteralPath $dirPath)) { continue }

  $files = Get-ChildItem -LiteralPath $dirPath -Recurse -Include '*.ps1', '*.psm1' -File
  foreach ($file in $files) {
    if ($exemptFiles.Contains($file.FullName)) { continue }

    $lines = Get-Content -LiteralPath $file.FullName
    $lineNum = 0
    foreach ($line in $lines) {
      $lineNum++
      # Match ConvertFrom-Json not preceded by Lizard or Microsoft.PowerShell.Utility\
      # Also ignore comments
      $trimmed = $line.Trim()
      if ($trimmed.StartsWith('#')) { continue }

      if ($line -match '(?<!Lizard)ConvertFrom-Json') {
        # Check if it has an explicit waiver comment on the line
        if ($line -match '#\s*exempt:json-reader-policy') { continue }

        $violations.Add([pscustomobject]@{
          File = [string]$file.FullName.Substring($LayerRoot.Length).TrimStart('\', '/')
          Line = $lineNum
          Content = $trimmed
        }) | Out-Null
      }
    }
  }
}

if ($violations.Count -gt 0) {
  Write-Host "JSON Reader Policy Violations Found ($($violations.Count)):" -ForegroundColor Red
  foreach ($v in $violations) {
    Write-Host ("  {0}:{1} -> {2}" -f $v.File, $v.Line, $v.Content) -ForegroundColor Yellow
  }
  Write-Host ""
  Write-Host "Policy Mandate: All JSON reading in scripts/ and tests/ must use ConvertFrom-LizardJson to preserve ISO-8601 string timestamps and prevent DateTime mutation." -ForegroundColor Red
  throw "JSON_READER_POLICY_VIOLATION: $($violations.Count) files contain unapproved ConvertFrom-Json calls."
}

Write-Host "JSON reader policy check passed. All $($scanDirs -join ', ') files use canonical ConvertFrom-LizardJson." -ForegroundColor Green
