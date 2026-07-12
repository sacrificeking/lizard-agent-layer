Set-StrictMode -Version 2.0

function Assert-True {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ASSERT_TRUE_FAILED: $Message" }
}

function Assert-False {
  param([bool]$Condition, [string]$Message)
  if ($Condition) { throw "ASSERT_FALSE_FAILED: $Message" }
}

function Assert-Equal {
  param($Expected, $Actual, [string]$Message)
  if ($Expected -ne $Actual) { throw "ASSERT_EQUAL_FAILED: $Message Expected '$Expected', got '$Actual'." }
}

function Assert-ThrowsCode {
  param([scriptblock]$Action, [string]$Code, [string]$Message)
  try {
    & $Action
  } catch {
    if ($_.Exception.Message -match [regex]::Escape($Code)) { return }
    throw "ASSERT_THROWS_CODE_FAILED: $Message Expected '$Code', got '$($_.Exception.Message)'."
  }
  throw "ASSERT_THROWS_CODE_FAILED: $Message Expected '$Code', but no exception was thrown."
}

function Test-LizardWindows {
  if ($PSVersionTable.ContainsKey('Platform')) { return $PSVersionTable['Platform'] -eq 'Win32NT' }
  return $true
}

function New-DirectoryLink {
  param([string]$Path, [string]$Target)
  $itemType = if (Test-LizardWindows) { 'Junction' } else { 'SymbolicLink' }
  New-Item -ItemType $itemType -Path $Path -Target $Target -Force | Out-Null
}

function Remove-DirectoryLink {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return }
  if (Test-LizardWindows) { [System.IO.Directory]::Delete($Path) }
  else { Remove-Item -LiteralPath $Path -Force }
}

function Get-CurrentPowerShellPath {
  $process = Get-Process -Id $PID
  if ($process.Path) { return $process.Path }
  if (Test-LizardWindows) { return (Join-Path $PSHOME 'powershell.exe') }
  return (Join-Path $PSHOME 'pwsh')
}

function Invoke-TestPowerShell {
  param([string]$ScriptPath, [string[]]$Arguments)
  $hostPath = Get-CurrentPowerShellPath
  $invokeArgs = @('-NoProfile')
  if (Test-LizardWindows) { $invokeArgs += @('-ExecutionPolicy', 'Bypass') }
  $invokeArgs += @('-File', $ScriptPath)
  $invokeArgs += @($Arguments)
  $global:LASTEXITCODE = 0
  $previousErrorAction = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = & $hostPath @invokeArgs 2>&1 | Out-String
    $exitCode = [int]$LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorAction
  }
  return [pscustomobject]@{ exit_code = $exitCode; output = $output }
}

function Assert-JsonSchemaValid {
  param(
    [string]$LayerRoot,
    [string]$SchemaPath,
    [string]$InstancePath,
    [string]$Message
  )
  $resolvedRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
  $resolvedInstance = (Resolve-Path -LiteralPath $InstancePath).Path
  $comparison = if (Test-LizardWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
  $rootPrefix = $resolvedRoot.TrimEnd([char[]]@('\', '/')) + [System.IO.Path]::DirectorySeparatorChar
  if (-not $resolvedInstance.StartsWith($rootPrefix, $comparison)) {
    throw "SCHEMA_TEST_INSTANCE_OUTSIDE_ROOT: $resolvedInstance"
  }
  $relativeInstance = $resolvedInstance.Substring($rootPrefix.Length).Replace('\', '/')
  $validatorPath = Join-Path $resolvedRoot 'tools\schema-validator\validate.mjs'
  $node = Get-Command node -ErrorAction SilentlyContinue
  if (-not $node) { throw 'SCHEMA_TEST_NODE_MISSING: Node.js is required for executable contract tests.' }
  $output = & $node.Source $validatorPath --root $resolvedRoot --schema $SchemaPath --instance $relativeInstance 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw "ASSERT_SCHEMA_VALID_FAILED: $Message $output" }
}

function Clear-TestDirectory {
  param([string]$Path, [string]$AllowedRoot, [string[]]$Links = @())
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd([char[]]@('\', '/'))
  $comparison = if (Test-LizardWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
  if (-not $fullPath.StartsWith(($fullRoot + [System.IO.Path]::DirectorySeparatorChar), $comparison)) {
    throw "TEST_CLEANUP_OUTSIDE_ROOT: $fullPath"
  }
  foreach ($link in @($Links)) { Remove-DirectoryLink -Path $link }
  if (Test-Path -LiteralPath $fullPath) { Remove-Item -LiteralPath $fullPath -Recurse -Force }
}

Export-ModuleMember -Function @(
  'Assert-Equal', 'Assert-False', 'Assert-JsonSchemaValid', 'Assert-ThrowsCode', 'Assert-True',
  'Clear-TestDirectory', 'Get-CurrentPowerShellPath', 'Invoke-TestPowerShell',
  'New-DirectoryLink', 'Remove-DirectoryLink', 'Test-LizardWindows'
)
