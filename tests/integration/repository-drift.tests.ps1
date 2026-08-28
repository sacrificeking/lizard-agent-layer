param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $LayerRoot 'scripts'))) {
    $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }
}
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force

$driftScript = Join-Path $LayerRoot 'scripts/check-repository-drift.ps1'

# 1. Assert repository drift checker passes cleanly on repository root
$cleanResult = Invoke-TestPowerShell -ScriptPath $driftScript -Arguments @('-RepoRoot', $LayerRoot)
Assert-Equal 0 $cleanResult.exit_code "Repository drift check must pass cleanly on valid repo. Output: $($cleanResult.output)"
Assert-True ($cleanResult.output -match 'PASS: Repository drift verification clean') 'Expected clean drift verification output'

Write-Host "PASS tests\integration\repository-drift.tests.ps1"
