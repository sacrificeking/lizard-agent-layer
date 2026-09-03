param(
  [Parameter(Mandatory = $true)][string]$TargetPath,
  [Parameter(Mandatory = $true)][string]$ApprovedPlanPath,
  [Parameter(Mandatory = $true)][string]$ApprovedPlanSha256,
  [Parameter(Mandatory = $true)][string]$OutputDir,
  [string]$KeyId = ("key-" + [Guid]::NewGuid().ToString('N').Substring(0, 8)),
  [string]$OrganizationId = 'local-operator',
  [string]$IssuerId = 'local-operator',
  [string]$PrincipalId = 'operator',
  [switch]$AllowTargetReportWrite
)

if ($IssuerId -ne $OrganizationId) {
  if ($PSBoundParameters.ContainsKey('OrganizationId') -and -not $PSBoundParameters.ContainsKey('IssuerId')) { $IssuerId = $OrganizationId }
  else { $OrganizationId = $IssuerId }
}

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir

Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Plan.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Trust.psm1') -Force

$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting

if (-not $AllowTargetReportWrite) {
  Assert-PathOutsideRoot -Path $ApprovedPlanPath -ExcludedRoot $TargetRoot -Label 'ApprovedPlanPath'
  Assert-PathOutsideRoot -Path $OutputDir -ExcludedRoot $TargetRoot -Label 'OutputDir'
}

$outputRoot = Initialize-SafeDirectory -Path $OutputDir

$planFull = ConvertTo-LizardFullPath -Path $ApprovedPlanPath
$planDir = Split-Path -Parent $planFull
$planSafeRoot = Resolve-SafeRoot -Path $planDir -RequireExisting
$planBytes = Get-SafeBytes -AuthorizedRoot $planSafeRoot -Path $planFull
$planRaw = (New-Object System.Text.UTF8Encoding($false, $true)).GetString($planBytes)
$planJson = ConvertFrom-LizardJson -InputObject $planRaw
$opKind = [string]$planJson.operation_kind

$plan = Read-LizardApprovedPlan -Path $ApprovedPlanPath -ExpectedSha256 $ApprovedPlanSha256 -ExpectedOperationKind $opKind

$rsa = [System.Security.Cryptography.RSA]::Create(2048)
try {
  $p = $rsa.ExportParameters($true)
} finally {
  $rsa.Dispose()
}

$privateJwk = [pscustomobject][ordered]@{
  kty = 'RSA'
  key_id = $KeyId
  issuer_id = $IssuerId
  principal_id = $PrincipalId
  n = ConvertTo-LizardBase64Url $p.Modulus
  e = ConvertTo-LizardBase64Url $p.Exponent
  d = ConvertTo-LizardBase64Url $p.D
  p = ConvertTo-LizardBase64Url $p.P
  q = ConvertTo-LizardBase64Url $p.Q
  dp = ConvertTo-LizardBase64Url $p.DP
  dq = ConvertTo-LizardBase64Url $p.DQ
  qi = ConvertTo-LizardBase64Url $p.InverseQ
}

$privateKeyPath = Join-Path $outputRoot 'private-key.jwk.json'
Set-SafeContent -AuthorizedRoot $outputRoot -Path $privateKeyPath -Value ($privateJwk | ConvertTo-Json -Depth 20)
$privateKeySha = Get-SafeFileHash -AuthorizedRoot $outputRoot -Path $privateKeyPath

$now = [DateTimeOffset]::UtcNow
$trustStore = [pscustomobject][ordered]@{
  schema_version = 1
  organization_id = $OrganizationId
  keys = @(
    [pscustomobject][ordered]@{
      issuer_id = $IssuerId
      key_id = $KeyId
      principal_id = $PrincipalId
      roles = @('operator')
      algorithm = 'RS256'
      status = 'active'
      not_before = $now.AddMinutes(-5).ToString('o')
      not_after = $now.AddDays(7).ToString('o')
      public_jwk = [pscustomobject][ordered]@{
        kty = 'RSA'
        n = $privateJwk.n
        e = $privateJwk.e
      }
    }
  )
  revoked_key_ids = @()
  revoked_envelope_ids = @()
  revoked_nonces = @()
}

$trustStorePath = Join-Path $outputRoot 'trust-store.json'
Set-SafeContent -AuthorizedRoot $outputRoot -Path $trustStorePath -Value ($trustStore | ConvertTo-Json -Depth 20)
$trustStoreSha = Get-SafeFileHash -AuthorizedRoot $outputRoot -Path $trustStorePath

$targetSubject = Get-LizardPlanRootHash $TargetRoot
$expectedPurpose = "$opKind-apply-approval"
$challengeNonce = (([Guid]::NewGuid().ToString('N')) + ([Guid]::NewGuid().ToString('N')))
$challenge = [pscustomobject][ordered]@{
  schema_version = 1
  challenge_id = [Guid]::NewGuid().ToString('N')
  nonce = $challengeNonce
  purpose = $expectedPurpose
  subject = $targetSubject
  payload_kind = 'operation-plan'
  binding_sha256 = $ApprovedPlanSha256.ToLowerInvariant()
  approval_ref = ("approval-" + [Guid]::NewGuid().ToString('N').Substring(0, 12))
  issued_at = $now.ToString('o')
  expires_at = $now.AddHours(2).ToString('o')
}

$challengePath = Join-Path $outputRoot 'challenge.json'
Set-SafeContent -AuthorizedRoot $outputRoot -Path $challengePath -Value ($challenge | ConvertTo-Json -Depth 20)
$challengeSha = Get-SafeFileHash -AuthorizedRoot $outputRoot -Path $challengePath

$envelope = New-LizardSignedEvidenceEnvelope `
  -Payload $plan `
  -PayloadKind 'operation-plan' `
  -Purpose $expectedPurpose `
  -Subject $targetSubject `
  -BindingSha256 $ApprovedPlanSha256.ToLowerInvariant() `
  -ChallengePath $challengePath `
  -ChallengeSha256 $challengeSha `
  -PrivateKeyPath $privateKeyPath `
  -PrivateKeySha256 $privateKeySha `
  -Now $now

$envelopePath = Join-Path $outputRoot 'approval-envelope.json'
Set-SafeContent -AuthorizedRoot $outputRoot -Path $envelopePath -Value ($envelope | ConvertTo-Json -Depth 20)

$replayLedgerPath = Join-Path $outputRoot 'replay-ledger.jsonl'
if (-not (Test-Path -LiteralPath $replayLedgerPath)) {
  Set-SafeContent -AuthorizedRoot $outputRoot -Path $replayLedgerPath -Value ""
}

Write-Host "Signed plan approval generated successfully."
Write-Host "CAUTION: The private key ($privateKeyPath) must NEVER be committed to git or stored inside the target repository."
Write-Host ""
Write-Host "Apply arguments:"
Write-Host "  -ApprovalEnvelopePath `"$envelopePath`""
Write-Host "  -TrustStorePath `"$trustStorePath`""
Write-Host "  -TrustStoreSha256 `"$trustStoreSha`""
Write-Host "  -ChallengePath `"$challengePath`""
Write-Host "  -ChallengeSha256 `"$challengeSha`""
Write-Host "  -ReplayLedgerPath `"$replayLedgerPath`""

return [pscustomobject][ordered]@{
  envelope_path = $envelopePath
  trust_store_path = $trustStorePath
  trust_store_sha256 = $trustStoreSha
  challenge_path = $challengePath
  challenge_sha256 = $challengeSha
  replay_ledger_path = $replayLedgerPath
  private_key_path = $privateKeyPath
}
