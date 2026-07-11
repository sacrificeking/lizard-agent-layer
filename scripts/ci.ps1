param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [switch]$SkipSmoke,
  [switch]$SkipMatrix,
  [switch]$SkipQuality,
  [switch]$SkipPacks,
  [switch]$SkipDrift,
  [switch]$StrictGitStatus
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Host.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix
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
    $global:LASTEXITCODE = 0
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
Write-Host "SkipPacks: $($SkipPacks.IsPresent)"
Write-Host "SkipDrift: $($SkipDrift.IsPresent)"
Write-Host "StrictGitStatus: $($StrictGitStatus.IsPresent)"
Write-Host ""

Invoke-CiStep 'validate' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\validate.ps1') -LayerRoot $LayerRoot
}
Invoke-CiStep 'schema mutations' {
  & node (Join-Path $LayerRoot 'tools\schema-validator\validate.mjs') --root $LayerRoot --mutation-corpus 'tools/schema-validator/mutation-corpus.json'
}
Invoke-CiStep 'focused safety' {
  & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'tests\run-focused.ps1') -LayerRoot $LayerRoot
}
if (-not $SkipPacks) {
  Invoke-CiStep 'packs' {
    & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\pack-report.ps1') -LayerRoot $LayerRoot -Strict
  }
}

if (-not $SkipDrift) {
  Invoke-CiStep 'drift' {
    & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\drift-check.ps1') -LayerRoot $LayerRoot -Strict
  }
}

if (-not $SkipQuality) {
  Invoke-CiStep 'quality' {
    & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\score-layer.ps1') -LayerRoot $LayerRoot -Strict
  }
}

if (-not $SkipSmoke) {
  Invoke-CiStep 'smoke' {
    & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'tests\smoke.ps1') -LayerRoot $LayerRoot
  }
}

if (-not $SkipMatrix) {
  Invoke-CiStep 'matrix' {
    & $PowerShellHost @PowerShellFilePrefix (Join-Path $LayerRoot 'scripts\matrix.ps1') -LayerRoot $LayerRoot
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
  skip_packs = $SkipPacks.IsPresent
  skip_drift = $SkipDrift.IsPresent
  strict_git_status = $StrictGitStatus.IsPresent
  results = @($Results.ToArray())
}
$ReportDir = Join-Path $LayerRoot '.tmp\ci'
$ReportDir = Initialize-SafeDirectory -Path $ReportDir
$ReportPath = Join-Path $ReportDir ('ci-report-{0}.json' -f (Get-Date -Format 'yyyyMMddHHmmss'))
Set-SafeContent -AuthorizedRoot $ReportDir -Path $ReportPath -Value ($Report | ConvertTo-Json -Depth 8)
Write-Host "CI passed. Report: $ReportPath"
