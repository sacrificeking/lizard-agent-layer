param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Json,
  [ValidateRange(1, 1000000)][int]$MaxFiles = 20000,
  [string[]]$ApprovedHarnesses = @()
)

$ErrorActionPreference = 'Stop'
$LayerRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Lizard.Host.psm1') -Force

$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$signals = New-Object System.Collections.Generic.List[string]
$reasons = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$packs = New-Object System.Collections.Generic.List[string]
$evidence = New-Object System.Collections.Generic.List[object]
$negativeSignals = New-Object System.Collections.Generic.List[string]
$detectedHarnesses = New-Object System.Collections.Generic.List[string]
$signalEvidenceIds = @{}

function Add-Warning { param([string]$Warning) if (-not $warnings.Contains($Warning)) { $warnings.Add($Warning) | Out-Null } }
function Add-Pack { param([string]$Pack) if (-not $packs.Contains($Pack)) { $packs.Add($Pack) | Out-Null } }
function Add-NegativeSignal { param([string]$Signal) if (-not $negativeSignals.Contains($Signal)) { $negativeSignals.Add($Signal) | Out-Null } }
function Add-DetectedHarness { param([string]$Harness) if (-not $detectedHarnesses.Contains($Harness)) { $detectedHarnesses.Add($Harness) | Out-Null } }
function Add-Signal {
  param(
    [Parameter(Mandatory = $true)][string]$Signal,
    [Parameter(Mandatory = $true)][string]$EvidenceId,
    [Parameter(Mandatory = $true)][ValidateSet('manifest', 'marker', 'path-group', 'instruction-file')][string]$EvidenceKind,
    [Parameter(Mandatory = $true)][ValidateSet('strong', 'supporting', 'weak')][string]$Strength,
    [Parameter(Mandatory = $true)][string]$Reason
  )
  if (-not $signals.Contains($Signal)) { $signals.Add($Signal) | Out-Null }
  if (-not $reasons.Contains($Reason)) { $reasons.Add($Reason) | Out-Null }
  $key = "$Signal|$EvidenceId"
  if (-not $signalEvidenceIds.ContainsKey($key)) {
    $signalEvidenceIds[$key] = $true
    $evidence.Add([ordered]@{ id = $EvidenceId; signal = $Signal; kind = $EvidenceKind; strength = $Strength }) | Out-Null
  }
}

function Sort-OrdinalStrings {
  param([object[]]$Values)
  $list = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) { if ($null -ne $value) { $list.Add([string]$value) | Out-Null } }
  $list.Sort([System.StringComparer]::Ordinal)
  return @($list.ToArray())
}

function Expand-AnalyzerValues {
  param([object[]]$Values)
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in @(([string]$value) -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed -and -not $result.Contains($trimmed)) { $result.Add($trimmed) | Out-Null }
    }
  }
  return @($result.ToArray())
}

function Get-SafeRepositoryIndex {
  param([string]$Root, [int]$Limit)
  $skipLookup = @{}
  foreach ($name in @('node_modules', '.git', 'dist', 'build', '.tmp', '.next', '.turbo', '.cache', 'coverage', 'vendor')) { $skipLookup[$name] = $true }
  $paths = New-Object System.Collections.Generic.List[string]
  $kinds = @{}
  $queue = New-Object System.Collections.Generic.Queue[object]
  $queue.Enqueue([pscustomobject]@{ relative = ''; full = $Root })
  $fileCount = 0
  $complete = $true

  while ($queue.Count -gt 0) {
    $directory = $queue.Dequeue()
    foreach ($entry in @(Get-SafeDirectoryEntries -AuthorizedRoot $Root -Path ([string]$directory.full))) {
      $relative = if ([string]::IsNullOrWhiteSpace([string]$directory.relative)) { [string]$entry.name } else { ([string]$directory.relative).TrimEnd('/') + '/' + [string]$entry.name }
      $paths.Add($relative) | Out-Null
      $kinds[$relative] = [string]$entry.kind
      if ([string]$entry.kind -eq 'file') {
        $fileCount++
        if ($fileCount -ge $Limit) { $complete = $false; break }
      } elseif (-not $skipLookup.ContainsKey(([string]$entry.name).ToLowerInvariant())) {
        $queue.Enqueue([pscustomobject]@{ relative = $relative; full = [string]$entry.path })
      }
    }
    if (-not $complete) { break }
  }

  if (-not $complete) { Add-Warning "File scan reached MaxFiles=$Limit; marker detection is incomplete." }
  return [pscustomobject]@{ paths = @(Sort-OrdinalStrings $paths.ToArray()); kinds = $kinds; complete = $complete; file_count = $fileCount }
}

$index = Get-SafeRepositoryIndex -Root $TargetRoot -Limit $MaxFiles
$pathLookup = @{}
foreach ($path in @($index.paths)) { $pathLookup[[string]$path] = $true }
function Has-Path { param([string]$Relative) return $pathLookup.ContainsKey($Relative.Replace('\', '/')) }
function Has-File { param([string]$Relative) $key = $Relative.Replace('\', '/'); return $pathLookup.ContainsKey($key) -and [string]$index.kinds[$key] -eq 'file' }

function Read-JsonSafe {
  param([string]$Relative)
  if (-not (Has-File $Relative)) { return $null }
  $path = Join-Path $TargetRoot $Relative
  try { return ConvertFrom-LizardJson -InputObject (Get-SafeContent -AuthorizedRoot $TargetRoot -Path $path -Raw -MaximumBytes 2097152) }
  catch { Add-Warning "$Relative exists but is not valid bounded JSON."; return $null }
}

$package = Read-JsonSafe 'package.json'
if ($null -ne $package) {
  Add-Signal 'node' 'manifest:package.json' 'manifest' 'strong' 'package.json is a valid bounded manifest.'
  $depNames = @()
  foreach ($bucket in @('dependencies', 'devDependencies', 'peerDependencies')) {
    if ($package.PSObject.Properties.Name -contains $bucket -and $null -ne $package.$bucket) { $depNames += @($package.$bucket.PSObject.Properties.Name) }
  }
  if ($package.PSObject.Properties.Name -contains 'workspaces') { Add-Signal 'monorepo' 'manifest:package.json#workspaces' 'manifest' 'strong' 'package.json declares workspaces.' }
  foreach ($dep in @(Sort-OrdinalStrings $depNames)) {
    switch -Regex ($dep) {
      '^react$|^vue$|^@angular/core$|^svelte$|^solid-js$' { Add-Signal 'frontend-ui' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'strong' 'package.json depends on a frontend UI framework.' }
      '^vite$|^webpack$|^rollup$|^esbuild$' { Add-Signal 'bundler' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'strong' 'package.json uses a frontend bundler/build tool.' }
      '^typescript$' { Add-Signal 'typescript' 'manifest:package.json#typescript' 'manifest' 'strong' 'package.json uses TypeScript.' }
      '^@supabase/supabase-js$|^supabase$|^pg$|^mysql$|^mysql2$|^oracledb$|^mssql$|^tedious$|^sqlite3$|^better-sqlite3$|^mongodb$|^mongoose$|^prisma$|^@prisma/client$|^typeorm$|^sequelize$|^knex$|^drizzle-orm$' { Add-Signal 'database' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'strong' 'package.json references database packages.' }
      '^express$|^fastify$|^@nestjs/core$|^koa$|^hono$|^@hapi/hapi$|^apollo-server$|^@apollo/server$|^graphql$|^trpc$|^@trpc/server$' { Add-Signal 'backend-api' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'strong' 'package.json references a backend API or server framework.' }
      '^next$|^nuxt$|^astro$' { Add-Signal 'fullstack-framework' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'strong' 'package.json uses a fullstack/SSR framework.' }
      '^openai$|^@anthropic-ai/sdk$|^ai$|^langchain$|^@langchain/' { Add-Signal 'agent-runtime' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'strong' 'package.json references an agent or LLM runtime package.' }
      '^tailwindcss$|^@radix-ui/|^lucide-react$|^framer-motion$' { Add-Signal 'design-ui' ("manifest:package.json#dependency:{0}" -f $dep) 'manifest' 'supporting' 'package.json references a UI/design-system package.' }
    }
  }
} else { Add-NegativeSignal 'package-json-absent-or-invalid' }

function Add-PathSignal {
  param([string]$Relative, [string]$Signal, [string]$Reason, [ValidateSet('strong', 'supporting', 'weak')][string]$Strength = 'supporting')
  if (Has-Path $Relative) { Add-Signal $Signal ("path:{0}" -f $Relative.Replace('\', '/')) 'marker' $Strength $Reason }
}

Add-PathSignal 'supabase' 'database' 'supabase/ directory exists.' 'supporting'
Add-PathSignal 'prisma' 'database' 'prisma/ directory exists.' 'strong'
Add-PathSignal 'migrations' 'database-migrations' 'migrations/ directory exists.' 'strong'
Add-PathSignal 'supabase/migrations' 'database-migrations' 'supabase/migrations directory exists.' 'strong'
Add-PathSignal 'db/migrations' 'database-migrations' 'db/migrations directory exists.' 'strong'
Add-PathSignal 'supabase/functions' 'backend-api' 'supabase/functions directory exists.' 'strong'
Add-PathSignal 'functions' 'backend-api' 'functions/ directory exists.' 'supporting'
Add-PathSignal 'api' 'backend-api' 'api/ directory exists.' 'supporting'
Add-PathSignal 'src/api' 'backend-api' 'src/api directory exists.' 'supporting'
Add-PathSignal 'src' 'src-tree' 'src/ directory exists.' 'weak'
if (Has-Path 'vite.config.ts' -or Has-Path 'vite.config.js') { Add-Signal 'bundler' 'path:vite.config' 'marker' 'supporting' 'A Vite config exists.' }
if (Has-Path 'tsconfig.json' -or Has-Path 'tsconfig.app.json') { Add-Signal 'typescript' 'path:tsconfig' 'marker' 'supporting' 'A TypeScript config exists.' }
Add-PathSignal 'DESIGN.md' 'design-system' 'DESIGN.md exists.' 'weak'
if (Has-Path 'AGENTS.md') { Add-Signal 'existing-agents' 'instruction:AGENTS.md' 'instruction-file' 'weak' 'AGENTS.md was detected as untrusted target content; install must preserve it.'; Add-DetectedHarness 'generic-agents-md' }
if (Has-Path 'CLAUDE.md') { Add-Signal 'existing-claude' 'instruction:CLAUDE.md' 'instruction-file' 'weak' 'CLAUDE.md was detected as untrusted target content; install must preserve it.'; Add-DetectedHarness 'claude-code' }
if (Has-Path 'GEMINI.md') { Add-Signal 'existing-gemini' 'instruction:GEMINI.md' 'instruction-file' 'weak' 'GEMINI.md was detected as untrusted target content; install must preserve it.'; Add-DetectedHarness 'gemini' }
if (Has-Path '.github/copilot-instructions.md') { Add-Signal 'github-copilot' 'instruction:.github/copilot-instructions.md' 'instruction-file' 'weak' 'Copilot instructions were detected as untrusted target content; install must preserve them.'; Add-DetectedHarness 'github-copilot' }
if (Has-Path '.cursor') { Add-Signal 'cursor' 'instruction:.cursor' 'instruction-file' 'weak' '.cursor was detected as untrusted target content; install must preserve it.'; Add-DetectedHarness 'cursor' }
if (Has-Path 'pnpm-workspace.yaml' -or Has-Path 'turbo.json' -or Has-Path 'nx.json' -or Has-Path 'lerna.json' -or Has-Path 'rush.json') { Add-Signal 'monorepo' 'path:workspace-config' 'marker' 'strong' 'A workspace or monorepo config exists.' }
if (Has-Path 'pyproject.toml' -or Has-Path 'requirements.txt' -or Has-Path 'poetry.lock') { Add-Signal 'python' 'path:python-project-marker' 'marker' 'strong' 'A Python project marker exists.' }
Add-PathSignal 'Cargo.toml' 'rust' 'Rust Cargo project marker exists.' 'strong'
Add-PathSignal 'go.mod' 'go' 'Go module marker exists.' 'strong'
if (Has-Path 'pom.xml' -or Has-Path 'build.gradle' -or Has-Path 'build.gradle.kts') { Add-Signal 'java' 'path:java-project-marker' 'marker' 'strong' 'A Java build marker exists.' }
if (@($index.paths | Where-Object { $_ -notmatch '/' -and $_ -match '\.csproj$' }).Count -gt 0) { Add-Signal 'dotnet' 'path:root-csproj' 'marker' 'strong' 'A root .NET project marker exists.' }
Add-PathSignal '.github/workflows' 'ci' 'GitHub Actions workflows exist.' 'supporting'
Add-PathSignal '.agent/loops' 'loop-runtime' '.agent/loops directory exists.' 'supporting'
Add-PathSignal '.agent/loops/lizard-agent-layer.loop-install.json' 'loop-runtime' 'The lizard-agent-layer loop manifest exists.' 'strong'
if (Has-Path '.env.example' -or Has-Path 'Dockerfile' -or Has-Path 'docker-compose.yml') { Add-Signal 'security' 'path:deployment-marker' 'marker' 'weak' 'An environment, container, or deployment marker exists.' }

function Get-MarkerGroupHits {
  param([string[]]$Markers)
  $hits = New-Object System.Collections.Generic.List[string]
  foreach ($marker in $Markers) {
    $pattern = '(?i)(^|[-_./])' + [regex]::Escape($marker) + '($|[-_./])'
    if (@($index.paths | Where-Object { $_ -match $pattern } | Select-Object -First 1).Count -gt 0) { $hits.Add($marker) | Out-Null }
  }
  return @(Sort-OrdinalStrings $hits.ToArray())
}

$financeHits = @(Get-MarkerGroupHits @('finance', 'accounting', 'ledger', 'precision'))
if ($financeHits.Count -ge 2) { Add-Signal 'precision' ("path-group:precision:{0}" -f ($financeHits -join ',')) 'path-group' 'weak' ("Precision/finance/accounting path groups detected ({0})." -f $financeHits.Count) }
else { Add-NegativeSignal 'precision-path-groups-below-threshold' }
$agentHits = @(Get-MarkerGroupHits @('agent', 'llm', 'openai', 'anthropic', 'gemini', 'mcp', 'rag', 'prompt'))
if ($agentHits.Count -ge 2) { Add-Signal 'agent-runtime' ("path-group:agent-runtime:{0}" -f ($agentHits -join ',')) 'path-group' 'weak' ("Agent/runtime path groups detected ({0})." -f $agentHits.Count) }
else { Add-NegativeSignal 'agent-runtime-path-groups-below-threshold' }
$securityHits = @(Get-MarkerGroupHits @('auth', 'secret', 'token', 'permission', 'policy', 'jwt', 'oauth', 'rls'))
if ($securityHits.Count -ge 2) { Add-Signal 'security' ("path-group:security:{0}" -f ($securityHits -join ',')) 'path-group' 'weak' ("Security-sensitive path groups detected ({0})." -f $securityHits.Count) }
else { Add-NegativeSignal 'security-path-groups-below-threshold' }
if (-not $index.complete) { Add-NegativeSignal 'recursive-scan-incomplete' }

$profile = 'minimal'
$risk = 'low'
if ($signals.Contains('python') -or $signals.Contains('rust') -or $signals.Contains('go') -or $signals.Contains('java') -or $signals.Contains('dotnet') -or $signals.Contains('monorepo') -or $signals.Contains('frontend-ui') -or $signals.Contains('bundler') -or $signals.Contains('typescript') -or $signals.Contains('database') -or $signals.Contains('backend-api')) { $profile = 'standard'; $risk = 'medium' }
$strongFullstack = ($signals.Contains('database') -or $signals.Contains('database-migrations')) -and ($signals.Contains('frontend-ui') -or $signals.Contains('backend-api') -or $signals.Contains('fullstack-framework'))
if ($strongFullstack -or ($signals.Contains('precision') -and $signals.Contains('database-migrations'))) { $profile = 'enterprise-fullstack'; $risk = 'high' }

$allowedHarnesses = @('generic-agents-md', 'codex', 'claude-code', 'gemini', 'github-copilot', 'cursor')
$approved = @(Expand-AnalyzerValues $ApprovedHarnesses)
if ($approved.Count -eq 0) { $approved = @('generic-agents-md'); $harnessApprovalSource = 'safe-default'; Add-NegativeSignal 'organization-harness-approval-not-supplied' }
else { $harnessApprovalSource = 'explicit-input' }
foreach ($harness in $approved) { if ($allowedHarnesses -notcontains $harness) { throw "ANALYZER_HARNESS_NOT_SUPPORTED: Unsupported approved harness '$harness'." } }
$harnesses = @(Sort-OrdinalStrings ($approved | Select-Object -Unique))
foreach ($detected in @($detectedHarnesses)) {
  if ($harnesses -notcontains $detected) { Add-Warning "Detected harness '$detected' is not recommended because it was not supplied through -ApprovedHarnesses." }
}

$skills = switch ($profile) {
  'minimal' { @('git-safety', 'research-audit') }
  'standard' { @('git-safety', 'staged-execution', 'research-audit', 'project-decision-harvest', 'repo-grounded-change', 'premortem') }
  'enterprise-fullstack' { @('git-safety', 'staged-execution', 'research-audit', 'project-decision-harvest', 'repo-grounded-change', 'premortem') }
}
if ($signals.Contains('frontend-ui') -or $signals.Contains('bundler') -or $signals.Contains('fullstack-framework')) { Add-Pack 'frontend-engineering' }
if ($signals.Contains('design-system') -or $signals.Contains('design-ui')) { Add-Pack 'design-system' }
if ($signals.Contains('database') -or $signals.Contains('database-migrations')) { Add-Pack 'database-backend' }
if ($signals.Contains('backend-api') -or $signals.Contains('fullstack-framework')) { Add-Pack 'backend-api' }
if ($signals.Contains('precision')) { Add-Pack 'precision-domain' }
if ($signals.Contains('agent-runtime')) { Add-Pack 'agent-runtime' }
if ($signals.Contains('loop-runtime')) { Add-Pack 'loop-engineering' }
if ($risk -eq 'high' -or $signals.Contains('database-migrations') -or $signals.Contains('backend-api') -or $signals.Contains('security') -or $signals.Contains('ci')) { Add-Pack 'security-hardening' }

$strongCount = @($evidence | Where-Object { $_.strength -eq 'strong' }).Count
$supportingCount = @($evidence | Where-Object { $_.strength -eq 'supporting' }).Count
$weakCount = @($evidence | Where-Object { $_.strength -eq 'weak' }).Count
$evidenceScore = [Math]::Min(100, ($strongCount * 18) + ($supportingCount * 8) + ($weakCount * 2))
$confidence = if (-not $index.complete) { 'low' } elseif ($profile -eq 'minimal') { 'medium' } elseif ($strongCount -ge 3) { 'high' } else { 'medium' }
$falsePositiveRisk = if ($profile -eq 'enterprise-fullstack' -and -not $strongFullstack) { 'medium' } elseif ($strongCount -ge 2) { 'low' } else { 'medium' }
$falseNegativeRisk = if (-not $index.complete) { 'high' } elseif ($profile -eq 'minimal') { 'medium' } else { 'low' }

$previewArgs = New-Object System.Collections.Generic.List[string]
$previewArgs.Add('-TargetPath'); $previewArgs.Add($TargetRoot)
$previewArgs.Add('-Profile'); $previewArgs.Add($profile)
$previewArgs.Add('-Harnesses'); $previewArgs.Add(($harnesses -join ','))
if ($packs.Count -gt 0) { $previewArgs.Add('-Packs'); $previewArgs.Add((@(Sort-OrdinalStrings $packs.ToArray()) -join ',')) }
$previewArgs.Add('-WritePlan'); $previewArgs.Add('-PlanPath'); $previewArgs.Add('.\.tmp\install-plan.md'); $previewArgs.Add('-CanonicalPlanPath'); $previewArgs.Add('.\.tmp\install-plan.json')
$previewInvocation = New-LizardPowerShellFileInvocation -ScriptPath (Join-Path $LayerRoot 'scripts\install.ps1') -ArgumentList $previewArgs.ToArray() -ResolveCurrent
$previewCommand = [string]$previewInvocation.display

$evidenceSorted = @($evidence | Sort-Object -Property id, signal)
$result = [ordered]@{
  schema_version = 2
  target = $TargetRoot
  recommendedProfile = $profile
  riskLevel = $risk
  recommendedHarnesses = @($harnesses)
  harnessApprovalSource = $harnessApprovalSource
  detectedHarnesses = @(Sort-OrdinalStrings $detectedHarnesses.ToArray())
  recommendedSkills = @(Sort-OrdinalStrings $skills)
  recommendedPacks = @(Sort-OrdinalStrings $packs.ToArray())
  signals = @(Sort-OrdinalStrings $signals.ToArray())
  evidence = $evidenceSorted
  negativeSignals = @(Sort-OrdinalStrings $negativeSignals.ToArray())
  reasons = @(Sort-OrdinalStrings $reasons.ToArray())
  warnings = @(Sort-OrdinalStrings $warnings.ToArray())
  calibration = [ordered]@{
    method = 'deterministic-rule-evidence-v1'
    score_kind = 'bounded-evidence-score-not-probability'
    evidence_score = $evidenceScore
    confidence = $confidence
    false_positive_risk = $falsePositiveRisk
    false_negative_risk = $falseNegativeRisk
    scan_complete = [bool]$index.complete
    scanned_files = [int]$index.file_count
    fixture_matrix = 'analyzer-calibration-v1'
  }
  projectShape = [ordered]@{ monorepo = $signals.Contains('monorepo'); nonNode = ($signals.Contains('python') -or $signals.Contains('rust') -or $signals.Contains('go') -or $signals.Contains('java') -or $signals.Contains('dotnet')); highRisk = ($risk -eq 'high') }
  previewInvocation = [ordered]@{ executable = [string]$previewInvocation.executable; argv = @($previewInvocation.argv) }
  previewCommand = $previewCommand
}

if ($Json) { $result | ConvertTo-Json -Depth 10; exit 0 }

Write-Host 'lizard-agent-layer target analysis'
Write-Host "Target: $TargetRoot"
Write-Host "Recommended profile: $profile"
Write-Host "Risk level: $risk"
Write-Host "Recommendation confidence: $confidence (bounded evidence score $evidenceScore; not a probability)"
Write-Host "Recommended approved harnesses: $($harnesses -join ', ')"
Write-Host "Detected target instruction harnesses: $((Sort-OrdinalStrings $detectedHarnesses.ToArray()) -join ', ')"
Write-Host "Recommended skills: $((Sort-OrdinalStrings $skills) -join ', ')"
Write-Host "Recommended packs: $((Sort-OrdinalStrings $packs.ToArray()) -join ', ')"
Write-Host ''
Write-Host 'Signals:'
foreach ($signal in @(Sort-OrdinalStrings $signals.ToArray())) { Write-Host "  - $signal" }
Write-Host ''
Write-Host 'Reasons:'
foreach ($reason in @(Sort-OrdinalStrings $reasons.ToArray())) { Write-Host "  - $reason" }
if ($warnings.Count -gt 0) { Write-Host ''; Write-Host 'Warnings:'; foreach ($warning in @(Sort-OrdinalStrings $warnings.ToArray())) { Write-Host "  - $warning" } }
Write-Host ''
Write-Host 'Preview command:'
Write-Host "  $previewCommand"
