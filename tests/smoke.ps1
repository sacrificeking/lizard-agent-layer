param(
  [string]$LayerRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$tmpRoot = Join-Path $LayerRoot ".tmp\smoke-$stamp"
$standardTarget = Join-Path $tmpRoot 'standard-target'
$cursorTarget = Join-Path $tmpRoot 'cursor-target'
$sidecarTarget = Join-Path $tmpRoot 'sidecar-target'
$analysisTarget = Join-Path $tmpRoot 'analysis-target'
$sidecarPlanPath = Join-Path $tmpRoot 'sidecar-install-plan.md'
$mergeSuggestionDir = Join-Path $tmpRoot 'merge-suggestions'

New-Item -ItemType Directory -Path $standardTarget -Force | Out-Null
New-Item -ItemType Directory -Path $cursorTarget -Force | Out-Null
New-Item -ItemType Directory -Path $sidecarTarget -Force | Out-Null
New-Item -ItemType Directory -Path $analysisTarget -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'supabase\functions\demo') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'supabase\migrations') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $analysisTarget 'src\pages\finance\dca') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $standardTarget 'README.md') -Value '# standard smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $cursorTarget 'README.md') -Value '# cursor smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sidecarTarget 'README.md') -Value '# sidecar smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Value '# Existing Project Instructions' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'README.md') -Value '# analysis smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'package.json') -Value '{"dependencies":{"@supabase/supabase-js":"latest","react":"latest"},"devDependencies":{"typescript":"latest","vite":"latest"}}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'vite.config.ts') -Value 'export default {}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'tsconfig.json') -Value '{}' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'DESIGN.md') -Value '# Design' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $analysisTarget 'src\pages\finance\dca\stocks-dca.ts') -Value 'export const marker = true;' -Encoding UTF8

function Run-Step {
  param([string]$Name, [scriptblock]$Block)
  Write-Host "== $Name =="
  & $Block
}

Run-Step 'validate layer' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\validate.ps1')
}

Run-Step 'analyze target recommendation' {
  $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\analyze-target.ps1') -TargetPath $analysisTarget -Json | Out-String
  $analysis = $json | ConvertFrom-Json
  if ($analysis.recommendedProfile -ne 'supabase-react-finance') { throw "Expected supabase-react-finance recommendation, got $($analysis.recommendedProfile)." }
  if (@($analysis.recommendedHarnesses) -notcontains 'codex') { throw 'Expected codex harness recommendation.' }
  if (@($analysis.signals) -notcontains 'finance') { throw 'Expected finance signal.' }
}

Run-Step 'install preview standard multi-harness' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $standardTarget -Profile standard | Out-String | Write-Host
}

Run-Step 'install apply standard multi-harness' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $standardTarget -Profile standard -Apply | Out-String | Write-Host
  foreach ($expected in @('AGENTS.md', 'CLAUDE.md', 'GEMINI.md', '.agents\skills\release\SKILL.md', '.claude\skills\release\SKILL.md', '.gemini\skills\release\SKILL.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $standardTarget $expected))) { throw "Expected missing standard artifact: $expected" }
  }
}

Run-Step 'doctor standard strict' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $standardTarget -Strict | Out-String | Write-Host
}

Run-Step 'install apply standard idempotent' {
  $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $standardTarget -Profile standard -Apply | Out-String
  Write-Host $output
  if ($output -notmatch 'Created:\s+1') {
    throw 'Expected second install to create only refreshed ownership manifest.'
  }
}

Run-Step 'install apply cursor override' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $cursorTarget -Profile minimal -Harnesses cursor -Apply | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath (Join-Path $cursorTarget '.cursor\rules\lizard-agent-layer.mdc'))) { throw 'Expected Cursor rule file.' }
  if (-not (Test-Path -LiteralPath (Join-Path $cursorTarget '.cursor\skills\git-safety\SKILL.md'))) { throw 'Expected Cursor skill mirror.' }
}

Run-Step 'doctor cursor strict' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $cursorTarget -Strict | Out-String | Write-Host
}

Run-Step 'install plan sidecar target' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -WritePlan -PlanPath $sidecarPlanPath | Out-String | Write-Host
  if (-not (Test-Path -LiteralPath $sidecarPlanPath)) { throw 'Expected install plan report.' }
  $plan = Get-Content -LiteralPath $sidecarPlanPath -Raw
  foreach ($expected in @('# lizard-agent-layer install plan', '## Merge suggestions', 'generic-agents-md', 'AGENTS.lizard-agent-layer.md', 'Suggested block')) {
    if ($plan -notmatch [regex]::Escape($expected)) { throw "Expected install plan to contain: $expected" }
  }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget '.agent')) { throw 'Preview plan wrote .agent into target.' }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md')) { throw 'Preview plan wrote sidecar into target.' }
}


Run-Step 'generate merge suggestions sidecar target' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\merge-suggestions.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -OutputDir $mergeSuggestionDir | Out-String | Write-Host
  $report = Join-Path $mergeSuggestionDir 'merge-suggestions.md'
  $json = Join-Path $mergeSuggestionDir 'merge-suggestions.json'
  $patch = Join-Path $mergeSuggestionDir 'generic-agents-md-AGENTS.md.patch'
  $block = Join-Path $mergeSuggestionDir 'generic-agents-md-AGENTS.md.block.md'
  foreach ($expectedPath in @($report, $json, $patch, $block)) {
    if (-not (Test-Path -LiteralPath $expectedPath)) { throw "Expected merge suggestion artifact: $expectedPath" }
  }
  $reportText = Get-Content -LiteralPath $report -Raw
  foreach ($expectedText in @('# lizard-agent-layer merge suggestions', 'merge-needed', 'AGENTS.lizard-agent-layer.md', 'Patch files')) {
    if ($reportText -notmatch [regex]::Escape($expectedText)) { throw "Expected merge report to contain: $expectedText" }
  }
  $patchText = Get-Content -LiteralPath $patch -Raw
  foreach ($expectedText in @('diff --git a/AGENTS.md b/AGENTS.md', '+## lizard-agent-layer', '+Review `AGENTS.lizard-agent-layer.md`')) {
    if ($patchText -notmatch [regex]::Escape($expectedText)) { throw "Expected patch to contain: $expectedText" }
  }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget '.agent')) { throw 'Merge suggestion generator wrote .agent into target.' }
  if (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md')) { throw 'Merge suggestion generator wrote sidecar into target.' }
}
Run-Step 'install apply sidecar target' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -Apply | Out-String | Write-Host
  $agents = Get-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Raw
  if ($agents -match 'lizard-agent-layer') { throw 'Existing AGENTS.md was overwritten or modified.' }
  if (-not (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md'))) { throw 'Expected sidecar AGENTS.lizard-agent-layer.md.' }
  $manifest = Get-Content -LiteralPath (Join-Path $sidecarTarget '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
  if (@($manifest.merge_suggestions).Count -lt 1) { throw 'Expected merge suggestions in install manifest.' }
}

Run-Step 'doctor sidecar non-strict' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $sidecarTarget | Out-String | Write-Host
}

Write-Host "Smoke passed. Scratch output: $tmpRoot"
