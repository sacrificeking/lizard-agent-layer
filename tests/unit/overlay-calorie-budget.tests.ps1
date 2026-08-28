param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
if (-not $LayerRoot) { $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not $LayerRoot) { $LayerRoot = (Get-Location).Path }
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force

$promptTrustPath = Join-Path $LayerRoot 'protocols/prompt-trust.md'
$permissionsPath = Join-Path $LayerRoot 'protocols/permissions.md'
$promptTrustLines = (Get-Content -LiteralPath $promptTrustPath).Count
$permissionsLines = (Get-Content -LiteralPath $permissionsPath).Count

$adapters = @(
  @{ name = 'codex'; file = 'adapters\codex\AGENTS.lizard.md' },
  @{ name = 'claude-code'; file = 'adapters\claude-code\CLAUDE.lizard.md' },
  @{ name = 'cursor'; file = 'adapters\cursor\lizard-agent-layer.mdc' },
  @{ name = 'github-copilot'; file = 'adapters\github-copilot\copilot-instructions.lizard.md' },
  @{ name = 'gemini'; file = 'adapters\gemini\GEMINI.lizard.md' },
  @{ name = 'generic-agents-md'; file = 'adapters\generic-agents-md\AGENTS.generic.lizard.md' }
)

foreach ($adapter in $adapters) {
  $adapterPath = Join-Path $LayerRoot $adapter.file
  Assert-True (Test-Path -LiteralPath $adapterPath -PathType Leaf) "Adapter file $($adapter.file) must exist."
  $adapterContent = Get-Content -LiteralPath $adapterPath -Raw
  $adapterLines = (Get-Content -LiteralPath $adapterPath).Count

  # 1. Total always-on prompt lines budget: Adapter + prompt-trust + permissions <= 80 lines
  $totalLines = $adapterLines + $promptTrustLines + $permissionsLines
  Assert-True ($totalLines -le 80) "Always-on prompt budget exceeded for $($adapter.name): $totalLines lines (max 80 lines)."

  # 2. No routing policy JSON dump in daily startup instructions
  Assert-False ($adapterContent -match 'policy\.json') "Adapter $($adapter.name) must not instruct models to read routing/policy.json on daily tasks."

  # 3. Ask-only pointer for USING.md (no boilerplate output line)
  Assert-False ($adapterContent -match 'Refer to \.agent/USING\.md') "Adapter $($adapter.name) must not instruct model to refer to USING.md on every output."
  Assert-True ($adapterContent -match 'If the user asks') "Adapter $($adapter.name) must use ask-only pointer for USING.md."
}

# 4. Cursor MDC verification: alwaysApply must be false, no global catch-all glob
$cursorMdc = Get-Content -LiteralPath (Join-Path $LayerRoot 'adapters/cursor/lizard-agent-layer.mdc') -Raw
Assert-True ($cursorMdc -match 'alwaysApply:\s*false') "Cursor MDC must set alwaysApply: false."
Assert-False ($cursorMdc -match 'globs:\s*\["\*\*/\*"\]') "Cursor MDC must not use global catch-all globs."

# 5. Standard & Enterprise profile skill list verification
$standardProfile = Get-Content -LiteralPath (Join-Path $LayerRoot 'profiles/standard.json') -Raw | ConvertFrom-LizardJson
$skills = @($standardProfile.skills)
Assert-Equal 6 $skills.Count "Standard profile must default to the 6 core matching skills."
Assert-True ($skills -contains 'git-safety') "Standard profile must include git-safety."
Assert-True ($skills -contains 'staged-execution') "Standard profile must include staged-execution."
Assert-True ($skills -contains 'research-audit') "Standard profile must include research-audit."
Assert-True ($skills -contains 'project-decision-harvest') "Standard profile must include project-decision-harvest."
Assert-True ($skills -contains 'repo-grounded-change') "Standard profile must include repo-grounded-change."
Assert-True ($skills -contains 'premortem') "Standard profile must include premortem."

$enterpriseProfile = Get-Content -LiteralPath (Join-Path $LayerRoot 'profiles/enterprise-fullstack.json') -Raw | ConvertFrom-LizardJson
$enterpriseSkills = @($enterpriseProfile.skills)
Assert-Equal 6 $enterpriseSkills.Count "Enterprise profile must default to the 6 core matching skills (diet)."

# 6. Single-harness install snippets in public docs (allowlist loop)
$publicDocsAllowlist = @(
  'README.md',
  'QUICKSTART.md',
  'INSTALL.md',
  'docs\getting-started.md',
  'docs\profiles.md',
  'docs\update-target.md',
  'docs\merge-suggestions.md'
)

$multiHarnessPattern = '-Harnesses\s+(codex|claude-code|gemini|github-copilot|cursor|generic-agents-md)\s*,'
foreach ($relDoc in $publicDocsAllowlist) {
  $docPath = Join-Path $LayerRoot $relDoc
  Assert-True (Test-Path -LiteralPath $docPath -PathType Leaf) "Public doc $relDoc must exist."
  $docContent = Get-Content -LiteralPath $docPath -Raw
  Assert-False ($docContent -match $multiHarnessPattern) "$relDoc must use single-harness snippets and not concrete multi-harness lists."
}

Write-Host "PASS overlay calorie budget tests: all adapters <= 80 always-on lines, ask-only USING.md, enterprise diet verified, single-harness examples."
