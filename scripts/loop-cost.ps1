param(
  [string]$Pattern = 'daily-triage',
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [ValidateSet('L0', 'L1', 'L2', 'L3')]
  [string]$Level,
  [string]$Cadence,
  [ValidateSet('budget', 'balanced', 'premium')]
  [string]$ModelClass = 'budget',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$patternPath = Join-Path $LayerRoot ("loops\{0}.json" -f $Pattern)
if (-not (Test-Path -LiteralPath $patternPath)) { throw "Unknown loop pattern '$Pattern'." }
$patternDoc = Get-Content -LiteralPath $patternPath -Raw | ConvertFrom-Json
$effectiveLevel = if ([string]::IsNullOrWhiteSpace($Level)) { [string]$patternDoc.readinessLevel } else { $Level }
$patternCadence = if ($patternDoc.cadence -and ($patternDoc.cadence.PSObject.Properties.Name -contains 'recommended')) { [string]$patternDoc.cadence.recommended } else { '1d' }
$effectiveCadence = if ([string]::IsNullOrWhiteSpace($Cadence)) { $patternCadence } else { $Cadence }

$baseTokens = @{ L0 = 1200; L1 = 3200; L2 = 6800; L3 = 12000 }
$riskMultiplier = @{ low = 1.0; medium = 1.15; high = 1.3 }
$modelMultiplier = @{ budget = 0.85; balanced = 1.0; premium = 1.25 }
$risk = if ($patternDoc.riskLevel) { [string]$patternDoc.riskLevel } else { 'medium' }
$perRun = [Math]::Round($baseTokens[$effectiveLevel] * $riskMultiplier[$risk] * $modelMultiplier[$ModelClass])

function Get-RunsPerDay {
  param([string]$Value)
  switch -Regex ($Value.ToLowerInvariant()) {
    '^(manual|on-demand|ad-hoc)$' { return 0 }
    '^daily$|^1d$' { return 1 }
    '^twice-daily$|^2d$' { return 2 }
    '^weekly$|^1w$' { return [double](1 / 7) }
    '^monthly$|^1mo$' { return [double](1 / 30) }
    '^(\d+)d$' { return [double](1 / [int]$Matches[1]) }
    '^(\d+)w$' { return [double](1 / ([int]$Matches[1] * 7)) }
    default { return 1 }
  }
}
$runsPerDay = Get-RunsPerDay $effectiveCadence
$dailyTokens = [Math]::Round($perRun * $runsPerDay)
$weeklyTokens = [Math]::Round($dailyTokens * 7)
$monthlyTokens = [Math]::Round($dailyTokens * 30)
$oldModelStrategy = @(
  'Use budget or small models for scan, triage, and checklist expansion.',
  'Escalate to balanced or premium models only for failing gates, critical diffs, ambiguous plans, or release approval.',
  'Keep loop state compact: last decision, open blockers, next command, and verification evidence only.',
  'Prefer L1/report-only loops for older models; avoid autonomous write loops unless the target has strong tests and narrow ownership.'
)
$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  pattern = [string]$patternDoc.name
  level = $effectiveLevel
  cadence = $effectiveCadence
  risk_level = $risk
  model_class = $ModelClass
  estimated_tokens_per_run = $perRun
  estimated_runs_per_day = $runsPerDay
  estimated_tokens_daily = $dailyTokens
  estimated_tokens_weekly = $weeklyTokens
  estimated_tokens_monthly = $monthlyTokens
  old_model_strategy = $oldModelStrategy
}

if ($Json) {
  $report | ConvertTo-Json -Depth 8
} else {
  Write-Host 'lizard-agent-layer loop cost estimate'
  Write-Host "Pattern: $($report.pattern)"
  Write-Host "Level: $effectiveLevel"
  Write-Host "Cadence: $effectiveCadence"
  Write-Host "Model class: $ModelClass"
  Write-Host "Estimated tokens/run: $perRun"
  Write-Host "Estimated tokens/day: $dailyTokens"
  Write-Host "Estimated tokens/week: $weeklyTokens"
  Write-Host "Estimated tokens/month: $monthlyTokens"
  Write-Host 'Old model strategy:'
  foreach ($line in $oldModelStrategy) { Write-Host "  - $line" }
}
