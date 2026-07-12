param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("documentation-recovery-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$output = Join-Path $fixture 'recovery-output'
New-Item -ItemType Directory -Path $target -Force | Out-Null

try {
  $troubleshooting = Get-Content -LiteralPath (Join-Path $LayerRoot 'docs\troubleshooting.md') -Raw
  foreach ($required in @(
    'TRANSACTION_LOCK_HELD', 'TRANSACTION_JOURNAL_MISSING', 'TRANSACTION_ROLLBACK_FAILED',
    'MANIFEST_READER_TOO_OLD', 'DOWNGRADE_APPROVAL_REQUIRED', 'EVIDENCE_HASH_MISMATCH',
    'SELF_VERIFICATION_FORBIDDEN', 'SCHEMA_VALIDATOR_DEPENDENCY_MISSING',
    'transaction-recover.ps1', 'manifest-diff.ps1', 'contract-check.ps1', '-HumanApproved'
  )) {
    Assert-True ($troubleshooting -match [regex]::Escape($required)) "Troubleshooting guide is missing '$required'."
  }

  foreach ($adr in @(
    '0001-source-of-truth-and-layer-boundaries.md', '0002-filesystem-and-report-containment.md',
    '0003-ownership-and-manifest-identity.md', '0004-adapter-composition-and-precedence.md',
    '0005-schema-and-manifest-evolution.md', '0006-transaction-and-recovery-semantics.md',
    '0007-report-boundaries-and-privacy.md', '0008-loop-lifecycle-and-no-auto-merge.md'
  )) {
    $path = Join-Path $LayerRoot "docs\adr\$adr"
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Missing ADR $adr."
    $text = Get-Content -LiteralPath $path -Raw
    foreach ($heading in @('Status: Accepted', '## Context', '## Decision', '## Consequences')) {
      Assert-True ($text -match [regex]::Escape($heading)) "ADR $adr is missing '$heading'."
    }
  }

  $recovery = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts\transaction-recover.ps1') -Arguments @('-TargetPath', $target, '-OutputDir', $output, '-Json')
  Assert-Equal 0 $recovery.exit_code "Documented clean recovery preview failed: $($recovery.output)"
  $report = $recovery.output | ConvertFrom-Json
  Assert-Equal 'CLEAN' ([string]$report.status) 'Clean target recovery preview must report CLEAN.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Recovery preview must not dirty the target.'

  Write-Host 'PASS tests\integration\documentation-recovery.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
