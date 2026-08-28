param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
$fixture = Join-Path $testRoot ("memory-mode-update-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$updateScript = Join-Path $LayerRoot 'scripts\update-target.ps1'
New-Item -ItemType Directory -Path $target -Force | Out-Null

try {
  $installApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', 'off')
  $install = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $installApproval.arguments
  Assert-Equal 0 $install.exit_code "Off prerequisite install must succeed: $($install.output)"

  $preserveOutput = Join-Path $fixture 'preserve-output'
  $preserveApproval = New-TestUpdateApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', $preserveOutput)
  $preservePlan = Get-Content -LiteralPath $preserveApproval.plan_path -Raw | ConvertFrom-LizardJson
  Assert-Equal 'off' ([string]$preservePlan.intent.options.previous_memory_mode) 'Outer update plan must bind installed memory mode.'
  Assert-Equal 'off' ([string]$preservePlan.intent.options.memory_mode) 'Update without override must preserve installed off mode.'
  Assert-Equal 'none' ([string]$preservePlan.intent.options.memory_transition) 'Preserving mode must bind a no-op transition.'
  $preserveChildPath = [string]$preservePlan.intent.options.install_canonical_plan_path
  $preserveChild = Get-Content -LiteralPath $preserveChildPath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'off' ([string]$preserveChild.intent.options.memory_mode) 'Nested install plan must bind preserved off mode.'
  $preserveApply = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments $preserveApproval.arguments
  Assert-Equal 0 $preserveApply.exit_code "Mode-preserving update must succeed: $($preserveApply.output)"
  $manifest = Get-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal 'off' ([string]$manifest.memory_mode) 'Mode-preserving update must leave manifest off.'

  $transitionOutput = Join-Path $fixture 'transition-output'
  $transitionApproval = New-TestUpdateApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', $transitionOutput, '-MemoryMode', 'private-episodic')
  $transitionPlan = Get-Content -LiteralPath $transitionApproval.plan_path -Raw | ConvertFrom-LizardJson
  Assert-Equal 'off' ([string]$transitionPlan.intent.options.previous_memory_mode) 'Transition update must bind its source mode.'
  Assert-Equal 'private-episodic' ([string]$transitionPlan.intent.options.memory_mode) 'Transition update must bind its destination mode.'
  Assert-Equal 'off->private-episodic' ([string]$transitionPlan.intent.options.memory_transition) 'Outer update plan must bind transition direction.'
  $transitionChildPath = [string]$transitionPlan.intent.options.install_canonical_plan_path
  $transitionChild = Get-Content -LiteralPath $transitionChildPath -Raw | ConvertFrom-LizardJson
  Assert-Equal 'private-episodic' ([string]$transitionChild.intent.options.memory_mode) 'Nested plan must bind transition destination.'
  Assert-Equal 'off->private-episodic' ([string]$transitionChild.intent.options.memory_transition) 'Nested plan must bind transition direction.'
  $transitionApply = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments $transitionApproval.arguments
  Assert-Equal 0 $transitionApply.exit_code "Update memory transition must succeed: $($transitionApply.output)"
  $manifest = Get-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-LizardJson
  Assert-Equal 'private-episodic' ([string]$manifest.memory_mode) 'Transition update must persist destination mode.'
  Assert-True (Test-Path -LiteralPath (Join-Path $target '.agent\memory\episodic\EPISODES.md') -PathType Leaf) 'Transition update must install private episodic seed.'
  $history = @(Get-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.update-history.jsonl') | ForEach-Object { $_ | ConvertFrom-LizardJson })
  $last = $history[-1]
  Assert-Equal 'off' ([string]$last.previous_memory_mode) 'Update history must record source mode.'
  Assert-Equal 'private-episodic' ([string]$last.memory_mode) 'Update history must record destination mode.'
  Assert-Equal 'off->private-episodic' ([string]$last.memory_transition) 'Update history must record transition direction.'

  Write-Host 'PASS tests\integration\memory-mode-update.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
