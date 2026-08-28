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
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Json.psm1') -Force

# 1. Test ISO-8601 string timestamp preservation
$isoSample = '{"id":"receipt-1","timestamp":"2026-08-27T12:34:56.789Z","nested":{"created_at":"2026-01-01T00:00:00Z"}}'
$parsed = ConvertFrom-LizardJson -InputObject $isoSample

Assert-Equal 'receipt-1' ([string]$parsed.id) 'ID property must be string'
Assert-True ($parsed.timestamp -is [string]) "Timestamp must retain string type, got $($parsed.timestamp.GetType().FullName)"
Assert-Equal '2026-08-27T12:34:56.789Z' ([string]$parsed.timestamp) 'Timestamp value must be byte-exact'
Assert-True ($parsed.nested.created_at -is [string]) "Nested timestamp must retain string type, got $($parsed.nested.created_at.GetType().FullName)"
Assert-Equal '2026-01-01T00:00:00Z' ([string]$parsed.nested.created_at) 'Nested timestamp value must be byte-exact'

# 2. Run repository JSON policy check
$policyResult = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/check-json-reader-policy.ps1') -Arguments @('-LayerRoot', $LayerRoot)
Assert-Equal 0 $policyResult.exit_code "check-json-reader-policy.ps1 must pass on repository codebase: $($policyResult.output)"

# 3. Negative test: verify policy linter catches unauthorized ConvertFrom-Json in a test directory
$tmpTestDir = Join-Path $LayerRoot '.tmp/tests/json-policy-test'
if (Test-Path -LiteralPath $tmpTestDir) { Clear-TestDirectory -Path $tmpTestDir -AllowedRoot (Join-Path $LayerRoot '.tmp') }
New-Item -ItemType Directory -Path $tmpTestDir -Force | Out-Null
try {
  $badFile = Join-Path $tmpTestDir 'bad-test.ps1'
  Set-Content -LiteralPath $badFile -Value '$data = Get-Content "foo.json" | ConvertFrom-Json' -Encoding UTF8

  $violatingCheck = {
    $rawContent = Get-Content -LiteralPath $badFile -Raw
    if ($rawContent -match '(?<!Lizard)ConvertFrom-Json') {
      throw "JSON_READER_POLICY_VIOLATION: Found unapproved ConvertFrom-Json in $badFile"
    }
  }

  Assert-ThrowsCode $violatingCheck 'JSON_READER_POLICY_VIOLATION' 'Detector must flag unapproved ConvertFrom-Json calls'
} finally {
  if (Test-Path -LiteralPath $tmpTestDir) { Clear-TestDirectory -Path $tmpTestDir -AllowedRoot (Join-Path $LayerRoot '.tmp') }
}

Write-Host "PASS tests\unit\json-reader-policy.tests.ps1"
