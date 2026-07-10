param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("version-gates-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$updateScript = Join-Path $LayerRoot 'scripts\update-target.ps1'
New-Item -ItemType Directory -Path $target -Force | Out-Null

function Read-Manifest { Get-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json }
function Write-Manifest { param($Manifest) $Manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Encoding UTF8 }

try {
  $install = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $target, '-Profile', 'minimal', '-Apply')
  Assert-Equal 0 $install.exit_code 'Version gate fixture install must succeed.'
  $manifest = Read-Manifest
  $manifest.layer_version = '99.0.0'
  Write-Manifest $manifest
  $manifestPath = Join-Path $target '.agent\lizard-agent-layer.install.json'
  $before = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash

  $previewDir = Join-Path $fixture 'preview'
  $preview = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments @('-TargetPath', $target, '-OutputDir', $previewDir)
  Assert-Equal 0 $preview.exit_code 'A downgrade preview must remain reviewable without mutation approval.'
  Assert-Equal $before ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash) 'Downgrade preview must not mutate the target manifest.'

  $blockedDir = Join-Path $fixture 'blocked'
  $blocked = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments @('-TargetPath', $target, '-OutputDir', $blockedDir, '-Apply')
  Assert-False ($blocked.exit_code -eq 0) 'Unapproved downgrade apply must fail.'
  Assert-True ($blocked.output -match 'DOWNGRADE_APPROVAL_REQUIRED') 'Blocked downgrade must expose an actionable stable code.'
  Assert-Equal $before ((Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash) 'Blocked downgrade must leave target state unchanged.'
  Assert-False (Test-Path -LiteralPath $blockedDir) 'Downgrade gate must run before report-directory writes.'

  $approvedDir = Join-Path $fixture 'approved'
  $approved = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments @('-TargetPath', $target, '-OutputDir', $approvedDir, '-Apply', '-AllowDowngrade', '-HumanApproved')
  Assert-Equal 0 $approved.exit_code 'Explicitly approved downgrade must apply.'
  $currentVersion = (Get-Content -LiteralPath (Join-Path $LayerRoot 'VERSION') -Raw).Trim()
  Assert-Equal $currentVersion ([string](Read-Manifest).layer_version) 'Approved downgrade must write the current layer version.'

  $future = Read-Manifest
  $future.schema_version = 99
  Write-Manifest $future
  $futureDir = Join-Path $fixture 'future-schema'
  $futureResult = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments @('-TargetPath', $target, '-OutputDir', $futureDir)
  Assert-False ($futureResult.exit_code -eq 0) 'Future manifest schema must fail closed.'
  Assert-True ($futureResult.output -match 'MANIFEST_READER_TOO_OLD') 'Future schema rejection must expose MANIFEST_READER_TOO_OLD.'
  Assert-False (Test-Path -LiteralPath $futureDir) 'Future schema gate must run before report writes.'

  $future.schema_version = 3
  $future.layer_version = 'not-a-version'
  Write-Manifest $future
  $malformedDir = Join-Path $fixture 'malformed-version'
  $malformed = Invoke-TestPowerShell -ScriptPath $updateScript -Arguments @('-TargetPath', $target, '-OutputDir', $malformedDir)
  Assert-False ($malformed.exit_code -eq 0) 'Malformed installed version must fail closed.'
  Assert-True ($malformed.output -match 'VERSION_FORMAT_INVALID') 'Malformed version rejection must expose VERSION_FORMAT_INVALID.'
  Assert-False (Test-Path -LiteralPath $malformedDir) 'Malformed version gate must run before report writes.'

  Write-Host 'PASS version gate adversarial tests'
} finally {
  Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot
}
