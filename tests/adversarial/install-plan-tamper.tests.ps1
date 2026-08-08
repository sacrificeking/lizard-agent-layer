param([string]$LayerRoot)

$ErrorActionPreference = 'Stop'
$RepoRoot = if ([string]::IsNullOrWhiteSpace($LayerRoot)) { Split-Path -Parent (Split-Path -Parent $PSScriptRoot) } else { (Resolve-Path -LiteralPath $LayerRoot).Path }
Import-Module (Join-Path $RepoRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $RepoRoot 'scripts\Lizard.Plan.psm1') -Force

$fixtureRoot = Join-Path $RepoRoot '.tmp\tests\install-plan-tamper'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$installScript = Join-Path $RepoRoot 'scripts\install.ps1'

function Write-TamperedPlan {
  param($Plan, [string]$Path)
  $canonical = ConvertTo-LizardCanonicalJson $Plan
  [System.IO.File]::WriteAllText($Path, $canonical, (New-Object System.Text.UTF8Encoding($false)))
  return Get-LizardPlanSha256 -CanonicalJson $canonical
}

function Invoke-TamperedInstallPlan {
  param([string]$Target, [scriptblock]$Mutate, [string]$CaseName)
  New-Item -ItemType Directory -Path $Target -Force | Out-Null
  $approval = New-TestInstallApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $Target, '-Profile', 'minimal')
  $plan = Get-Content -LiteralPath $approval.plan_path -Raw | ConvertFrom-Json
  & $Mutate $plan
  $tamperedPath = Join-Path $fixtureRoot ("{0}.json" -f $CaseName)
  $tamperedSha256 = Write-TamperedPlan -Plan $plan -Path $tamperedPath
  return Invoke-TestPowerShell -ScriptPath $installScript -Arguments @(
    '-TargetPath', $Target, '-Profile', 'minimal', '-Apply',
    '-ApprovedPlanPath', $tamperedPath, '-ApprovedPlanSha256', $tamperedSha256, '-HumanApproved'
  )
}

try {
  $target = Join-Path $fixtureRoot 'unbound-apply'
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  Set-Content -LiteralPath (Join-Path $target 'sentinel.txt') -Value 'preserve-me'
  $before = (Get-FileHash -LiteralPath (Join-Path $target 'sentinel.txt') -Algorithm SHA256).Hash

  $result = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Apply')
  Assert-False ($result.exit_code -eq 0) 'Apply without an externally supplied approved plan must fail closed.'
  Assert-True ($result.output -match 'PLAN_APPROVAL_REQUIRED') 'Unbound apply must expose PLAN_APPROVAL_REQUIRED.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer.lock')) 'Rejected apply must not acquire a transaction lock.'
  Assert-False (Test-Path -LiteralPath (Join-Path $target '.lizard-agent-layer-transactions')) 'Rejected apply must not create transaction metadata.'
  Assert-Equal $before ((Get-FileHash -LiteralPath (Join-Path $target 'sentinel.txt') -Algorithm SHA256).Hash) 'Rejected apply must preserve the target.'

  $boundTarget = Join-Path $fixtureRoot 'bound-target'
  New-Item -ItemType Directory -Path $boundTarget -Force | Out-Null
  $approval = New-TestInstallApprovalArguments -LayerRoot $RepoRoot -BaseArguments @('-TargetPath', $boundTarget, '-Profile', 'minimal')
  $approvedPlan = Get-Content -LiteralPath $approval.plan_path -Raw | ConvertFrom-Json
  $headOutput = @(& git -C $RepoRoot rev-parse --verify HEAD 2>$null)
  $headExit = $LASTEXITCODE
  Assert-Equal 0 $headExit 'Test repository HEAD must be readable.'
  Assert-Equal ([string]$headOutput[0]).Trim().ToLowerInvariant() ([string]$approvedPlan.intent.source_git_head) 'Generated install plan must bind the current source Git HEAD.'
  $wrongDigest = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@('-TargetPath', $boundTarget, '-Profile', 'minimal', '-Apply', '-ApprovedPlanPath', $approval.plan_path, '-ApprovedPlanSha256', ('0' * 64), '-HumanApproved'))
  Assert-False ($wrongDigest.exit_code -eq 0) 'Wrong independently supplied digest must fail closed.'
  Assert-True ($wrongDigest.output -match 'PLAN_BINDING_DIGEST_MISMATCH') 'Wrong digest must expose a stable binding code.'

  $actionResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'action-tamper') -CaseName 'action-tamper' -Mutate {
    param($plan)
    $entry = @($plan.intent.target_entries | Where-Object { $_.action -eq 'create' } | Select-Object -First 1)[0]
    $entry.action = 'preserve'
    $plan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $plan.intent
  }
  Assert-False ($actionResult.exit_code -eq 0) 'Canonically redigested target-action tampering must fail closed.'
  Assert-True ($actionResult.output -match 'PLAN_BINDING_INTENT_MISMATCH') 'Target-action tampering must expose an intent mismatch.'
  Assert-False (Test-Path -LiteralPath (Join-Path $fixtureRoot 'action-tamper\.lizard-agent-layer.lock')) 'Target-action rejection must occur before lock acquisition.'

  $ownershipResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'ownership-tamper') -CaseName 'ownership-tamper' -Mutate {
    param($plan)
    $entry = @($plan.intent.target_entries | Select-Object -First 1)[0]
    $entry.ownership = 'layer-owned'
    $plan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $plan.intent
  }
  Assert-False ($ownershipResult.exit_code -eq 0) 'Canonically redigested ownership tampering must fail closed.'
  Assert-True ($ownershipResult.output -match 'PLAN_BINDING_INTENT_MISMATCH') 'Ownership tampering must expose an intent mismatch.'

  $intendedResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'intended-hash-tamper') -CaseName 'intended-hash-tamper' -Mutate {
    param($plan)
    $entry = @($plan.intent.target_entries | Where-Object { $null -ne $_.intended_sha256 } | Select-Object -First 1)[0]
    $entry.intended_sha256 = ('f' * 64)
    $plan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $plan.intent
  }
  Assert-False ($intendedResult.exit_code -eq 0) 'Canonically redigested intended-output tampering must fail closed.'
  Assert-True ($intendedResult.output -match 'PLAN_BINDING_INTENT_MISMATCH') 'Intended-output tampering must expose an intent mismatch.'

  $headResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'head-tamper') -CaseName 'head-tamper' -Mutate {
    param($plan)
    $plan.intent.source_git_head = ('0' * 40)
    $plan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $plan.intent
  }
  Assert-False ($headResult.exit_code -eq 0) 'Canonically redigested source-HEAD tampering must fail closed.'
  Assert-True ($headResult.output -match 'PLAN_BINDING_SOURCE_MISMATCH|PLAN_BINDING_INTENT_MISMATCH') 'Source-HEAD tampering must expose a binding mismatch.'

  $optionResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'option-tamper') -CaseName 'option-tamper' -Mutate {
    param($plan)
    $plan.intent.options.force = $true
    $plan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $plan.intent
  }
  Assert-False ($optionResult.exit_code -eq 0) 'Canonically redigested option tampering must fail closed.'
  Assert-True ($optionResult.output -match 'PLAN_BINDING_OPTIONS_MISMATCH') 'Option tampering must expose an options mismatch.'

  $inputResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'input-tamper') -CaseName 'input-tamper' -Mutate {
    param($plan)
    $entry = @($plan.intent.inputs | Where-Object scope -eq 'layer' | Select-Object -First 1)[0]
    $entry.sha256 = ('0' * 64)
    $plan.intent_sha256 = Get-LizardPlanIntentSha256 -Intent $plan.intent
  }
  Assert-False ($inputResult.exit_code -eq 0) 'Canonically redigested source-input tampering must fail closed.'
  Assert-True ($inputResult.output -match 'PLAN_BINDING_INPUT_MISMATCH') 'Source-input tampering must expose an input mismatch.'

  $expiredResult = Invoke-TamperedInstallPlan -Target (Join-Path $fixtureRoot 'expired-plan') -CaseName 'expired-plan' -Mutate {
    param($plan)
    $created = [DateTimeOffset]::Parse([string]$plan.created_at, [System.Globalization.CultureInfo]::InvariantCulture)
    $plan.expires_at = $created.AddMilliseconds(1).ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
  }
  Assert-False ($expiredResult.exit_code -eq 0) 'Expired plan must fail through the install entrypoint.'
  Assert-True ($expiredResult.output -match 'PLAN_BINDING_EXPIRED') "Expired entrypoint plan must expose PLAN_BINDING_EXPIRED. Output: $($expiredResult.output)"

  $internalBypass = Invoke-TestPowerShell -ScriptPath $installScript -Arguments (@($approval.arguments) + '-InternalPlanProbe')
  Assert-False ($internalBypass.exit_code -eq 0) 'Internal plan-probe switch must not bypass a plan-bound apply.'
  Assert-True ($internalBypass.output -match 'PLAN_BINDING_INTERNAL_BYPASS') 'Internal plan-probe apply must expose a stable bypass code.'
  Assert-False (Test-Path -LiteralPath (Join-Path $boundTarget '.lizard-agent-layer.lock')) 'Internal bypass rejection must occur before lock acquisition.'

  Set-Content -LiteralPath (Join-Path $boundTarget 'AGENTS.md') -Value 'created-after-approval'
  $drifted = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $approval.arguments
  Assert-False ($drifted.exit_code -eq 0) 'Target drift after approval must fail closed.'
  Assert-True ($drifted.output -match 'PLAN_BINDING_TARGET_MISMATCH') 'Target drift must expose a stable binding code.'
  Assert-False (Test-Path -LiteralPath (Join-Path $boundTarget '.lizard-agent-layer.lock')) 'Drift rejection must occur before lock acquisition.'
  Assert-False (Test-Path -LiteralPath (Join-Path $boundTarget '.agent')) 'Drift rejection must not install target artifacts.'

  Write-Host 'PASS tests\adversarial\install-plan-tamper.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $RepoRoot '.tmp') }
}
