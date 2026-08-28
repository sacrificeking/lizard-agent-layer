param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $LayerRoot 'scripts'))) {
    $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Json.psm1') -Force

$readinessScript = Join-Path $LayerRoot 'scripts\release-readiness.ps1'

# 1. Test positive readiness run
$positiveResult = Invoke-TestPowerShell -ScriptPath $readinessScript -Arguments @('-LayerRoot', $LayerRoot, '-Json')
Assert-Equal 0 $positiveResult.exit_code "Release readiness should pass for clean repository. Output: $($positiveResult.output)"
$positiveReport = ConvertFrom-LizardJson -InputObject $positiveResult.output
Assert-True $positiveReport.ready 'Clean repository must be ready for release'
Assert-Equal 0 @($positiveReport.blockers).Count 'No blockers expected on clean repository'

# 2. Test negative readiness run (expected version mismatch)
$negativeResult = Invoke-TestPowerShell -ScriptPath $readinessScript -Arguments @('-LayerRoot', $LayerRoot, '-ExpectedVersion', '9.9.9', '-Json')
Assert-False ($negativeResult.exit_code -eq 0) 'Readiness check with mismatching expected version must fail closed'
$negativeReport = ConvertFrom-LizardJson -InputObject $negativeResult.output
Assert-False $negativeReport.ready 'Mismatching expected version must mark ready=false'
Assert-True (@($negativeReport.blockers).Count -gt 0) 'Blockers must be populated when check fails'

Write-Host "PASS tests\release\release-readiness.tests.ps1"
