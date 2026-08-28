param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("uninstall-preview-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$reports = Join-Path $fixture 'reports'
$script = Join-Path $LayerRoot 'scripts/uninstall.ps1'
New-Item -ItemType Directory -Path (Join-Path $target '.agent/owned'), $reports -Force | Out-Null

function Write-TestManifest {
  param([string]$InstalledHash, [string]$ArtifactPath = '.agent/owned/owned.txt')
  $manifest = [ordered]@{
    schema_version = 4
    layer = 'lizard-agent-layer'
    layer_version = '2.0.0'
    minimum_reader_schema_version = 4
    writer_schema_version = 4
    profile = 'minimal'
    memory_mode = 'curated'
    target_root = $target
    harnesses = @('codex')
    artifacts = @(
      [ordered]@{ path = '.agent'; kind = 'directory'; lifecycle = 'active'; ownership = 'layer-owned'; state = 'layer-owned'; source_version = '2.0.0'; adapter_aliases = @() },
      [ordered]@{ path = '.agent/owned'; kind = 'directory'; lifecycle = 'active'; ownership = 'layer-owned'; state = 'layer-owned'; source_version = '2.0.0'; adapter_aliases = @() },
      [ordered]@{ path = $ArtifactPath; kind = 'file'; lifecycle = 'active'; ownership = 'layer-owned'; state = 'layer-owned'; source_version = '2.0.0'; installed_hash = $InstalledHash; current_hash = $InstalledHash; adapter_aliases = @() }
    )
  }
  Set-Content -LiteralPath (Join-Path $target '.agent/lizard-agent-layer.install.json') -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding UTF8
}

try {
  $owned = Join-Path $target '.agent/owned/owned.txt'
  Set-Content -LiteralPath $owned -Value 'owned canary' -Encoding UTF8
  $ownedHash = (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-TestManifest -InstalledHash $ownedHash
  $planPath = Join-Path $reports 'preview.md'
  $preview = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-PlanPath', $planPath, '-Json')
  Assert-Equal 0 $preview.exit_code "Uninstall preview must succeed: $($preview.output)"
  Assert-True (Test-Path -LiteralPath $planPath -PathType Leaf) 'Preview must write a human-readable plan outside the target.'
  $canonicalPath = [System.IO.Path]::ChangeExtension($planPath, '.json')
  Assert-True (Test-Path -LiteralPath $canonicalPath -PathType Leaf) 'Preview must write an immutable canonical plan.'
  Assert-True (Test-Path -LiteralPath ($canonicalPath + '.sha256') -PathType Leaf) 'Preview must write the canonical plan digest sidecar.'
  $plan = Get-Content -LiteralPath $canonicalPath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'uninstall' ([string]$plan.operation_kind) 'Preview must emit an uninstall operation plan.'
  Assert-Equal 4 @($plan.intent.target_entries | Where-Object { $_.action -eq 'remove' }).Count 'Clean owned files, directories, and manifest must be removal targets.'
  Assert-True (Test-Path -LiteralPath $owned -PathType Leaf) 'Preview must not mutate target content.'

  $approvedSha = (Get-Content -LiteralPath ($canonicalPath + '.sha256') -Raw).Trim()
  Set-Content -LiteralPath $owned -Value 'changed after approval' -Encoding UTF8
  $tamperedApply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Apply', '-ApprovedPlanPath', $canonicalPath, '-ApprovedPlanSha256', $approvedSha, '-HumanApproved')
  Assert-False ($tamperedApply.exit_code -eq 0) 'Content drift after preview must fail before deletion.'
  Assert-True ($tamperedApply.output -match 'PLAN_BINDING_INTENT_MISMATCH|UNINSTALL_TARGET_HASH_MISMATCH') 'Content drift must expose a stable binding failure.'
  Assert-True (Test-Path -LiteralPath $owned -PathType Leaf) 'Rejected apply must preserve target content.'

  Set-Content -LiteralPath $owned -Value 'owned canary' -Encoding UTF8
  Assert-Equal $ownedHash ((Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()) 'The clean fixture must be restored exactly before approved apply.'
  $apply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Apply', '-ApprovedPlanPath', $canonicalPath, '-ApprovedPlanSha256', $approvedSha, '-HumanApproved', '-Json')
  Assert-Equal 0 $apply.exit_code "Exact approved uninstall must succeed: $($apply.output)"
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent')) 'Clean approved uninstall must remove files before now-empty owned directories.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Committed uninstall must remove the transaction lock.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer-transactions')) 'Committed uninstall must remove transaction metadata.'
  $receiptPath = [System.IO.Path]::ChangeExtension($planPath, '.receipt.json')
  Assert-True (Test-Path -LiteralPath $receiptPath -PathType Leaf) 'Approved uninstall must write a deletion receipt outside the target.'
  $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'completed' ([string]$receipt.status) 'Receipt must record completed removal.'
  Assert-Equal $plan.plan_id ([string]$receipt.plan_id) 'Receipt must bind the exact approved plan.'
  Assert-False ([bool]$receipt.final_manifest_present) 'Receipt must confirm manifest removal.'

  $noOpPlanPath = Join-Path $reports 'no-op.md'
  $noOpPreview = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-PlanPath', $noOpPlanPath, '-Json')
  Assert-Equal 0 $noOpPreview.exit_code "A repeated uninstall preview must be an idempotent no-op: $($noOpPreview.output)"
  $noOpPlan = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($noOpPlanPath, '.json')) -Raw | ConvertFrom-LizardJson
  Assert-Equal 0 @($noOpPlan.intent.target_entries).Count 'A target without an install manifest must produce an empty no-op plan.'

  $interruptedTarget = Join-Path $fixture 'interrupted'
  $target = $interruptedTarget
  New-Item -ItemType Directory -Path (Join-Path $target '.agent/owned') -Force | Out-Null
  $owned = Join-Path $target '.agent/owned/owned.txt'
  Set-Content -LiteralPath $owned -Value 'interruption canary' -Encoding UTF8
  $ownedHash = (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-TestManifest -InstalledHash $ownedHash
  $manifestBeforeInterruption = Get-Content -LiteralPath (Join-Path $target '.agent/lizard-agent-layer.install.json') -Raw
  $interruptedPlanPath = Join-Path $reports 'interrupted.md'
  $interruptedPreview = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-PlanPath', $interruptedPlanPath, '-TestFailAfterMutation', '1')
  Assert-Equal 0 $interruptedPreview.exit_code "Fault-injected uninstall preview must succeed: $($interruptedPreview.output)"
  $interruptedCanonical = [System.IO.Path]::ChangeExtension($interruptedPlanPath, '.json')
  $interruptedSha = (Get-Content -LiteralPath ($interruptedCanonical + '.sha256') -Raw).Trim()
  $interruptedApply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Apply', '-ApprovedPlanPath', $interruptedCanonical, '-ApprovedPlanSha256', $interruptedSha, '-HumanApproved', '-TestFailAfterMutation', '1')
  Assert-False ($interruptedApply.exit_code -eq 0) 'Fault injection after the first removal must abort uninstall.'
  Assert-True ($interruptedApply.output -match 'TRANSACTION_FAULT_INJECTED') 'Interrupted uninstall must expose the stable transaction fault code.'
  Assert-Equal $ownedHash ((Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()) 'Interrupted uninstall rollback must restore deleted file bytes exactly.'
  Assert-Equal $manifestBeforeInterruption (Get-Content -LiteralPath (Join-Path $target '.agent/lizard-agent-layer.install.json') -Raw) 'Interrupted uninstall rollback must preserve the exact manifest bytes.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Interrupted uninstall rollback must remove the transaction lock.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer-transactions')) 'Interrupted uninstall rollback must remove transaction metadata.'
  $retryPlanPath = Join-Path $reports 'interrupted-retry.md'
  $retryPreview = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-PlanPath', $retryPlanPath)
  Assert-Equal 0 $retryPreview.exit_code "Fresh preview after interruption recovery must succeed: $($retryPreview.output)"
  $retryCanonical = [System.IO.Path]::ChangeExtension($retryPlanPath, '.json')
  $retrySha = (Get-Content -LiteralPath ($retryCanonical + '.sha256') -Raw).Trim()
  $retryApply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Apply', '-ApprovedPlanPath', $retryCanonical, '-ApprovedPlanSha256', $retrySha, '-HumanApproved')
  Assert-Equal 0 $retryApply.exit_code "Fresh approved retry after interruption recovery must succeed: $($retryApply.output)"
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent')) 'Recovered uninstall retry must remove the owned tree.'

  $modifiedTarget = Join-Path $fixture 'modified'
  $target = $modifiedTarget
  New-Item -ItemType Directory -Path (Join-Path $target '.agent/owned') -Force | Out-Null
  $owned = Join-Path $target '.agent/owned/owned.txt'
  Set-Content -LiteralPath $owned -Value 'owned canary' -Encoding UTF8
  $ownedHash = (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-TestManifest -InstalledHash $ownedHash
  Set-Content -LiteralPath $owned -Value 'locally modified' -Encoding UTF8
  $planPath = Join-Path $reports 'modified.md'
  $canonicalPath = [System.IO.Path]::ChangeExtension($planPath, '.json')
  $modifiedPreview = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-PlanPath', $planPath, '-Json')
  Assert-Equal 0 $modifiedPreview.exit_code "Modified-content preview must succeed conservatively: $($modifiedPreview.output)"
  $modifiedPlan = Get-Content -LiteralPath $canonicalPath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'preserve' ([string](@($modifiedPlan.intent.target_entries | Where-Object { $_.path -eq '.agent/owned/owned.txt' })[0].action)) 'Modified layer-owned files must be preserved in managed-only scope.'
  Assert-Equal 'preserve' ([string](@($modifiedPlan.intent.target_entries | Where-Object { $_.path -eq '.agent/owned' })[0].action)) 'A directory containing a preserved artifact must also be preserved.'
  Assert-Equal 'replace' ([string](@($modifiedPlan.intent.target_entries | Where-Object { $_.path -eq '.agent/lizard-agent-layer.install.json' })[0].action)) 'The manifest must be updated transactionally when ownership evidence is still needed.'
  $modifiedSha = (Get-Content -LiteralPath ($canonicalPath + '.sha256') -Raw).Trim()
  $modifiedApply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Apply', '-ApprovedPlanPath', $canonicalPath, '-ApprovedPlanSha256', $modifiedSha, '-HumanApproved', '-Json')
  Assert-Equal 0 $modifiedApply.exit_code "Managed-only partial uninstall must succeed without losing ownership evidence: $($modifiedApply.output)"
  Assert-True (Test-Path -LiteralPath $owned -PathType Leaf) 'Managed-only partial uninstall must preserve the modified file.'
  Assert-True (Test-Path -LiteralPath (Join-Path $target '.agent/lizard-agent-layer.install.json') -PathType Leaf) 'Managed-only partial uninstall must retain the install manifest.'
  $residualManifest = Get-Content -LiteralPath (Join-Path $target '.agent/lizard-agent-layer.install.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal 'active' ([string](@($residualManifest.artifacts | Where-Object { $_.path -eq '.agent/owned/owned.txt' })[0].lifecycle)) 'Preserved modified content must retain active ownership evidence.'
  $modifiedReceipt = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($planPath, '.receipt.json')) -Raw | ConvertFrom-LizardJson
  Assert-Equal 'partial' ([string]$modifiedReceipt.status) 'Receipt must report a partial uninstall when residue is preserved.'
  Assert-True ([bool]$modifiedReceipt.final_manifest_present) 'Partial receipt must report retained manifest evidence.'
  Assert-True (@($modifiedReceipt.unresolved_residue) -contains '.agent/owned/owned.txt') 'Partial receipt must list preserved residue.'

  $completeWithoutConfirmation = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Scope', 'complete', '-PlanPath', (Join-Path $reports 'complete-rejected.md'))
  Assert-False ($completeWithoutConfirmation.exit_code -eq 0) 'Complete preview must require a separate modified-content purge confirmation.'
  Assert-True ($completeWithoutConfirmation.output -match 'UNINSTALL_SENSITIVE_PURGE_CONFIRMATION_REQUIRED') 'Missing complete confirmation must expose a stable code.'
  $completePlanPath = Join-Path $reports 'complete.md'
  $completeApproval = New-TestUninstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Scope', 'complete', '-ConfirmModifiedLayerOwnedPurge', '-PlanPath', $completePlanPath)
  $completeCanonical = [System.IO.Path]::ChangeExtension($completePlanPath, '.json')
  $completePlan = Get-Content -LiteralPath $completeCanonical -Raw | ConvertFrom-LizardJson
  Assert-Equal 'remove' ([string](@($completePlan.intent.target_entries | Where-Object { $_.path -eq '.agent/owned/owned.txt' })[0].action)) 'Confirmed complete plan may remove modified layer-owned content.'
  Assert-True ([bool]$completePlan.intent.options.confirm_modified_layer_owned_purge) 'Complete plan must bind the second purge confirmation.'
  $completeApply = Invoke-TestPowerShell -ScriptPath $script -Arguments ($completeApproval.arguments + @('-Json'))
  Assert-Equal 0 $completeApply.exit_code "Confirmed complete apply must remove modified layer-owned content: $($completeApply.output)"
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent')) 'Residue-free complete apply must remove the final owned tree.'
  $completeReceipt = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($completePlanPath, '.receipt.json')) -Raw | ConvertFrom-LizardJson
  Assert-Equal 'completed' ([string]$completeReceipt.status) 'Residue-free complete receipt must report completion.'

  $exportTarget = Join-Path $fixture 'export-target'
  $target = $exportTarget
  New-Item -ItemType Directory -Path (Join-Path $target '.agent/owned') -Force | Out-Null
  $owned = Join-Path $target '.agent/owned/owned.txt'
  Set-Content -LiteralPath $owned -Value 'export canary original' -Encoding UTF8
  $ownedHash = (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()
  Write-TestManifest -InstalledHash $ownedHash
  Set-Content -LiteralPath $owned -Value 'export canary modified' -Encoding UTF8
  $exportSourceHash = (Get-FileHash -LiteralPath $owned -Algorithm SHA256).Hash.ToLowerInvariant()
  $exportRoot = Join-Path $reports 'approved-export-root'
  New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
  $exportPlanPath = Join-Path $reports 'export-complete.md'
  $exportApproval = New-TestUninstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Scope', 'export-then-complete', '-ConfirmModifiedLayerOwnedPurge', '-ConfirmExportMayContainSensitiveData', '-ExportPath', $exportRoot, '-ExportRelativePaths', '.agent/owned/owned.txt', '-PlanPath', $exportPlanPath)
  $exportCanonical = [System.IO.Path]::ChangeExtension($exportPlanPath, '.json')
  $exportPlan = Get-Content -LiteralPath $exportCanonical -Raw | ConvertFrom-LizardJson
  Assert-Equal '.agent/owned/owned.txt' ([string]$exportPlan.intent.options.export_relative_paths[0]) 'Export plan must bind the exact relative allowlist.'
  Assert-True ([bool]$exportPlan.intent.options.confirm_export_may_contain_sensitive_data) 'Export plan must bind the sensitive-data confirmation.'
  $exportApply = Invoke-TestPowerShell -ScriptPath $script -Arguments ($exportApproval.arguments + @('-Json'))
  Assert-Equal 0 $exportApply.exit_code "Approved export-then-complete apply must succeed: $($exportApply.output)"
  $exportedFile = Join-Path $exportRoot '.agent/owned/owned.txt'
  Assert-True (Test-Path -LiteralPath $exportedFile -PathType Leaf) 'Export must recreate the selected relative path under the approved export root.'
  Assert-Equal $exportSourceHash ((Get-FileHash -LiteralPath $exportedFile -Algorithm SHA256).Hash.ToLowerInvariant()) 'Exported bytes must match the approved source hash.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.agent')) 'Successful export-then-complete must remove the residue-free target tree.'
  $exportReceipt = Get-Content -LiteralPath ([System.IO.Path]::ChangeExtension($exportPlanPath, '.receipt.json')) -Raw | ConvertFrom-LizardJson
  Assert-Equal 1 @($exportReceipt.exported).Count 'Receipt must record every verified export.'
  Assert-Equal $exportSourceHash ([string]$exportReceipt.exported[0].sha256) 'Receipt must bind the verified export hash.'

  $maliciousTarget = Join-Path $fixture 'malicious'
  New-Item -ItemType Directory -Path (Join-Path $maliciousTarget '.agent') -Force | Out-Null
  $target = $maliciousTarget
  Write-TestManifest -InstalledHash ('a' * 64) -ArtifactPath '../escape.txt'
  $bad = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $maliciousTarget, '-PlanPath', (Join-Path $reports 'bad.md'))
  Assert-False ($bad.exit_code -eq 0) 'Unsafe manifest artifact paths must fail closed.'
  Assert-True ($bad.output -match 'UNINSTALL_ARTIFACT_PATH_INVALID') 'Unsafe-path failure must expose a stable code.'

  $applyDisabled = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $maliciousTarget, '-Apply')
  Assert-False ($applyDisabled.exit_code -eq 0) 'Apply without exact approval must fail closed.'
  Assert-True ($applyDisabled.output -match 'PLAN_APPROVAL_REQUIRED') 'Apply must require the exact approval tuple before any implementation-stage response.'

  Write-Host 'PASS tests\integration\uninstall.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
