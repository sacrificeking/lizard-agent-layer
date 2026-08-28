[CmdletBinding()]
param(
  [string]$RepoRoot = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Split-Path -Parent $PSScriptRoot
}
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$jsonModule = Join-Path $RepoRoot 'scripts\Lizard.Json.psm1'
$safeFsModule = Join-Path $RepoRoot 'scripts\Lizard.SafeFs.psm1'
$profilesModule = Join-Path $RepoRoot 'scripts\Lizard.Profiles.psm1'
$hostModule = Join-Path $RepoRoot 'scripts\Lizard.Host.psm1'

Import-Module $jsonModule -Force
Import-Module $safeFsModule -Force
Import-Module $profilesModule -Force
Import-Module $hostModule -Force

$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix

$errors = New-Object System.Collections.Generic.List[string]

Write-Host "Running repository drift verification for: $RepoRoot"

# 1. Profile Registry Drift Verification
$builtinProfiles = @(Get-LizardBuiltinProfileIds -LayerRoot $RepoRoot)
$profilesDir = Join-Path $RepoRoot 'profiles'
$profileFiles = @(Get-ChildItem -LiteralPath $profilesDir -Filter '*.json' | ForEach-Object { $_.BaseName })

foreach ($profileId in $builtinProfiles) {
  if ($profileFiles -notcontains $profileId) {
    $errors.Add("DRIFT: Profile '$profileId' returned by Get-LizardBuiltinProfileIds but missing file under profiles/.")
  }
}
foreach ($profileFile in $profileFiles) {
  if ($builtinProfiles -notcontains $profileFile) {
    $errors.Add("DRIFT: Profile file '$profileFile.json' exists but is not registered in Get-LizardBuiltinProfileIds.")
  }
}

# 2. CI Matrix Consistency Verification
$ciWorkflowPath = Join-Path $RepoRoot '.github\workflows\lizard-agent-layer-ci.yml'
if (Test-Path -LiteralPath $ciWorkflowPath -PathType Leaf) {
  $ciContent = Get-Content -LiteralPath $ciWorkflowPath -Raw
  if ($ciContent -match 'supabase-react-finance') {
    $errors.Add("DRIFT: CI workflow contains stale profile reference 'supabase-react-finance'.")
  }
  foreach ($profileId in $builtinProfiles) {
    if ($ciContent -notmatch [regex]::Escape($profileId)) {
      $errors.Add("DRIFT: Profile '$profileId' is not referenced in CI workflow matrix.")
    }
  }
  $supportedHarnesses = @(Get-LizardSupportedHarnessIds -LayerRoot $RepoRoot)
  foreach ($harnessId in $supportedHarnesses) {
    if ($ciContent -notmatch [regex]::Escape($harnessId)) {
      $errors.Add("DRIFT: Supported harness '$harnessId' is not referenced in CI workflow matrix.")
    }
  }
} else {
  $errors.Add("DRIFT: CI workflow file missing at $ciWorkflowPath.")
}

# 3. JSON Reader Policy Linter
$policyChecker = Join-Path $RepoRoot 'scripts\check-json-reader-policy.ps1'
if (Test-Path -LiteralPath $policyChecker -PathType Leaf) {
  $policyOutput = & $PowerShellHost @PowerShellFilePrefix $policyChecker -LayerRoot $RepoRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    $errors.Add("DRIFT: JSON reader policy violations detected:`n$policyOutput")
  }
} else {
  $errors.Add("DRIFT: check-json-reader-policy.ps1 missing.")
}

# 4. Schema Validator Bindings Verification
$validatorScript = Join-Path $RepoRoot 'tools\schema-validator\validate.mjs'
$bindingsFile = Join-Path $RepoRoot 'tools\schema-validator\bindings.json'
if (Test-Path -LiteralPath $bindingsFile -PathType Leaf) {
  $bindingsDoc = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $bindingsFile -Raw)
  foreach ($binding in @($bindingsDoc.bindings)) {
    $schemaPath = Join-Path $RepoRoot ([string]$binding.schema).Replace('/', '\')
    if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
      $errors.Add("DRIFT: Binding references missing schema file '$($binding.schema)'.")
    }
  }
} else {
  $errors.Add("DRIFT: Schema validator bindings.json missing at $bindingsFile.")
}

if (Test-Path -LiteralPath $validatorScript -PathType Leaf) {
  $valOutput = & node $validatorScript 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    $errors.Add("DRIFT: Schema validator execution failed:`n$valOutput")
  }
} else {
  $errors.Add("DRIFT: tools/schema-validator/validate.mjs missing.")
}

# 5. Documentation Stale Identifier Check
$docFiles = @('README.md', 'QUICKSTART.md', 'INSTALL.md')
foreach ($docName in $docFiles) {
  $docPath = Join-Path $RepoRoot $docName
  if (Test-Path -LiteralPath $docPath -PathType Leaf) {
    $docContent = Get-Content -LiteralPath $docPath -Raw
    if ($docContent -match 'supabase-react-finance') {
      $errors.Add("DRIFT: Documentation file '$docName' contains stale profile 'supabase-react-finance'.")
    }
  }
}

if ($errors.Count -gt 0) {
  Write-Error ("Repository drift checks failed with {0} issue(s):`n - {1}" -f $errors.Count, ($errors -join "`n - "))
  exit 1
}

Write-Host "PASS: Repository drift verification clean (0 drift issues detected)."
