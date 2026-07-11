param(
  [string]$RepositoryRoot,
  [string]$FixtureRoot,
  [string]$LayerRoot
)

$ErrorActionPreference = 'Stop'
$effectiveRepositoryRoot = if (-not [string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot } elseif (-not [string]::IsNullOrWhiteSpace($LayerRoot)) { $LayerRoot } else { $null }
$RepoRoot = if ([string]::IsNullOrWhiteSpace($effectiveRepositoryRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $effectiveRepositoryRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.LoopEvidence.psm1') -Force

$fixtureRoot = if ([string]::IsNullOrWhiteSpace($FixtureRoot)) { Join-Path $RepoRoot '.tmp\tests\loop-evidence' } else { [System.IO.Path]::GetFullPath($FixtureRoot) }
$fixtureAllowedRoot = Split-Path -Parent $fixtureRoot
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot $fixtureAllowedRoot }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

$target = Join-Path $fixtureRoot 'target'
$worktree = Join-Path $fixtureRoot 'worktree'
$createOutput = Join-Path $fixtureRoot 'create-output'
$lifecyclePath = Join-Path $createOutput 'loop-worktree-lifecycle.json'
$installScript = Join-Path $RepoRoot 'scripts\install.ps1'
$loopInitScript = Join-Path $RepoRoot 'scripts\loop-init.ps1'
$worktreeScript = Join-Path $RepoRoot 'scripts\loop-worktree.ps1'
$verifyScript = Join-Path $RepoRoot 'scripts\loop-verify.ps1'
$auditScript = Join-Path $RepoRoot 'scripts\loop-audit.ps1'
$cleanupScript = Join-Path $RepoRoot 'scripts\loop-worktree-cleanup.ps1'
$branch = 'lizard/l2/evidence-test'

function Assert-GitSuccess {
  param([string[]]$Arguments, [string]$Message)
  $output = & git @Arguments 2>&1
  if ($LASTEXITCODE -ne 0) { throw "${Message}: $output" }
}

try {
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Assert-GitSuccess @('-C', $target, 'init', '--quiet') 'git init failed'
  Assert-GitSuccess @('-C', $target, 'config', 'user.email', 'tests@lizard-agent-layer.invalid') 'git email config failed'
  Assert-GitSuccess @('-C', $target, 'config', 'user.name', 'lizard tests') 'git name config failed'
  Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# fixture'
  Assert-GitSuccess @('-C', $target, 'add', 'README.md') 'git add failed'
  Assert-GitSuccess @('-C', $target, 'commit', '--quiet', '-m', 'fixture') 'git commit failed'

  $install = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Packs', 'loop-engineering', '-Apply')
  Assert-Equal 0 $install.exit_code "Loop pack install failed: $($install.output)"
  $loopInit = Invoke-TestPowerShell -ScriptPath $loopInitScript -Arguments @('-TargetPath', $target, '-Pattern', 'minimal-fix-assist', '-OutputDir', (Join-Path $fixtureRoot 'init-output'), '-Apply')
  Assert-Equal 0 $loopInit.exit_code "Loop init failed: $($loopInit.output)"

  $nestedPath = Join-Path $target 'nested-worktree'
  $nested = Invoke-TestPowerShell -ScriptPath $worktreeScript -Arguments @('-TargetPath', $target, '-Branch', 'lizard/l2/nested-test', '-WorktreePath', $nestedPath, '-OutputDir', (Join-Path $fixtureRoot 'nested-output'), '-Apply', '-HumanApproved')
  Assert-False ($nested.exit_code -eq 0) 'Target-contained worktree must be rejected.'
  Assert-False (Test-Path -LiteralPath $nestedPath) 'Rejected nested worktree path must remain absent.'

  $create = Invoke-TestPowerShell -ScriptPath $worktreeScript -Arguments @('-TargetPath', $target, '-ItemId', 'evidence-test', '-Branch', $branch, '-WorktreePath', $worktree, '-OutputDir', $createOutput, '-Apply', '-HumanApproved')
  Assert-Equal 0 $create.exit_code "Worktree creation failed: $($create.output)"
  Assert-True (Test-Path -LiteralPath $lifecyclePath) 'Worktree creation must write lifecycle contract.'
  $lifecycle = Read-LizardEvidenceEnvelope -Path $lifecyclePath -SchemaVersion 1
  Assert-Equal 'CREATED' $lifecycle.payload.status 'Lifecycle status must be CREATED.'
  Assert-Equal $branch $lifecycle.payload.branch 'Lifecycle branch mismatch.'
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$lifecycle.payload.operation_id)) 'Lifecycle operation ID is required.'

  $passOutput = Join-Path $fixtureRoot 'verify-pass'
  $pass = Invoke-TestPowerShell -ScriptPath $verifyScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-Verifier', 'independent-reviewer', '-Implementer', 'implementation-agent', '-Status', 'PASS', '-Summary', 'Evidence checks passed.', '-VerificationCommand', 'git rev-parse HEAD', '-EvidenceFile', 'README.md', '-OutputDir', $passOutput, '-Apply')
  Assert-Equal 0 $pass.exit_code "Evidence-bound PASS failed: $($pass.output)"
  $passReport = Get-Content -LiteralPath (Join-Path $passOutput 'loop-verify-report.json') -Raw | ConvertFrom-Json
  Assert-Equal 'PASS' $passReport.status 'Verifier effective status must be PASS.'
  Assert-Equal $lifecycle.payload.operation_id $passReport.operation_id 'Verifier must bind lifecycle operation ID.'
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$passReport.head_sha)) 'Verifier must bind HEAD SHA.'
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$passReport.git_state_hash)) 'Verifier must bind final git state hash.'
  Assert-Equal 0 ([int]$passReport.command_results[0].exit_code) 'Verification command must record exit zero.'
  $targetEvidence = Join-Path $target '.agent\loops\loop-verifier-report.evidence.json'
  $sealedEvidence = Read-LizardEvidenceEnvelope -Path $targetEvidence -SchemaVersion 1
  Assert-Equal $passReport.evidence_packet_hash $sealedEvidence.payload_hash 'Target evidence packet hash mismatch.'
  $sealedHashBeforeFailures = (Get-FileHash -LiteralPath $targetEvidence -Algorithm SHA256).Hash
  $targetVerifierMarkdown = Join-Path $target '.agent\loops\loop-verifier-report.md'
  $sealedMarkdownHashBeforeFailures = (Get-FileHash -LiteralPath $targetVerifierMarkdown -Algorithm SHA256).Hash

  $faultedWrite = Invoke-TestPowerShell -ScriptPath $verifyScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-Verifier', 'independent-reviewer', '-Implementer', 'implementation-agent', '-Status', 'PASS', '-Summary', 'This packet must roll back.', '-VerificationCommand', 'git rev-parse HEAD', '-OutputDir', (Join-Path $fixtureRoot 'verify-write-fault'), '-Apply', '-TestFailAfterMutation', '1')
  Assert-False ($faultedWrite.exit_code -eq 0) 'Fault-injected verifier target write must fail.'
  Assert-Equal $sealedHashBeforeFailures (Get-FileHash -LiteralPath $targetEvidence -Algorithm SHA256).Hash 'Verifier evidence write must roll back atomically.'
  Assert-Equal $sealedMarkdownHashBeforeFailures (Get-FileHash -LiteralPath $targetVerifierMarkdown -Algorithm SHA256).Hash 'Verifier Markdown write must roll back atomically.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Verifier rollback must release target lock.'

  $audit = Invoke-TestPowerShell -ScriptPath $auditScript -Arguments @('-TargetPath', $target, '-OutputDir', (Join-Path $fixtureRoot 'audit-pass'), '-Strict')
  Assert-Equal 0 $audit.exit_code "Fresh verifier evidence must pass strict audit: $($audit.output)"

  $evidenceBackup = Join-Path $fixtureRoot 'verifier-evidence.backup.json'
  Move-Item -LiteralPath $targetEvidence -Destination $evidenceBackup
  $missingEvidenceAudit = Invoke-TestPowerShell -ScriptPath $auditScript -Arguments @('-TargetPath', $target, '-OutputDir', (Join-Path $fixtureRoot 'audit-missing-evidence'), '-Strict')
  Assert-False ($missingEvidenceAudit.exit_code -eq 0) 'Declared PASS without evidence sidecar must fail audit.'
  Assert-True ($missingEvidenceAudit.output -match 'without a hashed evidence sidecar') 'Missing evidence sidecar failure must be explicit.'
  Move-Item -LiteralPath $evidenceBackup -Destination $targetEvidence

  $markdownBackup = Join-Path $fixtureRoot 'verifier-markdown.backup.md'
  Copy-Item -LiteralPath $targetVerifierMarkdown -Destination $markdownBackup
  $tamperedMarkdown = (Get-Content -LiteralPath $targetVerifierMarkdown -Raw) -replace 'Evidence packet hash: [a-f0-9]{64}', ('Evidence packet hash: ' + ('0' * 64))
  Set-Content -LiteralPath $targetVerifierMarkdown -Value $tamperedMarkdown
  $tamperedMarkdownAudit = Invoke-TestPowerShell -ScriptPath $auditScript -Arguments @('-TargetPath', $target, '-OutputDir', (Join-Path $fixtureRoot 'audit-tampered-markdown'), '-Strict')
  Assert-False ($tamperedMarkdownAudit.exit_code -eq 0) 'Markdown detached from evidence packet must fail audit.'
  Assert-True ($tamperedMarkdownAudit.output -match 'not bound to the current evidence packet hash') 'Markdown packet mismatch must be explicit.'
  Copy-Item -LiteralPath $markdownBackup -Destination $targetVerifierMarkdown -Force

  $tamperedLifecyclePath = Join-Path $fixtureRoot 'tampered-lifecycle.json'
  $tampered = Get-Content -LiteralPath $lifecyclePath -Raw | ConvertFrom-Json
  $tampered.payload.branch = 'lizard/l2/tampered'
  Set-Content -LiteralPath $tamperedLifecyclePath -Value ($tampered | ConvertTo-Json -Depth 12)
  $tamperedVerify = Invoke-TestPowerShell -ScriptPath $verifyScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $tamperedLifecyclePath, '-Verifier', 'independent-reviewer', '-OutputDir', (Join-Path $fixtureRoot 'verify-tampered'))
  Assert-False ($tamperedVerify.exit_code -eq 0) 'Tampered lifecycle must be rejected.'
  $tamperedReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'verify-tampered\loop-verify-report.json') -Raw | ConvertFrom-Json
  Assert-True ((@($tamperedReport.failures) -join ' ') -match 'EVIDENCE_HASH_MISMATCH') 'Tampered lifecycle must expose hash mismatch.'

  $selfVerify = Invoke-TestPowerShell -ScriptPath $verifyScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-Verifier', 'same-agent', '-Implementer', 'same-agent', '-Status', 'PASS', '-VerificationCommand', 'git rev-parse HEAD', '-OutputDir', (Join-Path $fixtureRoot 'verify-self'), '-Apply')
  Assert-False ($selfVerify.exit_code -eq 0) 'Self-verification must fail.'
  $selfReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'verify-self\loop-verify-report.json') -Raw | ConvertFrom-Json
  Assert-True ((@($selfReport.failures) -join ' ') -match 'SELF_VERIFICATION_FORBIDDEN') 'Self-verification must expose stable code.'

  $failedCommand = Invoke-TestPowerShell -ScriptPath $verifyScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-Verifier', 'independent-reviewer', '-Implementer', 'implementation-agent', '-Status', 'PASS', '-VerificationCommand', 'exit 7', '-OutputDir', (Join-Path $fixtureRoot 'verify-command-failure'), '-Apply')
  Assert-False ($failedCommand.exit_code -eq 0) 'PASS with a failed command must fail.'
  Assert-Equal $sealedHashBeforeFailures (Get-FileHash -LiteralPath $targetEvidence -Algorithm SHA256).Hash 'Rejected verdict must not replace sealed target evidence.'

  Assert-GitSuccess @('-C', $worktree, 'checkout', '--detach', '--quiet') 'detach failed'
  $detached = Invoke-TestPowerShell -ScriptPath $verifyScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-Verifier', 'independent-reviewer', '-OutputDir', (Join-Path $fixtureRoot 'verify-detached'))
  Assert-False ($detached.exit_code -eq 0) 'Detached HEAD must be rejected.'
  $detachedReport = Get-Content -LiteralPath (Join-Path $fixtureRoot 'verify-detached\loop-verify-report.json') -Raw | ConvertFrom-Json
  Assert-True ((@($detachedReport.failures) -join ' ') -match 'Detached HEAD') 'Detached HEAD rejection must be explicit.'
  Assert-GitSuccess @('-C', $worktree, 'checkout', '--quiet', $branch) 'branch restore failed'

  Add-Content -LiteralPath (Join-Path $worktree 'README.md') -Value 'changed after verification'
  $staleAudit = Invoke-TestPowerShell -ScriptPath $auditScript -Arguments @('-TargetPath', $target, '-OutputDir', (Join-Path $fixtureRoot 'audit-stale'), '-Strict')
  Assert-False ($staleAudit.exit_code -eq 0) 'Changed worktree must invalidate prior verifier evidence.'
  Assert-True ($staleAudit.output -match 'stale') 'Stale evidence audit must explain the state mismatch.'

  $unboundCleanup = Invoke-TestPowerShell -ScriptPath $cleanupScript -Arguments @('-TargetPath', $target, '-WorktreePath', $worktree, '-Branch', $branch, '-RemoveBranch', '-Force', '-OutputDir', (Join-Path $fixtureRoot 'cleanup-unbound'), '-Apply', '-HumanApproved')
  Assert-False ($unboundCleanup.exit_code -eq 0) 'Cleanup apply without lifecycle must fail closed.'
  Assert-True (Test-Path -LiteralPath $worktree) 'Rejected unbound cleanup must preserve worktree.'

  $tamperedCleanup = Invoke-TestPowerShell -ScriptPath $cleanupScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $tamperedLifecyclePath, '-WorktreePath', $worktree, '-Branch', $branch, '-RemoveBranch', '-Force', '-OutputDir', (Join-Path $fixtureRoot 'cleanup-tampered'), '-Apply', '-HumanApproved')
  Assert-False ($tamperedCleanup.exit_code -eq 0) 'Cleanup must reject tampered lifecycle.'
  Assert-True (Test-Path -LiteralPath $worktree) 'Tampered cleanup must preserve worktree.'

  $cleanup = Invoke-TestPowerShell -ScriptPath $cleanupScript -Arguments @('-TargetPath', $target, '-LifecyclePath', $lifecyclePath, '-WorktreePath', $worktree, '-Branch', $branch, '-RemoveBranch', '-Force', '-OutputDir', (Join-Path $fixtureRoot 'cleanup'), '-Apply', '-HumanApproved')
  Assert-Equal 0 $cleanup.exit_code "Lifecycle-bound cleanup failed: $($cleanup.output)"
  Assert-False (Test-Path -LiteralPath $worktree) 'Cleanup must remove worktree.'

  Write-Host 'PASS tests\adversarial\loop-evidence.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $worktree) { & git -C $target worktree remove --force $worktree 2>$null | Out-Null }
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot $fixtureAllowedRoot }
}
