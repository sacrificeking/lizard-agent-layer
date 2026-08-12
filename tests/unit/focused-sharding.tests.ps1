param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$runner = Join-Path $LayerRoot 'tests\run-focused.ps1'

function Get-ListedFocusedTests {
  param([int]$ShardIndex = 1, [int]$ShardCount = 1)
  $result = Invoke-TestPowerShell -ScriptPath $runner -Arguments @(
    '-LayerRoot', $LayerRoot,
    '-ShardIndex', ([string]$ShardIndex),
    '-ShardCount', ([string]$ShardCount),
    '-ListOnly'
  )
  Assert-Equal 0 $result.exit_code "Focused test listing failed for shard $ShardIndex of $ShardCount`: $($result.output)"
  return @($result.output -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

$all = @(Get-ListedFocusedTests)
Assert-True ($all.Count -gt 0) 'The focused test catalog must not be empty.'
Assert-Equal $all.Count @($all | Sort-Object -Unique).Count 'The focused test catalog must not contain duplicate paths.'

$members = New-Object System.Collections.Generic.List[string]
for ($shard = 1; $shard -le 6; $shard++) {
  $selected = @(Get-ListedFocusedTests -ShardIndex $shard -ShardCount 6)
  Assert-True ($selected.Count -gt 0) "Focused shard $shard of 6 must not be empty."
  foreach ($test in $selected) { $members.Add($test) | Out-Null }
}

Assert-Equal $all.Count $members.Count 'Six focused shards must contain exactly the full catalog size.'
Assert-Equal $all.Count @($members | Sort-Object -Unique).Count 'Focused shards must be pairwise disjoint.'
Assert-Equal (($all | Sort-Object) -join "`n") (($members | Sort-Object) -join "`n") 'Focused shards must cover the full catalog.'

$first = @(Get-ListedFocusedTests -ShardIndex 1 -ShardCount 6)
$firstRepeat = @(Get-ListedFocusedTests -ShardIndex 1 -ShardCount 6)
Assert-Equal ($first -join "`n") ($firstRepeat -join "`n") 'Focused shard selection must be deterministic.'

$invalid = Invoke-TestPowerShell -ScriptPath $runner -Arguments @('-LayerRoot', $LayerRoot, '-ShardIndex', '7', '-ShardCount', '6', '-ListOnly')
Assert-False ($invalid.exit_code -eq 0) 'A focused shard index above the shard count must fail closed.'
Assert-True ($invalid.output -match 'FOCUSED_SHARD_INVALID') 'An invalid focused shard selection must expose a stable failure code.'

Write-Host 'PASS tests\unit\focused-sharding.tests.ps1'
