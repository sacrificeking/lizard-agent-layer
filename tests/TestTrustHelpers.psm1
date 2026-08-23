Set-StrictMode -Version 2.0

$repoRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $repoRoot 'scripts\Lizard.Trust.psm1')

function Write-LizardTestJson {
  param([string]$Path, $Value)
  [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 20), (New-Object Text.UTF8Encoding($false)))
}

function New-LizardTestTrustMaterial {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$BindingSha256,
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)][DateTimeOffset]$Now,
    [string]$PrincipalId = 'independent-verifier',
    [string[]]$Roles = @('verifier'),
    [string]$Purpose = 'loop-completion',
    [string]$PayloadKind = 'verifier-evidence'
  )
  New-Item -ItemType Directory -Path $Root -Force | Out-Null
  $rsa = [Security.Cryptography.RSA]::Create()
  try { $p = $rsa.ExportParameters($true) } finally { $rsa.Dispose() }
  $private = [pscustomobject][ordered]@{
    kty = 'RSA'; key_id = 'test-key-01'; issuer_id = 'test-org'; principal_id = $PrincipalId
    n = ConvertTo-LizardBase64Url $p.Modulus; e = ConvertTo-LizardBase64Url $p.Exponent; d = ConvertTo-LizardBase64Url $p.D
    p = ConvertTo-LizardBase64Url $p.P; q = ConvertTo-LizardBase64Url $p.Q; dp = ConvertTo-LizardBase64Url $p.DP
    dq = ConvertTo-LizardBase64Url $p.DQ; qi = ConvertTo-LizardBase64Url $p.InverseQ
  }
  $privatePath = Join-Path $Root 'private.jwk.json'; Write-LizardTestJson $privatePath $private
  $trust = [pscustomobject][ordered]@{
    schema_version = 1; organization_id = 'test-org'
    keys = @([pscustomobject][ordered]@{
      issuer_id = 'test-org'; key_id = 'test-key-01'; principal_id = $PrincipalId; roles = @($Roles); algorithm = 'RS256'; status = 'active'
      not_before = $Now.AddHours(-1).ToString('o'); not_after = $Now.AddYears(1).ToString('o')
      public_jwk = [pscustomobject][ordered]@{ kty = 'RSA'; n = $private.n; e = $private.e }
    })
    revoked_key_ids = @(); revoked_envelope_ids = @(); revoked_nonces = @()
  }
  $trustPath = Join-Path $Root 'trust.json'; Write-LizardTestJson $trustPath $trust
  $challenge = [pscustomobject][ordered]@{
    schema_version = 1; challenge_id = [Guid]::NewGuid().ToString('N'); nonce = (([Guid]::NewGuid().ToString('N')) + ([Guid]::NewGuid().ToString('N')))
    purpose = $Purpose; subject = $Subject; payload_kind = $PayloadKind; binding_sha256 = $BindingSha256; approval_ref = 'test-approval-01'
    issued_at = $Now.AddMinutes(-1).ToString('o'); expires_at = $Now.AddMinutes(30).ToString('o')
  }
  $challengePath = Join-Path $Root 'challenge.json'; Write-LizardTestJson $challengePath $challenge
  return [pscustomobject]@{
    private_key_path = $privatePath; private_key_sha256 = Get-LizardTrustFileSha256 $privatePath
    trust_store_path = $trustPath; trust_store_sha256 = Get-LizardTrustFileSha256 $trustPath
    challenge_path = $challengePath; challenge_sha256 = Get-LizardTrustFileSha256 $challengePath
    replay_ledger_path = Join-Path $Root 'replay.jsonl'; principal_id = $PrincipalId
  }
}

Export-ModuleMember -Function 'New-LizardTestTrustMaterial'
