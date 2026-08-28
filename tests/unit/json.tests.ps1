param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Json.psm1') -Force

$json = '{"created_at":"2026-08-09T14:46:30.1234567Z","nested":{"expires_at":"2026-08-09T15:16:30.1234567+00:00"},"integer":42,"enabled":true,"empty":null}'
$document = ConvertFrom-LizardJson -InputObject $json
Assert-True ($document.created_at -is [string]) 'Top-level ISO timestamps must remain JSON strings.'
Assert-Equal '2026-08-09T14:46:30.1234567Z' ([string]$document.created_at) 'Top-level ISO timestamp bytes must round-trip unchanged.'
Assert-True ($document.nested.expires_at -is [string]) 'Nested ISO timestamps must remain JSON strings.'
Assert-Equal '2026-08-09T15:16:30.1234567+00:00' ([string]$document.nested.expires_at) 'Nested ISO timestamp bytes must round-trip unchanged.'
Assert-Equal 42 ([int]$document.integer) 'JSON integers must remain integers.'
Assert-True ($document.enabled -is [bool]) 'JSON booleans must remain booleans.'
Assert-True ($null -eq $document.empty) 'JSON null must remain null.'

Assert-ThrowsCode {
  ConvertFrom-LizardJson -InputObject '{invalid json' | Out-Null
} 'LIZARD_JSON_INVALID' 'Malformed JSON must fail with a stable parser code.'

Write-Host 'PASS tests\unit\json.tests.ps1'
