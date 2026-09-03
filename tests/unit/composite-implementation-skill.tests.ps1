param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Json.psm1') -Force

# 1. Verify composite implementation skill exists and is <= 80 lines
$implSkillPath = Join-Path $LayerRoot 'skills/implementation/SKILL.md'
Assert-True (Test-Path -LiteralPath $implSkillPath -PathType Leaf) 'skills/implementation/SKILL.md must exist.'
$implLines = (Get-Content -LiteralPath $implSkillPath).Count
Assert-True ($implLines -le 80) "Composite implementation SKILL.md budget exceeded: $implLines lines (max 80 lines)."

# 2. Verify implementation skill metadata exists
$implJsonPath = Join-Path $LayerRoot 'skills/implementation/skill.json'
Assert-True (Test-Path -LiteralPath $implJsonPath -PathType Leaf) 'skills/implementation/skill.json must exist.'
$implMeta = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $implJsonPath -Raw)
Assert-Equal 'implementation' ([string]$implMeta.name) 'Skill name must be implementation.'
Assert-Equal 'active' ([string]$implMeta.lifecycle_state) 'Skill lifecycle state must be active.'

# 3. Verify premortem L/M/H labels and bumped version
$premortemPath = Join-Path $LayerRoot 'skills/premortem/SKILL.md'
$premortemContent = Get-Content -LiteralPath $premortemPath -Raw
Assert-True ($premortemContent -match 'likelihood:\s*L\|M\|H') 'premortem/SKILL.md must require likelihood: L|M|H.'
Assert-True ($premortemContent -match 'impact:\s*L\|M\|H') 'premortem/SKILL.md must require impact: L|M|H.'
Assert-True ($premortemContent -match 'highest likelihood\s+`?H`?') 'premortem/SKILL.md must map Most Likely to highest likelihood H.'
Assert-True ($premortemContent -match 'highest impact\s+`?H`?') 'premortem/SKILL.md must map Most Dangerous to highest impact H.'

$premortemJsonPath = Join-Path $LayerRoot 'skills/premortem/skill.json'
$premortemMeta = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $premortemJsonPath -Raw)
Assert-Equal '1.0.1' ([string]$premortemMeta.version) 'premortem skill version must be bumped to 1.0.1.'

# 4. Verify templates/operator-card.md contains premortem guidance
$operatorCardPath = Join-Path $LayerRoot 'templates/operator-card.md'
$operatorCardContent = Get-Content -LiteralPath $operatorCardPath -Raw
Assert-True ($operatorCardContent -match 'premortem') 'templates/operator-card.md must mention premortem in daily prompts.'

# 5. Verify staged-execution references implementation skill and matching budget
$stagedPath = Join-Path $LayerRoot 'skills/staged-execution/SKILL.md'
$stagedContent = Get-Content -LiteralPath $stagedPath -Raw
Assert-True ($stagedContent -match 'implementation') 'staged-execution/SKILL.md must reference implementation skill.'
Assert-True ($stagedContent -match 'do not expect a third matching skill') 'staged-execution/SKILL.md must clarify matching budget limit.'

# 6. Verify 4-skill diet in standard and enterprise profiles
$stdProfile = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath (Join-Path $LayerRoot 'profiles/standard.json') -Raw)
$stdSkills = @($stdProfile.skills)
Assert-Equal 4 $stdSkills.Count 'Standard profile must have exactly 4 skills.'
Assert-True ($stdSkills -contains 'implementation') 'Standard profile must include implementation.'
Assert-False ($stdSkills -contains 'staged-execution') 'Standard profile must not duplicate staged-execution.'
Assert-False ($stdSkills -contains 'repo-grounded-change') 'Standard profile must not duplicate repo-grounded-change.'
Assert-False ($stdSkills -contains 'premortem') 'Standard profile must not duplicate premortem.'

$entProfile = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath (Join-Path $LayerRoot 'profiles/enterprise-fullstack.json') -Raw)
$entSkills = @($entProfile.skills)
Assert-Equal 4 $entSkills.Count 'Enterprise profile must have exactly 4 skills.'
Assert-True ($entSkills -contains 'implementation') 'Enterprise profile must include implementation.'

# 7. Verify all adapters contain matching-skill budget and doctor trust phrasing
$adapters = @(
  'adapters/codex/AGENTS.lizard.md',
  'adapters/claude-code/CLAUDE.lizard.md',
  'adapters/cursor/lizard-agent-layer.mdc',
  'adapters/github-copilot/copilot-instructions.lizard.md',
  'adapters/gemini/GEMINI.lizard.md',
  'adapters/generic-agents-md/AGENTS.generic.lizard.md'
)

foreach ($relPath in $adapters) {
  $adapterPath = Join-Path $LayerRoot $relPath
  $content = Get-Content -LiteralPath $adapterPath -Raw
  Assert-True ($content -match 'Load the one best matching skill') "Adapter $relPath must instruct loading one best matching skill."
  Assert-True ($content -match 'implementation') "Adapter $relPath must cite implementation as default."
  Assert-True ($content -match 'unknown repo trust or health triage') "Adapter $relPath must scope doctor to unknown trust."
}

Write-Host "PASS tests\unit\composite-implementation-skill.tests.ps1"
