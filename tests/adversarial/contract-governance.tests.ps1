param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("contract-governance-{0}" -f ([Guid]::NewGuid().ToString('N')))
$scriptPath = Join-Path $LayerRoot 'scripts\contract-check.ps1'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

try {
  $missingOutput = Join-Path $fixture 'missing'
  $missing = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-LayerRoot', $LayerRoot, '-ChangedPaths', 'scripts/Lizard.SafeFs.psm1', '-OutputDir', $missingOutput, '-Strict')
  Assert-False ($missing.exit_code -eq 0) 'Contract-sensitive change without declaration must fail.'
  Assert-True ($missing.output -match 'lacks a changed declaration') 'Missing declaration failure must be explicit.'

  $filesystemOutput = Join-Path $fixture 'filesystem'
  $filesystem = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-LayerRoot', $LayerRoot, '-ChangedPaths', 'scripts/Lizard.SafeFs.psm1,changes/2026-07-10-filesystem-safety.json', '-OutputDir', $filesystemOutput, '-Strict')
  Assert-Equal 0 $filesystem.exit_code "Filesystem declaration must cover its contract: $($filesystem.output)"
  $filesystemReportPath = Join-Path $filesystemOutput 'contract-check-report.json'
  $filesystemReport = Get-Content -LiteralPath $filesystemReportPath -Raw | ConvertFrom-Json
  Assert-Equal 'pass' ([string]$filesystemReport.status) 'Covered filesystem contract must pass.'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/contract-check-report.schema.json' -InstancePath $filesystemReportPath -Message 'Contract check report must satisfy its schema.'

  $manifestOutput = Join-Path $fixture 'manifest'
  $manifest = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-LayerRoot', $LayerRoot, '-ChangedPaths', 'schemas/install-manifest.schema.json,changes/2026-07-10-manifest-integrity.json', '-OutputDir', $manifestOutput, '-Strict')
  Assert-Equal 0 $manifest.exit_code "Manifest declaration must include ownership and schema decisions: $($manifest.output)"

  $docsOutput = Join-Path $fixture 'docs-only'
  $docs = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-LayerRoot', $LayerRoot, '-ChangedPaths', 'docs/troubleshooting.md', '-OutputDir', $docsOutput, '-Strict')
  Assert-Equal 0 $docs.exit_code 'Non-contract documentation change must not require a declaration.'
  $docsReport = Get-Content -LiteralPath (Join-Path $docsOutput 'contract-check-report.json') -Raw | ConvertFrom-Json
  Assert-Equal 'not-applicable' ([string]$docsReport.status) 'Non-contract change must report not-applicable.'

  Write-Host 'PASS tests\adversarial\contract-governance.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
