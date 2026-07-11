param(
  [string]$LayerRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Host.psm1') -Force
$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$tmpRoot = Join-Path $LayerRoot ".tmp\smoke-$stamp"
$standardTarget = Join-Path $tmpRoot 'standard-target'
$packTarget = Join-Path $tmpRoot 'pack-target'
$overlayTarget = Join-Path $tmpRoot 'overlay-target'
$cursorTarget = Join-Path $tmpRoot 'cursor-target'
$sidecarTarget = Join-Path $tmpRoot 'sidecar-target'
$analysisTarget = Join-Path $tmpRoot 'analysis-target'
$loopTarget = Join-Path $tmpRoot 'loop-target'
$l2Target = Join-Path $tmpRoot 'l2-target'
$sidecarPlanPath = Join-Path $tmpRoot 'sidecar-install-plan.md'
$packPlanPath = Join-Path $tmpRoot 'pack-install-plan.md'
$overlayUpdatePlanPath = Join-Path $tmpRoot 'overlay-update-plan.md'
$overlayUpdateOutputDir = Join-Path $tmpRoot 'overlay-update-output'
$overlayUpdateApplyOutputDir = Join-Path $tmpRoot 'overlay-update-apply-output'
$sidecarUpdateForceOutputDir = Join-Path $tmpRoot 'sidecar-update-force-output'
$mergeSuggestionDir = Join-Path $tmpRoot 'merge-suggestions'
$loopPlanPath = Join-Path $tmpRoot 'loop-init-plan.md'
$loopOutputDir = Join-Path $tmpRoot 'loop-init-output'
$loopAuditOutputDir = Join-Path $tmpRoot 'loop-audit-output'
$loopReportOutputDir = Join-Path $tmpRoot 'loop-report-output'
$loopSyncOutputDir = Join-Path $tmpRoot 'loop-sync-output'
$l2PlanPath = Join-Path $tmpRoot 'l2-loop-init-plan.md'
$l2InitOutputDir = Join-Path $tmpRoot 'l2-loop-init-output'
$l2AuditOutputDir = Join-Path $tmpRoot 'l2-loop-audit-output'
$l2WorktreeOutputDir = Join-Path $tmpRoot 'l2-worktree-output'
$l2VerifyOutputDir = Join-Path $tmpRoot 'l2-verify-output'
$l2NoApprovalOutputDir = Join-Path $tmpRoot 'l2-worktree-no-approval-output'
$l2VerifyMissingOutputDir = Join-Path $tmpRoot 'l2-verify-missing-output'
$l2VerifyMismatchOutputDir = Join-Path $tmpRoot 'l2-verify-mismatch-output'
$l2CleanupPreviewOutputDir = Join-Path $tmpRoot 'l2-cleanup-preview-output'
$l2CleanupOutputDir = Join-Path $tmpRoot 'l2-cleanup-output'
$l2WorktreePath = Join-Path $tmpRoot 'l2-assisted-worktree'

foreach ($target in @($standardTarget, $packTarget, $overlayTarget, $cursorTarget, $sidecarTarget, $analysisTarget, $loopTarget, $l2Target)) {
  New-Item -ItemType Directory -Path $target -Force | Out-Null
}
New-Item -ItemType Directory -Path (Join-Path $overlayTarget '.lizard-agent-layer\packs') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'supabase\functions\demo') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'supabase\migrations') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'src\pages\finance\dca') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget '.github\workflows') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'src\agents\openai\rag') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'src\lib\auth\token') -Force | Out-Null

Set-Content -LiteralPath (Join-Path $standardTarget 'README.md') -Value '# standard smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $packTarget 'README.md') -Value '# pack smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $overlayTarget 'README.md') -Value '# overlay smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $cursorTarget 'README.md') -Value '# cursor smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sidecarTarget 'README.md') -Value '# sidecar smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Value '# Existing Project Instructions' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'README.md') -Value '# analysis smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $loopTarget 'README.md') -Value '# loop smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $l2Target 'README.md') -Value '# l2 loop smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'package.json') -Value '{"dependencies":{"@supabase/supabase-js":"latest","react":"latest","openai":"latest"},"devDependencies":{"typescript":"latest","vite":"latest","tailwindcss":"latest"},"workspaces":["apps/*"]}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'vite.config.ts') -Value 'export default {}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'tsconfig.json') -Value '{}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'DESIGN.md') -Value '# Design' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'pnpm-workspace.yaml') -Value "packages:`n  - apps/*" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget '.github\workflows\ci.yml') -Value 'name: ci' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'src\pages\finance\dca\stocks-dca.ts') -Value 'export const marker = true;' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'src\agents\openai\rag\agent.ts') -Value 'export const agent = true;' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'src\lib\auth\token\jwt.ts') -Value 'export const token = true;' -Encoding UTF8
& git -C $l2Target init | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to initialize L2 smoke git repository.' }
& git -C $l2Target config user.email 'smoke@example.invalid'
& git -C $l2Target config user.name 'Smoke Test'
& git -C $l2Target add README.md
& git -C $l2Target commit -m 'init l2 smoke target' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Failed to commit L2 smoke repository.' }

$overlayPack = @{
  name = 'project-overlay'
  extends = 'finance-app'
  description = 'Project-specific smoke overlay pack.'
  riskLevel = 'high'
  projectSize = 'large'
  stack = @('overlay')
  harnesses = @('codex')
  skills = @('frontend-react')
  verification = @('verify overlay-specific behavior')
  recommendedForSignals = @('overlay')
  notes = 'Smoke overlay pack.'
}
$overlayPack | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $overlayTarget '.lizard-agent-layer\packs\project-overlay.json') -Encoding UTF8

function Run-Step {
  param([string]$Name, [scriptblock]$Block)
  Write-Host "== $Name =="
  & $Block
}

Run-Step 'validate layer' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\validate.ps1')
}

Run-Step 'analyze target recommendation' {
  $json = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\analyze-target.ps1') -TargetPath $analysisTarget -Json | Out-String
  $analysis = $json | ConvertFrom-Json
  if ($analysis.recommendedProfile -ne 'supabase-react-finance') { throw "Expected supabase-react-finance recommendation, got $($analysis.recommendedProfile)." }
  if (@($analysis.recommendedHarnesses) -notcontains 'codex') { throw 'Expected codex harness recommendation.' }
  foreach ($expectedSignal in @('finance', 'monorepo', 'agent-runtime', 'security')) {
    if (@($analysis.signals) -notcontains $expectedSignal) { throw "Expected signal: $expectedSignal" }
  }
  foreach ($expectedPack in @('frontend-product', 'design-system', 'supabase-react', 'finance-app', 'security-hardening', 'agent-runtime', 'loop-engineering')) {
    if (@($analysis.recommendedPacks) -notcontains $expectedPack) { throw "Expected pack recommendation: $expectedPack" }
  }
  if (-not $analysis.projectShape.monorepo) { throw 'Expected monorepo project shape.' }
}

Run-Step 'install apply pack merge' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $packTarget -Profile minimal -Packs frontend-product,security-hardening -WritePlan -PlanPath $packPlanPath -Apply | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $packPlanPath)) { throw 'Expected pack install plan report.' }
  $packPlan = Get-Content -LiteralPath $packPlanPath -Raw
  foreach ($expected in @('Requested packs', 'frontend-product', 'security-hardening', 'Risk level: `high`')) {
    if ($packPlan -notmatch [regex]::Escape($expected)) { throw "Expected pack plan to contain: $expected" }
  }
  $manifest = Get-Content -LiteralPath (Join-Path $packTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  foreach ($expected in @('frontend-product', 'security-hardening')) {
    if (@($manifest.requested_packs) -notcontains $expected) { throw "Expected requested pack in manifest: $expected" }
    if (@($manifest.packs) -notcontains $expected) { throw "Expected expanded pack in manifest: $expected" }
  }
  if (@($manifest.pack_sources).Count -lt 2) { throw 'Expected pack sources in manifest.' }
  $profileDoc = Get-Content -LiteralPath (Join-Path $packTarget '.agent\project-profile.json') -Raw | ConvertFrom-Json
  if ($profileDoc.riskLevel -ne 'high') { throw "Expected pack-merged risk high, got $($profileDoc.riskLevel)." }
  foreach ($expectedSkill in @('frontend-react', 'design-system', 'dependency-upgrade', 'security-hardening')) {
    if (@($profileDoc.skills) -notcontains $expectedSkill) { throw "Expected pack-merged skill: $expectedSkill" }
    if (-not (Test-Path -LiteralPath (Join-Path $packTarget ".agent\skills\$expectedSkill\SKILL.md"))) { throw "Expected installed pack skill: $expectedSkill" }
  }
}

Run-Step 'manifest diff pack target strict' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\manifest-diff.ps1') -TargetPath $packTarget -Strict | Out-String | Write-Host
}

Run-Step 'install apply loop engineering pack' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $loopTarget -Profile minimal -Packs loop-engineering -Apply | Out-String | Write-Host
  $manifest = Get-Content -LiteralPath (Join-Path $loopTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  if (@($manifest.requested_packs) -notcontains 'loop-engineering') { throw 'Expected requested loop-engineering pack.' }
  foreach ($expectedSkill in @('loop-triage', 'loop-verifier', 'loop-budget', 'loop-state-sync', 'loop-constraints', 'worktree-isolation', 'ci-triage', 'minimal-fix', 'release-readiness')) {
    if (-not (Test-Path -LiteralPath (Join-Path $loopTarget ".agent\skills\$expectedSkill\SKILL.md"))) { throw "Expected installed loop skill: $expectedSkill" }
  }
}

Run-Step 'loop init preview plan' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-init.ps1') -TargetPath $loopTarget -Pattern daily-triage -WritePlan -PlanPath $loopPlanPath -OutputDir $loopOutputDir | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $loopPlanPath)) { throw 'Expected loop init preview plan.' }
  if (Test-Path -LiteralPath (Join-Path $loopTarget '.agent\loops')) { throw 'Loop init preview wrote .agent/loops into target.' }
  $plan = Get-Content -LiteralPath $loopPlanPath -Raw
  foreach ($expected in @('# lizard-agent-layer loop init plan', 'Mode: `PREVIEW`', 'daily-triage', 'report-only')) {
    if ($plan -notmatch [regex]::Escape($expected)) { throw "Expected loop init plan to contain: $expected" }
  }
}

Run-Step 'loop init apply and gates' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-init.ps1') -TargetPath $loopTarget -Pattern daily-triage -OutputDir $loopOutputDir -Apply | Out-String | Write-Host
  foreach ($expectedPath in @('.agent\loops\LOOP.md', '.agent\loops\loop-budget.md', '.agent\loops\loop-run-log.md', '.agent\loops\loop-constraints.md', '.agent\loops\daily-triage-state.md', '.agent\loops\lizard-agent-layer.loop-install.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $loopTarget $expectedPath))) { throw "Expected loop runtime artifact: $expectedPath" }
  }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-audit.ps1') -TargetPath $loopTarget -OutputDir $loopAuditOutputDir -Strict | Out-String | Write-Host
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-report.ps1') -TargetPath $loopTarget -OutputDir $loopReportOutputDir -Strict | Out-String | Write-Host
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-sync.ps1') -TargetPath $loopTarget -OutputDir $loopSyncOutputDir -Strict | Out-String | Write-Host
  $costJson = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-cost.ps1') -Pattern daily-triage -Level L1 -Cadence 1d -Json | Out-String
  $cost = $costJson | ConvertFrom-Json
  if ($cost.pattern -ne 'daily-triage') { throw "Expected daily-triage cost pattern, got $($cost.pattern)." }
  if ($cost.estimated_tokens_daily -le 0 -or $cost.estimated_tokens_daily -gt 10000) { throw "Unexpected daily loop token estimate: $($cost.estimated_tokens_daily)." }
}

Run-Step 'L2 assisted loop init' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $l2Target -Profile minimal -Packs loop-engineering -Apply | Out-String | Write-Host
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-init.ps1') -TargetPath $l2Target -Pattern minimal-fix-assist -WritePlan -PlanPath $l2PlanPath -OutputDir $l2InitOutputDir | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $l2PlanPath)) { throw 'Expected L2 loop init preview plan.' }
  if (Test-Path -LiteralPath (Join-Path $l2Target '.agent\loops')) { throw 'L2 loop init preview wrote .agent/loops into target.' }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-init.ps1') -TargetPath $l2Target -Pattern minimal-fix-assist -OutputDir $l2InitOutputDir -Apply | Out-String | Write-Host
  foreach ($expectedPath in @('.agent\loops\worktree-policy.md', '.agent\loops\assisted-fix-plan.md', '.agent\loops\loop-verifier-report.md', '.agent\loops\minimal-fix-assist-state.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $l2Target $expectedPath))) { throw "Expected L2 runtime artifact: $expectedPath" }
  }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-audit.ps1') -TargetPath $l2Target -OutputDir $l2AuditOutputDir -Strict | Out-String | Write-Host
}

Run-Step 'L2 worktree and verifier gates' {
  $branch = 'lizard/l2/smoke-fix'
  $noApprovalOutput = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-worktree.ps1') -TargetPath $l2Target -ItemId smoke-fix -Branch $branch -WorktreePath $l2WorktreePath -OutputDir $l2NoApprovalOutputDir -Apply 2>&1
  $noApprovalExit = $LASTEXITCODE
  $noApprovalOutput | Out-String | Write-Host
  if ($noApprovalExit -eq 0) { throw 'Expected L2 worktree apply without HumanApproved to fail.' }
  if (Test-Path -LiteralPath $l2WorktreePath) { throw 'L2 worktree was created without HumanApproved.' }

  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-worktree.ps1') -TargetPath $l2Target -ItemId smoke-fix -Branch $branch -WorktreePath $l2WorktreePath -OutputDir $l2WorktreeOutputDir | Out-String | Write-Host
  if (Test-Path -LiteralPath $l2WorktreePath) { throw 'L2 worktree preview created a worktree.' }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-worktree.ps1') -TargetPath $l2Target -ItemId smoke-fix -Branch $branch -WorktreePath $l2WorktreePath -OutputDir $l2WorktreeOutputDir -Apply -HumanApproved | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $l2WorktreePath)) { throw 'Expected L2 assisted worktree to exist after approved apply.' }
  $worktreeReport = Get-Content -LiteralPath (Join-Path $l2WorktreeOutputDir 'loop-worktree-report.json') -Raw | ConvertFrom-Json
  if ($worktreeReport.auto_merge -ne $false) { throw 'L2 worktree report must keep auto_merge false.' }
  $lifecyclePath = Join-Path $l2WorktreeOutputDir 'loop-worktree-lifecycle.json'
  if (-not (Test-Path -LiteralPath $lifecyclePath)) { throw 'Expected worktree lifecycle contract.' }
  if ([string]::IsNullOrWhiteSpace([string]$worktreeReport.operation_id)) { throw 'Expected worktree operation ID.' }

  $missingVerifierOutput = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-verify.ps1') -TargetPath $l2Target -LifecyclePath $lifecyclePath -WorktreePath $l2WorktreePath -Branch $branch -OutputDir $l2VerifyMissingOutputDir 2>&1
  $missingVerifierExit = $LASTEXITCODE
  $missingVerifierOutput | Out-String | Write-Host
  if ($missingVerifierExit -eq 0) { throw 'Expected L2 verifier without Verifier to fail.' }
  $missingVerifierReport = Get-Content -LiteralPath (Join-Path $l2VerifyMissingOutputDir 'loop-verify-report.json') -Raw | ConvertFrom-Json
  if (@($missingVerifierReport.failures) -notcontains 'Verifier is required.') { throw 'Expected missing verifier failure in report.' }

  $mismatchOutput = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-verify.ps1') -TargetPath $l2Target -LifecyclePath $lifecyclePath -WorktreePath $l2WorktreePath -Branch 'lizard/l2/wrong-branch' -Verifier smoke-verifier -OutputDir $l2VerifyMismatchOutputDir 2>&1
  $mismatchExit = $LASTEXITCODE
  $mismatchOutput | Out-String | Write-Host
  if ($mismatchExit -eq 0) { throw 'Expected L2 verifier branch mismatch to fail.' }
  $mismatchReport = Get-Content -LiteralPath (Join-Path $l2VerifyMismatchOutputDir 'loop-verify-report.json') -Raw | ConvertFrom-Json
  if ($mismatchReport.branch_matches -ne $false) { throw 'Expected verifier branch_matches false for mismatch.' }
  if ($mismatchReport.same_git_common_dir -ne $true) { throw 'Expected mismatch verifier to still identify same repository.' }

  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-verify.ps1') -TargetPath $l2Target -LifecyclePath $lifecyclePath -WorktreePath $l2WorktreePath -Branch $branch -Verifier smoke-verifier -Status NEEDS_REVIEW -Summary 'Smoke verifier packet generated.' -OutputDir $l2VerifyOutputDir -Apply | Out-String | Write-Host
  $verifyReport = Get-Content -LiteralPath (Join-Path $l2VerifyOutputDir 'loop-verify-report.json') -Raw | ConvertFrom-Json
  if ($verifyReport.branch_matches -ne $true) { throw 'Expected verifier branch binding to pass.' }
  if ($verifyReport.same_git_common_dir -ne $true) { throw 'Expected verifier repository binding to pass.' }
  if ($verifyReport.verifier_file_safe -ne $true) { throw 'Expected verifier file path to be safe.' }
  $targetVerifier = Join-Path $l2Target '.agent\loops\loop-verifier-report.md'
  if (-not (Test-Path -LiteralPath $targetVerifier)) { throw 'Expected target verifier report.' }
  if (-not (Test-Path -LiteralPath (Join-Path $l2Target '.agent\loops\loop-verifier-report.evidence.json'))) { throw 'Expected target verifier evidence envelope.' }
  $verifierText = Get-Content -LiteralPath $targetVerifier -Raw
  foreach ($expected in @('Auto-merge: forbidden', 'Human merge review required: true', 'Merge allowed automatically: false')) {
    if ($verifierText -notmatch [regex]::Escape($expected)) { throw "Expected verifier report to contain: $expected" }
  }

  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-worktree-cleanup.ps1') -TargetPath $l2Target -LifecyclePath $lifecyclePath -WorktreePath $l2WorktreePath -Branch $branch -RemoveBranch -OutputDir $l2CleanupPreviewOutputDir | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $l2WorktreePath)) { throw 'L2 cleanup preview removed the worktree.' }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\loop-worktree-cleanup.ps1') -TargetPath $l2Target -LifecyclePath $lifecyclePath -WorktreePath $l2WorktreePath -Branch $branch -RemoveBranch -Force -OutputDir $l2CleanupOutputDir -Apply -HumanApproved | Out-String | Write-Host
  if (Test-Path -LiteralPath $l2WorktreePath) { throw 'Expected L2 cleanup apply to remove the worktree.' }
  $cleanupReport = Get-Content -LiteralPath (Join-Path $l2CleanupOutputDir 'loop-worktree-cleanup-report.json') -Raw | ConvertFrom-Json
  if ($cleanupReport.removed -ne $true) { throw 'Expected cleanup report removed true.' }
  if ($cleanupReport.branch_deleted -ne $true) { throw 'Expected cleanup report branch_deleted true.' }
  if ($cleanupReport.auto_merge -ne $false) { throw 'Cleanup report must keep auto_merge false.' }
}

Run-Step 'install apply target pack overlay' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $overlayTarget -Profile minimal -Packs project-overlay -Apply | Out-String | Write-Host
  $manifest = Get-Content -LiteralPath (Join-Path $overlayTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  if (@($manifest.requested_packs) -notcontains 'project-overlay') { throw 'Expected requested overlay pack.' }
  foreach ($expectedPack in @('finance-app', 'project-overlay')) {
    if (@($manifest.packs) -notcontains $expectedPack) { throw "Expected expanded overlay pack: $expectedPack" }
  }
  $overlaySource = @($manifest.pack_sources) | Where-Object { $_.name -eq 'project-overlay' } | Select-Object -First 1
  if (-not $overlaySource -or $overlaySource.source -ne 'target-overlay') { throw 'Expected target-overlay pack source.' }
  foreach ($expectedSkill in @('data-quality', 'security-hardening', 'frontend-react')) {
    if (-not (Test-Path -LiteralPath (Join-Path $overlayTarget ".agent\skills\$expectedSkill\SKILL.md"))) { throw "Expected overlay-expanded skill: $expectedSkill" }
  }
}

Run-Step 'manifest diff overlay target strict' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\manifest-diff.ps1') -TargetPath $overlayTarget -Strict | Out-String | Write-Host
}

Run-Step 'upgrade preserves requested packs' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\upgrade.ps1') -TargetPath $overlayTarget -Apply | Out-String | Write-Host
  $manifest = Get-Content -LiteralPath (Join-Path $overlayTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  if (@($manifest.requested_packs) -notcontains 'project-overlay') { throw 'Upgrade did not preserve requested overlay pack.' }
  if (@($manifest.packs) -notcontains 'finance-app') { throw 'Upgrade did not preserve expanded base pack.' }
}

Run-Step 'update target preview plan' {
  $historyPath = Join-Path $overlayTarget '.agent\lizard-agent-layer.update-history.jsonl'
  $historyCountBefore = if (Test-Path -LiteralPath $historyPath) { @(Get-Content -LiteralPath $historyPath).Count } else { 0 }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\update-target.ps1') -TargetPath $overlayTarget -PlanPath $overlayUpdatePlanPath -OutputDir $overlayUpdateOutputDir | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $overlayUpdatePlanPath)) { throw 'Expected update plan report.' }
  $plan = Get-Content -LiteralPath $overlayUpdatePlanPath -Raw
  foreach ($expected in @('# lizard-agent-layer update plan', 'Installed layer version', 'Current layer version', 'Requested packs: `project-overlay`', 'Preview only', 'Apply preserving existing files', 'Manifest differences')) {
    if ($plan -notmatch [regex]::Escape($expected)) { throw "Expected update plan to contain: $expected" }
  }
  $historyCountAfter = if (Test-Path -LiteralPath $historyPath) { @(Get-Content -LiteralPath $historyPath).Count } else { 0 }
  if ($historyCountAfter -ne $historyCountBefore) { throw 'Preview update changed update history.' }
  $reportPath = Join-Path $overlayUpdateOutputDir 'update-report.json'
  if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Expected update report JSON.' }
  $report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
  if ($report.mode -ne 'PREVIEW') { throw "Expected PREVIEW update report, got $($report.mode)." }
  if ($report.profile -ne 'minimal') { throw "Expected minimal update profile, got $($report.profile)." }
  if (@($report.requested_packs) -notcontains 'project-overlay') { throw 'Update preview did not preserve requested overlay pack.' }
}

Run-Step 'update target apply preserves packs' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\update-target.ps1') -TargetPath $overlayTarget -OutputDir $overlayUpdateApplyOutputDir -Apply | Out-String | Write-Host
  $manifest = Get-Content -LiteralPath (Join-Path $overlayTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  if (@($manifest.requested_packs) -notcontains 'project-overlay') { throw 'Update apply did not preserve requested overlay pack.' }
  if (@($manifest.packs) -notcontains 'finance-app') { throw 'Update apply did not preserve expanded base pack.' }
  $historyPath = Join-Path $overlayTarget '.agent\lizard-agent-layer.update-history.jsonl'
  if (-not (Test-Path -LiteralPath $historyPath)) { throw 'Expected update history JSONL.' }
  $history = @(Get-Content -LiteralPath $historyPath)
  if ($history.Count -lt 1) { throw 'Expected at least one update history entry.' }
  $last = $history[-1] | ConvertFrom-Json
  $currentVersion = (Get-Content -LiteralPath (Join-Path $LayerRoot 'VERSION') -Raw).Trim()
  if ($last.to_version -ne $currentVersion) { throw "Expected update history to_version $currentVersion, got $($last.to_version)." }
  if (@($last.requested_packs) -notcontains 'project-overlay') { throw 'Update history did not preserve requested overlay pack.' }
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\manifest-diff.ps1') -TargetPath $overlayTarget -Strict | Out-String | Write-Host
}

Run-Step 'install preview standard multi-harness' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $standardTarget -Profile standard | Out-String | Write-Host
}

Run-Step 'install apply standard multi-harness' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $standardTarget -Profile standard -Apply | Out-String | Write-Host
  foreach ($expected in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md', '.agents\skills\release\SKILL.md', '.claude\skills\release\SKILL.md', '.gemini\skills\release\SKILL.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $standardTarget $expected))) { throw "Expected missing standard artifact: $expected" }
  }
}

Run-Step 'doctor standard strict' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $standardTarget -Strict | Out-String | Write-Host
}

Run-Step 'install apply standard idempotent' {
  $output = & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $standardTarget -Profile standard -Apply | Out-String
  Write-Host $output
  if ($output -notmatch 'Created:\s+1') {
    throw 'Expected second install to create only refreshed ownership manifest.'
  }
}

Run-Step 'install apply cursor override' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $cursorTarget -Profile minimal -Harnesses cursor -Apply | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath (Join-Path $cursorTarget '.cursor\rules\lizard-agent-layer.mdc'))) { throw 'Expected Cursor rule file.' }
  if (-not (Test-Path -LiteralPath (Join-Path $cursorTarget '.cursor\skills\git-safety\SKILL.md'))) { throw 'Expected Cursor skill mirror.' }
}

Run-Step 'doctor cursor strict' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $cursorTarget -Strict | Out-String | Write-Host
}

Run-Step 'install plan sidecar target' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -WritePlan -PlanPath $sidecarPlanPath | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $sidecarPlanPath)) { throw 'Expected install plan report.' }
  $plan = Get-Content -LiteralPath $sidecarPlanPath -Raw
  foreach ($expected in @('# lizard-agent-layer install plan', '## Merge suggestions', 'generic-agents-md', 'AGENTS.lizard-agent-layer.md', 'Suggested block')) {
    if ($plan -notmatch [regex]::Escape($expected)) { throw "Expected install plan to contain: $expected" }
  }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget '.agent')) { throw 'Preview plan wrote .agent into target.' }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md')) { throw 'Preview plan wrote sidecar into target.' }
}

Run-Step 'generate merge suggestions sidecar target' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\merge-suggestions.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -OutputDir $mergeSuggestionDir | Out-String | Write-Host
  $report = Join-Path $mergeSuggestionDir 'merge-suggestions.md'
  $json = Join-Path $mergeSuggestionDir 'merge-suggestions.json'
  $patch = Join-Path $mergeSuggestionDir 'generic-agents-md-AGENTS.md.patch'
  $block = Join-Path $mergeSuggestionDir 'generic-agents-md-AGENTS.md.block.md'
  foreach ($expectedPath in @($report, $json, $patch, $block)) {
    if (-not (Test-Path -LiteralPath $expectedPath)) { throw "Expected merge suggestion artifact: $expectedPath" }
  }
  $reportText = Get-Content -LiteralPath $report -Raw
  foreach ($expectedText in @('# lizard-agent-layer merge suggestions', 'merge-needed', 'AGENTS.lizard-agent-layer.md', 'Patch files')) {
    if ($reportText -notmatch [regex]::Escape($expectedText)) { throw "Expected merge report to contain: $expectedText" }
  }
  $patchText = Get-Content -LiteralPath $patch -Raw
  foreach ($expectedText in @('diff --git a/AGENTS.md b/AGENTS.md', '+## lizard-agent-layer', '+Review `AGENTS.lizard-agent-layer.md`')) {
    if ($patchText -notmatch [regex]::Escape($expectedText)) { throw "Expected patch to contain: $expectedText" }
  }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget '.agent')) { throw 'Merge suggestion generator wrote .agent into target.' }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md')) { throw 'Merge suggestion generator wrote sidecar into target.' }
}

Run-Step 'install apply sidecar target' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -Apply | Out-String | Write-Host
  $agents = Get-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Raw
  if ($agents -match 'lizard-agent-layer') { throw 'Existing AGENTS.md was overwritten or modified.' }
  if (-not (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md'))) { throw 'Expected sidecar AGENTS.lizard-agent-layer.md.' }
  $manifest = Get-Content -LiteralPath (Join-Path $sidecarTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  if (@($manifest.merge_suggestions).Count -lt 1) { throw 'Expected merge suggestions in install manifest.' }
}

Run-Step 'update force managed preserves unowned instruction' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\update-target.ps1') -TargetPath $sidecarTarget -OutputDir $sidecarUpdateForceOutputDir -Apply -ForceManaged | Out-String | Write-Host
  $agents = Get-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Raw
  if ($agents -match 'lizard-agent-layer') { throw 'ForceManaged update overwrote or modified unowned AGENTS.md.' }
  if ($agents -notmatch '# Existing Project Instructions') { throw 'ForceManaged update changed existing AGENTS.md content.' }
  $historyPath = Join-Path $sidecarTarget '.agent\lizard-agent-layer.update-history.jsonl'
  if (-not (Test-Path -LiteralPath $historyPath)) { throw 'Expected sidecar update history JSONL.' }
}

Run-Step 'doctor sidecar non-strict' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $sidecarTarget | Out-String | Write-Host
}

Write-Host "Smoke passed. Scratch output: $tmpRoot"
