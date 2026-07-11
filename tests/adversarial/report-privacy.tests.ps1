param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("report-privacy-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$defaultOutput = Join-Path $fixture 'default-output'
$contextOutput = Join-Path $fixture 'context-output'
$scriptPath = Join-Path $LayerRoot 'scripts\merge-suggestions.ps1'
$canary = 'PRIVATE-INSTRUCTION-CANARY-7f31d42a'
New-Item -ItemType Directory -Path $target -Force | Out-Null

function Assert-GitSuccess {
  param([string[]]$Arguments, [string]$Message)
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & git @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  if ($exitCode -ne 0) { throw "${Message}: $output" }
}

function Assert-CanaryAbsent {
  param([string]$Path, [string]$Label)
  foreach ($file in @(Get-ChildItem -LiteralPath $Path -Recurse -File)) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    Assert-False ($content -match [regex]::Escape($canary)) "$Label leaked canary into $($file.Name)."
  }
}

try {
  Set-Content -LiteralPath (Join-Path $target 'AGENTS.md') -Value "# Private project rules`n$canary" -Encoding UTF8
  Assert-GitSuccess @('-C', $target, 'init', '--quiet') 'git init failed'
  Assert-GitSuccess @('-C', $target, 'config', 'user.email', 'tests@lizard-agent-layer.invalid') 'git email config failed'
  Assert-GitSuccess @('-C', $target, 'config', 'user.name', 'lizard tests') 'git name config failed'
  Assert-GitSuccess @('-C', $target, 'add', 'AGENTS.md') 'git add failed'
  Assert-GitSuccess @('-C', $target, 'commit', '--quiet', '-m', 'fixture') 'git commit failed'
  $targetHash = (Get-FileHash -LiteralPath (Join-Path $target 'AGENTS.md') -Algorithm SHA256).Hash

  $default = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'generic-agents-md', '-OutputDir', $defaultOutput)
  Assert-Equal 0 $default.exit_code "Default merge suggestions failed: $($default.output)"
  Assert-False ($default.output -match [regex]::Escape($canary)) 'Default console output leaked existing instruction content.'
  Assert-CanaryAbsent -Path $defaultOutput -Label 'Default report mode'
  Assert-Equal $targetHash (Get-FileHash -LiteralPath (Join-Path $target 'AGENTS.md') -Algorithm SHA256).Hash 'Report generation modified target instructions.'
  Assert-Equal 0 @(& git -C $target status --short).Count 'Report generation dirtied target Git state.'

  $jsonPath = Join-Path $defaultOutput 'merge-suggestions.json'
  $report = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
  Assert-Equal 'metadata-only' ([string]$report.sensitivity) 'Default report sensitivity must be metadata-only.'
  Assert-False ([bool]$report.include_existing_context) 'Default report must not include existing context.'
  Assert-True ([string]$report.results[0].instruction_sha256 -match '^[a-f0-9]{64}$') 'Default report must bind the source instruction hash.'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/merge-suggestions-report.schema.json' -InstancePath $jsonPath -Message 'Default merge report must satisfy its schema.'
  $patchText = Get-Content -LiteralPath ([string]$report.patch_files[0]) -Raw
  Assert-True ($patchText -match '@@ -2,0 \+3,') 'Metadata-only patch must use a zero-context append hunk.'
  $applyTarget = Join-Path $fixture 'patch-apply-target'
  New-Item -ItemType Directory -Path $applyTarget -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $target 'AGENTS.md') -Destination (Join-Path $applyTarget 'AGENTS.md')
  Assert-GitSuccess @('-C', $applyTarget, 'init', '--quiet') 'patch fixture git init failed'
  Assert-GitSuccess @('-C', $applyTarget, 'apply', '--unidiff-zero', ([string]$report.patch_files[0])) 'metadata-only patch must remain applyable'
  $appliedText = Get-Content -LiteralPath (Join-Path $applyTarget 'AGENTS.md') -Raw
  Assert-True ($appliedText -match [regex]::Escape($canary)) 'Applying metadata-only patch must preserve existing instructions.'
  Assert-True ($appliedText -match '## lizard-agent-layer') 'Applying metadata-only patch must append the suggested block.'

  $targetLocalOutput = Join-Path $target 'reports'
  $blocked = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'generic-agents-md', '-OutputDir', $targetLocalOutput)
  Assert-False ($blocked.exit_code -eq 0) 'Target-local report output must fail closed by default.'
  Assert-True ($blocked.output -match 'SAFEFS_FORBIDDEN_ROOT') 'Target-local report rejection must expose SAFEFS_FORBIDDEN_ROOT.'
  Assert-False (Test-Path -LiteralPath $targetLocalOutput) 'Rejected target-local output must remain absent.'

  $context = Invoke-TestPowerShell -ScriptPath $scriptPath -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'generic-agents-md', '-OutputDir', $contextOutput, '-IncludeExistingContext')
  Assert-Equal 0 $context.exit_code "Explicit context report failed: $($context.output)"
  $contextReport = Get-Content -LiteralPath (Join-Path $contextOutput 'merge-suggestions.json') -Raw | ConvertFrom-Json
  Assert-Equal 'contains-target-context' ([string]$contextReport.sensitivity) 'Explicit context report must be sensitivity-labelled.'
  Assert-True ([bool]$contextReport.include_existing_context) 'Explicit context mode must be recorded.'
  Assert-True ((Get-Content -LiteralPath ([string]$contextReport.patch_files[0]) -Raw) -match [regex]::Escape($canary)) 'Explicit context patch must retain compatibility behavior.'
  Assert-False ((Get-Content -LiteralPath (Join-Path $contextOutput 'merge-suggestions.md') -Raw) -match [regex]::Escape($canary)) 'Human report must not duplicate context even in compatibility mode.'
  Assert-False ((Get-Content -LiteralPath (Join-Path $contextOutput 'merge-suggestions.json') -Raw) -match [regex]::Escape($canary)) 'JSON report must not duplicate context even in compatibility mode.'
  Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/merge-suggestions-report.schema.json' -InstancePath (Join-Path $contextOutput 'merge-suggestions.json') -Message 'Context merge report must satisfy its schema.'

  Write-Host 'PASS tests\adversarial\report-privacy.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
