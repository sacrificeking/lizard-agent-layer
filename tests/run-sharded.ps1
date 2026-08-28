param(
  [int]$Shards = [Math]::Min([Environment]::ProcessorCount, 6),
  [string]$LayerRoot = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
if (-not $LayerRoot) { $LayerRoot = Split-Path -Parent $PSScriptRoot }
if (-not $LayerRoot) { $LayerRoot = (Get-Location).Path }
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host " Lizard Agent Layer: Parallel Sharded Test Runner" -ForegroundColor Cyan
Write-Host " LayerRoot: $LayerRoot"
Write-Host " CPU Cores: $([Environment]::ProcessorCount) | Parallel Shards: $Shards"
Write-Host "================================================================" -ForegroundColor Cyan

Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Host.psm1') -Force
$PowerShellHost = Get-LizardPowerShellHostPath

$scriptPath = Join-Path $LayerRoot 'tests/run-focused.ps1'
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

$jobs = @()
for ($i = 1; $i -le $Shards; $i++) {
  $shardIndex = $i
  Write-Host "-> Launching Shard $shardIndex of $Shards in parallel..." -ForegroundColor Gray
  $job = Start-Job -ScriptBlock {
    param($HostPath, $Script, $Root, $TotalShards, $CurrentShard)
    & $HostPath -NoProfile -File $Script -LayerRoot $Root -ShardCount $TotalShards -ShardIndex $CurrentShard
    return [int]$LASTEXITCODE
  } -ArgumentList $PowerShellHost, $scriptPath, $LayerRoot, $Shards, $shardIndex
  $jobs += [ordered]@{ Shard = $shardIndex; Job = $job }
}

Write-Host "`nAll $Shards shards running in parallel. Waiting for completion..." -ForegroundColor Yellow

$allPassed = $true
$totalPassed = 0

foreach ($entry in $jobs) {
  $shard = $entry.Shard
  $job = $entry.Job
  $output = @(Receive-Job -Job $job -Wait)
  $shardExitCode = if ($output.Count -gt 0 -and $output[-1] -is [int]) { [int]$output[-1] } else { 1 }
  Remove-Job -Job $job -Force

  $textLines = @($output | Where-Object { $_ -isnot [int] })

  $reportPath = Join-Path $LayerRoot (".tmp/tests/focused-test-report-shard-{0:D2}-of-{1:D2}.json" -f $shard, $Shards)
  $reportPass = $false
  if (Test-Path -LiteralPath $reportPath -PathType Leaf) {
    try {
      $rep = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-LizardJson
      if ([int]$rep.failed -eq 0 -and [int]$rep.passed -gt 0) { $reportPass = $true }
    } catch {}
  }

  if ($shardExitCode -eq 0 -or $reportPass) {
    Write-Host "[PASS] Shard $shard/$Shards PASSED" -ForegroundColor Green
  } else {
    Write-Host "[FAIL] Shard $shard/$Shards FAILED (ExitCode: $shardExitCode)" -ForegroundColor Red
    if ($textLines) {
      $textLines | Where-Object { $_ -match 'FAIL|ASSERT|Error' } | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkRed }
    }
    $allPassed = $false
  }

  if ($textLines) {
    $passCount = ($textLines | Where-Object { $_ -match '^PASS ' }).Count
    $totalPassed += $passCount
  }
}

$stopwatch.Stop()
$elapsed = [Math]::Round($stopwatch.Elapsed.TotalSeconds, 1)

Write-Host "`n================================================================" -ForegroundColor Cyan
Write-Host " Summary: Parallel Test Run Completed in $elapsed seconds!" -ForegroundColor Cyan
Write-Host " Passed: $totalPassed test files across $Shards parallel shards" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
Write-Host " Status: $(if ($allPassed) { 'ALL TESTS PASSED' } else { 'FAILURES DETECTED' })" -ForegroundColor $(if ($allPassed) { 'Green' } else { 'Red' })
Write-Host "================================================================" -ForegroundColor Cyan

if (-not $allPassed) { exit 1 }
