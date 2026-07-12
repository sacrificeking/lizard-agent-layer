param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string[]]$ChangedPaths,
  [string]$BaseRef,
  [string]$OutputDir,
  [switch]$Strict,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $LayerRoot '.tmp\contracts' }
$OutputDir = Initialize-SafeDirectory -Path $OutputDir

function Normalize-ContractPath {
  param([string]$Path)
  $value = $Path.Trim().Replace('\', '/').TrimStart('./')
  if ([string]::IsNullOrWhiteSpace($value) -or [System.IO.Path]::IsPathRooted($value) -or $value -match '^[A-Za-z]:' -or $value -match '(^|/)\.\.(/|$)') {
    throw "CONTRACT_PATH_INVALID: $Path"
  }
  return $value
}

function Expand-PathList {
  param($Values)
  $result = New-Object System.Collections.Generic.List[string]
  foreach ($value in @($Values)) {
    foreach ($part in ([string]$value -split ',')) {
      if (-not [string]::IsNullOrWhiteSpace($part)) {
        $normalized = Normalize-ContractPath $part
        if (-not $result.Contains($normalized)) { $result.Add($normalized) | Out-Null }
      }
    }
  }
  @($result.ToArray() | Sort-Object)
}

function Invoke-GitLines {
  param([string[]]$Arguments)
  $previous = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& git -C $LayerRoot @Arguments 2>$null)
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previous
  }
  if ($exitCode -ne 0) { return @() }
  @($output | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Get-DetectedChanges {
  $gitRoot = @(Invoke-GitLines @('rev-parse', '--show-toplevel'))
  if ($gitRoot.Count -eq 0) { return [pscustomobject]@{ comparison = 'no-git-repository'; paths = @() } }
  $resolvedGitRoot = [System.IO.Path]::GetFullPath(([string]$gitRoot[0]))
  if (-not $resolvedGitRoot.Equals($LayerRoot, (Get-LizardPathComparison))) {
    return [pscustomobject]@{ comparison = 'no-git-layer-root'; paths = @() }
  }

  $effectiveBase = $BaseRef
  if ([string]::IsNullOrWhiteSpace($effectiveBase) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
    $effectiveBase = "origin/$($env:GITHUB_BASE_REF)"
  }
  if (-not [string]::IsNullOrWhiteSpace($effectiveBase)) {
    $paths = Invoke-GitLines @('diff', '--name-only', "$effectiveBase...HEAD", '--')
    return [pscustomobject]@{ comparison = "$effectiveBase...HEAD"; paths = $paths }
  }
  if ($env:GITHUB_EVENT_NAME -eq 'push') {
    $paths = Invoke-GitLines @('diff', '--name-only', 'HEAD^', 'HEAD', '--')
    return [pscustomobject]@{ comparison = 'HEAD^..HEAD'; paths = $paths }
  }

  $tracked = Invoke-GitLines @('diff', '--name-only', 'HEAD', '--')
  $untracked = Invoke-GitLines @('ls-files', '--others', '--exclude-standard')
  return [pscustomobject]@{ comparison = 'working-tree'; paths = @($tracked + $untracked) }
}

function Test-PathPattern {
  param([string]$Path, [string[]]$Patterns)
  foreach ($pattern in @($Patterns)) { if ($Path -like ([string]$pattern)) { return $true } }
  return $false
}

$detected = if ($ChangedPaths -and $ChangedPaths.Count -gt 0) {
  [pscustomobject]@{ comparison = 'explicit'; paths = Expand-PathList $ChangedPaths }
} else {
  Get-DetectedChanges
}
$normalizedChanges = Expand-PathList $detected.paths
$registry = Get-Content -LiteralPath (Join-Path $LayerRoot 'registry\contracts.json') -Raw | ConvertFrom-Json
$declarationPaths = @($normalizedChanges | Where-Object { $_ -like 'changes/*.json' })
$declarations = New-Object System.Collections.Generic.List[object]
$failures = New-Object System.Collections.Generic.List[string]

foreach ($relative in $declarationPaths) {
  $fullPath = Join-Path $LayerRoot $relative
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
    if ([string]$detected.comparison -eq 'explicit') {
      $failures.Add("Changed declaration is missing: $relative") | Out-Null
    }
    continue
  }
  try {
    $doc = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    $declarations.Add([pscustomobject]@{ path = $relative; doc = $doc }) | Out-Null
  } catch {
    $failures.Add("Change declaration is invalid JSON: $relative") | Out-Null
  }
}

$impacted = New-Object System.Collections.Generic.List[object]
foreach ($contract in @($registry.contracts)) {
  $contractPaths = @($normalizedChanges | Where-Object { Test-PathPattern -Path $_ -Patterns @($contract.paths) })
  if ($contractPaths.Count -eq 0) { continue }
  $contractCovered = $true
  if (-not (Test-Path -LiteralPath (Join-Path $LayerRoot ([string]$contract.adr)) -PathType Leaf)) {
    $failures.Add("Contract '$($contract.id)' references missing ADR '$($contract.adr)'.") | Out-Null
    $contractCovered = $false
  }
  foreach ($changedPath in $contractPaths) {
    $covering = @($declarations | Where-Object {
      (Test-PathPattern -Path $changedPath -Patterns @($_.doc.changed_paths)) -and
      (@($_.doc.decision_records) -contains [string]$contract.adr) -and
      (-not [bool]$contract.migration_required -or [string]$_.doc.migration.disposition -in @('migration-required', 'backward-compatible'))
    })
    if ($covering.Count -eq 0) {
      $failures.Add("Contract '$($contract.id)' path '$changedPath' lacks a changed declaration linking '$($contract.adr)' with a valid migration disposition.") | Out-Null
      $contractCovered = $false
    }
  }
  $impacted.Add([ordered]@{
    id = [string]$contract.id
    adr = [string]$contract.adr
    migration_required = [bool]$contract.migration_required
    changed_paths = $contractPaths
    covered = $contractCovered
  }) | Out-Null
}

$status = if ($failures.Count -gt 0) { 'fail' } elseif ($impacted.Count -eq 0) { 'not-applicable' } else { 'pass' }
$report = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  status = $status
  comparison = [string]$detected.comparison
  changed_paths = $normalizedChanges
  declarations = $declarationPaths
  impacted_contracts = @($impacted.ToArray())
  failures = @($failures.ToArray())
}
$reportPath = Join-Path $OutputDir 'contract-check-report.json'
Set-SafeContent -AuthorizedRoot $OutputDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 10)

if ($Json) { $report | ConvertTo-Json -Depth 10 } else {
  Write-Host "Contract check: $status"
  Write-Host "Comparison: $($report.comparison)"
  Write-Host "Changed paths: $($normalizedChanges.Count)"
  Write-Host "Impacted contracts: $($impacted.Count)"
  Write-Host "Report: $reportPath"
  foreach ($failure in @($failures.ToArray())) { Write-Host "FAIL $failure" }
}
if ($Strict -and $failures.Count -gt 0) { exit 1 }
