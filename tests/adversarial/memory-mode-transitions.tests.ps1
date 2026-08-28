param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
$fixture = Join-Path $testRoot ("memory-mode-transitions-{0}" -f ([Guid]::NewGuid().ToString('N')))
$installScript = Join-Path $LayerRoot 'scripts/install.ps1'
$doctorScript = Join-Path $LayerRoot 'scripts/doctor.ps1'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

function Invoke-ApprovedMode {
  param([string]$Target, [string]$Mode, [int]$FailAfterMutation = 0)
  $base = @('-TargetPath', $Target, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', $Mode)
  if ($FailAfterMutation -gt 0) { $base += @('-TestFailAfterMutation', [string]$FailAfterMutation) }
  $approval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments $base
  $apply = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $approval.arguments
  return [pscustomobject]@{ approval = $approval; apply = $apply }
}

function New-InstalledModeTarget {
  param([string]$Name, [string]$Mode)
  $target = Join-Path $fixture $Name
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  $result = Invoke-ApprovedMode -Target $target -Mode $Mode
  Assert-Equal 0 $result.apply.exit_code "Initial $Mode install must succeed: $($result.apply.output)"
  return $target
}

function Assert-ManifestMode {
  param([string]$Target, [string]$Mode)
  $manifest = Get-Content -LiteralPath (Join-Path $Target '.agent/lizard-agent-layer.install.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal $Mode ([string]$manifest.memory_mode) "Manifest must remain in mode $Mode."
  return $manifest
}

try {
  $roundtrip = New-InstalledModeTarget -Name 'roundtrip' -Mode 'curated'
  $curatedSame = Invoke-ApprovedMode -Target $roundtrip -Mode 'curated'
  Assert-Equal 0 $curatedSame.apply.exit_code "curated -> curated must be idempotent: $($curatedSame.apply.output)"
  $curatedToPrivate = Invoke-ApprovedMode -Target $roundtrip -Mode 'private-episodic'
  Assert-Equal 0 $curatedToPrivate.apply.exit_code "curated -> private-episodic must succeed: $($curatedToPrivate.apply.output)"
  $privateSame = Invoke-ApprovedMode -Target $roundtrip -Mode 'private-episodic'
  Assert-Equal 0 $privateSame.apply.exit_code "private-episodic -> private-episodic must be idempotent: $($privateSame.apply.output)"
  $privateToOff = Invoke-ApprovedMode -Target $roundtrip -Mode 'off'
  Assert-Equal 0 $privateToOff.apply.exit_code "private-episodic -> off must succeed for unchanged managed content: $($privateToOff.apply.output)"
  $offSame = Invoke-ApprovedMode -Target $roundtrip -Mode 'off'
  Assert-Equal 0 $offSame.apply.exit_code "off -> off must be idempotent: $($offSame.apply.output)"
  $offToCurated = Invoke-ApprovedMode -Target $roundtrip -Mode 'curated'
  Assert-Equal 0 $offToCurated.apply.exit_code "off -> curated must reactivate curated artifacts: $($offToCurated.apply.output)"
  $toOff = Invoke-ApprovedMode -Target $roundtrip -Mode 'off'
  Assert-Equal 0 $toOff.apply.exit_code "curated -> off must succeed: $($toOff.apply.output)"
  $offManifest = Assert-ManifestMode -Target $roundtrip -Mode 'off'
  Assert-False (Test-Path -LiteralPath (Join-Path $roundtrip '.agent/memory')) 'curated -> off must remove the physical memory namespace.'
  Assert-True (@($offManifest.artifacts | Where-Object { ([string]$_.path).StartsWith('.agent/memory') -and $_.lifecycle -eq 'removed' }).Count -gt 0) 'Off manifest must retain non-executable removed tombstones.'
  $offPlan = Get-Content -LiteralPath $toOff.approval.plan_path -Raw | ConvertFrom-LizardJson
  foreach ($entry in @($offPlan.intent.target_entries | Where-Object { $_.action -eq 'remove' })) {
    Assert-True (-not [string]::IsNullOrWhiteSpace([string]$entry.precondition_identity_sha256)) "Removal must bind physical identity: $($entry.path)"
  }
  $doctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $roundtrip, '-Strict')
  Assert-Equal 0 $doctor.exit_code "Doctor must accept transitioned off target: $($doctor.output)"

  $toPrivate = Invoke-ApprovedMode -Target $roundtrip -Mode 'private-episodic'
  Assert-Equal 0 $toPrivate.apply.exit_code "off -> private-episodic must succeed: $($toPrivate.apply.output)"
  $null = Assert-ManifestMode -Target $roundtrip -Mode 'private-episodic'
  Assert-True (Test-Path -LiteralPath (Join-Path $roundtrip '.agent/memory/episodic/EPISODES.md') -PathType Leaf) 'Private episodic seed must be reactivated.'

  $toCurated = Invoke-ApprovedMode -Target $roundtrip -Mode 'curated'
  Assert-Equal 0 $toCurated.apply.exit_code "private-episodic -> curated must succeed for unchanged seed: $($toCurated.apply.output)"
  $null = Assert-ManifestMode -Target $roundtrip -Mode 'curated'
  Assert-False (Test-Path -LiteralPath (Join-Path $roundtrip '.agent/memory/episodic')) 'Curated transition must remove unchanged episodic namespace.'

  $modified = New-InstalledModeTarget -Name 'modified' -Mode 'curated'
  Add-Content -LiteralPath (Join-Path $modified '.agent/memory/personal/PREFERENCES.md') -Value 'local preference'
  $modifiedPreview = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $modified, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', 'off')
  Assert-True ($modifiedPreview.exit_code -ne 0) 'Modified curated content must block transition to off.'
  Assert-True ($modifiedPreview.output -match 'MEMORY_TRANSITION_MODIFIED_CONTENT') "Modified transition must expose stable code: $($modifiedPreview.output)"
  $null = Assert-ManifestMode -Target $modified -Mode 'curated'

  $unknown = New-InstalledModeTarget -Name 'unknown' -Mode 'private-episodic'
  Set-Content -LiteralPath (Join-Path $unknown '.agent/memory/episodic/private-note.md') -Value 'private note'
  $unknownPreview = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $unknown, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', 'off')
  Assert-True ($unknownPreview.exit_code -ne 0) 'Unknown episodic content must block transition to off.'
  Assert-True ($unknownPreview.output -match 'MEMORY_TRANSITION_USER_CONTENT') "Unknown transition must expose stable code: $($unknownPreview.output)"
  $null = Assert-ManifestMode -Target $unknown -Mode 'private-episodic'

  $inserted = New-InstalledModeTarget -Name 'inserted-after-preview' -Mode 'curated'
  $insertedBase = @('-TargetPath', $inserted, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', 'off')
  $insertedApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments $insertedBase
  Set-Content -LiteralPath (Join-Path $inserted '.agent/memory/inserted-after-preview.md') -Value 'late content'
  $insertedApply = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $insertedApproval.arguments
  Assert-True ($insertedApply.exit_code -ne 0) 'Content inserted after preview must invalidate apply.'
  Assert-True ($insertedApply.output -match 'MEMORY_TRANSITION_USER_CONTENT|PLAN_BINDING_PROBE_FAILED') "Late insertion must fail closed: $($insertedApply.output)"
  $null = Assert-ManifestMode -Target $inserted -Mode 'curated'

  $mismatch = New-InstalledModeTarget -Name 'plan-mismatch' -Mode 'curated'
  $offBase = @('-TargetPath', $mismatch, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', 'off')
  $offApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments $offBase
  $mismatchArgs = @('-TargetPath', $mismatch, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', 'private-episodic', '-Apply', '-ApprovedPlanPath', $offApproval.plan_path, '-ApprovedPlanSha256', $offApproval.sha256, '-HumanApproved')
  $mismatchApply = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $mismatchArgs
  Assert-True ($mismatchApply.exit_code -ne 0) 'CLI memory mode differing from approved plan must fail.'
  Assert-True ($mismatchApply.output -match 'PLAN_BINDING_OPTIONS_MISMATCH') "Plan mismatch must expose stable binding code: $($mismatchApply.output)"
  $null = Assert-ManifestMode -Target $mismatch -Mode 'curated'

  $rollback = New-InstalledModeTarget -Name 'rollback' -Mode 'curated'
  $fault = Invoke-ApprovedMode -Target $rollback -Mode 'off' -FailAfterMutation 1
  Assert-True ($fault.apply.exit_code -ne 0) 'Injected transition failure must fail apply.'
  Assert-True ($fault.apply.output -match 'TRANSACTION_FAULT_INJECTED') "Fault injection must expose transaction code: $($fault.apply.output)"
  $null = Assert-ManifestMode -Target $rollback -Mode 'curated'
  Assert-True (Test-Path -LiteralPath (Join-Path $rollback '.agent/memory/personal/PREFERENCES.md') -PathType Leaf) 'Rollback must restore removed memory bytes.'
  $recovery = Invoke-ApprovedMode -Target $rollback -Mode 'off'
  Assert-Equal 0 $recovery.apply.exit_code "Fresh transition after rollback must succeed: $($recovery.apply.output)"

  Write-Host 'PASS tests\adversarial\memory-mode-transitions.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
