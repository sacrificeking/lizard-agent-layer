param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("memory-modes-{0}" -f ([Guid]::NewGuid().ToString('N')))
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$doctorScript = Join-Path $LayerRoot 'scripts\doctor.ps1'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

function Install-TestMode {
  param([string]$Mode)
  $target = Join-Path $fixture $Mode
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  $approval = New-TestInstallApprovalArguments -LayerRoot $LayerRoot -BaseArguments @('-TargetPath', $target, '-Profile', 'minimal', '-Harnesses', 'codex', '-MemoryMode', $Mode)
  $apply = Invoke-TestPowerShell -ScriptPath $installScript -Arguments $approval.arguments
  Assert-Equal 0 $apply.exit_code "Approved $Mode install must succeed: $($apply.output)"
  return $target
}

try {
  foreach ($mode in @('curated', 'private-episodic', 'off')) {
    $target = Install-TestMode -Mode $mode
    $profile = Get-Content -LiteralPath (Join-Path $target '.agent\project-profile.json') -Raw | ConvertFrom-Json
    $manifest = Get-Content -LiteralPath (Join-Path $target '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
    Assert-Equal $mode ([string]$profile.memoryMode) "Installed profile must record effective mode $mode."
    Assert-Equal $mode ([string]$manifest.memory_mode) "Install manifest must record effective mode $mode."

    $memoryRoot = Join-Path $target '.agent\memory'
    if ($mode -eq 'off') {
      Assert-False (Test-Path -LiteralPath $memoryRoot) 'Off mode must not create a physical memory namespace.'
      Assert-Equal 0 @($manifest.artifacts | Where-Object { $_.lifecycle -ne 'removed' -and ([string]$_.path -eq '.agent/memory' -or ([string]$_.path).StartsWith('.agent/memory/')) }).Count 'Off mode must not retain active or retired-present memory artifacts.'
      $permissions = Get-Content -LiteralPath (Join-Path $target '.agent\protocols\permissions.md') -Raw
      Assert-False ($permissions -match '(?i)\.agent[/\\]memory|memory[/\\](?:personal|semantic|working|episodic)|working-memory') 'Off permissions must not grant managed memory writes.'
      foreach ($record in @($manifest.artifacts | Where-Object { $_.kind -eq 'file' -and ($_.adapter_id -or ([string]$_.path).StartsWith('.agent/protocols/')) })) {
        $path = Join-Path $target ([string]$record.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $content = Get-Content -LiteralPath $path -Raw
        Assert-False ($content -match '(?i)\.agent[/\\]memory|memory[/\\](?:personal|semantic|working|episodic)') "Off installed instructions must not reference managed memory paths: $($record.path)"
      }
    } else {
      foreach ($relative in @('personal\PREFERENCES.md', 'semantic\DECISIONS.md', 'semantic\LESSONS.md', 'working\WORKSPACE.md')) {
        Assert-True (Test-Path -LiteralPath (Join-Path $memoryRoot $relative) -PathType Leaf) "$mode must install curated memory artifact $relative."
      }
      $episodicPath = Join-Path $memoryRoot 'episodic\EPISODES.md'
      if ($mode -eq 'private-episodic') {
        Assert-True (Test-Path -LiteralPath $episodicPath -PathType Leaf) 'Private episodic mode must install the private episodic seed.'
        $ignore = Get-Content -LiteralPath (Join-Path $target '.agent\.gitignore') -Raw
        Assert-True ($ignore -match '(?m)^memory/episodic/\*\*$') 'Private episodic content must be ignored recursively.'
      } else {
        Assert-False (Test-Path -LiteralPath $episodicPath) 'Curated mode must not install private episodic history.'
      }
    }

    $doctor = Invoke-TestPowerShell -ScriptPath $doctorScript -Arguments @('-TargetPath', $target, '-Strict')
    Assert-Equal 0 $doctor.exit_code "Doctor must accept a clean $mode installation: $($doctor.output)"
  }

  Write-Host 'PASS tests\integration\memory-modes.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
