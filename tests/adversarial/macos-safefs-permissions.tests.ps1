param([string]$LayerRoot = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
  if (-not (Test-Path (Join-Path $LayerRoot 'scripts'))) {
    $LayerRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
  }
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.SafeFs.psm1') -Force

# 1. Test canonical macOS temporary path resolutions
$varPath = ConvertTo-LizardCanonicalTemporaryPath -Path '/var/folders/xx/123/T' -HostId 'macos-pwsh'
Assert-Equal '/private/var/folders/xx/123/T' $varPath 'macOS /var paths must be canonicalized to /private/var'

$tmpPath = ConvertTo-LizardCanonicalTemporaryPath -Path '/tmp/smoke-123' -HostId 'macos-pwsh'
Assert-Equal '/private/tmp/smoke-123' $tmpPath 'macOS /tmp paths must be canonicalized to /private/tmp'

$etcPath = ConvertTo-LizardCanonicalTemporaryPath -Path '/etc/config' -HostId 'macos-pwsh'
Assert-Equal '/private/etc/config' $etcPath 'macOS /etc paths must be canonicalized to /private/etc'

$nonAliased = ConvertTo-LizardCanonicalTemporaryPath -Path '/Users/runner/work' -HostId 'macos-pwsh'
Assert-Equal '/Users/runner/work' $nonAliased 'Non-aliased macOS paths must remain unchanged'

# 2. Test SafeFs file creation and reading across local environment
$fixtureRoot = Join-Path $LayerRoot '.tmp\tests\safefs-perm-test'
if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null

try {
  $testFile = Join-Path $fixtureRoot 'safe-file.txt'
  Set-SafeContent -AuthorizedRoot $fixtureRoot -Path $testFile -Value 'test-content'

  Assert-True (Test-Path -LiteralPath $testFile) 'SafeContent must create target file'
  $readBack = Get-SafeContent -AuthorizedRoot $fixtureRoot -Path $testFile -Raw
  Assert-Equal 'test-content' $readBack.Trim() 'Get-SafeContent must read back created content'

  # Test atomic replacement
  Set-SafeContent -AuthorizedRoot $fixtureRoot -Path $testFile -Value 'updated-content'
  $updatedRead = Get-SafeContent -AuthorizedRoot $fixtureRoot -Path $testFile -Raw
  Assert-Equal 'updated-content' $updatedRead.Trim() 'Atomic replace must update content cleanly'

  # Test read with standard .NET IO
  $dotNetRead = [System.IO.File]::ReadAllText($testFile).Trim()
  Assert-Equal 'updated-content' $dotNetRead 'External .NET File.ReadAllText must be permitted'
} finally {
  if (Test-Path -LiteralPath $fixtureRoot) { Clear-TestDirectory -Path $fixtureRoot -AllowedRoot (Join-Path $LayerRoot '.tmp') }
}

Write-Host "PASS tests\adversarial\macos-safefs-permissions.tests.ps1"
