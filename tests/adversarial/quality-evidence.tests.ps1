param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Host.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("quality-evidence-{0}" -f ([Guid]::NewGuid().ToString('N')))
$miniRoot = Join-Path $fixture 'layer'
$scoreScript = Join-Path $LayerRoot 'scripts\score-layer.ps1'

function New-MiniSkill {
  param([string]$Name, [bool]$WithSupport)
  $skillRoot = Join-Path $miniRoot "skills\$Name"
  New-Item -ItemType Directory -Path $skillRoot -Force | Out-Null
  $description = "Use when evaluating $Name behavior with explicit triggers, deterministic checks, and conservative safety boundaries across repositories."
  $content = @(
    '---', "name: $Name", "description: $description", '---', '', "# $Name", '',
    '## Workflow', '', '- Inspect the target.', '- Preserve existing files.', '- Apply the smallest change.', '- Record the result.', '',
    '## Verification', '', 'Run the executable test and verify its result before completion.', '',
    '## Safety', '', 'Require approval for destructive work, preserve rollback evidence, and avoid secrets.', '',
    'Example: validate one constrained fixture.'
  )
  Set-Content -LiteralPath (Join-Path $skillRoot 'SKILL.md') -Value $content -Encoding UTF8
  if ($WithSupport) {
    New-Item -ItemType Directory -Path (Join-Path $skillRoot 'references') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $skillRoot 'references\contract.md') -Value '# Contract' -Encoding UTF8
  }
  return $skillRoot
}

function Write-Evidence {
  param([string]$SkillRoot, [string]$TestPath, [string]$PositivePattern, [string]$NegativePattern)
  $name = Split-Path -Leaf $SkillRoot
  $doc = [ordered]@{
    schema_version = 1
    skill = $name
    provenance = [ordered]@{ owner = 'quality fixture'; reviewed_at = '2026-07-12T00:00:00Z'; review_record = 'REVIEW.md' }
    compatibility = [ordered]@{ hosts = @(Get-LizardHostId); model_classes = @('model-agnostic') }
    fixtures = @(
      [ordered]@{ id = 'positive-case'; kind = 'positive'; test_path = $TestPath; assertion_pattern = $PositivePattern; description = 'Executable positive behavior fixture passes.' },
      [ordered]@{ id = 'negative-case'; kind = 'negative'; test_path = $TestPath; assertion_pattern = $NegativePattern; description = 'Executable negative behavior fixture fails closed.' }
    )
  }
  Set-Content -LiteralPath (Join-Path $SkillRoot 'evidence.json') -Value ($doc | ConvertTo-Json -Depth 8) -Encoding UTF8
}

try {
  foreach ($path in @('skills', 'adapters', 'profiles', 'registry', 'tests', '.tmp\tests')) { New-Item -ItemType Directory -Path (Join-Path $miniRoot $path) -Force | Out-Null }
  foreach ($name in @('quality-rubric.json', 'risk-signals.json', 'maturity-levels.json', 'behavioral-readiness.json')) {
    Copy-Item -LiteralPath (Join-Path $LayerRoot "registry\$name") -Destination (Join-Path $miniRoot "registry\$name")
  }
  Set-Content -LiteralPath (Join-Path $miniRoot 'REVIEW.md') -Value '# Reviewed fixture' -Encoding UTF8

  $stuffed = New-MiniSkill -Name 'keyword-stuffed' -WithSupport $true
  New-Item -ItemType Directory -Path (Join-Path $stuffed 'tests') -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $stuffed 'tests\decorative.md') -Value 'test verify safety approval rollback' -Encoding UTF8

  $verified = New-MiniSkill -Name 'behavior-verified' -WithSupport $true
  $broken = New-MiniSkill -Name 'broken-evidence' -WithSupport $true
  $verifiedTestRel = 'tests/verified.tests.ps1'
  $brokenTestRel = 'tests/broken.tests.ps1'
  Set-Content -LiteralPath (Join-Path $miniRoot $verifiedTestRel) -Value @("# VERIFIED_POSITIVE_ASSERTION", "# VERIFIED_NEGATIVE_ASSERTION", "Write-Host 'PASS verified fixture'") -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $miniRoot $brokenTestRel) -Value @("# BROKEN_POSITIVE_ASSERTION", "# BROKEN_NEGATIVE_ASSERTION", 'exit 7') -Encoding UTF8
  Write-Evidence -SkillRoot $verified -TestPath $verifiedTestRel -PositivePattern 'VERIFIED_POSITIVE_ASSERTION' -NegativePattern 'VERIFIED_NEGATIVE_ASSERTION'
  Write-Evidence -SkillRoot $broken -TestPath $brokenTestRel -PositivePattern 'BROKEN_POSITIVE_ASSERTION' -NegativePattern 'BROKEN_NEGATIVE_ASSERTION'

  $verifiedRun = Invoke-TestPowerShell -ScriptPath (Join-Path $miniRoot $verifiedTestRel) -Arguments @()
  $brokenRun = Invoke-TestPowerShell -ScriptPath (Join-Path $miniRoot $brokenTestRel) -Arguments @()
  Assert-Equal 0 $verifiedRun.exit_code 'Verified fixture setup must pass.'
  Assert-False ($brokenRun.exit_code -eq 0) 'Broken fixture setup must fail.'
  $focused = [ordered]@{
    schema_version = 2
    generated_at = (Get-Date).ToUniversalTime().ToString('o')
    host = [ordered]@{ id = Get-LizardHostId; powershell_edition = [string]$PSVersionTable.PSEdition; powershell_version = [string]$PSVersionTable.PSVersion }
    tests = @(
      [ordered]@{ test = $verifiedTestRel; status = 'pass'; exit_code = 0; seconds = 0; output = $verifiedRun.output.Trim() },
      [ordered]@{ test = $brokenTestRel; status = 'fail'; exit_code = $brokenRun.exit_code; seconds = 0; output = $brokenRun.output.Trim() }
    )
    passed = 1
    failed = 1
  }
  Set-Content -LiteralPath (Join-Path $miniRoot '.tmp\tests\focused-test-report.json') -Value ($focused | ConvertTo-Json -Depth 8) -Encoding UTF8

  $outputDir = Join-Path $miniRoot '.tmp\quality'
  $score = Invoke-TestPowerShell -ScriptPath $scoreScript -Arguments @('-LayerRoot', $miniRoot, '-OutputDir', $outputDir)
  Assert-Equal 0 $score.exit_code "Non-strict adversarial score failed unexpectedly: $($score.output)"
  $report = Get-Content -LiteralPath (Join-Path $outputDir 'layer-quality-report.json') -Raw | ConvertFrom-Json
  $stuffedResult = @($report.skills | Where-Object { $_.name -eq 'keyword-stuffed' })[0]
  $verifiedResult = @($report.skills | Where-Object { $_.name -eq 'behavior-verified' })[0]
  $brokenResult = @($report.skills | Where-Object { $_.name -eq 'broken-evidence' })[0]
  Assert-True ([int]$stuffedResult.documentation_score -ge 90) 'Keyword-stuffed fixture must exercise a high lexical score.'
  Assert-Equal 0 ([int]$stuffedResult.behavioral_readiness_score) 'Undeclared evidence must score zero behaviorally.'
  Assert-Equal 'ready' ([string]$stuffedResult.maturity) 'Keyword-stuffing must not reach hardened or certified maturity.'
  Assert-Equal 100 ([int]$verifiedResult.behavioral_readiness_score) 'Passing positive and negative evidence must receive full behavioral readiness.'
  Assert-Equal 'certified' ([string]$verifiedResult.maturity) 'Documented, supported, behaviorally verified fixture must certify.'
  Assert-Equal 'ready' ([string]$brokenResult.maturity) 'Failed evidence must cap maturity at ready.'
  Assert-Equal 'fail' ([string]$report.gate) 'Declared failed evidence must fail the quality report gate.'

  $strict = Invoke-TestPowerShell -ScriptPath $scoreScript -Arguments @('-LayerRoot', $miniRoot, '-OutputDir', (Join-Path $miniRoot '.tmp\quality-strict'), '-Strict')
  Assert-False ($strict.exit_code -eq 0) 'Strict quality must reject failed behavioral evidence.'
  Assert-True ($strict.output -match 'behavioral evidence failed') 'Strict quality rejection must explain behavioral evidence failure.'

  Write-Host 'PASS tests\adversarial\quality-evidence.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
