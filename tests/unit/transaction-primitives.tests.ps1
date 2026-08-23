param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Transaction.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("transaction-primitives-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
New-Item -ItemType Directory -Path $target -Force | Out-Null

function Assert-NoTransactionMetadata {
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'A terminal transaction must remove its lock.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer-transactions')) 'A terminal transaction must remove its empty metadata store.'
}

try {
  $rolledBackPath = Join-Path $target 'rolled-back.txt'
  Start-LizardTransaction -TargetRoot $target -OperationName 'primitive-rollback' | Out-Null
  Set-LizardTransactionalContent -Path $rolledBackPath -Value 'temporary'
  Add-LizardTransactionalContent -Path $rolledBackPath -Value 'append'
  Undo-LizardTransaction | Out-Null
  Assert-False (Test-Path -LiteralPath $rolledBackPath) 'Rollback must remove a transaction-created file through the handle-bound delete primitive.'
  Assert-NoTransactionMetadata

  $committedPath = Join-Path $target 'committed.txt'
  Start-LizardTransaction -TargetRoot $target -OperationName 'primitive-commit' | Out-Null
  Set-LizardTransactionalContent -Path $committedPath -Value 'committed'
  Complete-LizardTransaction | Out-Null
  Assert-True ((Get-Content -LiteralPath $committedPath -Raw) -match 'committed') 'Commit must retain the atomically written target file.'
  Assert-NoTransactionMetadata

  $deleteDirectory = Join-Path $target 'delete-and-restore'
  $deleteFile = Join-Path $deleteDirectory 'owned.txt'
  New-Item -ItemType Directory -Path $deleteDirectory -Force | Out-Null
  Set-Content -LiteralPath $deleteFile -Value 'restore canary' -Encoding UTF8
  $deleteHash = (Get-FileHash -LiteralPath $deleteFile -Algorithm SHA256).Hash.ToLowerInvariant()
  Start-LizardTransaction -TargetRoot $target -OperationName 'primitive-delete-rollback' | Out-Null
  Remove-LizardTransactionalItem -Path $deleteFile -Kind File
  Remove-LizardTransactionalItem -Path $deleteDirectory -Kind EmptyDirectory
  Assert-False (Test-Path -LiteralPath $deleteDirectory) 'Transactional deletion must remove the explicit file and then its empty directory.'
  Undo-LizardTransaction | Out-Null
  Assert-True (Test-Path -LiteralPath $deleteDirectory -PathType Container) 'Rollback must recreate an explicitly deleted empty directory.'
  Assert-Equal $deleteHash ((Get-FileHash -LiteralPath $deleteFile -Algorithm SHA256).Hash.ToLowerInvariant()) 'Rollback must restore deleted file bytes exactly.'
  Assert-NoTransactionMetadata

  Start-LizardTransaction -TargetRoot $target -OperationName 'primitive-delete-commit' | Out-Null
  Remove-LizardTransactionalItem -Path $deleteFile -Kind File
  Remove-LizardTransactionalItem -Path $deleteDirectory -Kind EmptyDirectory
  Complete-LizardTransaction | Out-Null
  Assert-False (Test-Path -LiteralPath $deleteDirectory) 'Commit must retain the explicit deletion.'
  Assert-NoTransactionMetadata

  Start-LizardTransaction -TargetRoot $target -OperationName 'lock-owner' | Out-Null
  Assert-ThrowsCode { Start-LizardTransaction -TargetRoot $target -OperationName 'lock-contender' | Out-Null } 'TRANSACTION_LOCK_HELD' 'Create-new lock publication must admit only one transaction.'
  Undo-LizardTransaction | Out-Null
  Assert-NoTransactionMetadata

  Write-Host 'PASS tests\unit\transaction-primitives.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
