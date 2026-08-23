param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'tests\TestTrustHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Plan.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Records.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Trust.psm1') -Force

$testRoot = Join-Path $LayerRoot ('.tmp\tests\records-lifecycle-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $testRoot 'target'
$plans = Join-Path $testRoot 'plans'
$exportRoot = Join-Path $testRoot 'export'
$trustRoot = Join-Path $testRoot 'trust'
New-Item -ItemType Directory -Path $target, $plans, $exportRoot, $trustRoot -Force | Out-Null
$script = Join-Path $LayerRoot 'scripts\records-lifecycle.ps1'
$policyPath = Join-Path $LayerRoot 'retention-policies\conservative.json'
$policySha = (Get-FileHash -LiteralPath $policyPath -Algorithm SHA256).Hash.ToLowerInvariant()
$asOf = [DateTimeOffset]'2026-08-22T12:00:00Z'

function Write-TestUtf8 {
  param([string]$Path, [string]$Value)
  $parent = Split-Path -Parent $Path
  New-Item -ItemType Directory -Path $parent -Force | Out-Null
  [IO.File]::WriteAllText($Path, $Value, (New-Object Text.UTF8Encoding($false)))
}

function Set-TestTimestamp {
  param([string]$Path, [DateTimeOffset]$Timestamp)
  (Get-Item -LiteralPath $Path).LastWriteTimeUtc = $Timestamp.UtcDateTime
}

function Invoke-Records {
  param([string]$Action, [string]$ReceiptId, [string]$PlanPath, [switch]$Apply, [string]$Sha256, [int]$FailAfterMutation = 0, [string[]]$Classes, [switch]$WithHold, [string]$SelectedExportRoot = $exportRoot)
  $args = @('-LayerRoot', $LayerRoot, '-TargetRoot', $target, '-Action', $Action, '-PolicyPath', $policyPath, '-PolicySha256', $policySha, '-AsOf', $asOf.ToString('o'))
  if (-not [string]::IsNullOrWhiteSpace($ReceiptId)) { $args += @('-ReceiptId', $ReceiptId) }
  if (@($Classes).Count -gt 0) { $args += @('-Classes', ($Classes -join ',')) }
  if (-not [string]::IsNullOrWhiteSpace($SelectedExportRoot)) { $args += @('-ExportRoot', $SelectedExportRoot) }
  if ($WithHold) { $args += @('-HoldEvidencePath', $script:holdPath, '-HoldTrustStorePath', $script:trust.trust_store_path, '-HoldTrustStoreSha256', $script:trust.trust_store_sha256, '-HoldChallengePath', $script:trust.challenge_path, '-HoldChallengeSha256', $script:trust.challenge_sha256) }
  if ($Apply) { $args += @('-Apply', '-ApprovedPlanPath', $PlanPath, '-ApprovedPlanSha256', $Sha256, '-HumanApproved') }
  elseif (-not [string]::IsNullOrWhiteSpace($PlanPath)) { $args += @('-CanonicalPlanPath', $PlanPath) }
  if ($FailAfterMutation -gt 0) { $args += @('-FailAfterMutation', [string]$FailAfterMutation) }
  return Invoke-TestPowerShell -ScriptPath $script -Arguments $args
}

try {
  $working = Join-Path $target '.agent\memory\working\WORKSPACE.md'
  $preferences = Join-Path $target '.agent\memory\personal\PREFERENCES.md'
  $decisions = Join-Path $target '.agent\memory\semantic\DECISIONS.md'
  $lessons = Join-Path $target '.agent\memory\semantic\LESSONS.md'
  Write-TestUtf8 $working 'old working memory'
  Write-TestUtf8 $preferences 'boundary memory under hold'
  Write-TestUtf8 $decisions 'not yet expired memory'
  Write-TestUtf8 $lessons 'exact boundary without hold'
  Set-TestTimestamp $working ([DateTimeOffset]'2025-08-21T12:00:00Z')
  Set-TestTimestamp $preferences ([DateTimeOffset]'2025-08-22T12:00:00Z')
  Set-TestTimestamp $decisions ([DateTimeOffset]'2025-08-22T12:00:01Z')
  Set-TestTimestamp $lessons ([DateTimeOffset]'2025-08-22T12:00:00Z')

  $historyPath = Join-Path $target '.agent\lizard-agent-layer.update-history.jsonl'
  $oldHistory = '{"schema_version":2,"updated_at":"2025-01-01T00:00:00Z","id":"old"}'
  $recentHistory = '{"schema_version":2,"updated_at":"2026-08-22T11:00:00Z","id":"recent"}'
  Write-TestUtf8 $historyPath ($oldHistory + "`n" + $recentHistory + "`n")

  $decisionReceipt = Join-Path $target '.agent\routing\receipts\decisions\old-route.json'
  Write-TestUtf8 $decisionReceipt '{"schema_version":2,"artifact_kind":"signed-evidence","payload":{"created_at":"2025-01-01T00:00:00Z"}}'

  $eventsPath = Join-Path $target '.agent\loops\archive\events.jsonl'
  Write-TestUtf8 $eventsPath '{"schema_version":1,"occurred_at":"2025-01-01T00:00:00Z","event_hash":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
  $runLog = Join-Path $target '.agent\loops\archive\loop-run-log.md'
  Write-TestUtf8 $runLog 'old loop operator log'
  Set-TestTimestamp $runLog ([DateTimeOffset]'2025-01-01T00:00:00Z')
  $userNote = Join-Path $target '.agent\loops\archive\user-notes.txt'
  Write-TestUtf8 $userNote 'must be preserved'

  $targetRootHash = Get-LizardPlanRootHash $target
  $binding = Get-LizardRecordsHoldBinding -PolicyId 'conservative-default' -PolicySha256 $policySha -TargetRootHash $targetRootHash -AsOf $asOf
  $script:trust = New-LizardTestTrustMaterial -Root $trustRoot -BindingSha256 $binding -Subject 'conservative-default' -Now $asOf -PrincipalId 'records-officer-01' -Roles @('records-officer') -Purpose 'records-disposition' -PayloadKind 'records-hold-register'
  $heldRecordId = New-LizardRecordId -ArtifactClass memory -RelativePath '.agent/memory/personal/PREFERENCES.md'
  $holdPayload = [pscustomobject][ordered]@{
    schema_version = 1; artifact_kind = 'records-hold-register'; policy_id = 'conservative-default'; policy_sha256 = $policySha; target_root_hash = $targetRootHash
    effective_at = $asOf.AddHours(-1).ToString('o'); expires_at = $asOf.AddHours(1).ToString('o')
    holds = @([pscustomobject][ordered]@{ hold_id = 'matter-01'; scope = 'records'; artifact_classes = @(); record_ids = @($heldRecordId); owner_id = 'legal-team'; reason_code = 'ACTIVE_MATTER'; active_from = $asOf.AddDays(-1).ToString('o'); expires_at = $null })
  }
  $holdEnvelope = New-LizardSignedEvidenceEnvelope -Payload $holdPayload -PayloadKind records-hold-register -Purpose records-disposition -Subject conservative-default -BindingSha256 $binding -ChallengePath $script:trust.challenge_path -ChallengeSha256 $script:trust.challenge_sha256 -PrivateKeyPath $script:trust.private_key_path -PrivateKeySha256 $script:trust.private_key_sha256 -Now $asOf
  $script:holdPath = Join-Path $trustRoot 'hold-envelope.json'
  Write-TestUtf8 $script:holdPath ($holdEnvelope | ConvertTo-Json -Depth 20)

  $noAuthority = Invoke-Records -Action Purge -ReceiptId 'purge-no-authority' -PlanPath (Join-Path $plans 'no-authority.json')
  Assert-True ($noAuthority.exit_code -ne 0 -and $noAuthority.output -match 'RECORDS_HOLD_AUTHORITY_REQUIRED') 'Purge without authenticated hold authority must fail before plan creation.'

  $planPath = Join-Path $plans 'purge.json'
  $preview = Invoke-Records -Action Purge -ReceiptId 'purge-01' -PlanPath $planPath -WithHold
  Assert-Equal 0 $preview.exit_code "Purge preview must succeed. $($preview.output)"
  Assert-True (Test-Path -LiteralPath $working -PathType Leaf) 'Preview must not delete expired memory.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent\records')) 'Preview must not write a target receipt.'
  $sha = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()

  $fault = Invoke-Records -Action Purge -ReceiptId 'purge-01' -PlanPath $planPath -Apply -Sha256 $sha -WithHold -FailAfterMutation 1
  Assert-True ($fault.exit_code -ne 0 -and $fault.output -match 'TRANSACTION_FAULT_INJECTED') "Injected purge failure must be observable. $($fault.output)"
  Assert-True (Test-Path -LiteralPath $working -PathType Leaf) 'Interrupted purge must restore deleted content.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent\records\deletion-receipts\purge-01.json')) 'Interrupted purge must roll back its receipt.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Interrupted purge rollback must clear the target lock.'
  Assert-True (Test-Path -LiteralPath (Join-Path $exportRoot "records-export-purge-01.json") -PathType Leaf) 'Pre-delete export must survive interruption for retry.'

  $retry = Invoke-Records -Action Purge -ReceiptId 'purge-01' -PlanPath $planPath -Apply -Sha256 $sha -WithHold
  Assert-Equal 0 $retry.exit_code "Retry from the same approved plan must succeed. $($retry.output)"
  Assert-False (Test-Path -LiteralPath $working) 'Record older than the TTL boundary must be deleted.'
  Assert-True (Test-Path -LiteralPath $preferences -PathType Leaf) 'Legal hold must override exact-boundary expiry.'
  Assert-True (Test-Path -LiteralPath $decisions -PathType Leaf) 'Record one second before expiry must remain.'
  Assert-False (Test-Path -LiteralPath $lessons) 'Record expires at the exact boundary and must be deleted when not held.'
  Assert-False (Test-Path -LiteralPath $decisionReceipt) 'Expired route decision must be deleted.'
  Assert-False (Test-Path -LiteralPath $eventsPath) 'Expired inactive loop event log must be deleted.'
  Assert-False (Test-Path -LiteralPath $runLog) 'Expired inactive loop run log must be deleted.'
  Assert-True (Test-Path -LiteralPath $userNote -PathType Leaf) 'Unknown user content must be preserved.'
  $remainingHistory = Get-SafeContent -AuthorizedRoot $target -Path $historyPath -Raw
  Assert-False ($remainingHistory -match '"id":"old"') 'Selective JSONL purge must remove expired update history.'
  Assert-True ($remainingHistory -match '"id":"recent"') 'Selective JSONL purge must retain recent update history.'

  $receiptPath = Join-Path $target '.agent\records\deletion-receipts\purge-01.json'
  $receipt = Get-SafeContent -AuthorizedRoot $target -Path $receiptPath -Raw | ConvertFrom-Json
  Assert-Equal 'records-deletion-receipt' ([string]$receipt.artifact_kind) 'Purge must write deletion evidence.'
  Assert-Equal 'records-officer-01' ([string]$receipt.records_officer) 'Receipt must bind authenticated records authority.'
  Assert-True (@($receipt.deleted_records).Count -ge 5) 'Receipt must enumerate selectively deleted records.'
  Assert-False ([bool]$receipt.raw_content_stored) 'Deletion receipt must not store raw content.'

  $standaloneExport = Join-Path $testRoot 'standalone-export'
  New-Item -ItemType Directory -Path $standaloneExport | Out-Null
  $exportPlan = Join-Path $plans 'export.json'
  $exportPreview = Invoke-Records -Action Export -ReceiptId 'export-01' -PlanPath $exportPlan -Classes @('memory') -SelectedExportRoot $standaloneExport
  Assert-Equal 0 $exportPreview.exit_code "Standalone export preview must succeed. $($exportPreview.output)"
  $exportSha = (Get-FileHash -LiteralPath $exportPlan -Algorithm SHA256).Hash.ToLowerInvariant()
  $exportApply = Invoke-Records -Action Export -ReceiptId 'export-01' -PlanPath $exportPlan -Apply -Sha256 $exportSha -Classes @('memory') -SelectedExportRoot $standaloneExport
  Assert-Equal 0 $exportApply.exit_code "Standalone export apply must succeed. $($exportApply.output)"
  Assert-True (Test-Path -LiteralPath (Join-Path $standaloneExport 'records-export-export-01.json') -PathType Leaf) 'Standalone export must write a manifest.'

  $activeEvents = Join-Path $target '.agent\loops\active\events.jsonl'
  Write-TestUtf8 $activeEvents '{"schema_version":1,"occurred_at":"2025-01-01T00:00:00Z","event_hash":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}'
  Write-TestUtf8 (Join-Path $target '.agent\loops\lizard-agent-layer.loop-install.json') '{"schema_version":1}'
  $activePlan = Join-Path $plans 'active-loop-purge.json'
  $activeBlocked = Invoke-Records -Action Purge -ReceiptId 'purge-active-loop' -PlanPath $activePlan -Classes @('loop-events') -WithHold -SelectedExportRoot $exportRoot
  Assert-True ($activeBlocked.exit_code -ne 0 -and $activeBlocked.output -match 'RECORDS_NOTHING_SELECTED') 'Operational loop guard must block purge of active runtime logs.'
  Assert-True (Test-Path -LiteralPath $activeEvents -PathType Leaf) 'Operationally blocked loop evidence must remain.'

  Write-Host 'PASS tests\integration\records-lifecycle.tests.ps1'
} finally {
  Clear-TestDirectory -Path $testRoot -AllowedRoot (Join-Path $LayerRoot '.tmp\tests')
}
