param([string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))))

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.Trust.psm1') -Force

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw "ASSERT_TRUE_FAILED: $Message" } }
function Assert-ThrowsCode {
  param([scriptblock]$Action, [string]$Code)
  $caught = $null
  try { & $Action } catch { $caught = $_ }
  if ($null -eq $caught -or $caught.Exception.Message -notmatch ([regex]::Escape($Code))) { throw "ASSERT_THROWS_FAILED: Expected $Code, got $($caught.Exception.Message)" }
}
function Write-Json { param([string]$Path, $Value) Set-Content -LiteralPath $Path -Value ($Value | ConvertTo-Json -Depth 20) -Encoding UTF8 }

$testRoot = Join-Path $RepoRoot ('.tmp\tests\signed-evidence-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
try {
  $rsa = [Security.Cryptography.RSA]::Create()
  $parameters = $rsa.ExportParameters($true)
  $private = [pscustomobject][ordered]@{
    kty = 'RSA'; key_id = 'verifier-key-01'; issuer_id = 'example-org'; principal_id = 'verifier-01'
    n = ConvertTo-LizardBase64Url $parameters.Modulus; e = ConvertTo-LizardBase64Url $parameters.Exponent
    d = ConvertTo-LizardBase64Url $parameters.D; p = ConvertTo-LizardBase64Url $parameters.P; q = ConvertTo-LizardBase64Url $parameters.Q
    dp = ConvertTo-LizardBase64Url $parameters.DP; dq = ConvertTo-LizardBase64Url $parameters.DQ; qi = ConvertTo-LizardBase64Url $parameters.InverseQ
  }
  $rsa.Dispose()
  $keyPath = Join-Path $testRoot 'private.jwk.json'; Write-Json $keyPath $private
  $keySha = Get-LizardTrustFileSha256 $keyPath
  $now = [DateTimeOffset]'2026-08-22T10:00:00.0000000+00:00'
  $trust = [pscustomobject][ordered]@{
    schema_version = 1; organization_id = 'example-org'
    keys = @([pscustomobject][ordered]@{
      issuer_id = 'example-org'; key_id = 'verifier-key-01'; principal_id = 'verifier-01'; roles = @('verifier')
      algorithm = 'RS256'; status = 'active'; not_before = '2026-08-22T09:00:00.0000000+00:00'; not_after = '2027-08-22T10:00:00.0000000+00:00'
      public_jwk = [pscustomobject][ordered]@{ kty = 'RSA'; n = $private.n; e = $private.e }
    })
    revoked_key_ids = @(); revoked_envelope_ids = @(); revoked_nonces = @()
  }
  $trustPath = Join-Path $testRoot 'trust.json'; Write-Json $trustPath $trust
  $trustSha = Get-LizardTrustFileSha256 $trustPath
  $binding = ('a' * 64)
  $challenge = [pscustomobject][ordered]@{
    schema_version = 1; challenge_id = ('b' * 32); nonce = ('c' * 64); purpose = 'loop-completion'
    subject = 'operation-01'; payload_kind = 'verifier-evidence'; binding_sha256 = $binding; approval_ref = 'approval-01'
    issued_at = '2026-08-22T09:59:00.0000000+00:00'; expires_at = '2026-08-22T10:30:00.0000000+00:00'
  }
  $challengePath = Join-Path $testRoot 'challenge.json'; Write-Json $challengePath $challenge
  $challengeSha = Get-LizardTrustFileSha256 $challengePath
  $payload = [pscustomobject][ordered]@{ operation_id = 'operation-01'; effective_status = 'PASS'; auto_merge = $false }
  $envelope = New-LizardSignedEvidenceEnvelope -Payload $payload -PayloadKind verifier-evidence -Purpose loop-completion -Subject operation-01 -BindingSha256 $binding -ChallengePath $challengePath -ChallengeSha256 $challengeSha -PrivateKeyPath $keyPath -PrivateKeySha256 $keySha -Now $now
  $trustRead = Read-LizardTrustStore -Path $trustPath -ExpectedSha256 $trustSha -Now $now
  $challengeRead = Read-LizardTrustChallenge -Path $challengePath -ExpectedSha256 $challengeSha -Now $now
  $verified = Test-LizardSignedEvidenceEnvelope -Envelope $envelope -TrustStoreRead $trustRead -ChallengeRead $challengeRead -ExpectedPayloadKind verifier-evidence -ExpectedPurpose loop-completion -ExpectedSubject operation-01 -ExpectedBindingSha256 $binding -RequiredRole verifier -Now $now
  Assert-True ($verified.principal_id -eq 'verifier-01') 'Trusted principal should come from the signing key.'
  Assert-True ($verified.approval_ref -eq 'approval-01') 'External approval reference should survive verification.'

  $tampered = $envelope | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  $tampered.payload.effective_status = 'FAIL'
  Assert-ThrowsCode { Test-LizardSignedEvidenceEnvelope -Envelope $tampered -TrustStoreRead $trustRead -ChallengeRead $challengeRead -ExpectedPayloadKind verifier-evidence -ExpectedPurpose loop-completion -ExpectedSubject operation-01 -ExpectedBindingSha256 $binding -RequiredRole verifier -Now $now } 'TRUST_PAYLOAD_HASH_MISMATCH'
  Assert-ThrowsCode { Test-LizardSignedEvidenceEnvelope -Envelope $envelope -TrustStoreRead $trustRead -ChallengeRead $challengeRead -ExpectedPayloadKind verifier-evidence -ExpectedPurpose loop-completion -ExpectedSubject operation-02 -ExpectedBindingSha256 $binding -RequiredRole verifier -Now $now } 'TRUST_ENVELOPE_CONTEXT_MISMATCH'
  Assert-ThrowsCode { Test-LizardSignedEvidenceEnvelope -Envelope $envelope -TrustStoreRead $trustRead -ChallengeRead $challengeRead -ExpectedPayloadKind verifier-evidence -ExpectedPurpose loop-completion -ExpectedSubject operation-01 -ExpectedBindingSha256 $binding -RequiredRole implementer -Now $now } 'TRUST_ROLE_UNAUTHORIZED'

  $ledger = Join-Path $testRoot 'replay.jsonl'
  Use-LizardReplayLedger -LedgerPath $ledger -EnvelopeId $envelope.envelope_id -Nonce $envelope.nonce -Purpose loop-completion -Now $now | Out-Null
  Assert-ThrowsCode { Use-LizardReplayLedger -LedgerPath $ledger -EnvelopeId $envelope.envelope_id -Nonce $envelope.nonce -Purpose loop-completion -Now $now } 'TRUST_REPLAY_DETECTED'

  $revoked = $trust | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  $revoked.revoked_key_ids = @('verifier-key-01')
  $revokedPath = Join-Path $testRoot 'trust-revoked.json'; Write-Json $revokedPath $revoked
  $revokedRead = Read-LizardTrustStore -Path $revokedPath -ExpectedSha256 (Get-LizardTrustFileSha256 $revokedPath) -Now $now
  Assert-ThrowsCode { Test-LizardSignedEvidenceEnvelope -Envelope $envelope -TrustStoreRead $revokedRead -ChallengeRead $challengeRead -ExpectedPayloadKind verifier-evidence -ExpectedPurpose loop-completion -ExpectedSubject operation-01 -ExpectedBindingSha256 $binding -RequiredRole verifier -Now $now } 'TRUST_EVIDENCE_REVOKED'

  Write-Host 'signed-evidence adversarial tests passed'
} finally {
  if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
