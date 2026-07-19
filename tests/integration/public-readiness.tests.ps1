param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("public-readiness-{0}" -f ([Guid]::NewGuid().ToString('N')))
$freshTarget = Join-Path $fixture 'fresh-target'
$existingTarget = Join-Path $fixture 'existing-target'
New-Item -ItemType Directory -Path $freshTarget -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $existingTarget '.github') -Force | Out-Null
$existingInstruction = '# Organization-owned Copilot instructions'
Set-Content -LiteralPath (Join-Path $existingTarget '.github\copilot-instructions.md') -Value $existingInstruction -Encoding UTF8

try {
  foreach ($document in @('README.md', 'INSTALL.md', 'UNINSTALL.md', 'SECURITY.md', 'docs/getting-started.md', 'docs/enterprise-usage.md', 'docs/dependencies.md')) {
    Assert-True (Test-Path -LiteralPath (Join-Path $LayerRoot $document) -PathType Leaf) "Missing public document $document."
  }

  $installGuide = Get-Content -LiteralPath (Join-Path $LayerRoot 'INSTALL.md') -Raw
  foreach ($required in @('Suggested user prompt', 'analyze-target.ps1', 'Decision Record', '-WritePlan', 'Step 6: Approval Gate', 'doctor.ps1', 'manifest-diff.ps1')) {
    Assert-True ($installGuide -match [regex]::Escape($required)) "INSTALL.md is missing '$required'."
  }

  $uninstallGuide = Get-Content -LiteralPath (Join-Path $LayerRoot 'UNINSTALL.md') -Raw
  foreach ($required in @('Suggested user prompt', 'managed-only', 'complete', 'unchanged layer-owned', 'Exact Removal Plan', 'Step 7: Approval Gate', 'Verify Complete Removal', 'Recovery')) {
    Assert-True ($uninstallGuide -match [regex]::Escape($required)) "UNINSTALL.md is missing '$required'."
  }
  Assert-False ($uninstallGuide -match 'Remove-Item\s+[^\r\n]*-Recurse') 'UNINSTALL.md must not prescribe a generic recursive deletion command.'

  $dependencies = Get-Content -LiteralPath (Join-Path $LayerRoot 'docs\dependencies.md') -Raw
  Assert-True ($dependencies -match 'zero known vulnerabilities') 'Dependency snapshot must record the completed live audit.'
  Assert-True ($dependencies -match 'no outdated packages') 'Dependency snapshot must record the completed outdated check.'
  Assert-False ($dependencies -match 'blocked the final live') 'Dependency snapshot must not retain a resolved release blocker.'

  $version = (Get-Content -LiteralPath (Join-Path $LayerRoot 'VERSION') -Raw).Trim()
  $package = Get-Content -LiteralPath (Join-Path $LayerRoot 'package.json') -Raw | ConvertFrom-Json
  $lockText = Get-Content -LiteralPath (Join-Path $LayerRoot 'package-lock.json') -Raw
  $changelog = Get-Content -LiteralPath (Join-Path $LayerRoot 'CHANGELOG.md') -Raw
  $escapedVersion = [regex]::Escape($version)
  Assert-True ($version -match '^[0-9]+\.[0-9]+\.[0-9]+$') 'Public release version must use semantic version format.'
  Assert-Equal $version ([string]$package.version) 'package.json version must match VERSION.'
  Assert-True ($lockText -match ('(?s)^\s*\{\s*"name"\s*:\s*"lizard-agent-layer-tooling"\s*,\s*"version"\s*:\s*"' + $escapedVersion + '"')) 'package-lock.json version must match VERSION.'
  Assert-True ($lockText -match ('(?s)"packages"\s*:\s*\{\s*""\s*:\s*\{\s*"name"\s*:\s*"lizard-agent-layer-tooling"\s*,\s*"version"\s*:\s*"' + $escapedVersion + '"')) 'Root lock package version must match VERSION.'
  Assert-True ($changelog -match ('(?m)^## ' + $escapedVersion + ' - [0-9]{4}-[0-9]{2}-[0-9]{2}\r?$')) 'Public changelog must contain a dated entry for VERSION.'

  foreach ($removed in @(
    'AUDIT_FINDINGS_AND_IMPLEMENTATION_PLAN.md', 'docs/roadmap.md',
    'schemas/loop-budget.schema.json', 'schemas/loop-constraints.schema.json', 'schemas/loop-state.schema.json'
  )) {
    Assert-False (Test-Path -LiteralPath (Join-Path $LayerRoot $removed)) "Internal or superseded artifact remains: $removed."
  }

  $workflow = Get-Content -LiteralPath (Join-Path $LayerRoot '.github\workflows\lizard-agent-layer-ci.yml') -Raw
  Assert-Equal 2 ([regex]::Matches($workflow, 'actions/checkout@[a-f0-9]{40}')).Count 'Every checkout use must be pinned to a full commit SHA.'
  Assert-Equal 2 ([regex]::Matches($workflow, 'actions/setup-node@[a-f0-9]{40}')).Count 'Every setup-node use must be pinned to a full commit SHA.'
  Assert-Equal 2 ([regex]::Matches($workflow, 'persist-credentials:\s*false')).Count 'Every checkout must disable persisted credentials.'
  Assert-Equal 2 ([regex]::Matches($workflow, 'package-manager-cache:\s*false')).Count 'Every setup-node use must disable package-manager caching.'
  Assert-False ($workflow -match 'uses:\s*[^\r\n]+@v[0-9]') 'Workflow actions must not use mutable major tags.'

  $networkPatterns = 'Invoke-WebRequest|Invoke-RestMethod|System\.Net\.Http\.HttpClient|System\.Net\.WebClient|Start-BitsTransfer|\bcurl(?:\.exe)?\b|\bwget(?:\.exe)?\b'
  $networkHits = @(Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'scripts') -File -Recurse | Select-String -Pattern $networkPatterns)
  Assert-Equal 0 $networkHits.Count 'Repository scripts must not contain undeclared HTTP clients or transfer commands.'

  $installPath = Join-Path $LayerRoot 'scripts\install.ps1'
  $freshInstall = Invoke-TestPowerShell -ScriptPath $installPath -Arguments @('-TargetPath', $freshTarget, '-Profile', 'minimal', '-Harnesses', 'github-copilot', '-Apply')
  Assert-Equal 0 $freshInstall.exit_code "Fresh GitHub Copilot installation failed: $($freshInstall.output)"
  $freshInstruction = Join-Path $freshTarget '.github\copilot-instructions.md'
  Assert-True (Test-Path -LiteralPath $freshInstruction -PathType Leaf) 'Fresh target must receive Copilot repository instructions.'
  Assert-True ((Get-Content -LiteralPath $freshInstruction -Raw) -match 'lizard-agent-layer') 'Fresh Copilot instructions must identify the layer.'

  $existingInstall = Invoke-TestPowerShell -ScriptPath $installPath -Arguments @('-TargetPath', $existingTarget, '-Profile', 'minimal', '-Harnesses', 'github-copilot', '-Apply')
  Assert-Equal 0 $existingInstall.exit_code "Existing GitHub Copilot installation failed: $($existingInstall.output)"
  Assert-Equal $existingInstruction ((Get-Content -LiteralPath (Join-Path $existingTarget '.github\copilot-instructions.md') -Raw).Trim()) 'Existing organization-owned Copilot instructions must remain unchanged.'
  Assert-True (Test-Path -LiteralPath (Join-Path $existingTarget '.github\copilot-instructions.lizard-agent-layer.md') -PathType Leaf) 'Existing target must receive a reviewable Copilot sidecar.'

  $manifestPath = Join-Path $existingTarget '.agent\lizard-agent-layer.install.json'
  $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
  Assert-Equal $version ([string]$manifest.layer_version) 'Installed manifest must record the current public version.'
  Assert-True (@($manifest.harnesses) -contains 'github-copilot') 'Installed manifest must record the Copilot harness.'

  $doctor = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts\doctor.ps1') -Arguments @('-TargetPath', $existingTarget, '-Strict')
  Assert-Equal 0 $doctor.exit_code "Doctor must accept the sidecar installation: $($doctor.output)"

  Write-Host 'PASS tests\integration\public-readiness.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
