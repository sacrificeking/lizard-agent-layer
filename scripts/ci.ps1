param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$SkipSmoke,
  [switch]$SkipMatrix,
  [switch]$SkipQuality,
  [switch]$StrictGitStatus
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$StartedAt = Get-Date
$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param([string]$Name, [string]$Status, [int]$ExitCode, [double]$Seconds)
  $Results.Add([ordered]@{ name = $Name; status = $Status; exit_code = $ExitCode; seconds = [Math]::Round($Seconds, 3) }) | Out-Null
}

function Invoke-CiStep {
  param([string]$Name, [scriptblock]$Block)
  Write-Host "== $Name =="
  $stepStart = Get-Date
  try {
    & $Block
    $exitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
    if ($exitCode -ne 0) { throw "$Name exited with code $exitCode." }
    Add-Result -Name $Name -Status 'pass' -ExitCode 0 -Seconds (((Get-Date) - $stepStart).TotalSeconds)
    Write-Host "PASS $Name"
  } catch {
    Add-Result -Name $Name -Status 'fail' -ExitCode 1 -Seconds (((Get-Date) - $stepStart).TotalSeconds)
    Write-Host "FAIL $Name"
    Write-Host $_.Exception.Message
    throw
  }
  Write-Host ""
}

Write-Host "lizard-agent-layer CI"
Write-Host "Layer: $LayerRoot"
Write-Host "SkipSmoke: $($SkipSmoke.IsPresent)"
Write-Host "SkipMatrix: $($SkipMatrix.IsPresent)"
Write-Host "SkipQuality: $($SkipQuality.IsPresent)"
Write-Host "StrictGitStatus: $($StrictGitStatus.IsPresent)"
Write-Host ""

Invoke-CiStep 'validate' {
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\validate.ps1') -LayerRoot $LayerRoot
}

if (-not $SkipQuality) {
  Invoke-CiStep 'quality' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\score-layer.ps1') -LayerRoot $LayerRoot -Strict
  }
}

if (-not $SkipSmoke) {
  Invoke-CiStep 'smoke' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'tests\smoke.ps1') -LayerRoot $LayerRoot
  }
}

if (-not $SkipMatrix) {
  Invoke-CiStep 'matrix' {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $LayerRoot 'scripts\matrix.ps1') -LayerRoot $LayerRoot
  }
}

if ($StrictGitStatus) {
  Invoke-CiStep 'git status' {
    $status = & git -C $LayerRoot status --short
    if ($status) { Write-Host $status; throw 'Working tree is not clean.' }
  }
}

$Duration = ((Get-Date) - $StartedAt).TotalSeconds
$Report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  layer_root = $LayerRoot
  duration_seconds = [Math]::Round($Duration, 3)
  skip_smoke = $SkipSmoke.IsPresent
  skip_matrix = $SkipMatrix.IsPresent
  skip_quality = $SkipQuality.IsPresent
  strict_git_status = $StrictGitStatus.IsPresent
  results = @($Results.ToArray())
}
$ReportDir = Join-Path $LayerRoot '.tmp\ci'
New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null
$ReportPath = Join-Path $ReportDir ('ci-report-{0}.json' -f (Get-Date -Format 'yyyyMMddHHmmss'))
$Report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
Write-Host "CI passed. Report: $ReportPath"
