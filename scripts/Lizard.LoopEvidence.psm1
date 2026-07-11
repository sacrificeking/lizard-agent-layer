Set-StrictMode -Version 2.0

function Get-LizardEvidenceSha256 {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) { $Value = '' }
  $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
}

function Get-LizardEvidencePayloadHash {
  param([Parameter(Mandatory = $true)]$Payload)
  return Get-LizardEvidenceSha256 -Value ($Payload | ConvertTo-Json -Depth 20 -Compress)
}

function New-LizardEvidenceEnvelope {
  param([Parameter(Mandatory = $true)][int]$SchemaVersion, [Parameter(Mandatory = $true)]$Payload)
  [pscustomobject][ordered]@{
    schema_version = $SchemaVersion
    payload = $Payload
    payload_hash = Get-LizardEvidencePayloadHash -Payload $Payload
  }
}

function Read-LizardEvidenceEnvelope {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$SchemaVersion)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "EVIDENCE_FILE_MISSING: $Path" }
  try { $envelope = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
  catch { throw "EVIDENCE_JSON_INVALID: $($_.Exception.Message)" }
  if ([int]$envelope.schema_version -ne $SchemaVersion) { throw "EVIDENCE_SCHEMA_UNSUPPORTED: Expected $SchemaVersion, got $($envelope.schema_version)." }
  if ($null -eq $envelope.payload -or [string]::IsNullOrWhiteSpace([string]$envelope.payload_hash)) { throw 'EVIDENCE_ENVELOPE_INVALID: payload and payload_hash are required.' }
  $actualHash = Get-LizardEvidencePayloadHash -Payload $envelope.payload
  if ($actualHash -ne [string]$envelope.payload_hash) { throw "EVIDENCE_HASH_MISMATCH: Expected $($envelope.payload_hash), got $actualHash." }
  return $envelope
}

function Get-LizardNormalizedGitPath {
  param([string]$Path, [string]$BasePath)
  if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function Get-LizardGitStateEvidence {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$WorktreePath)
  $rootOutput = & git -C $WorktreePath rev-parse --show-toplevel 2>&1
  if ($LASTEXITCODE -ne 0) { throw "GIT_STATE_ROOT_FAILED: $rootOutput" }
  $root = Get-LizardNormalizedGitPath -Path ([string]($rootOutput | Select-Object -First 1)) -BasePath $WorktreePath
  $headOutput = & git -C $root rev-parse HEAD 2>&1
  if ($LASTEXITCODE -ne 0) { throw "GIT_STATE_HEAD_FAILED: $headOutput" }
  $head = [string]($headOutput | Select-Object -First 1)
  $branchOutput = & git -C $root branch --show-current 2>&1
  if ($LASTEXITCODE -ne 0) { throw "GIT_STATE_BRANCH_FAILED: $branchOutput" }
  $branch = [string]($branchOutput | Select-Object -First 1)
  $status = @(& git -C $root status --porcelain=v1 --untracked-files=all 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "GIT_STATE_STATUS_FAILED: $($status -join '; ')" }
  $diff = (& git -C $root diff --binary HEAD -- 2>&1 | Out-String)
  if ($LASTEXITCODE -ne 0) { throw 'GIT_STATE_DIFF_FAILED: Unable to capture tracked diff.' }
  $untrackedPaths = @(& git -C $root ls-files --others --exclude-standard 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "GIT_STATE_UNTRACKED_FAILED: $($untrackedPaths -join '; ')" }
  $untracked = New-Object System.Collections.Generic.List[object]
  foreach ($relative in @($untrackedPaths | Sort-Object)) {
    if ([string]::IsNullOrWhiteSpace([string]$relative)) { continue }
    $full = [System.IO.Path]::GetFullPath((Join-Path $root ([string]$relative)))
    $untracked.Add([pscustomobject][ordered]@{
      path = ([string]$relative).Replace('\', '/')
      sha256 = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant()
    }) | Out-Null
  }
  $payload = [pscustomobject][ordered]@{
    worktree_root = $root
    head_sha = $head
    branch = $branch
    dirty = (@($status).Count -gt 0)
    status = @($status)
    tracked_diff_sha256 = Get-LizardEvidenceSha256 -Value $diff
    untracked_files = @($untracked.ToArray())
  }
  return [pscustomobject][ordered]@{
    payload = $payload
    state_hash = Get-LizardEvidencePayloadHash -Payload $payload
  }
}

Export-ModuleMember -Function @(
  'Get-LizardEvidencePayloadHash',
  'Get-LizardEvidenceSha256',
  'Get-LizardGitStateEvidence',
  'Get-LizardNormalizedGitPath',
  'New-LizardEvidenceEnvelope',
  'Read-LizardEvidenceEnvelope'
)
