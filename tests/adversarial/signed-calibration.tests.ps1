param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'tests/TestTrustHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Trust.psm1') -Force
$testRoot = Join-Path $LayerRoot '.tmp/tests'; $fixture = Join-Path $testRoot ("signed-calibration-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'; $routing = Join-Path $target '.agent/routing'; $script = Join-Path $LayerRoot 'scripts/calibrate-model.ps1'
try {
  New-Item -ItemType Directory -Path $routing -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $target '.agent/project-profile.json') -Value '{"modelMode":"inventory-routing","modelInventory":".agent/routing/inventory.json","modelRuntime":".agent/routing/runtime.json"}'
  Copy-Item -LiteralPath (Join-Path $LayerRoot 'tests/schema/fixtures/model-inventory.valid.json') -Destination (Join-Path $routing 'inventory.json')
  Copy-Item -LiteralPath (Join-Path $LayerRoot 'tests/schema/fixtures/routing-runtime.valid.json') -Destination (Join-Path $routing 'runtime.json')
  $payload = Get-Content -LiteralPath (Join-Path $LayerRoot 'tests/schema/fixtures/model-evaluation.valid.json') -Raw | ConvertFrom-LizardJson
  $binding = Get-LizardCalibrationTrustBinding -TargetRoot $target -EvaluationId $payload.evaluation_id -ModelId $payload.model_id -Provider $payload.provider -ExecutorId $payload.executor_id -ConfigurationFingerprint $payload.configuration_fingerprint -Cases @($payload.cases)
  $now = [DateTimeOffset]::UtcNow
  $trust = New-LizardTestTrustMaterial -Root (Join-Path $fixture 'trust') -BindingSha256 $binding -Subject $payload.evaluation_id -Now $now -PrincipalId 'independent-evaluator' -Roles @('evaluator') -Purpose 'model-calibration' -PayloadKind 'model-evaluation'
  $envelope = New-LizardSignedEvidenceEnvelope -Payload $payload -PayloadKind model-evaluation -Purpose model-calibration -Subject $payload.evaluation_id -BindingSha256 $binding -ChallengePath $trust.challenge_path -ChallengeSha256 $trust.challenge_sha256 -PrivateKeyPath $trust.private_key_path -PrivateKeySha256 $trust.private_key_sha256 -Now $now
  $evaluationPath = Join-Path $fixture 'evaluation.json'; [IO.File]::WriteAllText($evaluationPath, ($envelope | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  $args = @('-TargetPath',$target,'-EvaluationPath',$evaluationPath,'-TrustStorePath',$trust.trust_store_path,'-TrustStoreSha256',$trust.trust_store_sha256,'-TrustChallengePath',$trust.challenge_path,'-TrustChallengeSha256',$trust.challenge_sha256,'-ReplayLedgerPath',$trust.replay_ledger_path,'-Json')
  $preview = Invoke-TestPowerShell -ScriptPath $script -Arguments $args
  Assert-Equal 0 $preview.exit_code "Signed calibration preview failed: $($preview.output)"
  $previewDoc = $preview.output | ConvertFrom-LizardJson
  Assert-Equal 'independent-evaluator' ([string]$previewDoc.authenticated_evaluator_id) 'Calibration identity must come from the evaluator signing key.'
  $apply = Invoke-TestPowerShell -ScriptPath $script -Arguments ($args + '-Apply')
  Assert-Equal 0 $apply.exit_code "Signed calibration apply failed: $($apply.output)"
  $replay = Invoke-TestPowerShell -ScriptPath $script -Arguments ($args + '-Apply')
  Assert-False ($replay.exit_code -eq 0) 'A consumed evaluation envelope must not be applied twice.'
  Assert-True ($replay.output -match 'TRUST_REPLAY_DETECTED') "Calibration replay rejection must be explicit: $($replay.output)"

  $tampered = $envelope | ConvertTo-Json -Depth 20 | ConvertFrom-LizardJson; $tampered.payload.cases[0].score = 1.0
  $tamperedPath = Join-Path $fixture 'tampered.json'; [IO.File]::WriteAllText($tamperedPath, ($tampered | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
  $tamperedArgs = @($args); $index = [Array]::IndexOf($tamperedArgs, '-EvaluationPath'); $tamperedArgs[$index + 1] = $tamperedPath
  $tamperedResult = Invoke-TestPowerShell -ScriptPath $script -Arguments $tamperedArgs
  Assert-False ($tamperedResult.exit_code -eq 0) 'Changed scores behind a stale signature must fail closed.'
  Assert-True ($tamperedResult.output -match 'TRUST_(ENVELOPE_CONTEXT_MISMATCH|PAYLOAD_HASH_MISMATCH)') "Calibration tamper rejection must identify the trust boundary: $($tamperedResult.output)"
  Write-Host 'PASS tests\adversarial\signed-calibration.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
