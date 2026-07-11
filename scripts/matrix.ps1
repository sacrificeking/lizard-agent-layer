param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string[]]$Profiles,
  [string[]]$Harnesses,
  [switch]$KeepScratch
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Host.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix
$profilesRoot = Join-Path $LayerRoot 'profiles'
$adaptersRoot = Join-Path $LayerRoot 'adapters'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$tmpRoot = Join-Path $LayerRoot ".tmp\matrix-$stamp"
$results = New-Object System.Collections.Generic.List[object]

function Expand-List {
  param($Values)
  $out = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in ([string]$value -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed -and -not $out.Contains($trimmed)) { $out.Add($trimmed) | Out-Null }
    }
  }
  return @($out)
}

$selectedProfiles = Expand-List $Profiles
if ($selectedProfiles.Count -eq 0) {
  $selectedProfiles = @(Get-ChildItem -LiteralPath $profilesRoot -Filter '*.json' -File | ForEach-Object { $_.BaseName } | Sort-Object)
}

$selectedHarnesses = Expand-List $Harnesses
if ($selectedHarnesses.Count -eq 0) {
  $selectedHarnesses = @(Get-ChildItem -LiteralPath $adaptersRoot -Directory | ForEach-Object { $_.Name } | Sort-Object)
}

$tmpRoot = Initialize-SafeDirectory -Path $tmpRoot

Write-Host "lizard-agent-layer matrix"
Write-Host "Layer: $LayerRoot"
Write-Host "Profiles: $($selectedProfiles -join ', ')"
Write-Host "Harnesses: $($selectedHarnesses -join ', ')"
Write-Host "Scratch: $tmpRoot"
Write-Host ""

foreach ($profile in $selectedProfiles) {
  $profilePath = Join-Path $profilesRoot "$profile.json"
  if (-not (Test-Path -LiteralPath $profilePath)) { throw "Unknown profile '$profile'." }
  foreach ($harness in $selectedHarnesses) {
    $adapterPath = Join-Path $adaptersRoot "$harness\adapter.json"
    if (-not (Test-Path -LiteralPath $adapterPath)) { throw "Unknown harness '$harness'." }

    $target = Join-Path $tmpRoot "$profile--$harness"
    New-SafeDirectory -AuthorizedRoot $tmpRoot -Path $target | Out-Null
    Set-SafeContent -AuthorizedRoot $target -Path (Join-Path $target 'README.md') -Value "# matrix $profile $harness"

    $status = 'pass'
    $message = ''
    try {
      $installOutput = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $target -Profile $profile -Harnesses $harness -Apply 2>&1 | Out-String
      if ($LASTEXITCODE -ne 0) { throw "install failed: $installOutput" }
      $doctorOutput = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $target -Strict 2>&1 | Out-String
      if ($LASTEXITCODE -ne 0) { throw "doctor failed: $doctorOutput" }
      Write-Host "PASS $profile / $harness"
    } catch {
      $status = 'fail'
      $message = $_.Exception.Message
      Write-Host "FAIL $profile / $harness"
      Write-Host "  $message"
    }

    $results.Add([ordered]@{
      profile = $profile
      harness = $harness
      status = $status
      message = $message
      target = $target
    }) | Out-Null
  }
}

$report = New-Object System.Collections.Specialized.OrderedDictionary
$report['generated_at'] = (Get-Date).ToUniversalTime().ToString('o')
$report['profiles'] = @($selectedProfiles)
$report['harnesses'] = @($selectedHarnesses)
$report['results'] = @($results.ToArray())
$reportPath = Join-Path $tmpRoot 'matrix-report.json'
Set-SafeContent -AuthorizedRoot $tmpRoot -Path $reportPath -Value ($report | ConvertTo-Json -Depth 8)

$failures = @($results | Where-Object { $_.status -ne 'pass' })
Write-Host ""
Write-Host "Matrix report: $reportPath"
Write-Host "Passed: $($results.Count - $failures.Count)"
Write-Host "Failed: $($failures.Count)"
Write-Host "Scratch retained for audit: $tmpRoot"

if ($failures.Count -gt 0) { exit 1 }
if ($KeepScratch) { Write-Host "KeepScratch requested; no cleanup is performed by this script." }
