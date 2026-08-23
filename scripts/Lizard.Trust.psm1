Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.Plan.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')

function New-LizardTrustException {
  param([string]$Code, [string]$Message)
  $exception = New-Object System.InvalidOperationException ("{0}: {1}" -f $Code, $Message)
  $exception.Data['trust_code'] = $Code
  return $exception
}

function Get-LizardTrustSha256 {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-LizardTrustFileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (New-LizardTrustException 'TRUST_FILE_MISSING' "File is missing: $Path") }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function ConvertFrom-LizardBase64Url {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value -notmatch '^[A-Za-z0-9_-]+$') { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'JWK value is not base64url.') }
  $text = $Value.Replace('-', '+').Replace('_', '/')
  while (($text.Length % 4) -ne 0) { $text += '=' }
  try { return [Convert]::FromBase64String($text) }
  catch { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'JWK value cannot be decoded.') }
}

function ConvertTo-LizardBase64Url {
  param([Parameter(Mandatory = $true)][byte[]]$Value)
  return ([Convert]::ToBase64String($Value)).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Assert-LizardTrustProperties {
  param($Document, [string[]]$Required, [string[]]$Allowed, [string]$Label)
  if ($null -eq $Document -or $Document -isnot [pscustomobject]) { throw (New-LizardTrustException 'TRUST_SHAPE_INVALID' "$Label must be a JSON object.") }
  $names = @($Document.PSObject.Properties.Name)
  foreach ($name in $Required) { if ($names -notcontains $name) { throw (New-LizardTrustException 'TRUST_SHAPE_INVALID' "$Label is missing '$name'.") } }
  foreach ($name in $names) { if ($Allowed -notcontains $name) { throw (New-LizardTrustException 'TRUST_SHAPE_INVALID' "$Label contains unsupported property '$name'.") } }
}

function Assert-LizardTrustIdentifier {
  param([AllowNull()]$Value, [string]$Label, [int]$MaxLength = 128)
  if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$Value) -or ([string]$Value).Length -gt $MaxLength -or [string]$Value -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._:/@+-]*$') {
    throw (New-LizardTrustException 'TRUST_IDENTIFIER_INVALID' "$Label must be an opaque bounded identifier.")
  }
}

function ConvertTo-LizardTrustUtc {
  param($Value, [string]$Label)
  if ($Value -isnot [string]) { throw (New-LizardTrustException 'TRUST_TIME_INVALID' "$Label must be an RFC3339 timestamp.") }
  $parsed = [DateTimeOffset]::MinValue
  if (-not [DateTimeOffset]::TryParseExact([string]$Value, 'o', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
    throw (New-LizardTrustException 'TRUST_TIME_INVALID' "$Label must be an RFC3339 timestamp.")
  }
  return $parsed.ToUniversalTime()
}

function Read-LizardTrustJson {
  param([string]$Path, [string]$ExpectedSha256, [string]$Label)
  if ($ExpectedSha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTrustException 'TRUST_DIGEST_REQUIRED' "$Label requires an exact SHA-256 digest.") }
  $actual = Get-LizardTrustFileSha256 -Path $Path
  if ($actual -ne $ExpectedSha256) { throw (New-LizardTrustException 'TRUST_DIGEST_MISMATCH' "$Label digest mismatch.") }
  try { $document = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $Path -Raw) }
  catch { throw (New-LizardTrustException 'TRUST_JSON_INVALID' "$Label JSON is invalid: $($_.Exception.Message)") }
  return [pscustomobject]@{ document = $document; sha256 = $actual; path = [IO.Path]::GetFullPath($Path) }
}

function Read-LizardTrustStore {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ExpectedSha256, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
  $read = Read-LizardTrustJson -Path $Path -ExpectedSha256 $ExpectedSha256 -Label 'Trust store'
  $store = $read.document
  $fields = @('schema_version', 'organization_id', 'keys', 'revoked_key_ids', 'revoked_envelope_ids', 'revoked_nonces')
  Assert-LizardTrustProperties $store $fields $fields 'Trust store'
  if ([int]$store.schema_version -ne 1) { throw (New-LizardTrustException 'TRUST_SCHEMA_UNSUPPORTED' 'Trust store schema_version must be 1.') }
  Assert-LizardTrustIdentifier $store.organization_id 'organization_id'
  foreach ($listName in @('revoked_key_ids', 'revoked_envelope_ids', 'revoked_nonces')) {
    if ($store.$listName -isnot [System.Array]) { throw (New-LizardTrustException 'TRUST_SHAPE_INVALID' "$listName must be an array.") }
  }
  $seen = @{}
  foreach ($key in @($store.keys)) {
    $keyFields = @('issuer_id', 'key_id', 'principal_id', 'roles', 'algorithm', 'status', 'not_before', 'not_after', 'public_jwk')
    Assert-LizardTrustProperties $key $keyFields $keyFields 'Trust key'
    foreach ($name in @('issuer_id', 'key_id', 'principal_id')) { Assert-LizardTrustIdentifier $key.$name $name }
    if ([string]$key.issuer_id -ne [string]$store.organization_id) { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'Trust key issuer must equal organization_id.') }
    if ($seen.ContainsKey([string]$key.key_id)) { throw (New-LizardTrustException 'TRUST_KEY_DUPLICATE' "Duplicate key_id '$($key.key_id)'.") }
    $seen[[string]$key.key_id] = $true
    if ([string]$key.algorithm -ne 'RS256' -or [string]$key.status -notin @('active', 'disabled')) { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'Trust key algorithm/status is invalid.') }
    if ($key.roles -isnot [System.Array] -or @($key.roles).Count -eq 0) { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'Trust key roles must be a non-empty array.') }
    foreach ($role in @($key.roles)) { Assert-LizardTrustIdentifier $role 'role' }
    $notBefore = ConvertTo-LizardTrustUtc $key.not_before 'not_before'
    $notAfter = ConvertTo-LizardTrustUtc $key.not_after 'not_after'
    if ($notAfter -le $notBefore) { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'Trust key validity interval is invalid.') }
    $jwkFields = @('kty', 'n', 'e')
    Assert-LizardTrustProperties $key.public_jwk $jwkFields $jwkFields 'public_jwk'
    if ([string]$key.public_jwk.kty -ne 'RSA') { throw (New-LizardTrustException 'TRUST_KEY_INVALID' 'Only RSA JWKs are supported.') }
    [void](ConvertFrom-LizardBase64Url $key.public_jwk.n); [void](ConvertFrom-LizardBase64Url $key.public_jwk.e)
  }
  return [pscustomobject]@{ store = $store; sha256 = $read.sha256; path = $read.path; now = $Now.ToUniversalTime() }
}

function Get-LizardRouteTrustBinding {
  [CmdletBinding()]
  param([string]$TargetRoot, [string]$ReceiptId, [string]$RouterId, [string]$RequestSha256, [string]$PolicySha256, [string]$RuntimeSourceSha256, [string]$InventorySha256)
  Assert-LizardTrustIdentifier $ReceiptId 'receipt_id'; Assert-LizardTrustIdentifier $RouterId 'router_id'
  foreach ($hash in @($RequestSha256, $PolicySha256, $RuntimeSourceSha256, $InventorySha256)) { if ($hash -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTrustException 'TRUST_BINDING_INVALID' 'Route binding requires exact SHA-256 inputs.') } }
  return Get-LizardPlanSha256 -InputObject ([pscustomobject][ordered]@{
    binding_kind = 'route-decision-v1'; target_root_identity_sha256 = Get-LizardPlanRootHash -TargetRoot $TargetRoot
    receipt_id = $ReceiptId; router_id = $RouterId; request_sha256 = $RequestSha256; policy_sha256 = $PolicySha256
    runtime_source_sha256 = $RuntimeSourceSha256; inventory_sha256 = $InventorySha256
  })
}

function Get-LizardExecutionTrustBinding {
  [CmdletBinding()]
  param([string]$TargetRoot, [string]$ReceiptId, [string]$RouteDecisionId, [string]$RoutePayloadSha256, [string]$ExecutorId, [string]$ConfigurationFingerprint, [string]$ActualModel, [string]$ActualProvider)
  foreach ($id in @($ReceiptId, $RouteDecisionId, $ExecutorId)) { Assert-LizardTrustIdentifier $id 'execution binding identifier' 200 }
  foreach ($id in @($ConfigurationFingerprint, $ActualModel, $ActualProvider)) { if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 200 -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$') { throw (New-LizardTrustException 'TRUST_BINDING_INVALID' 'Execution identity is not an opaque bounded identifier.') } }
  if ($RoutePayloadSha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTrustException 'TRUST_BINDING_INVALID' 'Execution binding requires the exact route payload hash.') }
  return Get-LizardPlanSha256 -InputObject ([pscustomobject][ordered]@{
    binding_kind = 'execution-receipt-v1'; target_root_identity_sha256 = Get-LizardPlanRootHash -TargetRoot $TargetRoot
    receipt_id = $ReceiptId; route_decision_id = $RouteDecisionId; route_payload_sha256 = $RoutePayloadSha256
    executor_id = $ExecutorId; configuration_fingerprint = $ConfigurationFingerprint; actual_model = $ActualModel; actual_provider = $ActualProvider
  })
}

function Get-LizardCalibrationTrustBinding {
  [CmdletBinding()]
  param([string]$TargetRoot, [string]$EvaluationId, [string]$ModelId, [string]$Provider, [string]$ExecutorId, [string]$ConfigurationFingerprint, [Parameter(Mandatory = $true)]$Cases)
  foreach ($id in @($EvaluationId, $ExecutorId)) { Assert-LizardTrustIdentifier $id 'calibration binding identifier' 200 }
  foreach ($id in @($ModelId, $Provider, $ConfigurationFingerprint)) { if ($id -isnot [string] -or [string]::IsNullOrWhiteSpace($id) -or $id.Length -gt 200 -or $id -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/@+-]*$') { throw (New-LizardTrustException 'TRUST_BINDING_INVALID' 'Calibration identity is not an opaque bounded identifier.') } }
  $caseSetSha256 = Get-LizardPlanSha256 -InputObject @($Cases)
  return Get-LizardPlanSha256 -InputObject ([pscustomobject][ordered]@{
    binding_kind = 'model-calibration-v1'; target_root_identity_sha256 = Get-LizardPlanRootHash -TargetRoot $TargetRoot
    evaluation_id = $EvaluationId; model_id = $ModelId; provider = $Provider; executor_id = $ExecutorId
    configuration_fingerprint = $ConfigurationFingerprint; case_set_sha256 = $caseSetSha256
  })
}

function Read-LizardTrustChallenge {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$ExpectedSha256, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
  $read = Read-LizardTrustJson -Path $Path -ExpectedSha256 $ExpectedSha256 -Label 'Challenge'
  $challenge = $read.document
  $fields = @('schema_version', 'challenge_id', 'nonce', 'purpose', 'subject', 'payload_kind', 'binding_sha256', 'approval_ref', 'issued_at', 'expires_at')
  Assert-LizardTrustProperties $challenge $fields $fields 'Challenge'
  if ([int]$challenge.schema_version -ne 1) { throw (New-LizardTrustException 'TRUST_SCHEMA_UNSUPPORTED' 'Challenge schema_version must be 1.') }
  foreach ($name in @('challenge_id', 'purpose', 'subject', 'payload_kind', 'approval_ref')) { Assert-LizardTrustIdentifier $challenge.$name $name }
  if ([string]$challenge.challenge_id -notmatch '^[a-f0-9]{32}$' -or [string]$challenge.nonce -notmatch '^[a-f0-9]{64}$' -or [string]$challenge.binding_sha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTrustException 'TRUST_CHALLENGE_INVALID' 'Challenge identifiers or binding hash are invalid.') }
  $issued = ConvertTo-LizardTrustUtc $challenge.issued_at 'issued_at'
  $expires = ConvertTo-LizardTrustUtc $challenge.expires_at 'expires_at'
  $clock = $Now.ToUniversalTime()
  if ($expires -le $issued -or $clock -lt $issued.AddMinutes(-5) -or $clock -gt $expires) { throw (New-LizardTrustException 'TRUST_CHALLENGE_EXPIRED' 'Challenge is not valid at the current time.') }
  return [pscustomobject]@{ challenge = $challenge; sha256 = $read.sha256; path = $read.path }
}

function ConvertTo-LizardRsaParameters {
  param($Jwk, [switch]$Private)
  $parameters = New-Object System.Security.Cryptography.RSAParameters
  $parameters.Modulus = ConvertFrom-LizardBase64Url $Jwk.n
  $parameters.Exponent = ConvertFrom-LizardBase64Url $Jwk.e
  if ($Private) {
    foreach ($name in @('d', 'p', 'q', 'dp', 'dq', 'qi')) { if ($Jwk.PSObject.Properties.Name -notcontains $name) { throw (New-LizardTrustException 'TRUST_PRIVATE_KEY_INVALID' "Private JWK is missing '$name'.") } }
    $parameters.D = ConvertFrom-LizardBase64Url $Jwk.d
    $parameters.P = ConvertFrom-LizardBase64Url $Jwk.p
    $parameters.Q = ConvertFrom-LizardBase64Url $Jwk.q
    $parameters.DP = ConvertFrom-LizardBase64Url $Jwk.dp
    $parameters.DQ = ConvertFrom-LizardBase64Url $Jwk.dq
    $parameters.InverseQ = ConvertFrom-LizardBase64Url $Jwk.qi
  }
  return $parameters
}

function Get-LizardSignedEvidenceDocument {
  param($Envelope)
  return [pscustomobject][ordered]@{
    schema_version = [int]$Envelope.schema_version; artifact_kind = [string]$Envelope.artifact_kind; envelope_id = [string]$Envelope.envelope_id
    payload_kind = [string]$Envelope.payload_kind; issuer_id = [string]$Envelope.issuer_id; key_id = [string]$Envelope.key_id
    principal_id = [string]$Envelope.principal_id; issued_at = [string]$Envelope.issued_at; expires_at = [string]$Envelope.expires_at
    purpose = [string]$Envelope.purpose; subject = [string]$Envelope.subject; nonce = [string]$Envelope.nonce
    challenge_sha256 = [string]$Envelope.challenge_sha256; binding_sha256 = [string]$Envelope.binding_sha256
    approval_ref = [string]$Envelope.approval_ref; payload_sha256 = [string]$Envelope.payload_sha256
    signature_algorithm = [string]$Envelope.signature_algorithm
  }
}

function Read-LizardPrivateJwk {
  param([string]$Path, [string]$ExpectedSha256)
  $read = Read-LizardTrustJson -Path $Path -ExpectedSha256 $ExpectedSha256 -Label 'Private signing key'
  $fields = @('kty', 'key_id', 'issuer_id', 'principal_id', 'n', 'e', 'd', 'p', 'q', 'dp', 'dq', 'qi')
  Assert-LizardTrustProperties $read.document $fields $fields 'Private JWK'
  if ([string]$read.document.kty -ne 'RSA') { throw (New-LizardTrustException 'TRUST_PRIVATE_KEY_INVALID' 'Only RSA private JWKs are supported.') }
  foreach ($name in @('key_id', 'issuer_id', 'principal_id')) { Assert-LizardTrustIdentifier $read.document.$name $name }
  return $read.document
}

function New-LizardSignedEvidenceEnvelope {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Payload,
    [Parameter(Mandatory = $true)][string]$PayloadKind,
    [Parameter(Mandatory = $true)][string]$Purpose,
    [Parameter(Mandatory = $true)][string]$Subject,
    [Parameter(Mandatory = $true)][string]$BindingSha256,
    [Parameter(Mandatory = $true)][string]$ChallengePath,
    [Parameter(Mandatory = $true)][string]$ChallengeSha256,
    [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
    [Parameter(Mandatory = $true)][string]$PrivateKeySha256,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )
  $challengeRead = Read-LizardTrustChallenge -Path $ChallengePath -ExpectedSha256 $ChallengeSha256 -Now $Now
  $challenge = $challengeRead.challenge
  if ([string]$challenge.payload_kind -ne $PayloadKind -or [string]$challenge.purpose -ne $Purpose -or [string]$challenge.subject -ne $Subject -or [string]$challenge.binding_sha256 -ne $BindingSha256) { throw (New-LizardTrustException 'TRUST_CHALLENGE_BINDING_MISMATCH' 'Challenge does not authorize this payload context.') }
  $key = Read-LizardPrivateJwk -Path $PrivateKeyPath -ExpectedSha256 $PrivateKeySha256
  $issued = $Now.ToUniversalTime()
  $challengeExpiry = ConvertTo-LizardTrustUtc $challenge.expires_at 'expires_at'
  $expires = if ($challengeExpiry -lt $issued.AddHours(1)) { $challengeExpiry } else { $issued.AddHours(1) }
  $payloadHash = Get-LizardPlanSha256 -InputObject $Payload
  $envelope = [pscustomobject][ordered]@{
    schema_version = 2; artifact_kind = 'signed-evidence'; envelope_id = [Guid]::NewGuid().ToString('N'); payload_kind = $PayloadKind
    issuer_id = [string]$key.issuer_id; key_id = [string]$key.key_id; principal_id = [string]$key.principal_id
    issued_at = $issued.ToString('o'); expires_at = $expires.ToString('o'); purpose = $Purpose; subject = $Subject
    nonce = [string]$challenge.nonce; challenge_sha256 = $challengeRead.sha256; binding_sha256 = $BindingSha256
    approval_ref = [string]$challenge.approval_ref; payload_sha256 = $payloadHash; signature_algorithm = 'RS256'
    payload = $Payload; signature = $null
  }
  $canonical = ConvertTo-LizardCanonicalJson (Get-LizardSignedEvidenceDocument $envelope)
  $rsa = [Security.Cryptography.RSA]::Create()
  try {
    $rsa.ImportParameters((ConvertTo-LizardRsaParameters -Jwk $key -Private))
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($canonical)
    $signature = $rsa.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $envelope.signature = ConvertTo-LizardBase64Url $signature
  } finally { $rsa.Dispose() }
  return $envelope
}

function Test-LizardSignedEvidenceEnvelope {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]$Envelope,
    [Parameter(Mandatory = $true)]$TrustStoreRead,
    [Parameter(Mandatory = $true)]$ChallengeRead,
    [Parameter(Mandatory = $true)][string]$ExpectedPayloadKind,
    [Parameter(Mandatory = $true)][string]$ExpectedPurpose,
    [Parameter(Mandatory = $true)][string]$ExpectedSubject,
    [Parameter(Mandatory = $true)][string]$ExpectedBindingSha256,
    [Parameter(Mandatory = $true)][string]$RequiredRole,
    [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow
  )
  $fields = @('schema_version','artifact_kind','envelope_id','payload_kind','issuer_id','key_id','principal_id','issued_at','expires_at','purpose','subject','nonce','challenge_sha256','binding_sha256','approval_ref','payload_sha256','signature_algorithm','payload','signature')
  Assert-LizardTrustProperties $Envelope $fields $fields 'Signed evidence envelope'
  if ([int]$Envelope.schema_version -ne 2 -or [string]$Envelope.artifact_kind -ne 'signed-evidence' -or [string]$Envelope.signature_algorithm -ne 'RS256') { throw (New-LizardTrustException 'TRUST_ENVELOPE_INVALID' 'Signed evidence envelope metadata is invalid.') }
  foreach ($name in @('payload_kind','issuer_id','key_id','principal_id','purpose','subject','approval_ref')) { Assert-LizardTrustIdentifier $Envelope.$name $name }
  if ([string]$Envelope.envelope_id -notmatch '^[a-f0-9]{32}$' -or [string]$Envelope.nonce -notmatch '^[a-f0-9]{64}$' -or [string]$Envelope.payload_sha256 -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTrustException 'TRUST_ENVELOPE_INVALID' 'Signed evidence identifiers are invalid.') }
  if ([string]$Envelope.payload_kind -ne $ExpectedPayloadKind -or [string]$Envelope.purpose -ne $ExpectedPurpose -or [string]$Envelope.subject -ne $ExpectedSubject -or [string]$Envelope.binding_sha256 -ne $ExpectedBindingSha256) { throw (New-LizardTrustException 'TRUST_ENVELOPE_CONTEXT_MISMATCH' 'Signed evidence does not match the required context.') }
  $challenge = $ChallengeRead.challenge
  if ([string]$Envelope.challenge_sha256 -ne [string]$ChallengeRead.sha256 -or [string]$Envelope.nonce -ne [string]$challenge.nonce -or [string]$Envelope.approval_ref -ne [string]$challenge.approval_ref) { throw (New-LizardTrustException 'TRUST_CHALLENGE_MISMATCH' 'Signed evidence does not match the supplied challenge.') }
  if ([string]$challenge.payload_kind -ne $ExpectedPayloadKind -or [string]$challenge.purpose -ne $ExpectedPurpose -or [string]$challenge.subject -ne $ExpectedSubject -or [string]$challenge.binding_sha256 -ne $ExpectedBindingSha256) { throw (New-LizardTrustException 'TRUST_CHALLENGE_BINDING_MISMATCH' 'Challenge does not match the required context.') }
  $clock = $Now.ToUniversalTime(); $issued = ConvertTo-LizardTrustUtc $Envelope.issued_at 'issued_at'; $expires = ConvertTo-LizardTrustUtc $Envelope.expires_at 'expires_at'
  if ($expires -le $issued -or $clock -lt $issued.AddMinutes(-5) -or $clock -gt $expires) { throw (New-LizardTrustException 'TRUST_ENVELOPE_EXPIRED' 'Signed evidence is not valid at the current time.') }
  $payloadHash = Get-LizardPlanSha256 -InputObject $Envelope.payload
  if ($payloadHash -ne [string]$Envelope.payload_sha256) { throw (New-LizardTrustException 'TRUST_PAYLOAD_HASH_MISMATCH' 'Signed evidence payload hash mismatch.') }
  $store = $TrustStoreRead.store
  if (@($store.revoked_envelope_ids) -contains [string]$Envelope.envelope_id -or @($store.revoked_nonces) -contains [string]$Envelope.nonce -or @($store.revoked_key_ids) -contains [string]$Envelope.key_id) { throw (New-LizardTrustException 'TRUST_EVIDENCE_REVOKED' 'Signed evidence, nonce, or key is revoked.') }
  $matches = @($store.keys | Where-Object { [string]$_.key_id -eq [string]$Envelope.key_id -and [string]$_.issuer_id -eq [string]$Envelope.issuer_id -and [string]$_.principal_id -eq [string]$Envelope.principal_id })
  if ($matches.Count -ne 1) { throw (New-LizardTrustException 'TRUST_KEY_UNTRUSTED' 'Signing key is not uniquely trusted for this principal.') }
  $trustedKey = $matches[0]
  if ([string]$trustedKey.status -ne 'active' -or @($trustedKey.roles) -notcontains $RequiredRole) { throw (New-LizardTrustException 'TRUST_ROLE_UNAUTHORIZED' "Signing key lacks active '$RequiredRole' authority.") }
  $notBefore = ConvertTo-LizardTrustUtc $trustedKey.not_before 'not_before'; $notAfter = ConvertTo-LizardTrustUtc $trustedKey.not_after 'not_after'
  if ($issued -lt $notBefore -or $issued -gt $notAfter -or $clock -gt $notAfter) { throw (New-LizardTrustException 'TRUST_KEY_EXPIRED' 'Signing key is not valid for the evidence time.') }
  $canonical = ConvertTo-LizardCanonicalJson (Get-LizardSignedEvidenceDocument $Envelope)
  $rsa = [Security.Cryptography.RSA]::Create()
  try {
    $rsa.ImportParameters((ConvertTo-LizardRsaParameters $trustedKey.public_jwk))
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes($canonical)
    $signature = ConvertFrom-LizardBase64Url $Envelope.signature
    if (-not $rsa.VerifyData($bytes, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)) { throw (New-LizardTrustException 'TRUST_SIGNATURE_INVALID' 'Signed evidence signature is invalid.') }
  } finally { $rsa.Dispose() }
  return [pscustomobject]@{ envelope = $Envelope; payload = $Envelope.payload; principal_id = [string]$Envelope.principal_id; approval_ref = [string]$Envelope.approval_ref; envelope_id = [string]$Envelope.envelope_id; nonce = [string]$Envelope.nonce }
}

function Read-LizardSignedEvidenceFile {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw (New-LizardTrustException 'TRUST_EVIDENCE_MISSING' "Signed evidence is missing: $Path") }
  try { return ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $Path -Raw) }
  catch { throw (New-LizardTrustException 'TRUST_EVIDENCE_JSON_INVALID' $_.Exception.Message) }
}

function Use-LizardReplayLedger {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$LedgerPath, [Parameter(Mandatory = $true)][string]$EnvelopeId, [Parameter(Mandatory = $true)][string]$Nonce, [Parameter(Mandatory = $true)][string]$Purpose, [DateTimeOffset]$Now = [DateTimeOffset]::UtcNow)
  if ($EnvelopeId -notmatch '^[a-f0-9]{32}$' -or $Nonce -notmatch '^[a-f0-9]{64}$') { throw (New-LizardTrustException 'TRUST_REPLAY_RECORD_INVALID' 'Replay identifiers are invalid.') }
  $full = [IO.Path]::GetFullPath($LedgerPath); $root = Split-Path -Parent $full
  if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw (New-LizardTrustException 'TRUST_REPLAY_ROOT_MISSING' 'Replay ledger parent must already exist.') }
  $safe = Resolve-SafeTargetDestination -AuthorizedRoot $root -DestinationPath $full
  $lockPath = "$safe.lock"; $lock = $null
  try {
    try { $lock = New-Object IO.FileStream($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None) }
    catch { throw (New-LizardTrustException 'TRUST_REPLAY_LEDGER_BUSY' 'Replay ledger is locked by another consumer.') }
    if (Test-Path -LiteralPath $safe -PathType Leaf) {
      foreach ($line in @(Get-Content -LiteralPath $safe)) {
        if ([string]::IsNullOrWhiteSpace([string]$line)) { continue }
        try { $entry = ConvertFrom-LizardJson -InputObject $line } catch { throw (New-LizardTrustException 'TRUST_REPLAY_LEDGER_INVALID' 'Replay ledger contains invalid JSON.') }
        if ([string]$entry.envelope_id -eq $EnvelopeId -or [string]$entry.nonce -eq $Nonce) { throw (New-LizardTrustException 'TRUST_REPLAY_DETECTED' 'Evidence envelope or challenge nonce was already consumed.') }
      }
    }
    $entry = [pscustomobject][ordered]@{ schema_version = 1; envelope_id = $EnvelopeId; nonce = $Nonce; purpose = $Purpose; consumed_at = $Now.ToUniversalTime().ToString('o') }
    Add-SafeContent -AuthorizedRoot $root -Path $safe -Value (($entry | ConvertTo-Json -Compress) + [Environment]::NewLine)
    return $entry
  } finally {
    if ($null -ne $lock) { $lock.Dispose() }
    if (Test-Path -LiteralPath $lockPath -PathType Leaf) { Remove-Item -LiteralPath $lockPath -Force }
  }
}

Export-ModuleMember -Function @(
  'ConvertTo-LizardBase64Url', 'Get-LizardCalibrationTrustBinding', 'Get-LizardExecutionTrustBinding', 'Get-LizardRouteTrustBinding', 'Get-LizardTrustFileSha256', 'New-LizardSignedEvidenceEnvelope', 'Read-LizardSignedEvidenceFile',
  'Read-LizardTrustChallenge', 'Read-LizardTrustStore', 'Test-LizardSignedEvidenceEnvelope', 'Use-LizardReplayLedger'
)
