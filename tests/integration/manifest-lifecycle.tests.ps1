param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
$fixture = Join-Path $testRoot ("manifest-lifecycle-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$updateScript = Join-Path $LayerRoot 'scripts\update-target.ps1'
$doctorScript = Join-Path $LayerRoot 'scripts\doctor.ps1'
$diffScript = Join-Path $LayerRoot 'scripts\manifest-diff.ps1'
New-Item -ItemType Directory -Path $target -Force | Out-Null

function Read-Manifest {
  Get-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-LizardJson
}

function Find-Artifact {
  param($Manifest, [string]$Path)
  @($Manifest.artifacts | Where-Object { [string]$_.path -eq $Path })
}

function Invoke-PlannedInstall {
  param([string[]]$Arguments)
  $approval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments $Arguments
  $result = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $approval.arguments
  Assert-Equal 0 $result.exit_code "Plan-bound lifecycle install must succeed: $($result.output)"
  return $approval
}

try {
  $frontendPath = '.agent/skills/frontend-engineering/SKILL.md'
  $modifiedPath = '.agent/skills/design-system/SKILL.md'
  $baseArguments = @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'codex')
  $packArguments = @($baseArguments) + @('-Packs', 'frontend-engineering')

  $null = Invoke-PlannedInstall -Arguments $packArguments
  $initial = Read-Manifest
  Assert-Equal 4 ([int]$initial.schema_version) 'Lifecycle manifests must use schema v4.'
  Assert-Equal 'active' ([string](Find-Artifact -Manifest $initial -Path $frontendPath)[0].lifecycle) 'Selected artifacts must be active.'
  $initialFrontend = (Find-Artifact -Manifest $initial -Path $frontendPath)[0]
  $initialInstalledHash = [string]$initialFrontend.installed_hash
  $frontendPhysicalPath = Join-Path $target ($frontendPath.Replace('/', '\'))
  $modifiedPhysicalPath = Join-Path $target ($modifiedPath.Replace('/', '\'))
  Add-Content -LiteralPath $modifiedPhysicalPath -Value 'local-retired-canary' -Encoding UTF8

  $updatePreviewOutput = Join-Path $fixture 'update-contraction-preview'
  $updateApproval = New-TestUpdateApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-OutputDir', $updatePreviewOutput, '-Packs', 'security-hardening')
  $updateMarkdown = Get-Content -LiteralPath (Join-Path $updatePreviewOutput 'update-plan.md') -Raw
  Assert-True ($updateMarkdown -match [regex]::Escape("retired-present:$frontendPath")) 'Update Markdown plans must expose exact retired paths.'
  Assert-True (Test-Path -LiteralPath $updateApproval.plan_path -PathType Leaf) 'Update contraction preview must emit a canonical outer plan.'

  $contractionApproval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments $baseArguments
  $contractionPlan = Get-Content -LiteralPath $contractionApproval.plan_path -Raw | ConvertFrom-LizardJson
  $retiredOptionEntries = @($contractionPlan.intent.options.retired_artifacts | Where-Object { [string]$_.path -eq $frontendPath })
  Assert-Equal 1 $retiredOptionEntries.Count 'Canonical install options must expose each retired path exactly once.'
  Assert-Equal 'retired-present' ([string]$retiredOptionEntries[0].lifecycle) 'Canonical install options must bind retired lifecycle.'
  $retiredPlanEntries = @($contractionPlan.intent.target_entries | Where-Object { [string]$_.path -eq $frontendPath })
  Assert-Equal 1 $retiredPlanEntries.Count 'Canonical contraction plans must expose each retired path exactly once.'
  Assert-Equal 'preserve' ([string]$retiredPlanEntries[0].action) 'Contract reduction must preserve retired content.'
  $contraction = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $contractionApproval.arguments
  Assert-Equal 0 $contraction.exit_code "Plan-bound contraction must succeed: $($contraction.output)"

  $retired = Read-Manifest
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/install-manifest.schema.json' -InstancePath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Message 'Lifecycle manifest must satisfy schema v4.'
  $retiredFrontend = @(Find-Artifact -Manifest $retired -Path $frontendPath)
  Assert-Equal 1 $retiredFrontend.Count 'Contract reduction must retain one ownership record.'
  Assert-Equal 'retired-present' ([string]$retiredFrontend[0].lifecycle) 'Physically present deselected artifacts must become retired-present.'
  Assert-Equal 'layer-owned' ([string]$retiredFrontend[0].ownership) 'Retirement must preserve ownership.'
  Assert-Equal $initialInstalledHash ([string]$retiredFrontend[0].installed_hash) 'Retirement must preserve installed identity.'
  Assert-True (Test-Path -LiteralPath $frontendPhysicalPath -PathType Leaf) 'Contract reduction must not delete retired content.'
  $retiredModified = (Find-Artifact -Manifest $retired -Path $modifiedPath)[0]
  Assert-Equal 'retired-present' ([string]$retiredModified.lifecycle) 'Modified deselected content must remain retired-present.'
  Assert-Equal 'locally-modified' ([string]$retiredModified.state) 'Modified retired content must retain its integrity classification.'
  $retiredDiff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', (Join-Path $fixture 'retired-diff'), '-Strict')
  Assert-Equal 0 $retiredDiff.exit_code "Manifest diff must accept internally consistent retired-present records: $($retiredDiff.output)"
  $retiredDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
  Assert-Equal 0 $retiredDoctor.exit_code "Doctor must accept internally consistent retired-present records: $($retiredDoctor.output)"

  $missingLifecycle = Read-Manifest
  (Find-Artifact -Manifest $missingLifecycle -Path $frontendPath)[0].PSObject.Properties.Remove('lifecycle')
  $missingLifecycle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8
  $missingLifecycleDiff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', (Join-Path $fixture 'missing-lifecycle-diff'), '-Strict')
  Assert-False ($missingLifecycleDiff.exit_code -eq 0) 'Manifest diff must reject schema-v4 records without lifecycle.'
  $missingLifecycleDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
  Assert-False ($missingLifecycleDoctor.exit_code -eq 0) 'Doctor must reject schema-v4 records without lifecycle.'
  $retired | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8

  $wrongKindLifecycle = Read-Manifest
  $wrongKindRecord = (Find-Artifact -Manifest $wrongKindLifecycle -Path $frontendPath)[0]
  $wrongKindRecord.lifecycle = 'retired-missing'
  $wrongKindRecord.kind = 'directory'
  $wrongKindLifecycle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8
  $wrongKindDiff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', (Join-Path $fixture 'wrong-kind-lifecycle-diff'), '-Strict')
  Assert-False ($wrongKindDiff.exit_code -eq 0) 'Manifest diff must reject an allegedly absent lifecycle path occupied by another object kind.'
  $wrongKindDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
  Assert-False ($wrongKindDoctor.exit_code -eq 0) 'Doctor must reject an allegedly absent lifecycle path occupied by another object kind.'
  $wrongKindPreview = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($baseArguments) + @('-CanonicalPlanPath', (Join-Path $fixture 'wrong-kind-plan.json')))
  Assert-False ($wrongKindPreview.exit_code -eq 0) 'Install preview must fail closed when a retired artifact path has the wrong object kind.'
  Assert-True ($wrongKindPreview.output -match 'MANIFEST_ARTIFACT_KIND_MISMATCH') 'Wrong-kind preview failure must expose a stable classification.'
  $retired | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8

  $invalidLifecycle = Read-Manifest
  (Find-Artifact -Manifest $invalidLifecycle -Path $frontendPath)[0].lifecycle = 'removed'
  $invalidLifecycle | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8
  $invalidDiffDir = Join-Path $fixture 'invalid-lifecycle-diff'
  $invalidDiff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', $invalidDiffDir, '-Strict')
  Assert-False ($invalidDiff.exit_code -eq 0) 'Manifest diff must reject a removed record whose path reappeared.'
  $invalidDiffReport = Get-Content -LiteralPath (Join-Path $invalidDiffDir 'manifest-diff.json') -Raw | ConvertFrom-LizardJson
  Assert-True (@($invalidDiffReport.differences | Where-Object { [string]$_.kind -eq 'artifact-lifecycle-mismatch' -and [string]$_.value -eq $frontendPath }).Count -eq 1) 'Manifest diff must identify the exact lifecycle mismatch.'
  $invalidDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
  Assert-False ($invalidDoctor.exit_code -eq 0) 'Doctor must reject a removed record whose path reappeared.'
  $retired | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8

  $null = Invoke-PlannedInstall -Arguments $baseArguments
  $repeated = Read-Manifest
  $repeatedFrontend = @(Find-Artifact -Manifest $repeated -Path $frontendPath)
  Assert-Equal 1 $repeatedFrontend.Count 'Repeated contraction must not duplicate retired records.'
  Assert-Equal 'retired-present' ([string](Find-Artifact -Manifest $repeated -Path $frontendPath)[0].lifecycle) 'Repeated contraction must be lifecycle-idempotent.'

  Remove-Item -LiteralPath $frontendPhysicalPath -Force
  $null = Invoke-PlannedInstall -Arguments $baseArguments
  $missing = Read-Manifest
  $missingFrontend = (Find-Artifact -Manifest $missing -Path $frontendPath)[0]
  Assert-Equal 'retired-missing' ([string]$missingFrontend.lifecycle) 'Missing deselected artifacts must remain as retired-missing evidence.'
  Assert-Equal 'missing' ([string]$missingFrontend.state) 'Retired-missing artifacts must expose missing physical state.'
  Assert-Equal $initialInstalledHash ([string]$missingFrontend.installed_hash) 'Retired-missing evidence must retain the last installed identity.'
  $missingDiff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $target, '-LayerRoot', $LayerRoot, '-OutputDir', (Join-Path $fixture 'missing-diff'), '-Strict')
  Assert-Equal 0 $missingDiff.exit_code "Manifest diff must accept internally consistent retired-missing records: $($missingDiff.output)"
  $missingDoctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
  Assert-Equal 0 $missingDoctor.exit_code "Doctor must accept internally consistent retired-missing records: $($missingDoctor.output)"

  $null = Invoke-PlannedInstall -Arguments $packArguments
  $reactivated = Read-Manifest
  Assert-Equal 'active' ([string](Find-Artifact -Manifest $reactivated -Path $frontendPath)[0].lifecycle) 'Reselected missing artifacts must reactivate.'
  Assert-True (Test-Path -LiteralPath $frontendPhysicalPath -PathType Leaf) 'Reselected missing layer artifacts must be restored.'
  Assert-Equal 'active' ([string](Find-Artifact -Manifest $reactivated -Path $modifiedPath)[0].lifecycle) 'Reselected modified artifacts must reactivate without replacement.'
  Assert-True ((Get-Content -LiteralPath $modifiedPhysicalPath -Raw) -match 'local-retired-canary') 'Reactivation must preserve local modifications.'

  Write-Host 'PASS tests\integration\manifest-lifecycle.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
