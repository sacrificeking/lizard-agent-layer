param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Json.psm1') -Force

$testRoot = Join-Path $LayerRoot ('.tmp/tests/win-happy-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$targetRoot = Join-Path $testRoot 'target'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null

$lizardScript = Join-Path $LayerRoot 'scripts/lizard.ps1'
$doctorScript = Join-Path $LayerRoot 'scripts/doctor.ps1'
$installScript = Join-Path $LayerRoot 'scripts/install.ps1'

try {
  # 1. Test lizard.ps1 unknown command
  $unknownResult = Invoke-TestPowerShell -ScriptPath $lizardScript -Arguments @('invalid-command')
  Assert-False ($unknownResult.exit_code -eq 0) 'Unknown command in lizard.ps1 must return non-zero.'
  Assert-True ($unknownResult.output -match 'Supported commands: doctor, install, update, uninstall, analyze, manifest-diff, new-approval, schema-check') 'Error output must list supported commands.'

  # 2. Test install minimal target to verify layer_root in manifest
  $planPath = Join-Path $testRoot 'install-plan.md'
  $canonicalPlanPath = Join-Path $testRoot 'install-plan.json'
  $installResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-PlanPath', $planPath,
    '-CanonicalPlanPath', $canonicalPlanPath
  )
  Assert-Equal 0 $installResult.exit_code "Preview install failed: $($installResult.output)"

  $applyResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-Profile', 'minimal',
    '-Harnesses', 'generic-agents-md',
    '-Apply',
    '-ApprovedPlanPath', $canonicalPlanPath,
    '-HumanApproved'
  )
  Assert-Equal 0 $applyResult.exit_code "Apply install failed: $($applyResult.output)"

  $manifestPath = Join-Path $targetRoot '.agent/lizard-agent-layer.install.json'
  Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Install manifest must exist.'
  $manifest = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $manifestPath -Raw)
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$manifest.layer_root)) 'Manifest must record layer_root.'

  # 3. Test doctor.ps1 discovering LayerRoot from manifest
  $doctorAutoResult = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $targetRoot)
  Assert-Equal 0 $doctorAutoResult.exit_code "Doctor with manifest discovery failed: $($doctorAutoResult.output)"
  Assert-True ($doctorAutoResult.output -match 'lizard-agent-layer doctor') 'Doctor header expected.'

  # 4. Test doctor.ps1 with explicit -LayerRoot
  $doctorExplicitResult = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @(
    '-TargetPath', $targetRoot,
    '-LayerRoot', $LayerRoot
  )
  Assert-Equal 0 $doctorExplicitResult.exit_code "Doctor with explicit LayerRoot failed: $($doctorExplicitResult.output)"

  # 5. Test doctor.ps1 with missing recorded layer_root throws LAYER_ROOT_MISSING
  $manifest.layer_root = 'C:/nonexistent/lizard-layer-test'
  Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding UTF8
  $doctorMissingResult = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $targetRoot)
  Assert-False ($doctorMissingResult.exit_code -eq 0) 'Doctor with missing layer_root must fail closed.'
  Assert-True ($doctorMissingResult.output -match 'LAYER_ROOT_MISSING') 'Expected LAYER_ROOT_MISSING error.'

  # 6. Test lizard.ps1 running doctor subcommand
  # Restore manifest
  $manifest.layer_root = $LayerRoot.Replace('\', '/')
  Set-Content -LiteralPath $manifestPath -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding UTF8
  $lizardDoctorResult = Invoke-TestPowerShell -ScriptPath $lizardScript -Arguments @(
    'doctor',
    '-TargetPath', $targetRoot
  )
  Assert-Equal 0 $lizardDoctorResult.exit_code "lizard.ps1 doctor failed: $($lizardDoctorResult.output)"

  Write-Host "PASS tests\unit\windows-happy-path.tests.ps1"
} finally {
  if (Test-Path -LiteralPath $testRoot) {
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
