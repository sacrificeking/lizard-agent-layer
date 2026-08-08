param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Plan.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("plan-unit-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$output = Join-Path $fixture 'approved'
New-Item -ItemType Directory -Path $target, $output -Force | Out-Null

function New-TestPlan {
  param([string]$OperationKind = 'install', [string]$Profile = 'minimal', [int]$TtlMinutes = 30)
  $inputHash = ('a' * 64)
  $expectedHash = ('b' * 64)
  return New-LizardOperationPlan -OperationKind $OperationKind -TargetRoot $target -LayerRoot $LayerRoot -Options ([pscustomobject]@{ profile = $Profile; force = $false }) -Inputs @(
    [ordered]@{ scope = 'layer'; path = 'profiles/minimal.json'; sha256 = $inputHash }
  ) -TargetEntries @(
    [ordered]@{ path = '.agent/project-profile.json'; kind = 'file'; action = 'create'; precondition_kind = 'absent'; precondition_sha256 = $null; ownership = 'unmanaged'; intended_sha256 = $expectedHash }
  ) -TtlMinutes $TtlMinutes
}

try {
  $originalCulture = [System.Threading.Thread]::CurrentThread.CurrentCulture
  try {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = New-Object System.Globalization.CultureInfo('de-DE')
    $left = [pscustomobject]@{ z = "line1`nline2"; a = 1234; nested = [pscustomobject]@{ y = $true; x = $null }; array = @('two', 1) }
    $right = [pscustomobject]@{ array = @('two', 1); nested = [pscustomobject]@{ x = $null; y = $true }; a = 1234; z = "line1`nline2" }
    $leftJson = ConvertTo-LizardCanonicalJson $left
    $rightJson = ConvertTo-LizardCanonicalJson $right
    Assert-Equal $leftJson $rightJson 'Canonical JSON must be independent of property insertion order.'
    Assert-Equal '{"a":1234,"array":["two",1],"nested":{"x":null,"y":true},"z":"line1\nline2"}' $leftJson 'Canonical JSON must use invariant integers, sorted nested keys, and escaped newlines.'
    Assert-False ($leftJson -match "`r|`n") 'Canonical JSON must contain no formatting newlines.'
  } finally {
    [System.Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
  }

  $plan = New-TestPlan
  $writeResult = Write-LizardOperationPlan -Plan $plan -AuthorizedRoot $output -Path 'install-plan.json'
  Assert-True (Test-Path -LiteralPath $writeResult.path -PathType Leaf) 'Canonical plan write must create the approval file.'
  Assert-True (Test-Path -LiteralPath $writeResult.sha256_path -PathType Leaf) 'Canonical plan write must create a convenience digest sidecar.'
  Assert-Equal $writeResult.sha256 ((Get-Content -LiteralPath $writeResult.sha256_path -Raw).Trim()) 'Digest sidecar must contain the canonical plan SHA-256.'
  $writtenBytes = [System.IO.File]::ReadAllBytes($writeResult.path)
  Assert-False ($writtenBytes.Length -ge 3 -and $writtenBytes[0] -eq 0xEF -and $writtenBytes[1] -eq 0xBB -and $writtenBytes[2] -eq 0xBF) 'Approval file must be UTF-8 without BOM.'
  $approved = Read-LizardApprovedPlan -AuthorizedRoot $output -Path 'install-plan.json' -Sha256 $writeResult.sha256 -OperationKind install
  Assert-Equal $plan.plan_id $approved.plan_id 'Approved plan must survive canonical write/read roundtrip.'
  Assert-Equal $plan.intent_sha256 (Get-LizardPlanIntentSha256 -Plan $approved) 'Roundtrip intent must retain its canonical identity.'
  Push-Location $output
  try {
    $relativeApproved = Read-LizardApprovedPlan -Path 'install-plan.json' -Sha256 $writeResult.sha256 -OperationKind install
    Assert-Equal $plan.plan_id $relativeApproved.plan_id 'Relative approved-plan paths must resolve once from the current directory.'
  } finally {
    Pop-Location
  }
  Push-Location $fixture
  try {
    $nestedRelativeApproved = Read-LizardApprovedPlan -Path 'approved\install-plan.json' -Sha256 $writeResult.sha256 -OperationKind install
    Assert-Equal $plan.plan_id $nestedRelativeApproved.plan_id 'Nested relative approved-plan paths must not be appended twice.'
  } finally {
    Pop-Location
  }

  Assert-ThrowsCode { Read-LizardApprovedPlan -AuthorizedRoot $output -Path $writeResult.path -Sha256 ('0' * 64) -OperationKind install | Out-Null } 'PLAN_BINDING_DIGEST_MISMATCH' 'Wrong approval digest must fail closed.'
  Assert-ThrowsCode { Read-LizardApprovedPlan -AuthorizedRoot $output -Path $writeResult.path -Sha256 $writeResult.sha256 -OperationKind update | Out-Null } 'PLAN_BINDING_OPERATION_MISMATCH' 'Operation mismatch must fail closed.'

  $noncanonicalPath = Join-Path $output 'noncanonical.json'
  $noncanonical = (ConvertTo-LizardCanonicalJson $plan) + "`n"
  [System.IO.File]::WriteAllText($noncanonicalPath, $noncanonical, (New-Object System.Text.UTF8Encoding($false)))
  $noncanonicalHash = Get-LizardPlanSha256 -CanonicalJson $noncanonical
  Assert-ThrowsCode { Read-LizardApprovedPlan -AuthorizedRoot $output -Path $noncanonicalPath -Sha256 $noncanonicalHash -OperationKind install | Out-Null } 'PLAN_BINDING_NONCANONICAL' 'Edited noncanonical bytes must fail even when their supplied digest matches.'

  $expired = New-TestPlan -TtlMinutes 1
  $expiredPath = Join-Path $output 'expired.json'
  $expiredCanonical = ConvertTo-LizardCanonicalJson $expired
  [System.IO.File]::WriteAllText($expiredPath, $expiredCanonical, (New-Object System.Text.UTF8Encoding($false)))
  $afterExpiry = ([DateTimeOffset]::Parse([string]$expired.expires_at)).AddSeconds(1)
  Assert-ThrowsCode { Read-LizardApprovedPlan -AuthorizedRoot $output -Path $expiredPath -Sha256 (Get-LizardPlanSha256 -CanonicalJson $expiredCanonical) -OperationKind install -Now $afterExpiry | Out-Null } 'PLAN_BINDING_EXPIRED' 'Expired approval must fail closed.'

  $candidate = New-TestPlan -Profile 'regulated'
  Assert-ThrowsCode { Assert-LizardPlanIntentMatch -ApprovedPlan $plan -CandidatePlan $candidate | Out-Null } 'PLAN_BINDING_INTENT_MISMATCH' 'Candidate intent drift must fail closed.'
  $sameIntentCandidate = New-TestPlan
  Assert-Equal $plan.intent_sha256 (Assert-LizardPlanIntentMatch -ApprovedPlan $plan -CandidatePlan $sameIntentCandidate) 'Equivalent candidate intent must match despite a new plan ID and timestamp.'

  Write-Host 'PASS tests\unit\plan.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
