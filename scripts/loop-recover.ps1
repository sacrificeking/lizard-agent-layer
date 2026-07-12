param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Pattern,
  [Parameter(Mandatory = $true)][string]$RunId,
  [string]$Actor = 'human-operator',
  [string]$TestNowUtc,
  [switch]$Apply,
  [switch]$HumanApproved,
  [switch]$Json,
  [string]$OutputDir,
  [int]$TestFailAfterMutation = 0
)

$ErrorActionPreference = 'Stop'
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
$effectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) { Join-Path $LayerRoot ".tmp\loops\recover-$stamp" } elseif ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path (Get-Location).Path $OutputDir }
Assert-PathOutsideRoot -Path $effectiveOutputDir -ExcludedRoot $context.target_root -Label 'OutputDir'
$effectiveOutputDir = Initialize-SafeDirectory -Path $effectiveOutputDir
$documents = Get-LizardLoopRuntimeDocuments -Context $context
$chain = Test-LizardLoopEventChain -Context $context
$expires = if ([string]$documents.lease.status -eq 'active') { [DateTimeOffset]::Parse([string]$documents.lease.expires_at).UtcDateTime } else { $null }
$available = [string]$documents.lease.status -eq 'active' -and [string]$documents.lease.run_id -eq $RunId -and $expires -le $now
if ($Apply -and -not $HumanApproved) { throw 'LOOP_RECOVERY_HUMAN_APPROVAL_REQUIRED: Recovery mutates authoritative state.' }
if ($Apply -and -not $available) { throw 'LOOP_RECOVERY_NOT_AVAILABLE: The requested lease is absent, mismatched, or not stale.' }
$result = if ($Apply) { Invoke-LizardLoopRecovery -Context $context -RunId $RunId -Actor $Actor -Now $now -FailAfterMutation $TestFailAfterMutation } else { [pscustomobject][ordered]@{ status = if ($available) { 'recovery-available' } else { 'recovery-unavailable' }; run_id = $RunId; lease_status = [string]$documents.lease.status; lease_expires_at = $documents.lease.expires_at; event_count = [int]$chain.count } }
$report = [ordered]@{ schema_version = 1; generated_at = $now.ToString('o'); mode = if ($Apply) { 'APPLY' } else { 'PREVIEW' }; action = 'recover'; target = $context.target_root; pattern = $context.pattern; readiness_level = $context.readiness_level; result = $result; auto_merge = $false; human_merge_review_required = $true }
$reportPath = Join-Path $effectiveOutputDir 'loop-recovery-report.json'
Set-SafeContent -AuthorizedRoot $effectiveOutputDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 20)
if ($Json) { $report | ConvertTo-Json -Depth 20 } else { Write-Host "Loop recovery $($report.mode): $($result.status)"; Write-Host "Run: $RunId"; Write-Host "Report: $reportPath" }
