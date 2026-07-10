param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force

$tests = @(
  'tests\unit\safe-fs.tests.ps1',
  'tests\adversarial\install-containment.tests.ps1',
  'tests\integration\manifest-v3.tests.ps1',
  'tests\adversarial\version-gates.tests.ps1'
)
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
$reportPath = Join-Path $reportDir 'focused-test-report.json'
$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  tests = @($results.ToArray())
  passed = @($results | Where-Object { $_.status -eq 'pass' }).Count
  failed = @($results | Where-Object { $_.status -eq 'fail' }).Count
}
Set-SafeContent -AuthorizedRoot $reportDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 8)

if ($report.failed -gt 0) { exit 1 }
Write-Host "Focused safety tests passed. Report: $reportPath"
