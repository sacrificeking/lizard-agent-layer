param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.Json.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.Plan.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts/Lizard.Trust.psm1') -Force

$testRoot = Join-Path $RepoRoot ('.tmp/tests/signed-apply-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$targetRoot = Join-Path $testRoot 'target'
New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null

$installScript = Join-Path $RepoRoot 'scripts/install.ps1'

try {
  # 1. Generate RSA key pair for operator
  $rsa = [Security.Cryptography.RSA]::Create()
  $parameters = $rsa.ExportParameters($true)
  $operatorKey = [pscustomobject][ordered]@{
    kty = 'RSA'; key_id = 'operator-key-01'; issuer_id = 'acme-corp'; principal_id = 'security-officer-alice'
    n = ConvertTo-LizardBase64Url $parameters.Modulus; e = ConvertTo-LizardBase64Url $parameters.Exponent
    d = ConvertTo-LizardBase64Url $parameters.D; p = ConvertTo-LizardBase64Url $parameters.P; q = ConvertTo-LizardBase64Url $parameters.Q
    dp = ConvertTo-LizardBase64Url $parameters.DP; dq = ConvertTo-LizardBase64Url $parameters.DQ; qi = ConvertTo-LizardBase64Url $parameters.InverseQ
  }
  $rsa.Dispose()

  $keyPath = Join-Path $testRoot 'operator-private.jwk.json'
  Set-Content -LiteralPath $keyPath -Value ($operatorKey | ConvertTo-Json -Depth 20) -Encoding UTF8
  $keySha = Get-LizardTrustFileSha256 $keyPath

  $now = [DateTimeOffset]::UtcNow

  # 2. Generate Trust Store with 'operator' role
  $trustStore = [pscustomobject][ordered]@{
    schema_version = 1; organization_id = 'acme-corp'
    keys = @([pscustomobject][ordered]@{
      issuer_id = 'acme-corp'; key_id = 'operator-key-01'; principal_id = 'security-officer-alice'; roles = @('operator')
      algorithm = 'RS256'; status = 'active'; not_before = $now.AddDays(-1).ToString('o'); not_after = $now.AddYears(1).ToString('o')
      public_jwk = [pscustomobject][ordered]@{ kty = 'RSA'; n = $operatorKey.n; e = $operatorKey.e }
    })
    revoked_key_ids = @(); revoked_envelope_ids = @(); revoked_nonces = @()
  }
  $trustStorePath = Join-Path $testRoot 'trust-store.json'
  Set-Content -LiteralPath $trustStorePath -Value ($trustStore | ConvertTo-Json -Depth 20) -Encoding UTF8
  $trustStoreSha = Get-LizardTrustFileSha256 $trustStorePath

  # 3. Create plan preview using standard test helper
  $approval = New-TestInstallApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $targetRoot, '-Profile', 'minimal', '-Harnesses', 'generic-agents-md')
  $planPath = $approval.plan_path
  $planSha = $approval.sha256
  $planDoc = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $planPath -Raw)

  $targetRootIdentity = Get-LizardPlanRootHash $targetRoot

  # 4. Create short-lived challenge
  $challenge = [pscustomobject][ordered]@{
    schema_version = 1
    challenge_id = [Guid]::NewGuid().ToString('N')
    nonce = [Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')
    purpose = 'install-apply-approval'
    subject = $targetRootIdentity
    payload_kind = 'operation-plan'
    binding_sha256 = $planSha
    approval_ref = 'change-ticket-4821'
    issued_at = $now.AddMinutes(-1).ToString('o')
    expires_at = $now.AddMinutes(30).ToString('o')
  }
  $challengePath = Join-Path $testRoot 'challenge.json'
  Set-Content -LiteralPath $challengePath -Value ($challenge | ConvertTo-Json -Depth 20) -Encoding UTF8
  $challengeSha = Get-LizardTrustFileSha256 $challengePath

  # 5. Sign the approval envelope
  $envelope = New-LizardSignedEvidenceEnvelope `
    -Payload $planDoc `
    -PayloadKind 'operation-plan' `
    -Purpose 'install-apply-approval' `
    -Subject $targetRootIdentity `
    -BindingSha256 $planSha `
    -ChallengePath $challengePath `
    -ChallengeSha256 $challengeSha `
    -PrivateKeyPath $keyPath `
    -PrivateKeySha256 $keySha `
    -Now $now

  $envelopePath = Join-Path $testRoot 'approval-envelope.json'
  Set-Content -LiteralPath $envelopePath -Value ($envelope | ConvertTo-Json -Depth 20) -Encoding UTF8

  # Assert 1: Opt-in without required flags throws PLAN_SIGNED_APPROVAL_REQUIRED
  $missingArgsResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($approval.arguments) + @('-RequireSignedApproval'))
  Assert-False ($missingArgsResult.exit_code -eq 0) 'Opt-in signed approval without trust args must fail closed.'
  Assert-True ($missingArgsResult.output -match 'PLAN_SIGNED_APPROVAL_REQUIRED') 'Expected PLAN_SIGNED_APPROVAL_REQUIRED error.'

  # Assert 1b: Missing replay ledger throws PLAN_REPLAY_LEDGER_REQUIRED
  $missingLedgerResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($approval.arguments) + @(
    '-RequireSignedApproval',
    '-ApprovalEnvelopePath', $envelopePath,
    '-TrustStorePath', $trustStorePath,
    '-TrustStoreSha256', $trustStoreSha,
    '-ChallengePath', $challengePath,
    '-ChallengeSha256', $challengeSha
  ))
  Assert-False ($missingLedgerResult.exit_code -eq 0) 'Signed approval without replay ledger must fail closed.'
  Assert-True ($missingLedgerResult.output -match 'PLAN_REPLAY_LEDGER_REQUIRED') 'Expected PLAN_REPLAY_LEDGER_REQUIRED error.'

  $replayLedger = Join-Path $testRoot 'apply-replay.jsonl'

  # Assert 2: Envelope inside target root throws PLAN_APPROVAL_ENVELOPE_IN_TARGET
  $insideEnvelopePath = Join-Path $targetRoot 'approval-envelope.json'
  Set-Content -LiteralPath $insideEnvelopePath -Value ($envelope | ConvertTo-Json -Depth 20) -Encoding UTF8
  $insideResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($approval.arguments) + @(
    '-RequireSignedApproval',
    '-ApprovalEnvelopePath', $insideEnvelopePath,
    '-TrustStorePath', $trustStorePath,
    '-TrustStoreSha256', $trustStoreSha,
    '-ChallengePath', $challengePath,
    '-ChallengeSha256', $challengeSha,
    '-ReplayLedgerPath', $replayLedger
  ))
  Assert-False ($insideResult.exit_code -eq 0) 'Envelope inside target must fail closed.'
  Assert-True ($insideResult.output -match 'PLAN_APPROVAL_ENVELOPE_IN_TARGET') 'Expected PLAN_APPROVAL_ENVELOPE_IN_TARGET error.'

  # Assert 3: Valid signed apply succeeds
  $replayLedger = Join-Path $testRoot 'apply-replay.jsonl'
  $validResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($approval.arguments) + @(
    '-RequireSignedApproval',
    '-ApprovalEnvelopePath', $envelopePath,
    '-TrustStorePath', $trustStorePath,
    '-TrustStoreSha256', $trustStoreSha,
    '-ChallengePath', $challengePath,
    '-ChallengeSha256', $challengeSha,
    '-ReplayLedgerPath', $replayLedger
  ))
  Assert-Equal 0 $validResult.exit_code "Signed apply failed: $($validResult.output)"
  Assert-True (Test-Path -LiteralPath (Join-Path $targetRoot '.agent/lizard-agent-layer.install.json') -PathType Leaf) 'Install manifest should be created on successful signed apply.'

  # Assert 4: Replay with the same envelope/challenge fails closed
  $replayResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($approval.arguments) + @(
    '-RequireSignedApproval',
    '-ApprovalEnvelopePath', $envelopePath,
    '-TrustStorePath', $trustStorePath,
    '-TrustStoreSha256', $trustStoreSha,
    '-ChallengePath', $challengePath,
    '-ChallengeSha256', $challengeSha,
    '-ReplayLedgerPath', $replayLedger
  ))
  Assert-False ($replayResult.exit_code -eq 0) 'Replay of consumed envelope must fail closed.'
  Assert-True ($replayResult.output -match 'TRUST_REPLAY_DETECTED') 'Replay of consumed envelope must be detected and rejected.'

  Write-Host 'PASS tests\adversarial\signed-apply-approval.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
