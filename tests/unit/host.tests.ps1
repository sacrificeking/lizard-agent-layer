param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Host.psm1') -Force

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

foreach ($case in @(
  @{ id = 'windows-powershell-5.1'; executable = 'powershell.exe'; execution_policy = $true },
  @{ id = 'windows-pwsh'; executable = 'pwsh'; execution_policy = $true },
  @{ id = 'linux-pwsh'; executable = 'pwsh'; execution_policy = $false },
  @{ id = 'macos-pwsh'; executable = 'pwsh'; execution_policy = $false }
)) {
  $invocation = New-LizardPowerShellFileInvocation -ScriptPath './scripts/install.ps1' -ArgumentList @('-TargetPath', 'path with spaces') -HostId $case.id
  Assert-Equal $case.executable ([string]$invocation.executable) "Generated executable mismatch for $($case.id)."
  Assert-True (@($invocation.argv) -contains '-File') "Generated argv lacks -File for $($case.id)."
  Assert-Equal ([bool]$case.execution_policy) (@($invocation.argv) -contains '-ExecutionPolicy') "Generated execution-policy compatibility mismatch for $($case.id)."
  Assert-True ([string]$invocation.display -match [regex]::Escape($case.executable)) "Display command lacks host executable for $($case.id)."
  Assert-True ([string]$invocation.display -match '"path with spaces"') "Display command does not quote an argv item for $($case.id)."
}

$fixtureRoot = Join-Path $LayerRoot '.tmp/tests/host'
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
  foreach ($generatedCommandSource in @('scripts/install.ps1', 'scripts/analyze-target.ps1')) {
    $hardCoded = @(Select-String -LiteralPath (Join-Path $LayerRoot $generatedCommandSource) -Pattern 'powershell/.exe' -CaseSensitive:$false)
    Assert-Equal 0 $hardCoded.Count "Generated command source still hard-codes powershell.exe: $generatedCommandSource"
  }

  $generatedTarget = Join-Path $fixtureRoot 'generated-target'
  $generatedCwd = Join-Path $fixtureRoot 'generated-cwd'
  New-Item -ItemType Directory -Path $generatedTarget, $generatedCwd -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $generatedTarget 'README.md') -Value '# portable generated command' -Encoding UTF8
  $analysisResult = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/analyze-target.ps1') -Arguments @('-TargetPath', $generatedTarget, '-ApprovedHarnesses', 'generic-agents-md', '-Json')
  Assert-Equal 0 $analysisResult.exit_code "Analyzer invocation generation failed: $($analysisResult.output)"
  $analysis = $analysisResult.output | ConvertFrom-LizardJson
  $originalLocation = (Get-Location).Path
  try {
    Set-Location -LiteralPath $generatedCwd
    $generatedOutput = & ([string]$analysis.previewInvocation.executable) @($analysis.previewInvocation.argv) 2>&1 | Out-String
    $generatedExit = [int]$LASTEXITCODE
  } finally { Set-Location -LiteralPath $originalLocation }
  Assert-Equal 0 $generatedExit "Exact analyzer executable/argv did not execute on the current host: $generatedOutput"
  Assert-False (Test-Path -LiteralPath (Join-Path $generatedTarget '.agent')) 'Generated analyzer preview invocation mutated the target.'
  $generatedPlan = Join-Path $generatedCwd '.tmp/install-plan.md'
  Assert-True (Test-Path -LiteralPath $generatedPlan -PathType Leaf) 'Generated analyzer preview invocation did not write its outside-target plan.'
  $generatedPlanText = Get-Content -LiteralPath $generatedPlan -Raw
  Assert-True ($generatedPlanText -match [regex]::Escape([string]$analysis.previewInvocation.executable)) 'Install plan did not render the current host executable.'
  if ($hostId -in @('linux-pwsh', 'macos-pwsh')) {
    Assert-False ($generatedPlanText -match 'powershell\.exe|ExecutionPolicy') 'Unix generated plan contains Windows-only command syntax.'
  }
  Write-Host 'PASS tests\unit\host.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
}
