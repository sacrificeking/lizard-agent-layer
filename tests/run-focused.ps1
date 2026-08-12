[CmdletBinding()]
param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [ValidateRange(1, 64)][int]$ShardIndex = 1,
  [ValidateRange(1, 64)][int]$ShardCount = 1,
  [switch]$ListOnly
)

$ErrorActionPreference = 'Stop'
if ($ShardIndex -gt $ShardCount) { throw "FOCUSED_SHARD_INVALID: ShardIndex $ShardIndex exceeds ShardCount $ShardCount." }
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Host.psm1') -Force

$tests = @(
  'tests\unit\json.tests.ps1',
  'tests\unit\safe-fs.tests.ps1',
  'tests\unit\mount-boundary.tests.ps1',
  'tests\unit\host.tests.ps1',
  'tests\unit\plan.tests.ps1',
  'tests\unit\focused-sharding.tests.ps1',
  'tests\adversarial\install-plan-tamper.tests.ps1',
  'tests\adversarial\install-containment.tests.ps1',
  'tests\adversarial\report-privacy.tests.ps1',
  'tests\adversarial\quality-evidence.tests.ps1',
  'tests\adversarial\contract-governance.tests.ps1',
  'tests\integration\manifest-v3.tests.ps1',
  'tests\integration\manifest-lifecycle.tests.ps1',
  'tests\integration\install-plan-binding.tests.ps1',
  'tests\integration\update-plan-binding.tests.ps1',
  'tests\adversarial\version-gates.tests.ps1',
  'tests\integration\transaction.tests.ps1',
  'tests\integration\documentation-recovery.tests.ps1',
  'tests\integration\public-readiness.tests.ps1',
  'tests\integration\model-routing.tests.ps1',
  'tests\integration\loop-runtime.tests.ps1',
  'tests\adversarial\loop-evidence.tests.ps1'
)
$tests = @(
  for ($index = 0; $index -lt $tests.Count; $index++) {
    if (($index % $ShardCount) -eq ($ShardIndex - 1)) { $tests[$index] }
  }
)
if ($tests.Count -eq 0) { throw "FOCUSED_SHARD_EMPTY: Shard $ShardIndex of $ShardCount selects no tests." }
if ($ListOnly) {
  $tests | ForEach-Object { $_.Replace('\', '/') }
  exit 0
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($relative in $tests) {
  $path = Join-Path $LayerRoot $relative
  $started = Get-Date
  $result = Invoke-TestPowerShell -ScriptPath $path -Arguments @('-LayerRoot', $LayerRoot)
  $status = if ($result.exit_code -eq 0) { 'pass' } else { 'fail' }
  $results.Add([ordered]@{
    test = $relative.Replace('\', '/')
    status = $status
    exit_code = $result.exit_code
    seconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 3)
    output = $result.output.Trim()
  }) | Out-Null
  Write-Host ("{0} {1}" -f $status.ToUpperInvariant(), $relative)
  if ($result.output) { Write-Host $result.output.Trim() }
}

$reportDir = Initialize-SafeDirectory -Path (Join-Path $LayerRoot '.tmp\tests')
$reportName = if ($ShardCount -eq 1) { 'focused-test-report.json' } else { 'focused-test-report-shard-{0:D2}-of-{1:D2}.json' -f $ShardIndex, $ShardCount }
$reportPath = Join-Path $reportDir $reportName
$report = [ordered]@{
  schema_version = 2
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  host = [ordered]@{
    id = Get-LizardHostId
    powershell_edition = [string]$PSVersionTable.PSEdition
    powershell_version = [string]$PSVersionTable.PSVersion
  }
  tests = @($results.ToArray())
  passed = @($results | Where-Object { $_.status -eq 'pass' }).Count
  failed = @($results | Where-Object { $_.status -eq 'fail' }).Count
}
Set-SafeContent -AuthorizedRoot $reportDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 8)
Assert-JsonSchemaValid -LayerRoot $LayerRoot -SchemaPath 'schemas/focused-test-report.schema.json' -InstancePath $reportPath -Message 'Focused test report must satisfy its executable schema.'

if ($report.failed -gt 0) { exit 1 }
Write-Host "Focused safety tests passed for shard $ShardIndex of $ShardCount. Report: $reportPath"
