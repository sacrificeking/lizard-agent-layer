param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
if (-not $LayerRoot) { $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
if (-not $LayerRoot) { $LayerRoot = (Get-Location).Path }
$LayerRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
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

# 5. Standard & Enterprise profile skill list verification (4-skill diet with composite implementation)
$standardProfile = Get-Content -LiteralPath (Join-Path $LayerRoot 'profiles/standard.json') -Raw | ConvertFrom-LizardJson
$skills = @($standardProfile.skills)
Assert-Equal 4 $skills.Count "Standard profile must default to the 4 core matching skills (diet)."
Assert-True ($skills -contains 'git-safety') "Standard profile must include git-safety."
Assert-True ($skills -contains 'implementation') "Standard profile must include composite implementation."
Assert-True ($skills -contains 'research-audit') "Standard profile must include research-audit."
Assert-True ($skills -contains 'project-decision-harvest') "Standard profile must include project-decision-harvest."

$enterpriseProfile = Get-Content -LiteralPath (Join-Path $LayerRoot 'profiles/enterprise-fullstack.json') -Raw | ConvertFrom-LizardJson
$enterpriseSkills = @($enterpriseProfile.skills)
Assert-Equal 4 $enterpriseSkills.Count "Enterprise profile must default to the 4 core matching skills (diet)."
Assert-True ($enterpriseSkills -contains 'implementation') "Enterprise profile must include composite implementation."

# 5b. Verify skills/implementation/SKILL.md line count budget <= 80 lines
$implSkillPath = Join-Path $LayerRoot 'skills/implementation/SKILL.md'
Assert-True (Test-Path -LiteralPath $implSkillPath -PathType Leaf) "skills/implementation/SKILL.md must exist."
$implSkillLines = (Get-Content -LiteralPath $implSkillPath).Count
Assert-True ($implSkillLines -le 80) "Composite implementation SKILL.md budget exceeded: $implSkillLines lines (max 80 lines)."

# 6. Single-harness install snippets and front-door contract in public docs (allowlist loop)
$publicDocsAllowlist = @(
  'README.md',
  'QUICKSTART.md',
  'INSTALL.md',
  'docs\getting-started.md',
  'docs\profiles.md',
  'docs\update-target.md',
  'docs\merge-suggestions.md',
  'docs\install-plans.md',
  'docs\packs.md',
  'docs\loop-engineering.md',
  'UNINSTALL.md'
)

$multiHarnessPattern = '-Harnesses\s+(codex|claude-code|gemini|github-copilot|cursor|generic-agents-md)\s*,'
foreach ($relDoc in $publicDocsAllowlist) {
  $docPath = Join-Path $LayerRoot $relDoc
  Assert-True (Test-Path -LiteralPath $docPath -PathType Leaf) "Public doc $relDoc must exist."
  $docContent = Get-Content -LiteralPath $docPath -Raw
  Assert-False ($docContent -match $multiHarnessPattern) "$relDoc must use single-harness snippets and not concrete multi-harness lists."

  $codeBlocks = [regex]::Matches($docContent, '```(?:powershell|bash|sh|text)?\r?\n(.*?)\r?\n```', [System.Text.RegularExpressions.RegexOptions]::Singleline)
  foreach ($block in $codeBlocks) {
    $lines = $block.Groups[1].Value -split '\r?\n'
    foreach ($line in $lines) {
      if ($line -match 'install\.ps1\b' -and ($line -match '-Profile\s+standard\b' -or $line -match '-Profile\s+enterprise-fullstack\b')) {
        Assert-True ($line -match '-Harnesses\b') "Snippet in $relDoc with standard/enterprise-fullstack profile must specify -Harnesses: $line"
      }
      if ($line -match '(install|update-target|uninstall)\.ps1\b' -and $line -match '-TargetPath\s+["'']?\.') {
        Assert-False ($line -match '-(PlanPath|CanonicalPlanPath|ApprovedPlanPath|OutputDir)\s+["'']?(\.\\|\./)?\.tmp[\\/]') "Snippet in $relDoc with -TargetPath '.' must not use relative .tmp for plan/output path: $line"
      }
    }
  }
}

Write-Host "PASS overlay calorie budget tests: all adapters <= 80 always-on lines, ask-only USING.md, enterprise diet verified, front-door contract verified."
