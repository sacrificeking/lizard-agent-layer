param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("install-uninstall-roundtrip-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$reports = Join-Path $fixture 'reports'
$install = Join-Path $LayerRoot 'scripts\install.ps1'
$uninstall = Join-Path $LayerRoot 'scripts\uninstall.ps1'
New-Item -ItemType Directory -Path $target, $reports -Force | Out-Null

try {
  $installPlan = Join-Path $reports 'install.json'
  $installPreview = Invoke-TestPowerShell -ScriptPath $install -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'codex', '-CanonicalPlanPath', $installPlan)
  Assert-Equal 0 $installPreview.exit_code "Real installer preview failed: $($installPreview.output)"
  $installSha = (Get-Content -LiteralPath ($installPlan + '.sha256') -Raw).Trim()
  $installApply = Invoke-TestPowerShell -ScriptPath $install -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'codex', '-Apply', '-ApprovedPlanPath', $installPlan, '-ApprovedPlanSha256', $installSha, '-HumanApproved')
  Assert-Equal 0 $installApply.exit_code "Real installer apply failed: $($installApply.output)"
  $manifestPath = Join-Path $target '.agent\lizard-agent-layer.install.json'
  Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Real installation must produce a schema-v4 manifest.'
  $installedManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  foreach ($nestedDirectory in @('.agent/memory', '.agents', '.agent/skills/research-audit/references', '.agent/skills/research-audit/tests')) {
    $directoryRecord = @($installedManifest.artifacts | Where-Object { $_.path -eq $nestedDirectory })
    Assert-Equal 1 $directoryRecord.Count "Every nested skill directory must have one manifest record: $nestedDirectory"
    Assert-Equal 'directory' ([string]$directoryRecord[0].kind) "Nested skill path must be recorded as a directory: $nestedDirectory"
    Assert-Equal 'layer-owned' ([string]$directoryRecord[0].ownership) "New nested skill directories must remain removable layer-owned artifacts: $nestedDirectory"
  }

  $modifiedPath = Join-Path $target '.agent\memory\personal\PREFERENCES.md'
  Add-Content -LiteralPath $modifiedPath -Value 'local preference canary' -Encoding UTF8
  $modifiedHash = (Get-FileHash -LiteralPath $modifiedPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $managedPlan = Join-Path $reports 'managed-only.md'
  $managedPreview = Invoke-TestPowerShell -ScriptPath $uninstall -Arguments @('-TargetPath', $target, '-PlanPath', $managedPlan)
  Assert-Equal 0 $managedPreview.exit_code "Managed-only preview on a real installation failed: $($managedPreview.output)"
  $managedCanonical = [System.IO.Path]::ChangeExtension($managedPlan, '.json')
  $managedSha = (Get-Content -LiteralPath ($managedCanonical + '.sha256') -Raw).Trim()
  $managedApply = Invoke-TestPowerShell -ScriptPath $uninstall -Arguments @('-TargetPath', $target, '-Apply', '-ApprovedPlanPath', $managedCanonical, '-ApprovedPlanSha256', $managedSha, '-HumanApproved')
  Assert-Equal 0 $managedApply.exit_code "Managed-only partial apply on a real installation failed: $($managedApply.output)"
  Assert-Equal $modifiedHash ((Get-FileHash -LiteralPath $modifiedPath -Algorithm SHA256).Hash.ToLowerInvariant()) 'Managed-only partial apply must preserve modified bytes exactly.'
  Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'Partial apply must retain residual ownership evidence.'
  $residual = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  Assert-Equal 'active' ([string](@($residual.artifacts | Where-Object { $_.path -eq '.agent/memory/personal/PREFERENCES.md' })[0].lifecycle)) 'Modified artifact must remain active in the residual manifest.'
  Assert-True (@($residual.artifacts | Where-Object { $_.lifecycle -eq 'removed' }).Count -gt 0) 'Removed unchanged artifacts must retain tombstoned ownership records.'

  $completePlan = Join-Path $reports 'complete.md'
  $completePreview = Invoke-TestPowerShell -ScriptPath $uninstall -Arguments @('-TargetPath', $target, '-Scope', 'complete', '-ConfirmModifiedLayerOwnedPurge', '-PlanPath', $completePlan)
  Assert-Equal 0 $completePreview.exit_code "Complete preview after partial removal failed: $($completePreview.output)"
  $completeCanonical = [System.IO.Path]::ChangeExtension($completePlan, '.json')
  $completeSha = (Get-Content -LiteralPath ($completeCanonical + '.sha256') -Raw).Trim()
  $completeApply = Invoke-TestPowerShell -ScriptPath $uninstall -Arguments @('-TargetPath', $target, '-Scope', 'complete', '-ConfirmModifiedLayerOwnedPurge', '-Apply', '-ApprovedPlanPath', $completeCanonical, '-ApprovedPlanSha256', $completeSha, '-HumanApproved')
  Assert-Equal 0 $completeApply.exit_code "Complete apply after partial removal failed: $($completeApply.output)"
  Assert-Equal 0 @([System.IO.Directory]::EnumerateFileSystemEntries($target)).Count 'Install then partial then complete uninstall must restore the originally empty target tree.'

  Write-Host 'PASS tests\integration\uninstall-install-roundtrip.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
