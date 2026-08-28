param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $LayerRoot 'scripts'))) {
    $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Transaction.psm1') -Force

$fixtureRoot = Join-Path $LayerRoot '.tmp/tests/tx-poststate-test'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

try {
  # 1. Test external recreation after deletion causes rollback failure
  $targetFile = Join-Path $fixtureRoot 'pre-existing.txt'
  Set-SafeContent -AuthorizedRoot $fixtureRoot -Path $targetFile -Value 'original-pre-existing-content'
  
  $tx = Start-LizardTransaction -TargetRoot $fixtureRoot -OperationName 'test-deletion-rollback'
  Remove-LizardTransactionalItem -Path $targetFile -Kind File
  
  Assert-False (Test-Path -LiteralPath $targetFile) 'File must be deleted in transaction'

  # Simulate external recreation before rollback occurs
  [System.IO.File]::WriteAllText($targetFile, 'recreated-by-external-process')

  $rollbackError = $null
  try {
    Undo-LizardTransaction
  } catch {
    $rollbackError = $_
  }

  Assert-True ($null -ne $rollbackError) 'Rollback must fail closed when deleted target was recreated'
  Assert-True ($rollbackError.Exception.Message -match 'TRANSACTION_ROLLBACK_DESTINATION_DIVERGED') 'Expected TRANSACTION_ROLLBACK_DESTINATION_DIVERGED'

  # Assert external content is untouched
  $surviving = [System.IO.File]::ReadAllText($targetFile)
  Assert-Equal 'recreated-by-external-process' $surviving 'External file must remain untouched by failed rollback'

  # Clean up lock manually for next test
  $lockFile = Join-Path $fixtureRoot '.lizard-agent-layer.lock'
  $txStore = Join-Path $fixtureRoot '.lizard-agent-layer-transactions'
  if (Test-Path -LiteralPath $lockFile) { Remove-Item -LiteralPath $lockFile -Force }
  if (Test-Path -LiteralPath $txStore) { Remove-Item -LiteralPath $txStore -Recurse -Force }

  # 2. Test external modification of written file causes rollback failure
  $writeFile = Join-Path $fixtureRoot 'written-file.txt'
  $tx2 = Start-LizardTransaction -TargetRoot $fixtureRoot -OperationName 'test-write-diverged'
  Set-LizardTransactionalContent -Path $writeFile -Value 'initial-tx-write'

  # External process changes written file
  [System.IO.File]::WriteAllText($writeFile, 'external-mutation')

  $rollbackError2 = $null
  try {
    Undo-LizardTransaction
  } catch {
    $rollbackError2 = $_
  }

  Assert-True ($null -ne $rollbackError2) 'Rollback must fail closed when written target was mutated externally'
  Assert-True ($rollbackError2.Exception.Message -match 'TRANSACTION_ROLLBACK_DESTINATION_DIVERGED') 'Expected TRANSACTION_ROLLBACK_DESTINATION_DIVERGED'
  
  # Assert external content is untouched
  $surviving2 = [System.IO.File]::ReadAllText($writeFile)
  Assert-Equal 'external-mutation' $surviving2 'External file must not be removed or overwritten'

} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
}

Write-Host "PASS tests\adversarial\transaction-poststate.tests.ps1"
