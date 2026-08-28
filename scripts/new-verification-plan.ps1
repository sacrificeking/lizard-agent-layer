param(
  [string]$WorktreePath = (Get-Location).Path,
  [Parameter(Mandatory)][ValidateSet('git-head', 'git-missing-ref-probe')][string[]]$CommandId,
  [string]$OutputPath,
  [ValidateRange(1, 1440)][int]$ValidForMinutes = 30,
  [switch]$WritePlan,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.ConstrainedRunner.psm1') -Force

$worktreeRoot = Resolve-SafeRoot -Path $WorktreePath -RequireExisting
$createdAt = [DateTimeOffset]::UtcNow
$plan = New-LizardVerificationPlan -WorktreeRoot $worktreeRoot -CommandIds $CommandId -CreatedAt $createdAt -ExpiresAt $createdAt.AddMinutes($ValidForMinutes)
$planJson = $plan | ConvertTo-Json -Depth 12
$encoding = New-Object System.Text.UTF8Encoding($false)
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $previewSha256 = ([System.BitConverter]::ToString($sha.ComputeHash($encoding.GetBytes($planJson)))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }

$writtenPath = $null
$writtenSha256 = $null
if ($WritePlan) {
  if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $planDir = Initialize-SafeDirectory -Path (Join-Path $LayerRoot '.tmp/verification-plans')
    $OutputPath = Join-Path $planDir ("verification-{0}.json" -f $plan.plan_id)
  } else {
    $OutputPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) { [System.IO.Path]::GetFullPath($OutputPath) } else { [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $OutputPath)) }
    $planDir = Initialize-SafeDirectory -Path (Split-Path -Parent $OutputPath)
  }
  Assert-PathOutsideRoot -Path $OutputPath -ExcludedRoot $worktreeRoot -Label 'Verification plan path'
  Set-SafeContent -AuthorizedRoot $planDir -Path $OutputPath -Value $planJson
  $writtenPath = [System.IO.Path]::GetFullPath($OutputPath)
  $writtenSha256 = (Get-FileHash -LiteralPath $writtenPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

$result = [pscustomobject][ordered]@{
  mode = if ($WritePlan) { 'WRITE' } else { 'PREVIEW' }
  plan = $plan
  preview_sha256 = $previewSha256
  written_path = $writtenPath
  written_sha256 = $writtenSha256
}
if ($Json) { $result | ConvertTo-Json -Depth 14 }
else {
  Write-Host "Verification plan: $($result.mode)"
  Write-Host "Plan ID: $($plan.plan_id)"
  Write-Host "Commands: $(@($CommandId) -join ', ')"
  Write-Host "Expires: $($plan.expires_at)"
  if ($WritePlan) {
    Write-Host "Path: $writtenPath"
    Write-Host "SHA-256: $writtenSha256"
    Write-Host 'Review the exact plan outside the worktree before approving loop-verify.'
  } else {
    Write-Host 'Preview only. Use -WritePlan to create an independently reviewable plan outside the worktree.'
  }
}
