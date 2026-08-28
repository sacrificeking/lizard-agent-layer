param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.SafeFs.psm1') -Force

$fixtureRoot = Join-Path $LayerRoot '.tmp/tests/analyzer-hardening'
$allowedRoot = Join-Path $LayerRoot '.tmp'
$links = New-Object System.Collections.Generic.List[string]
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot $allowedRoot }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

function Invoke-AnalyzerJson {
  param([string]$Target, [string[]]$Extra = @())
  $result = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/analyze-target.ps1') -Arguments (@('-TargetPath', $Target, '-Json') + @($Extra))
  if ($result.exit_code -ne 0) { throw "ANALYZER_TEST_EXECUTION_FAILED: $($result.output)" }
  return $result.output | ConvertFrom-LizardJson
}

try {
  $negative = Join-Path $fixtureRoot 'negative'
  New-Item -ItemType Directory -Path (Join-Path $negative 'src/refinance') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $negative 'README.md') -Value 'finance market supabase react words are prose, not executable project evidence' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $negative 'src/refinance/application.txt') -Value 'not a financial product marker' -Encoding UTF8
  $negativeResult = Invoke-AnalyzerJson -Target $negative
  Assert-Equal 'minimal' ([string]$negativeResult.recommendedProfile) 'Prose and partial-token paths must not create a false positive profile.'
  Assert-False (@($negativeResult.signals) -contains 'finance') 'A refinance path must not match the bounded finance token rule.'
  Assert-Equal 'medium' ([string]$negativeResult.calibration.false_positive_risk) 'Weak negative fixture must retain a candid false-positive risk.'

  $positive = Join-Path $fixtureRoot 'positive'
  foreach ($path in @('supabase\functions', 'supabase\migrations', 'src\finance\dca', '.github')) { New-Item -ItemType Directory -Path (Join-Path $positive $path) -Force | Out-Null }
  Set-Content -LiteralPath (Join-Path $positive 'package.json') -Value '{"dependencies":{"@supabase/supabase-js":"1","react":"1"},"devDependencies":{"typescript":"1","vite":"1"}}' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $positive 'CLAUDE.md') -Value '# untrusted target instructions' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $positive 'src/finance/dca/index.ts') -Value 'export {}' -Encoding UTF8
  $positiveResult = Invoke-AnalyzerJson -Target $positive -Extra @('-ApprovedHarnesses', 'github-copilot,codex')
  Assert-Equal 'enterprise-fullstack' ([string]$positiveResult.recommendedProfile) 'Strong manifest and directory evidence must identify the rich fixture.'
  Assert-Equal 'high' ([string]$positiveResult.calibration.confidence) 'Strong complete evidence must produce high rule confidence.'
  Assert-Equal 'explicit-input' ([string]$positiveResult.harnessApprovalSource) 'Harness recommendations must identify explicit approval input.'
  Assert-Equal 'codex,github-copilot' (@($positiveResult.recommendedHarnesses) -join ',') 'Only explicitly approved harnesses may be recommended, in deterministic order.'
  Assert-True (@($positiveResult.detectedHarnesses) -contains 'claude-code') 'Target instruction files must be reported separately as detected.'
  Assert-False (@($positiveResult.recommendedHarnesses) -contains 'claude-code') 'Detected target instructions must not self-authorize a harness.'
  Assert-True (@($positiveResult.evidence | Where-Object { $_.id -like 'manifest:package.json*' }).Count -gt 0) 'Recommendation must include stable manifest evidence.'
  Assert-Equal 'bounded-evidence-score-not-probability' ([string]$positiveResult.calibration.score_kind) 'Evidence score must not be presented as a probability.'

  # Explicit precision threshold test: 1 marker below threshold, 2 markers satisfies threshold
  Assert-False (@($positiveResult.signals) -contains 'precision') 'Single finance marker must not emit precision signal.'
  Assert-True (@($positiveResult.negativeSignals) -contains 'precision-path-groups-below-threshold') 'Single finance marker must record negative precision signal.'

  $precisionTarget = Join-Path $fixtureRoot 'precision-multi'
  New-Item -ItemType Directory -Path (Join-Path $precisionTarget 'src/finance/dca') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $precisionTarget 'src/lib/ledger/entry') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $precisionTarget 'src/finance/dca/calc.ts') -Value 'export {}' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $precisionTarget 'src/lib/ledger/entry/audit.ts') -Value 'export {}' -Encoding UTF8
  $precisionResult = Invoke-AnalyzerJson -Target $precisionTarget
  Assert-True (@($precisionResult.signals) -contains 'precision') 'Two distinct precision/finance path markers must emit precision signal.'
  Assert-True (@($precisionResult.recommendedPacks) -contains 'precision-domain') 'Precision signal must recommend precision-domain pack.'

  $repeatResult = Invoke-AnalyzerJson -Target $positive -Extra @('-ApprovedHarnesses', 'github-copilot,codex')
  Assert-Equal ($positiveResult | ConvertTo-Json -Depth 10 -Compress) ($repeatResult | ConvertTo-Json -Depth 10 -Compress) 'Repeated analysis of an unchanged tree must be byte-order deterministic after JSON parsing.'

  $boundedResult = Invoke-AnalyzerJson -Target $positive -Extra @('-MaxFiles', '1')
  Assert-False ([bool]$boundedResult.calibration.scan_complete) 'MaxFiles must produce an explicit incomplete scan state.'
  Assert-Equal 'low' ([string]$boundedResult.calibration.confidence) 'Incomplete scans must cap recommendation confidence at low.'
  Assert-Equal 'high' ([string]$boundedResult.calibration.false_negative_risk) 'Incomplete scans must report high false-negative risk.'

  $outside = Join-Path $fixtureRoot 'outside'
  $linkedTarget = Join-Path $fixtureRoot 'linked-target'
  New-Item -ItemType Directory -Path $outside, $linkedTarget -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $outside 'package.json') -Value '{"dependencies":{"@supabase/supabase-js":"1","react":"1"}}' -Encoding UTF8
  $link = Join-Path $linkedTarget 'linked'
  New-DirectoryLink -Path $link -Target $outside
  $links.Add($link) | Out-Null
  $linkedResult = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/analyze-target.ps1') -Arguments @('-TargetPath', $linkedTarget, '-Json')
  Assert-True ($linkedResult.exit_code -ne 0) 'A linked scan entry must fail closed.'
  Assert-True ($linkedResult.output -match 'SAFEFS_REPARSE_POINT') 'A linked scan entry must return the stable SafeFs code.'

  $raceRoot = Join-Path $fixtureRoot 'race-root'
  $raceDirectory = Join-Path $raceRoot 'inside'
  $heldDirectory = Join-Path $raceRoot 'held'
  $raceOutside = Join-Path $fixtureRoot 'race-outside'
  New-Item -ItemType Directory -Path $raceDirectory, $raceOutside -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $raceDirectory 'safe.txt') -Value 'safe' -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $raceOutside 'outside-secret-name.txt') -Value 'outside' -Encoding UTF8
  $safeFsModule = Get-Module Lizard.SafeFs
  $env:LIZARD_SAFEFS_TESTING = '1'
  $raceState = [pscustomobject]@{ swapped = $false }
  $raceAction = {
    param($Context)
    if ([string]$Context.path -ne $raceDirectory) { return }
    Move-Item -LiteralPath $raceDirectory -Destination $heldDirectory
    New-DirectoryLink -Path $raceDirectory -Target $raceOutside
    $raceState.swapped = $true
  }.GetNewClosure()
  & $safeFsModule { param($Action) Set-LizardSafeFsTestHook -Event 'after-directory-identity-acquired' -Action $Action } $raceAction
  try {
    Assert-ThrowsCode { Get-SafeDirectoryEntries -AuthorizedRoot $raceRoot -Path $raceDirectory | Out-Null } 'SAFEFS_REPARSE_POINT' 'A synchronized directory swap must fail before entries are returned.'
  } finally {
    & $safeFsModule { Clear-LizardSafeFsTestHooks }
    Remove-Item Env:LIZARD_SAFEFS_TESTING -ErrorAction SilentlyContinue
    if ($raceState.swapped -and (Test-Path -LiteralPath $raceDirectory)) { Remove-DirectoryLink -Path $raceDirectory }
    if ($raceState.swapped -and (Test-Path -LiteralPath $heldDirectory)) { Move-Item -LiteralPath $heldDirectory -Destination $raceDirectory }
  }

  Write-Host 'PASS tests\adversarial\analyzer-hardening.tests.ps1'
} finally {
  Remove-Item Env:LIZARD_SAFEFS_TESTING -ErrorAction SilentlyContinue
  foreach ($linkPath in @($links.ToArray())) { if (Test-Path -LiteralPath $linkPath) { Remove-DirectoryLink -Path $linkPath } }
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot $allowedRoot }
}
