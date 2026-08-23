param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("uninstall-tamper-{0}" -f ([Guid]::NewGuid().ToString('N')))
$reports = Join-Path $fixture 'reports'
$script = Join-Path $LayerRoot 'scripts\uninstall.ps1'
New-Item -ItemType Directory -Path $reports -Force | Out-Null

function New-UninstallFixture {
  param([string]$Name)
  $root = Join-Path $fixture $Name
  $ownedDirectory = Join-Path $root '.agent\owned'
  $ownedFile = Join-Path $ownedDirectory 'owned.txt'
  New-Item -ItemType Directory -Path $ownedDirectory -Force | Out-Null
  Set-Content -LiteralPath $ownedFile -Value 'owned canary' -Encoding UTF8
  $hash = (Get-FileHash -LiteralPath $ownedFile -Algorithm SHA256).Hash.ToLowerInvariant()
  $manifest = [ordered]@{
    schema_version = 4; layer = 'lizard-agent-layer'; layer_version = '2.0.0'
    minimum_reader_schema_version = 4; writer_schema_version = 4; profile = 'minimal'; memory_mode = 'curated'; target_root = $root; harnesses = @('codex')
    artifacts = @(
      [ordered]@{ path = '.agent'; kind = 'directory'; lifecycle = 'active'; ownership = 'layer-owned'; state = 'layer-owned'; source_version = '2.0.0'; adapter_aliases = @() },
      [ordered]@{ path = '.agent/owned'; kind = 'directory'; lifecycle = 'active'; ownership = 'layer-owned'; state = 'layer-owned'; source_version = '2.0.0'; adapter_aliases = @() },
      [ordered]@{ path = '.agent/owned/owned.txt'; kind = 'file'; lifecycle = 'active'; ownership = 'layer-owned'; state = 'layer-owned'; source_version = '2.0.0'; installed_hash = $hash; current_hash = $hash; adapter_aliases = @() }
    )
  }
  Set-Content -LiteralPath (Join-Path $root '.agent\lizard-agent-layer.install.json') -Value ($manifest | ConvertTo-Json -Depth 10) -Encoding UTF8
  return [pscustomobject]@{ root = $root; owned_directory = $ownedDirectory; owned_file = $ownedFile; hash = $hash }
}

function New-ApprovedPreview {
  param($Target, [string]$Name)
  $markdown = Join-Path $reports ($Name + '.md')
  $preview = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $Target.root, '-PlanPath', $markdown)
  Assert-Equal 0 $preview.exit_code "Adversarial preview must succeed: $($preview.output)"
  $canonical = [System.IO.Path]::ChangeExtension($markdown, '.json')
  return [pscustomobject]@{ path = $canonical; sha256 = (Get-Content -LiteralPath ($canonical + '.sha256') -Raw).Trim() }
}

try {
  $recreated = New-UninstallFixture -Name 'recreated'
  $recreatedPlan = New-ApprovedPreview -Target $recreated -Name 'recreated'
  Remove-Item -LiteralPath $recreated.owned_file -Force
  Set-Content -LiteralPath $recreated.owned_file -Value 'owned canary' -Encoding UTF8
  Assert-Equal $recreated.hash ((Get-FileHash -LiteralPath $recreated.owned_file -Algorithm SHA256).Hash.ToLowerInvariant()) 'Recreated canary must retain identical bytes.'
  $recreatedApply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $recreated.root, '-Apply', '-ApprovedPlanPath', $recreatedPlan.path, '-ApprovedPlanSha256', $recreatedPlan.sha256, '-HumanApproved')
  Assert-False ($recreatedApply.exit_code -eq 0) 'Delete-and-recreate with identical bytes must fail physical identity binding.'
  Assert-True ($recreatedApply.output -match 'PLAN_BINDING_INTENT_MISMATCH|UNINSTALL_TARGET_IDENTITY_MISMATCH') 'Identity drift must expose a stable binding failure.'
  Assert-True (Test-Path -LiteralPath $recreated.owned_file -PathType Leaf) 'Rejected identity drift must preserve the recreated file.'

  $unknown = New-UninstallFixture -Name 'unknown-child'
  $unknownPlan = New-ApprovedPreview -Target $unknown -Name 'unknown-child'
  $unknownFile = Join-Path $unknown.owned_directory 'user-owned.txt'
  Set-Content -LiteralPath $unknownFile -Value 'user canary' -Encoding UTF8
  $unknownApply = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $unknown.root, '-Apply', '-ApprovedPlanPath', $unknownPlan.path, '-ApprovedPlanSha256', $unknownPlan.sha256, '-HumanApproved')
  Assert-False ($unknownApply.exit_code -eq 0) 'Unexpected content in an approved directory must stop removal.'
  Assert-True (Test-Path -LiteralPath $unknownFile -PathType Leaf) 'Unexpected user content must never be deleted.'
  Assert-True (Test-Path -LiteralPath $unknown.owned_file -PathType Leaf) 'Failed directory removal must roll back the previously deleted owned file.'
  Assert-Equal $unknown.hash ((Get-FileHash -LiteralPath $unknown.owned_file -Algorithm SHA256).Hash.ToLowerInvariant()) 'Rollback must restore the owned file exactly.'
  Assert-True (Test-Path -LiteralPath (Join-Path $unknown.root '.agent\lizard-agent-layer.install.json') -PathType Leaf) 'Rollback must restore the install manifest.'
  Assert-False (Test-Path -LiteralPath (Join-Path $unknown.root '.lizard-agent-layer.lock')) 'Rollback must clean the transaction lock.'
  Assert-False (Test-Path -LiteralPath (Join-Path $unknown.root '.lizard-agent-layer-transactions')) 'Rollback must clean transaction metadata.'

  Write-Host 'PASS tests\adversarial\uninstall-tamper.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
