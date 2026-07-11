param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [ValidateSet('Rollback')][string]$Action = 'Rollback',
  [switch]$Apply,
  [switch]$HumanApproved,
  [switch]$Force,
  [switch]$Json,
  [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Transaction.psm1') -Force
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'

function Resolve-UserPath {
  param([string]$Path, [string]$Fallback)
  $candidate = if ([string]::IsNullOrWhiteSpace($Path)) { $Fallback } else { $Path }
  if ([System.IO.Path]::IsPathRooted($candidate)) { return [System.IO.Path]::GetFullPath($candidate) }
  return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $candidate))
}

$EffectiveOutputDir = Resolve-UserPath -Path $OutputDir -Fallback (Join-Path $LayerRoot ".tmp\transactions\recover-$stamp")
Assert-PathOutsideRoot -Path $EffectiveOutputDir -ExcludedRoot $TargetRoot -Label 'OutputDir'
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$lock = Get-LizardTransactionLock -TargetRoot $TargetRoot
$ownerRunning = $false
$result = $null

if ($null -eq $lock) {
  $warnings.Add('No transaction lock exists; the target has no recoverable operation.') | Out-Null
} else {
  try { $ownerRunning = $null -ne (Get-Process -Id ([int]$lock.owner_pid) -ErrorAction Stop) }
  catch { $ownerRunning = $false }
  if ($Apply -and -not $HumanApproved) { $failures.Add('Apply requires -HumanApproved.') | Out-Null }
  if ($Apply -and $ownerRunning -and -not $Force) { $failures.Add("Transaction owner PID $($lock.owner_pid) is still running. Use -Force only after confirming it is stale.") | Out-Null }
}

if ($Apply -and $null -ne $lock -and $failures.Count -eq 0) {
  Join-LizardTransaction -TargetRoot $TargetRoot -OperationId ([string]$lock.operation_id) | Out-Null
  $result = Undo-LizardTransaction
}

$status = if ($failures.Count -gt 0) { 'STOP' } elseif ($null -eq $lock) { 'CLEAN' } elseif ($Apply) { 'ROLLED_BACK' } else { 'RECOVERY_AVAILABLE' }
$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
  status = $status
  action = $Action
  target = $TargetRoot
  operation_id = if ($lock) { [string]$lock.operation_id } else { $null }
  operation_name = if ($lock) { [string]$lock.operation_name } else { $null }
  owner_pid = if ($lock) { [int]$lock.owner_pid } else { $null }
  owner_running = $ownerRunning
  human_approved = $HumanApproved.IsPresent
  force = $Force.IsPresent
  recovery_result = $result
  warnings = @($warnings.ToArray())
  failures = @($failures.ToArray())
}
$jsonPath = Join-Path $EffectiveOutputDir 'transaction-recovery-report.json'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 10)

if ($Json) {
  $report | ConvertTo-Json -Depth 10
} else {
  Write-Host 'lizard-agent-layer transaction recovery'
  Write-Host "Mode: $($report.mode)"
  Write-Host "Status: $status"
  Write-Host "Target: $TargetRoot"
  Write-Host "Operation: $($report.operation_id)"
  Write-Host "Owner running: $ownerRunning"
  Write-Host "Report: $jsonPath"
  if (-not $Apply -and $null -ne $lock) { Write-Host 'Preview only. Re-run with -Apply -HumanApproved after confirming the owner process is stale.' }
}
if ($failures.Count -gt 0) { exit 1 }
