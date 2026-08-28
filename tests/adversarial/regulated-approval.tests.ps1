param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
$fixture = Join-Path $testRoot ("regulated-approval-{0}" -f ([Guid]::NewGuid().ToString('N')))
$routeScript = Join-Path $LayerRoot 'scripts/route-task.ps1'

try {
  foreach ($modelMode in @('inherit-current', 'inventory-routing')) {
    $target = Join-Path $fixture "$modelMode-target"
    New-Item -ItemType Directory -Path (Join-Path $target '.agent/routing') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $LayerRoot 'routing-policies/staged-balanced.json') -Destination (Join-Path $target '.agent/routing/policy.json')
    $profile = [ordered]@{ profile = 'minimal'; routingPolicy = 'staged-balanced'; modelMode = $modelMode }
    Set-Content -LiteralPath (Join-Path $target '.agent/project-profile.json') -Value ($profile | ConvertTo-Json -Depth 5)

    foreach ($phase in @('strategy', 'execution', 'verification')) {
      foreach ($risk in @('low', 'medium', 'high')) {
        $id = "regulated-$modelMode-$phase-$risk"
        $arguments = @('-TargetPath', $target, '-Phase', $phase, '-TaskClass', 'implementation', '-RiskLevel', $risk, '-DataClass', 'regulated', '-Signals', 'regulated-data,security-sensitive,repeated-verification-failure', '-AttemptCount', '999', '-AvailableModels', 'caller-selected-model', '-ReceiptId', $id, '-Json')
        $result = Invoke-TestPowerShell -ScriptPath $routeScript -Arguments $arguments
        Assert-Equal 0 $result.exit_code "Regulated route evaluation must return a review decision: $($result.output)"
        $receipt = $result.output | ConvertFrom-LizardJson
        Assert-Equal 'human-review' ([string]$receipt.decision) "Regulated $modelMode/$phase/$risk data must require human review without a trusted approval authority."
        Assert-True ($null -eq $receipt.route_id) 'Regulated human-review decision must not select a technical route.'
        Assert-True ($null -eq $receipt.selected_role) 'Regulated human-review decision must not select a role.'
        Assert-True ($null -eq $receipt.recommended_model) 'Regulated human-review decision must not recommend a model.'
        Assert-True ($null -eq $receipt.recommended_provider) 'Regulated human-review decision must not recommend a provider.'
        Assert-True (@($receipt.reason_codes) -contains 'REGULATED_APPROVAL_REQUIRED') 'Regulated review must expose the stable approval-required reason code.'
        Assert-True ((@($receipt.reason_codes) -contains 'HUMAN_REVIEW_SIGNAL') -eq $false) 'Caller signals must not replace the authoritative regulated-data decision code.'
        Assert-True ((@($receipt.reason_codes) -contains 'ATTEMPT_LIMIT_EXCEEDED') -eq $false) 'Attempt limits must not replace the authoritative regulated-data decision code.'
        if ($modelMode -eq 'inherit-current') {
          Assert-True (@($receipt.reason_codes) -contains 'REGULATED_RUNTIME_IDENTITY_UNAVAILABLE') 'Inherit-current review must expose the unavailable-identity reason code.'
        } else {
          Assert-True ((@($receipt.reason_codes) -contains 'REGULATED_RUNTIME_IDENTITY_UNAVAILABLE') -eq $false) 'Inventory mode must not claim that runtime identity is inherently unavailable.'
          Assert-True ((@($receipt.reason_codes) -contains 'INVENTORY_ROUTING_FAILED') -eq $false) 'Regulated review must occur before inventory routing is attempted.'
        }
      }
    }
  }

  $invalidTarget = Join-Path $fixture 'invalid-policy-target'
  New-Item -ItemType Directory -Path (Join-Path $invalidTarget '.agent/routing') -Force | Out-Null
  $invalidPolicy = Get-Content -LiteralPath (Join-Path $LayerRoot 'routing-policies/staged-balanced.json') -Raw | ConvertFrom-LizardJson
  $invalidPolicy.regulated_data.default_decision = 'route'
  Set-Content -LiteralPath (Join-Path $invalidTarget '.agent/routing/policy.json') -Value ($invalidPolicy | ConvertTo-Json -Depth 20)
  Set-Content -LiteralPath (Join-Path $invalidTarget '.agent/project-profile.json') -Value (([ordered]@{ profile = 'minimal'; routingPolicy = 'staged-balanced'; modelMode = 'inherit-current' }) | ConvertTo-Json -Depth 5)
  $doctor = Invoke-TestPowerShell -ScriptPath (Join-Path $LayerRoot 'scripts/doctor.ps1') -Arguments @('-TargetPath', $invalidTarget, '-Strict')
  Assert-False ($doctor.exit_code -eq 0) 'Doctor must reject a policy that weakens the regulated-data default.'
  Assert-True ($doctor.output -match 'REGULATED_POLICY_INVALID') 'Doctor must expose the stable regulated-policy failure code.'

  Write-Host 'PASS tests\adversarial\regulated-approval.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
