param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Host.psm1') -Force

$hostPath = Get-LizardPowerShellHostPath
$hostId = Get-LizardHostId
Assert-True ($hostId -in @('windows-powershell-5.1', 'windows-pwsh', 'linux-pwsh', 'macos-pwsh')) "Unexpected portable host ID '$hostId'."
Assert-True (Test-Path -LiteralPath $hostPath -PathType Leaf) 'Current PowerShell host path must exist.'
$prefix = @(Get-LizardPowerShellFilePrefix)
Assert-True ($prefix -contains '-NoProfile') 'Child process prefix must disable profiles.'
Assert-Equal '-File' $prefix[-1] 'Child process prefix must end with -File.'
if (Test-LizardWindowsHost) {
  Assert-True ($prefix -contains '-ExecutionPolicy') 'Windows child host must include execution policy compatibility.'
} else {
  Assert-False ($prefix -contains '-ExecutionPolicy') 'Unix child host must not receive Windows execution policy arguments.'
}

$fixtureRoot = Join-Path $LayerRoot '.tmp\tests\host'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
try {
  $probePath = Join-Path $fixtureRoot 'probe.ps1'
  Set-Content -LiteralPath $probePath -Value "Write-Output ('HOST_PROBE:' + `$PSVersionTable.PSEdition)" -Encoding UTF8
  $output = & $hostPath @prefix $probePath 2>&1 | Out-String
  Assert-Equal 0 ([int]$LASTEXITCODE) "Current-host child process failed: $output"
  Assert-True ($output -match 'HOST_PROBE:') 'Current-host child process did not execute the probe.'

  $bareCalls = @()
  foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'scripts'), (Join-Path $LayerRoot 'tests') -Include '*.ps1', '*.psm1' -Recurse -File)) {
    $matches = Select-String -LiteralPath $file.FullName -Pattern '&\s*powershell\.exe\b' -CaseSensitive:$false
    foreach ($match in @($matches)) { $bareCalls += "$($file.FullName):$($match.LineNumber)" }
  }
  Assert-Equal 0 $bareCalls.Count "Executable code still invokes powershell.exe directly: $($bareCalls -join ', ')"
  Write-Host 'PASS tests\unit\host.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
}
