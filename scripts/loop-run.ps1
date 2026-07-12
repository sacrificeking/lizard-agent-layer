param(
  [ValidateSet('Status', 'Start', 'Complete', 'Fail')][string]$Action = 'Status',
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Pattern,
  [string]$RunId,
  [string]$ItemId,
  [string]$Owner,
  [string]$OperationId,
  [int]$TokenEstimate = 1,
  [int]$ActualTokens = 0,
  [string]$Summary = '',
  [string]$VerifierEvidencePath,
  [string]$TestNowUtc,
  [switch]$Apply,
  [switch]$Json,
  [string]$OutputDir,
  [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
trap {
  [Console]::Error.WriteLine($_.Exception.Message)
  exit 1
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.LoopRuntime.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$context = Resolve-LizardLoopRuntimeContext -TargetPath $TargetPath -Pattern $Pattern
if (-not [string]::IsNullOrWhiteSpace($TestNowUtc)) {
  $testRoot = Join-Path $LayerRoot '.tmp\tests'
  if (-not (Test-Path -LiteralPath $testRoot -PathType Container) -or -not (Test-LizardPathWithinRoot -Path $context.target_root -AuthorizedRoot $testRoot -AllowRoot)) { throw 'LOOP_TEST_CLOCK_FORBIDDEN: TestNowUtc is restricted to LayerRoot/.tmp/tests fixtures.' }
}
$now = ConvertTo-LizardLoopUtc -NowUtc $TestNowUtc
$stamp = $now.ToString('yyyyMMddHHmmss')
$effectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) { Join-Path $LayerRoot ".tmp\loops\run-$stamp" } elseif ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path (Get-Location).Path $OutputDir }
Assert-PathOutsideRoot -Path $effectiveOutputDir -ExcludedRoot $context.target_root -Label 'OutputDir'
$effectiveOutputDir = Initialize-SafeDirectory -Path $effectiveOutputDir

if ([string]::IsNullOrWhiteSpace($RunId) -and $Action -eq 'Start') { $RunId = [Guid]::NewGuid().ToString('N') }
$mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }
$result = $null
if ($Action -eq 'Status') {
  $documents = Get-LizardLoopRuntimeDocuments -Context $context
  $chain = Test-LizardLoopEventChain -Context $context
  $result = [pscustomobject][ordered]@{ status = 'inspected'; runtime_status = [string]$documents.state.status; active_run_id = $documents.state.active_run_id; state_revision = [int]$documents.state.revision; event_count = [int]$chain.count; event_head = $chain.last_hash; budget_window = $documents.state.budget_window; lease = $documents.lease }
} elseif (-not $Apply) {
  $result = [pscustomobject][ordered]@{ status = 'preview'; action = $Action.ToLowerInvariant(); run_id = $RunId; item_id = $ItemId; token_estimate = $TokenEstimate; target = $context.target_root; pattern = $context.pattern; readiness_level = $context.readiness_level }
} elseif ($Action -eq 'Start') {
  $result = Invoke-LizardLoopStart -Context $context -RunId $RunId -ItemId $ItemId -Owner $Owner -TokenEstimate $TokenEstimate -OperationId $OperationId -Now $now -FailAfterMutation $TestFailAfterMutation
} elseif ($Action -eq 'Complete') {
  $result = Invoke-LizardLoopFinish -Context $context -Outcome completed -RunId $RunId -Actor $Owner -ActualTokens $ActualTokens -Summary $Summary -VerifierEvidencePath $VerifierEvidencePath -Now $now -FailAfterMutation $TestFailAfterMutation
} else {
  $result = Invoke-LizardLoopFinish -Context $context -Outcome failed -RunId $RunId -Actor $Owner -ActualTokens $ActualTokens -Summary $Summary -VerifierEvidencePath $VerifierEvidencePath -Now $now -FailAfterMutation $TestFailAfterMutation
}

$report = [ordered]@{ schema_version = 1; generated_at = $now.ToString('o'); mode = $mode; action = $Action.ToLowerInvariant(); target = $context.target_root; pattern = $context.pattern; readiness_level = $context.readiness_level; result = $result; auto_merge = $false; human_merge_review_required = $true }
$reportPath = Join-Path $effectiveOutputDir 'loop-run-report.json'
Set-SafeContent -AuthorizedRoot $effectiveOutputDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 20)
if ($Json) { $report | ConvertTo-Json -Depth 20 } else {
  Write-Host "Loop runtime $mode $Action"
  Write-Host "Pattern: $($context.pattern)"
  Write-Host "Status: $($result.status)"
  if ($result.PSObject.Properties.Name -contains 'run_id') { Write-Host "Run: $($result.run_id)" }
  Write-Host "Report: $reportPath"
  if (-not $Apply -and $Action -ne 'Status') { Write-Host 'Preview only. Re-run with -Apply to mutate runtime state.' }
}
