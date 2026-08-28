param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $LayerRoot 'scripts'))) {
    $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Profiles.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Json.psm1') -Force

$ciWorkflowPath = Join-Path $LayerRoot '.github\workflows\lizard-agent-layer-ci.yml'
Assert-True (Test-Path -LiteralPath $ciWorkflowPath) "CI workflow must exist at $ciWorkflowPath"

$canonicalProfiles = @(Get-LizardBuiltinProfileIds -LayerRoot $LayerRoot)
$canonicalHarnesses = @(Get-LizardSupportedHarnessIds -LayerRoot $LayerRoot)

Assert-True ($canonicalProfiles.Count -ge 3) "At least 3 builtin profiles must exist"
Assert-True ($canonicalProfiles -contains 'minimal') "minimal profile must exist"
Assert-True ($canonicalProfiles -contains 'standard') "standard profile must exist"
Assert-True ($canonicalProfiles -contains 'enterprise-fullstack') "enterprise-fullstack profile must exist"

$ciContent = Get-Content -LiteralPath $ciWorkflowPath -Raw

# 1. Parse matrix profile entries
$matrixProfileMatches = [regex]::Matches($ciContent, 'profile:\s*([a-zA-Z0-9_-]+)')
$foundProfiles = New-Object System.Collections.Generic.HashSet[string]
foreach ($match in $matrixProfileMatches) {
  $profileId = $match.Groups[1].Value
  if ($canonicalProfiles -notcontains $profileId) {
    throw "CI_MATRIX_UNKNOWN_PROFILE: Profile '$profileId' in CI workflow does not exist in profiles/ directory."
  }
  $foundProfiles.Add($profileId) | Out-Null
}

# 2. Assert all canonical profiles are covered in CI matrix
foreach ($canonical in $canonicalProfiles) {
  Assert-True ($foundProfiles.Contains($canonical)) "CI_MATRIX_PROFILE_MISSING: Canonical profile '$canonical' is missing from CI workflow matrix."
}

# 3. Assert no stale profile names appear in workflow
Assert-False ($ciContent -match 'supabase-react-finance') "CI workflow must not contain stale profile references like supabase-react-finance."

# 4. Negative test: verify detector catches unknown profile
$tamperedYaml = $ciContent + "`n          - { os: ubuntu-latest, profile: non-existent-profile, harnesses: '', label: fake }"
$testDetector = {
  param([string]$YamlContent, [string[]]$KnownProfiles)
  $matches = [regex]::Matches($YamlContent, 'profile:\s*([a-zA-Z0-9_-]+)')
  foreach ($m in $matches) {
    $p = $m.Groups[1].Value
    if ($KnownProfiles -notcontains $p) {
      throw "CI_MATRIX_UNKNOWN_PROFILE: $p"
    }
  }
}

$caught = $false
try {
  & $testDetector $tamperedYaml $canonicalProfiles
} catch {
  if ($_.Exception.Message -match 'CI_MATRIX_UNKNOWN_PROFILE: non-existent-profile') {
    $caught = $true
  }
}
Assert-True $caught "Negative test: Unknown profile in workflow must throw CI_MATRIX_UNKNOWN_PROFILE"

Write-Host "PASS tests\integration\ci-matrix-consistency.tests.ps1"
