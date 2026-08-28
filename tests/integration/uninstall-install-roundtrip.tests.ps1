param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("install-uninstall-roundtrip-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$reports = Join-Path $fixture 'reports'
$install = Join-Path $LayerRoot 'scripts/install.ps1'
$uninstall = Join-Path $LayerRoot 'scripts/uninstall.ps1'
New-Item -ItemType Directory -Path $target, $reports -Force | Out-Null

try {
  $installApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'codex')
  $installApply = Invoke-TestPowerShell -ScriptPath $install -Arguments $installApproval.arguments
  Assert-Equal 0 $installApply.exit_code "Real installer apply failed: $($installApply.output)"
  $manifestPath = Join-Path $target '.agent/lizard-agent-layer.install.json'
  Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Real installation must produce a schema-v4 manifest.'
  $installedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-LizardJson
  foreach ($nestedDirectory in @('.agent/memory', '.agents', '.agent/skills/research-audit/references', '.agent/skills/research-audit/tests')) {
    $directoryRecord = @($installedManifest.artifacts | Where-Object { $_.path -eq $nestedDirectory })
    Assert-Equal 1 $directoryRecord.Count "Every nested skill directory must have one manifest record: $nestedDirectory"
    Assert-Equal 'directory' ([string]$directoryRecord[0].kind) "Nested skill path must be recorded as a directory: $nestedDirectory"
    Assert-Equal 'layer-owned' ([string]$directoryRecord[0].ownership) "New nested skill directories must remain removable layer-owned artifacts: $nestedDirectory"
  }

  $modifiedPath = Join-Path $target '.agent/memory/personal/PREFERENCES.md'
  Add-Content -LiteralPath $modifiedPath -Value 'local preference canary' -Encoding UTF8
  $modifiedHash = (Get-FileHash -LiteralPath $modifiedPath -Algorithm SHA256).Hash.ToLowerInvariant()
  
  $managedApproval = New-TestUninstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Scope', 'managed-only')
  $managedApply = Invoke-TestPowerShell -ScriptPath $uninstall -Arguments $managedApproval.arguments
  Assert-Equal 0 $managedApply.exit_code "Managed-only partial apply on a real installation failed: $($managedApply.output)"
  Assert-Equal $modifiedHash ((Get-FileHash -LiteralPath $modifiedPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'Managed-only partial apply must preserve modified bytes exactly.'
  Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Partial apply must retain residual ownership evidence.'
  $residual = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'active' ([string](@($residual.artifacts | Where-Object { $_.path -eq '.agent/memory/personal/PREFERENCES.md' })[0].lifecycle)) 'Modified artifact must remain active in the residual manifest.'
  Assert-True (@($residual.artifacts | Where-Object { $_.lifecycle -eq 'removed' }).Count -gt 0) 'Removed unchanged artifacts must retain tombstoned ownership records.'

  $completeApproval = New-TestUninstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Scope', 'complete', '-ConfirmModifiedLayerOwnedPurge')
  $completeApply = Invoke-TestPowerShell -ScriptPath $uninstall -Arguments $completeApproval.arguments
  Assert-Equal 0 $completeApply.exit_code "Complete apply after partial removal failed: $($completeApply.output)"
  Assert-Equal 0 @([System.IO.Directory]::EnumerateFileSystemEntries($target)).Count 'Install then partial then complete uninstall must restore the originally empty target tree.'

  Write-Host 'PASS tests\integration\uninstall-install-roundtrip.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
