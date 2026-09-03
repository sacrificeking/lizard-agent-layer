[CmdletBinding()]
param(
  [Parameter(Position = 0, Mandatory = $true)][string]$Command,
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LayerRoot = Split-Path -Parent $ScriptDir

$pwshCmd = Get-Command 'pwsh' -ErrorAction SilentlyContinue
$psExe = if ($null -ne $pwshCmd) { $pwshCmd.Source } else { 'powershell.exe' }
$psArgs = if ($psExe -eq 'powershell.exe') {
  @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File')
} else {
  @('-NoProfile', '-File')
}

switch ($Command.ToLowerInvariant()) {
  'doctor' {
    & $psExe @psArgs (Join-Path $ScriptDir 'doctor.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'install' {
    & $psExe @psArgs (Join-Path $ScriptDir 'install.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'update' {
    & $psExe @psArgs (Join-Path $ScriptDir 'update-target.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'uninstall' {
    & $psExe @psArgs (Join-Path $ScriptDir 'uninstall.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'analyze' {
    & $psExe @psArgs (Join-Path $ScriptDir 'analyze-target.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'manifest-diff' {
    & $psExe @psArgs (Join-Path $ScriptDir 'manifest-diff.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'new-approval' {
    & $psExe @psArgs (Join-Path $ScriptDir 'new-approval.ps1') @RemainingArgs
    exit $LASTEXITCODE
  }
  'schema-check' {
    $npmCmd = if ($env:OS -eq 'Windows_NT' -or $IsWindows) { 'npm.cmd' } else { 'npm' }
    & $npmCmd run schema:check
    exit $LASTEXITCODE
  }
  default {
    Write-Host "Unknown command '$Command'. Supported commands: doctor, install, update, uninstall, analyze, manifest-diff, new-approval, schema-check."
    exit 1
  }
}
