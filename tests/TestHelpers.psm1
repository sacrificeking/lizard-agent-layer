Set-StrictMode -Version 2.0

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ASSERT_TRUE_FAILED: $Message" }
}

function Assert-False {
  param([bool]$Condition, [string]$Message)
  if ($Condition) { throw "ASSERT_FALSE_FAILED: $Message" }
}

function Assert-Equal {
  param($Expected, $Actual, [string]$Message)
  if ($Expected -ne $Actual) { throw "ASSERT_EQUAL_FAILED: $Message Expected '$Expected', got '$Actual'." }
}

function Assert-ThrowsCode {
  param([scriptblock]$Action, [string]$Code, [string]$Message)
  try {
    & $Action
  } catch {
    if ($_.Exception.Message -match [regex]::Escape($Code)) { return }
    throw "ASSERT_THROWS_CODE_FAILED: $Message Expected '$Code', got '$($_.Exception.Message)'."
  }
  throw "ASSERT_THROWS_CODE_FAILED: $Message Expected '$Code', but no exception was thrown."
}

function Test-LizardWindows {
  if ($PSVersionTable.ContainsKey('Platform')) { return $PSVersionTable['Platform'] -eq 'Win32NT' }
  return $true
}

function New-DirectoryLink {
  param([string]$Path, [string]$Target)
  $itemType = if (Test-LizardWindows) { 'Junction' } else { 'SymbolicLink' }
  New-Item -ItemType $itemType -Path $Path -Target $Target -Force | Out-Null
}

function Remove-DirectoryLink {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if (Test-LizardWindows) { [System.IO.Directory]::Delete($Path) }
  else { Remove-Item -LiteralPath $Path -Force }
}

function Get-CurrentPowerShellPath {
  $process = Get-Process -Id $PID
  if ($process.Path) { return $process.Path }
  if (Test-LizardWindows) { return (Join-Path $PSHOME 'powershell.exe') }
  return (Join-Path $PSHOME 'pwsh')
}

function Invoke-TestPowerShell {
  param([string]$ScriptPath, [string[]]$Arguments)
  $hostPath = Get-CurrentPowerShellPath
  $invokeArgs = @('-NoProfile')
  if (Test-LizardWindows) { $invokeArgs += @('-ExecutionPolicy', 'Bypass') }
  $invokeArgs += @('-File', $ScriptPath)
  $invokeArgs += @($Arguments)
  $global:LASTEXITCODE = 0
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $hostPath @invokeArgs 2>&1 | Out-String
    $exitCode = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  return [pscustomobject]@{ exit_code = $exitCode; output = $output }
}

function New-TestInstallApprovalArguments {
  param(
    [Parameter(Mandatory = $true)][string]$LayerRoot,
    [Parameter(Mandatory = $true)][string[]]$BaseArguments
  )
  if (@($BaseArguments) -contains '-Apply') { throw 'TEST_PLAN_ARGUMENTS_INVALID: BaseArguments must describe preview, not apply.' }
  $LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
  $planRoot = Join-Path $LayerRoot '.tmp\tests\approved-plans'
  New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
  $planPath = Join-Path $planRoot ("install-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
  $installScript = Join-Path $LayerRoot 'scripts\install.ps1'
  $previewArguments = @($BaseArguments) + @('-CanonicalPlanPath', $planPath)
  $preview = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $previewArguments
  if ($preview.exit_code -ne 0) { throw "TEST_PLAN_PREVIEW_FAILED: $($preview.output)" }
  if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "TEST_PLAN_MISSING: $planPath" }
  $sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $planDoc = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $planPath -Raw)
  $target = [string]$planDoc.intent.target_root
  
  Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Plan.psm1') -Global -Force
  $targetIdentity = Get-LizardPlanRootHash -TargetRoot $target
  
  $riskLevel = 'low'
  if ($planDoc.intent.options.PSObject.Properties['risk_level']) {
    $riskLevel = [string]$planDoc.intent.options.risk_level
  } elseif ($planDoc.intent.options.profile -eq 'enterprise-fullstack') {
    $riskLevel = 'high'
  }
  
  $isForce = (@($BaseArguments) -contains '-Force')
  $isForceManaged = (@($BaseArguments) -contains '-ForceManaged')
  $isRequireSigned = (@($BaseArguments) -contains '-RequireSignedApproval')
  $policy = Get-LizardOperationApprovalPolicy -OperationKind 'install' -RiskLevel $riskLevel -Profile ([string]$planDoc.intent.options.profile) -Force:$isForce -ForceManaged:$isForceManaged -RequireSignedApproval:$isRequireSigned

  $finalArgs = @($BaseArguments) + @('-Apply', '-ApprovedPlanPath', $planPath, '-ApprovedPlanSha256', $sha256, '-HumanApproved')

  if ($policy.signed_approval_required) {
    Import-Module (Join-Path $LayerRoot 'tests\TestTrustHelpers.psm1') -Global -Force
    Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Trust.psm1') -Global -Force

    $trustRoot = Join-Path $LayerRoot ('.tmp\tests\trust-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $trustRoot -Force | Out-Null
    $now = [DateTimeOffset]::UtcNow
    $purpose = 'install-apply-approval'
    $trust = New-LizardTestTrustMaterial -Root $trustRoot -BindingSha256 $sha256 -Subject $targetIdentity -Now $now -PrincipalId 'test-operator' -Roles @('operator') -Purpose $purpose -PayloadKind 'operation-plan'

    $envelope = New-LizardSignedEvidenceEnvelope `
      -Payload $planDoc `
      -PayloadKind 'operation-plan' `
      -Purpose $purpose `
      -Subject $targetIdentity `
      -BindingSha256 $sha256 `
      -ChallengePath $trust.challenge_path `
      -ChallengeSha256 $trust.challenge_sha256 `
      -PrivateKeyPath $trust.private_key_path `
      -PrivateKeySha256 $trust.private_key_sha256 `
      -Now $now

    $envelopePath = Join-Path $trustRoot 'approval-envelope.json'
    [System.IO.File]::WriteAllText($envelopePath, ($envelope | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))

    $finalArgs += @(
      '-RequireSignedApproval',
      '-ApprovalEnvelopePath', $envelopePath,
      '-TrustStorePath', $trust.trust_store_path,
      '-TrustStoreSha256', $trust.trust_store_sha256,
      '-ChallengePath', $trust.challenge_path,
      '-ChallengeSha256', $trust.challenge_sha256,
      '-ReplayLedgerPath', $trust.replay_ledger_path
    )
  }

  return [pscustomobject]@{
    plan_path = $planPath
    sha256 = $sha256
    preview = $preview
    arguments = $finalArgs
  }
}

function New-TestUpdateApprovalArguments {
  param(
    [Parameter(Mandatory = $true)][string]$LayerRoot,
    [Parameter(Mandatory = $true)][string[]]$BaseArguments
  )
  if (@($BaseArguments) -contains '-Apply') { throw 'TEST_PLAN_ARGUMENTS_INVALID: BaseArguments must describe preview, not apply.' }
  $LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
  $planRoot = Join-Path $LayerRoot '.tmp\tests\approved-plans'
  New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
  $planPath = Join-Path $planRoot ("update-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
  $updateScript = Join-Path $LayerRoot 'scripts\update-target.ps1'
  $preview = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments (@($BaseArguments) + @('-CanonicalPlanPath', $planPath))
  if ($preview.exit_code -ne 0) { throw "TEST_UPDATE_PLAN_PREVIEW_FAILED: $($preview.output)" }
  if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "TEST_UPDATE_PLAN_MISSING: $planPath" }
  $sha256 = (Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash.ToLowerInvariant()
  
  $planDoc = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $planPath -Raw)
  $target = [string]$planDoc.intent.target_root
  
  Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Plan.psm1') -Global -Force
  $targetIdentity = Get-LizardPlanRootHash -TargetRoot $target

  $isForce = (@($BaseArguments) -contains '-Force')
  $isForceManaged = (@($BaseArguments) -contains '-ForceManaged')
  $isRequireSigned = (@($BaseArguments) -contains '-RequireSignedApproval')
  $policy = Get-LizardOperationApprovalPolicy -OperationKind 'update' -RiskLevel 'medium' -Force:$isForce -ForceManaged:$isForceManaged -RequireSignedApproval:$isRequireSigned

  $finalArgs = @($BaseArguments) + @('-Apply', '-ApprovedPlanPath', $planPath, '-ApprovedPlanSha256', $sha256, '-HumanApproved')

  if ($policy.signed_approval_required) {
    Import-Module (Join-Path $LayerRoot 'tests\TestTrustHelpers.psm1') -Global -Force
    Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Trust.psm1') -Global -Force

    $trustRoot = Join-Path $LayerRoot ('.tmp\tests\trust-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $trustRoot -Force | Out-Null
    $now = [DateTimeOffset]::UtcNow
    $purpose = 'update-apply-approval'
    $trust = New-LizardTestTrustMaterial -Root $trustRoot -BindingSha256 $sha256 -Subject $targetIdentity -Now $now -PrincipalId 'test-operator' -Roles @('operator') -Purpose $purpose -PayloadKind 'operation-plan'

    $envelope = New-LizardSignedEvidenceEnvelope `
      -Payload $planDoc `
      -PayloadKind 'operation-plan' `
      -Purpose $purpose `
      -Subject $targetIdentity `
      -BindingSha256 $sha256 `
      -ChallengePath $trust.challenge_path `
      -ChallengeSha256 $trust.challenge_sha256 `
      -PrivateKeyPath $trust.private_key_path `
      -PrivateKeySha256 $trust.private_key_sha256 `
      -Now $now

    $envelopePath = Join-Path $trustRoot 'approval-envelope.json'
    [System.IO.File]::WriteAllText($envelopePath, ($envelope | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))

    $finalArgs += @(
      '-RequireSignedApproval',
      '-ApprovalEnvelopePath', $envelopePath,
      '-TrustStorePath', $trust.trust_store_path,
      '-TrustStoreSha256', $trust.trust_store_sha256,
      '-ChallengePath', $trust.challenge_path,
      '-ChallengeSha256', $trust.challenge_sha256,
      '-ReplayLedgerPath', $trust.replay_ledger_path
    )
  }

  return [pscustomobject]@{
    plan_path = $planPath
    sha256 = $sha256
    preview = $preview
    arguments = $finalArgs
  }
}

function New-TestUninstallApprovalArguments {
  param(
    [Parameter(Mandatory = $true)][string]$LayerRoot,
    [Parameter(Mandatory = $true)][string[]]$BaseArguments
  )
  if (@($BaseArguments) -contains '-Apply') { throw 'TEST_PLAN_ARGUMENTS_INVALID: BaseArguments must describe preview, not apply.' }
  $LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
  
  $planPath = $null
  for ($i = 0; $i -lt $BaseArguments.Length; $i++) {
    if ($BaseArguments[$i] -eq '-PlanPath' -and ($i + 1) -lt $BaseArguments.Length) {
      $planPath = $BaseArguments[$i + 1]
      break
    }
    if ($BaseArguments[$i] -eq '-CanonicalPlanPath' -and ($i + 1) -lt $BaseArguments.Length) {
      $planPath = $BaseArguments[$i + 1]
      break
    }
  }

  $previewArgs = @($BaseArguments)
  if ([string]::IsNullOrWhiteSpace($planPath)) {
    $planRoot = Join-Path $LayerRoot '.tmp\tests\approved-plans'
    New-Item -ItemType Directory -Path $planRoot -Force | Out-Null
    $planPath = Join-Path $planRoot ("uninstall-{0}.json" -f ([Guid]::NewGuid().ToString('N')))
    $previewArgs += @('-CanonicalPlanPath', $planPath)
  }
  
  $uninstallScript = Join-Path $LayerRoot 'scripts\uninstall.ps1'
  $preview = Invoke-TestPowerShell -ScriptPath $uninstallScript -Arguments $previewArgs
  if ($preview.exit_code -ne 0) { throw "TEST_UNINSTALL_PLAN_PREVIEW_FAILED: $($preview.output)" }

  $canonicalJsonPath = if ($planPath.EndsWith('.json', [System.StringComparison]::OrdinalIgnoreCase)) { $planPath } else { [System.IO.Path]::ChangeExtension($planPath, '.json') }
  if (-not (Test-Path -LiteralPath $canonicalJsonPath -PathType Leaf)) { throw "TEST_UNINSTALL_PLAN_MISSING: $canonicalJsonPath" }
  $sha256 = (Get-FileHash -LiteralPath $canonicalJsonPath -Algorithm SHA256).Hash.ToLowerInvariant()
  
  $planDoc = ConvertFrom-LizardJson -InputObject (Get-Content -LiteralPath $canonicalJsonPath -Raw)
  $target = [string]$planDoc.intent.target_root
  $scope = [string]$planDoc.intent.options.scope
  
  Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Plan.psm1') -Global -Force
  $targetIdentity = Get-LizardPlanRootHash -TargetRoot $target

  $isRequireSigned = (@($BaseArguments) -contains '-RequireSignedApproval')
  $policy = Get-LizardOperationApprovalPolicy -OperationKind 'uninstall' -RiskLevel 'medium' -Scope $scope -RequireSignedApproval:$isRequireSigned

  $finalArgs = @($BaseArguments) + @('-Apply', '-ApprovedPlanPath', $canonicalJsonPath, '-ApprovedPlanSha256', $sha256, '-HumanApproved')

  if ($policy.signed_approval_required) {
    Import-Module (Join-Path $LayerRoot 'tests\TestTrustHelpers.psm1') -Global -Force
    Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Trust.psm1') -Global -Force

    $trustRoot = Join-Path $LayerRoot ('.tmp\tests\trust-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $trustRoot -Force | Out-Null
    $now = [DateTimeOffset]::UtcNow
    $purpose = 'uninstall-apply-approval'
    $trust = New-LizardTestTrustMaterial -Root $trustRoot -BindingSha256 $sha256 -Subject $targetIdentity -Now $now -PrincipalId 'test-operator' -Roles @('operator') -Purpose $purpose -PayloadKind 'operation-plan'

    $envelope = New-LizardSignedEvidenceEnvelope `
      -Payload $planDoc `
      -PayloadKind 'operation-plan' `
      -Purpose $purpose `
      -Subject $targetIdentity `
      -BindingSha256 $sha256 `
      -ChallengePath $trust.challenge_path `
      -ChallengeSha256 $trust.challenge_sha256 `
      -PrivateKeyPath $trust.private_key_path `
      -PrivateKeySha256 $trust.private_key_sha256 `
      -Now $now

    $envelopePath = Join-Path $trustRoot 'approval-envelope.json'
    [System.IO.File]::WriteAllText($envelopePath, ($envelope | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))

    $finalArgs += @(
      '-RequireSignedApproval',
      '-ApprovalEnvelopePath', $envelopePath,
      '-TrustStorePath', $trust.trust_store_path,
      '-TrustStoreSha256', $trust.trust_store_sha256,
      '-ChallengePath', $trust.challenge_path,
      '-ChallengeSha256', $trust.challenge_sha256,
      '-ReplayLedgerPath', $trust.replay_ledger_path
    )
  }

  return [pscustomobject]@{
    plan_path = $planPath
    sha256 = $sha256
    preview = $preview
    arguments = $finalArgs
  }
}

function Assert-JsonSchemaValid {
  param(
    [string]$LayerRoot,
    [string]$SchemaPath,
    [string]$InstancePath,
    [string]$Message
  )
  $resolvedRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
  $resolvedInstance = (Resolve-Path -LiteralPath $InstancePath).Path
  $comparison = if (Test-LizardWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
  $rootPrefix = $resolvedRoot.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $resolvedInstance.StartsWith($rootPrefix, $comparison)) {
    throw "SCHEMA_TEST_INSTANCE_OUTSIDE_ROOT: $resolvedInstance"
  }
  $relativeInstance = $resolvedInstance.Substring($rootPrefix.Length).Replace('\', '/')
  $validatorPath = Join-Path $resolvedRoot 'tools\schema-validator\validate.mjs'
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { throw 'SCHEMA_TEST_NODE_MISSING: Node.js is required for executable contract tests.' }
  $output = & $node.Source $validatorPath --root $resolvedRoot --schema $SchemaPath --instance $relativeInstance 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "ASSERT_SCHEMA_VALID_FAILED: $Message $output" }
}

function Clear-TestDirectory {
  param([string]$Path, [string]$AllowedRoot, [string[]]$Links = @())
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char[]]@('\', '/'))
  $comparison = if (Test-LizardWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
  if (-not $fullPath.StartsWith(($fullRoot + [System.IO.Path]::DirectorySeparatorChar), $comparison)) {
    throw "TEST_CLEANUP_OUTSIDE_ROOT: $fullPath"
  }
  foreach ($link in @($Links)) { Remove-DirectoryLink -Path $link }
  if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Recurse -Force }
}

$layerRootForJson = Split-Path -Parent $PSScriptRoot
if (Test-Path (Join-Path $layerRootForJson 'scripts\Lizard.Json.psm1')) {
  Import-Module (Join-Path $layerRootForJson 'scripts\Lizard.Json.psm1') -Force
}

function ConvertFrom-TestJson {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)][AllowEmptyString()][string]$InputObject
  )
  process {
    ConvertFrom-LizardJson -InputObject $InputObject
  }
}

Export-ModuleMember -Function @(
  'Assert-Equal', 'Assert-False', 'Assert-JsonSchemaValid', 'Assert-ThrowsCode', 'Assert-True',
  'Clear-TestDirectory', 'Get-CurrentPowerShellPath', 'Invoke-TestPowerShell',
  'New-DirectoryLink', 'New-TestInstallApprovalArguments', 'New-TestUpdateApprovalArguments', 'New-TestUninstallApprovalArguments', 'Remove-DirectoryLink', 'Test-LizardWindows',
  'ConvertFrom-LizardJson', 'ConvertFrom-TestJson'
)
