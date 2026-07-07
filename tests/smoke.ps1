param(
  [string]$LayerRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$tmpRoot = Join-Path $LayerRoot ".tmp\smoke-$stamp"
$standardTarget = Join-Path $tmpRoot 'standard-target'
$cursorTarget = Join-Path $tmpRoot 'cursor-target'
$sidecarTarget = Join-Path $tmpRoot 'sidecar-target'

New-Item -ItemType Directory -Path $standardTarget -Force | Out-Null
New-Item -ItemType Directory -Path $cursorTarget -Force | Out-Null
New-Item -ItemType Directory -Path $sidecarTarget -Force | Out-Null
Set-Content -LiteralPath (Join-Path $standardTarget 'README.md') -Value '# standard smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $cursorTarget 'README.md') -Value '# cursor smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sidecarTarget 'README.md') -Value '# sidecar smoke target' -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Value '# Existing Project Instructions' -Encoding UTF8

function Run-Step {
  param([string]$Name, [scriptblock]$Block)
  Write-Host "== $Name =="
  & $Block
}

Run-Step 'validate layer' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\validate.ps1')
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

Run-Step 'install apply sidecar target' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\install.ps1') -TargetPath $sidecarTarget -Profile minimal -Harnesses generic-agents-md -Apply | Out-String | Write-Host
  $agents = Get-Content -LiteralPath (Join-Path $sidecarTarget 'AGENTS.md') -Raw
  if ($agents -match 'lizard-agent-layer') { throw 'Existing AGENTS.md was overwritten or modified.' }
  if (-not (Test-Path -LiteralPath (Join-Path $sidecarTarget 'AGENTS.lizard-agent-layer.md'))) { throw 'Expected sidecar AGENTS.lizard-agent-layer.md.' }
}

Run-Step 'doctor sidecar non-strict' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\doctor.ps1') -TargetPath $sidecarTarget | Out-String | Write-Host
}

Write-Host "Smoke passed. Scratch output: $tmpRoot"
