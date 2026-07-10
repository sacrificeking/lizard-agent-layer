param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("install-containment-{0}" -f ([Guid]::NewGuid().ToString('N')))
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$links = New-Object System.Collections.Generic.List[string]
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

function New-CaseDirectories {
  param([string]$Name)
  $caseRoot = Join-Path $fixture $Name
  $target = Join-Path $caseRoot 'target'
  $outside = Join-Path $caseRoot 'outside'
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  New-Item -ItemType Directory -Path $outside -Force | Out-Null
  return [pscustomobject]@{ target = $target; outside = $outside }
}

function Assert-OutsideEmpty {
  param([string]$Path, [string]$Case)
  $entries = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue)
  Assert-Equal 0 $entries.Count "$Case must produce zero writes outside the authorized root."
}

try {
  foreach ($forceMode in @('-Force', '-ForceManaged')) {
    $case = New-CaseDirectories -Name ("agent-link-{0}" -f $forceMode.TrimStart('-').ToLowerInvariant())
    $agentLink = Join-Path $case.target '.agent'
    New-DirectoryLink -Path $agentLink -Target $case.outside
    $links.Add($agentLink) | Out-Null
    $result = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $case.target, '-Profile', 'minimal', '-Apply', $forceMode)
    Assert-False ($result.exit_code -eq 0) "$forceMode must reject a linked .agent destination."
    Assert-True ($result.output -match 'SAFEFS_REPARSE_POINT') "$forceMode must expose the stable reparse-point rejection code."
    Assert-OutsideEmpty -Path $case.outside -Case $forceMode
  }

  $mirrorCase = New-CaseDirectories -Name 'adapter-mirror-link'
  $agentsLink = Join-Path $mirrorCase.target '.agents'
  New-DirectoryLink -Path $agentsLink -Target $mirrorCase.outside
  $links.Add($agentsLink) | Out-Null
  $mirrorResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $mirrorCase.target, '-Profile', 'minimal', '-Harnesses', 'codex', '-Apply')
  Assert-False ($mirrorResult.exit_code -eq 0) 'A linked harness mirror must fail installation.'
  Assert-True ($mirrorResult.output -match 'SAFEFS_REPARSE_POINT') 'Harness mirror rejection must expose SAFEFS_REPARSE_POINT.'
  Assert-OutsideEmpty -Path $mirrorCase.outside -Case 'adapter mirror'

  $reportCase = New-CaseDirectories -Name 'linked-report-root'
  $reportLink = Join-Path $reportCase.target '..\report-link'
  New-DirectoryLink -Path $reportLink -Target $reportCase.outside
  $links.Add($reportLink) | Out-Null
  $reportResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $reportCase.target, '-Profile', 'minimal', '-WritePlan', '-PlanPath', (Join-Path $reportLink 'plan.md'))
  Assert-False ($reportResult.exit_code -eq 0) 'A linked report root must be rejected.'
  Assert-True ($reportResult.output -match 'SAFEFS_REPARSE_POINT') 'Linked report rejection must expose SAFEFS_REPARSE_POINT.'
  Assert-OutsideEmpty -Path $reportCase.outside -Case 'linked report root'

  $previewCase = New-CaseDirectories -Name 'preview-target-noop'
  $targetPlan = Join-Path $previewCase.target 'reports\plan.md'
  $previewResult = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $previewCase.target, '-Profile', 'minimal', '-WritePlan', '-PlanPath', $targetPlan)
  Assert-False ($previewResult.exit_code -eq 0) 'Preview report writes inside the target must fail closed.'
  Assert-True ($previewResult.output -match 'SAFEFS_FORBIDDEN_ROOT') 'Preview target-local report rejection must expose SAFEFS_FORBIDDEN_ROOT.'
  Assert-False (Test-Path -LiteralPath (Join-Path $previewCase.target 'reports')) 'Rejected preview must leave the target unchanged.'

  Write-Host 'PASS installer containment adversarial tests'
} finally {
  Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot -Links @($links.ToArray())
}
