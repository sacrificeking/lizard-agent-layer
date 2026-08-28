[CmdletBinding()]
param(
  [string]$CandidateSha = '',
  [string]$ExpectedVersion = '',
  [string]$LayerRoot = '',
  [switch]$RequireCleanWorkingTree,
  [switch]$Json
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path

Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Json.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Host.psm1') -Force

$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix

$versionFile = Join-Path $LayerRoot 'VERSION'
$currentVersion = if (Test-Path -LiteralPath $versionFile -PathType Leaf) { (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { '' }

if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) {
  $ExpectedVersion = $currentVersion
}

$checks = New-Object System.Collections.Generic.List[object]
$blockers = New-Object System.Collections.Generic.List[string]

function Add-CheckResult {
  param([string]$Name, [string]$Status, [string]$Details = '')
  $checks.Add([pscustomobject][ordered]@{
    name = $Name
    status = $Status
    details = $Details
  }) | Out-Null
  if ($Status -ne 'pass') {
    $blockers.Add("$Name : $Details") | Out-Null
  }
}

# 1. Check Version Consistency
if ([string]::IsNullOrWhiteSpace($currentVersion)) {
  Add-CheckResult -Name 'version_consistency' -Status 'fail' -Details 'VERSION file is missing or empty.'
} elseif ($currentVersion -ne $ExpectedVersion) {
  Add-CheckResult -Name 'version_consistency' -Status 'fail' -Details "VERSION '$currentVersion' does not match expected '$ExpectedVersion'."
} else {
  $pkgFile = Join-Path $LayerRoot 'package.json'
  if (Test-Path -LiteralPath $pkgFile -PathType Leaf) {
    $pkgDoc = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $pkgFile -Raw)
    if ([string]$pkgDoc.version -ne $currentVersion) {
      Add-CheckResult -Name 'version_consistency' -Status 'fail' -Details "package.json version '$($pkgDoc.version)' differs from VERSION '$currentVersion'."
    } else {
      Add-CheckResult -Name 'version_consistency' -Status 'pass' -Details "Version $currentVersion is consistent across VERSION and package.json."
    }
  } else {
    Add-CheckResult -Name 'version_consistency' -Status 'pass' -Details "Version $currentVersion verified."
  }
}

# 2. Check Repository Drift
$driftScript = Join-Path $LayerRoot 'scripts\check-repository-drift.ps1'
if (Test-Path -LiteralPath $driftScript -PathType Leaf) {
  $driftOutput = & $PowerShellHost @PowerShellFilePrefix $driftScript -RepoRoot $LayerRoot 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) {
    Add-CheckResult -Name 'repository_drift' -Status 'pass' -Details 'No profile, harness, CI matrix, or schema drift detected.'
  } else {
    Add-CheckResult -Name 'repository_drift' -Status 'fail' -Details $driftOutput.Trim()
  }
} else {
  Add-CheckResult -Name 'repository_drift' -Status 'fail' -Details 'scripts/check-repository-drift.ps1 is missing.'
}

# 3. Check JSON Reader Policy
$policyScript = Join-Path $LayerRoot 'scripts\check-json-reader-policy.ps1'
if (Test-Path -LiteralPath $policyScript -PathType Leaf) {
  $policyOutput = & $PowerShellHost @PowerShellFilePrefix $policyScript -LayerRoot $LayerRoot 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) {
    Add-CheckResult -Name 'json_reader_policy' -Status 'pass' -Details 'All PowerShell scripts and test files use ConvertFrom-LizardJson.'
  } else {
    Add-CheckResult -Name 'json_reader_policy' -Status 'fail' -Details $policyOutput.Trim()
  }
} else {
  Add-CheckResult -Name 'json_reader_policy' -Status 'fail' -Details 'scripts/check-json-reader-policy.ps1 is missing.'
}

# 4. Check Schema Validation
$validatorScript = Join-Path $LayerRoot 'tools\schema-validator\validate.mjs'
if (Test-Path -LiteralPath $validatorScript -PathType Leaf) {
  $valOutput = & node $validatorScript 2>&1 | Out-String
  if ($LASTEXITCODE -eq 0) {
    Add-CheckResult -Name 'schema_validation' -Status 'pass' -Details 'All schema bindings passed.'
  } else {
    Add-CheckResult -Name 'schema_validation' -Status 'fail' -Details $valOutput.Trim()
  }
} else {
  Add-CheckResult -Name 'schema_validation' -Status 'fail' -Details 'tools/schema-validator/validate.mjs is missing.'
}

# 5. Check Changelog Version Presence
$changelogFile = Join-Path $LayerRoot 'CHANGELOG.md'
if (Test-Path -LiteralPath $changelogFile -PathType Leaf) {
  $changelogContent = Get-Content -LiteralPath $changelogFile -Raw
  if ($changelogContent -match [regex]::Escape($ExpectedVersion)) {
    Add-CheckResult -Name 'changelog_consistency' -Status 'pass' -Details "CHANGELOG.md contains entries for version $ExpectedVersion."
  } else {
    Add-CheckResult -Name 'changelog_consistency' -Status 'fail' -Details "CHANGELOG.md does not contain header for version $ExpectedVersion."
  }
} else {
  Add-CheckResult -Name 'changelog_consistency' -Status 'fail' -Details 'CHANGELOG.md is missing.'
}

# 6. Check Clean Working Tree (if requested)
if ($RequireCleanWorkingTree.IsPresent) {
  $statusOutput = & git -C $LayerRoot status --porcelain 2>&1 | Out-String
  if ([string]::IsNullOrWhiteSpace($statusOutput.Trim())) {
    Add-CheckResult -Name 'working_tree_clean' -Status 'pass' -Details 'Working tree is clean.'
  } else {
    Add-CheckResult -Name 'working_tree_clean' -Status 'fail' -Details "Working tree has uncommitted modifications:`n$statusOutput"
  }
}

$isReady = ($blockers.Count -eq 0)

$report = [pscustomobject][ordered]@{
  schema_version = 1
  ready = $isReady
  candidate_sha = if ([string]::IsNullOrWhiteSpace($CandidateSha)) { $null } else { $CandidateSha }
  version = $ExpectedVersion
  checks = @($checks.ToArray())
  blockers = @($blockers.ToArray())
}

if ($Json.IsPresent) {
  $report | ConvertTo-Json -Depth 5
} else {
  Write-Host ("=== Release Readiness Report: Version {0} ===" -f $ExpectedVersion)
  Write-Host ("Overall Status: {0}" -f (if ($isReady) { 'READY FOR RELEASE' } else { 'BLOCKED' }))
  foreach ($c in $checks) {
    Write-Host (" [{0}] {1}: {2}" -f (if ($c.status -eq 'pass') { 'PASS' } else { 'FAIL' }), $c.name, $c.details)
  }
  if (-not $isReady) {
    Write-Host "`nRelease Blockers:"
    foreach ($b in $blockers) {
      Write-Host (" - {0}" -f $b)
    }
  }
}

if (-not $isReady) {
  exit 1
}
