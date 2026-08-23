Set-StrictMode -Version 2.0

Import-Module (Join-Path $PSScriptRoot 'Lizard.SafeFs.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')
Import-Module (Join-Path $PSScriptRoot 'Lizard.LoopEvidence.psm1')

function Get-LizardVerificationCommandDefinition {
  param([Parameter(Mandatory)][string]$CommandId)
  switch ($CommandId) {
    'git-head' { return [pscustomobject][ordered]@{ executable_id = 'git'; argv = @('rev-parse', 'HEAD') } }
    'git-missing-ref-probe' { return [pscustomobject][ordered]@{ executable_id = 'git'; argv = @('rev-parse', '--verify', 'refs/heads/lizard-verification-ref-must-not-exist') } }
    default { throw 'VERIFICATION_COMMAND_ID_DENIED: command is not in the built-in non-network allowlist.' }
  }
}

function Get-LizardResolvedGitExecutable {
  $command = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
  $path = [System.IO.Path]::GetFullPath([string]$command.Source)
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'VERIFICATION_EXECUTABLE_MISSING: git executable is unavailable.' }
  [pscustomobject][ordered]@{
    id = 'git'
    path = $path
    sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}

function Get-LizardRootIdentitySha256 {
  param([Parameter(Mandatory)][string]$WorktreeRoot)
  $identity = Get-LizardSafeRootIdentity -AuthorizedRoot $WorktreeRoot
  Get-LizardEvidenceSha256 -Value ($identity | ConvertTo-Json -Depth 5 -Compress)
}

function New-LizardVerificationPlan {
  param(
    [Parameter(Mandatory)][string]$WorktreeRoot,
    [Parameter(Mandatory)][string[]]$CommandIds,
    [DateTimeOffset]$CreatedAt = [DateTimeOffset]::UtcNow,
    [DateTimeOffset]$ExpiresAt = ([DateTimeOffset]::UtcNow.AddMinutes(30))
  )
  $root = Resolve-SafeRoot -Path $WorktreeRoot -RequireExisting
  if ($ExpiresAt -le $CreatedAt -or $ExpiresAt -gt $CreatedAt.AddHours(24)) { throw 'VERIFICATION_PLAN_EXPIRY_INVALID: expiry must be after creation and within 24 hours.' }
  if (@($CommandIds).Count -lt 1 -or @($CommandIds).Count -gt 16) { throw 'VERIFICATION_PLAN_COMMAND_COUNT_INVALID: one to sixteen commands are required.' }
  $commands = New-Object System.Collections.Generic.List[object]
  foreach ($commandId in @($CommandIds)) {
    $definition = Get-LizardVerificationCommandDefinition -CommandId $commandId
    $commands.Add([pscustomobject][ordered]@{ command_id = $commandId; timeout_seconds = 30; expected_exit_codes = @(0) }) | Out-Null
  }
  $executable = Get-LizardResolvedGitExecutable
  [pscustomobject][ordered]@{
    schema_version = 1
    artifact_kind = 'verification-command-plan'
    plan_id = [Guid]::NewGuid().ToString('N')
    created_at = $CreatedAt.ToUniversalTime().ToString('o')
    expires_at = $ExpiresAt.ToUniversalTime().ToString('o')
    runner_id = 'lizard-constrained-verifier-v1'
    worktree_root = $root
    worktree_identity_sha256 = Get-LizardRootIdentitySha256 -WorktreeRoot $root
    executable = $executable
    commands = @($commands.ToArray())
    restrictions = [pscustomobject][ordered]@{
      shell = $false
      network = 'denied-by-command-allowlist'
      working_directory = 'worktree-root-only'
      environment = 'sanitized-minimal'
      child_processes = 'allowlisted-executable-only'
      interactive = $false
      output = 'hash-and-size-only'
    }
  }
}

function Assert-LizardVerificationPlanShape {
  param([Parameter(Mandatory)]$Plan)
  $required = @('schema_version','artifact_kind','plan_id','created_at','expires_at','runner_id','worktree_root','worktree_identity_sha256','executable','commands','restrictions')
  $actual = @($Plan.PSObject.Properties.Name)
  foreach ($name in $required) { if ($actual -notcontains $name) { throw "VERIFICATION_PLAN_INVALID: missing $name." } }
  foreach ($name in $actual) { if ($required -notcontains $name) { throw 'VERIFICATION_PLAN_INVALID: unknown top-level field.' } }
  if ([int]$Plan.schema_version -ne 1 -or [string]$Plan.artifact_kind -ne 'verification-command-plan' -or [string]$Plan.runner_id -ne 'lizard-constrained-verifier-v1') { throw 'VERIFICATION_PLAN_INVALID: unsupported plan contract.' }
  if ([string]$Plan.plan_id -notmatch '^[a-f0-9]{32}$' -or [string]$Plan.worktree_identity_sha256 -notmatch '^[a-f0-9]{64}$') { throw 'VERIFICATION_PLAN_INVALID: plan or worktree identity is malformed.' }
  $created = [DateTimeOffset]::Parse([string]$Plan.created_at)
  $expires = [DateTimeOffset]::Parse([string]$Plan.expires_at)
  if ($expires -le [DateTimeOffset]::UtcNow -or $expires -le $created -or $expires -gt $created.AddHours(24)) { throw 'VERIFICATION_PLAN_EXPIRED: verification plan is stale or has an invalid lifetime.' }
  if (@($Plan.commands).Count -lt 1 -or @($Plan.commands).Count -gt 16) { throw 'VERIFICATION_PLAN_INVALID: command count is outside 1..16.' }
  if ($Plan.restrictions.shell -ne $false -or [string]$Plan.restrictions.network -ne 'denied-by-command-allowlist' -or [string]$Plan.restrictions.working_directory -ne 'worktree-root-only' -or [string]$Plan.restrictions.environment -ne 'sanitized-minimal' -or [string]$Plan.restrictions.child_processes -ne 'allowlisted-executable-only' -or $Plan.restrictions.interactive -ne $false -or [string]$Plan.restrictions.output -ne 'hash-and-size-only') { throw 'VERIFICATION_PLAN_RESTRICTIONS_INVALID: constrained-runner restrictions were weakened.' }
  foreach ($command in @($Plan.commands)) {
    $commandFields = @($command.PSObject.Properties.Name)
    foreach ($requiredCommandField in @('command_id','timeout_seconds','expected_exit_codes')) { if ($commandFields -notcontains $requiredCommandField) { throw 'VERIFICATION_PLAN_INVALID: command entry is incomplete.' } }
    foreach ($field in $commandFields) { if ($field -notin @('command_id','timeout_seconds','expected_exit_codes')) { throw 'VERIFICATION_PLAN_INVALID: command entry has an unknown field.' } }
    $null = Get-LizardVerificationCommandDefinition -CommandId ([string]$command.command_id)
    if ([int]$command.timeout_seconds -lt 1 -or [int]$command.timeout_seconds -gt 120) { throw 'VERIFICATION_PLAN_INVALID: timeout is outside 1..120 seconds.' }
    if (@($command.expected_exit_codes).Count -lt 1 -or @($command.expected_exit_codes).Count -gt 8) { throw 'VERIFICATION_PLAN_INVALID: expected exit codes are missing or excessive.' }
    foreach ($exitCode in @($command.expected_exit_codes)) { if ([int]$exitCode -lt 0 -or [int]$exitCode -gt 255) { throw 'VERIFICATION_PLAN_INVALID: expected exit code is outside 0..255.' } }
  }
}

function Read-LizardVerificationPlan {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$ExpectedSha256,
    [Parameter(Mandatory)][string]$WorktreeRoot
  )
  if ($ExpectedSha256 -notmatch '^[a-f0-9]{64}$') { throw 'VERIFICATION_PLAN_DIGEST_INVALID: expected SHA-256 is required.' }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw 'VERIFICATION_PLAN_MISSING: approved command plan is unavailable.' }
  $bytes = [System.IO.File]::ReadAllBytes($fullPath)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $actualSha256 = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() } finally { $sha.Dispose() }
  if ($actualSha256 -ne $ExpectedSha256) { throw 'VERIFICATION_PLAN_DIGEST_MISMATCH: approved command plan bytes changed.' }
  $encoding = New-Object System.Text.UTF8Encoding($false, $true)
  try { $text = $encoding.GetString($bytes) } catch { throw 'VERIFICATION_PLAN_ENCODING_INVALID: plan must be strict UTF-8.' }
  if ($text.Length -gt 131072) { throw 'VERIFICATION_PLAN_INVALID: plan exceeds 128 KiB.' }
  $plan = ConvertFrom-LizardJson -InputObject $text
  Assert-LizardVerificationPlanShape -Plan $plan
  $root = Resolve-SafeRoot -Path $WorktreeRoot -RequireExisting
  $comparison = Get-LizardPathComparison
  if (-not ([System.IO.Path]::GetFullPath([string]$plan.worktree_root).Equals($root, $comparison))) { throw 'VERIFICATION_PLAN_WORKTREE_MISMATCH: plan is bound to another worktree.' }
  if ([string]$plan.worktree_identity_sha256 -ne (Get-LizardRootIdentitySha256 -WorktreeRoot $root)) { throw 'VERIFICATION_PLAN_WORKTREE_IDENTITY_MISMATCH: worktree root object changed.' }
  $resolvedExecutable = Get-LizardResolvedGitExecutable
  if ([string]$plan.executable.id -ne 'git' -or -not ([System.IO.Path]::GetFullPath([string]$plan.executable.path).Equals([string]$resolvedExecutable.path, $comparison)) -or [string]$plan.executable.sha256 -ne [string]$resolvedExecutable.sha256) { throw 'VERIFICATION_PLAN_EXECUTABLE_MISMATCH: git executable identity changed.' }
  [pscustomobject][ordered]@{ plan = $plan; sha256 = $actualSha256; path = $fullPath; executable = $resolvedExecutable }
}

function Invoke-LizardConstrainedCommand {
  param([Parameter(Mandatory)]$Command, [Parameter(Mandatory)][string]$ExecutablePath, [Parameter(Mandatory)][string]$WorktreeRoot)
  $definition = Get-LizardVerificationCommandDefinition -CommandId ([string]$Command.command_id)
  $started = (Get-Date).ToUniversalTime().ToString('o')
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $ExecutablePath
  $startInfo.Arguments = @($definition.argv) -join ' '
  $startInfo.WorkingDirectory = $WorktreeRoot
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $startInfo.EnvironmentVariables.Clear()
  if ($env:SystemRoot) { $startInfo.EnvironmentVariables['SystemRoot'] = $env:SystemRoot }
  if ($env:WINDIR) { $startInfo.EnvironmentVariables['WINDIR'] = $env:WINDIR }
  $startInfo.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
  $startInfo.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = if ($env:OS -eq 'Windows_NT') { 'NUL' } else { '/dev/null' }
  $startInfo.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
  $startInfo.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo
  try {
    if (-not $process.Start()) { throw 'VERIFICATION_RUNNER_START_FAILED: allowlisted executable did not start.' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $timedOut = -not $process.WaitForExit(([int]$Command.timeout_seconds * 1000))
    if ($timedOut) {
      try { $process.Kill() } catch {}
      $process.WaitForExit()
    }
    $stdout = [string]$stdoutTask.Result
    $stderr = [string]$stderrTask.Result
    $combined = $stdout + $stderr
    $exitCode = if ($timedOut) { 124 } else { [int]$process.ExitCode }
  } finally { $process.Dispose() }
  [pscustomobject][ordered]@{
    command_id = [string]$Command.command_id
    started_at = $started
    completed_at = (Get-Date).ToUniversalTime().ToString('o')
    exit_code = $exitCode
    expected_exit_codes = @($Command.expected_exit_codes | ForEach-Object { [int]$_ })
    timed_out = $timedOut
    output_sha256 = Get-LizardEvidenceSha256 -Value $combined
    output_bytes = (New-Object System.Text.UTF8Encoding($false)).GetByteCount($combined)
  }
}

function Invoke-LizardVerificationPlan {
  param([Parameter(Mandatory)]$ApprovedPlan, [Parameter(Mandatory)][string]$WorktreeRoot)
  $results = New-Object System.Collections.Generic.List[object]
  foreach ($command in @($ApprovedPlan.plan.commands)) {
    $results.Add((Invoke-LizardConstrainedCommand -Command $command -ExecutablePath ([string]$ApprovedPlan.executable.path) -WorktreeRoot $WorktreeRoot)) | Out-Null
  }
  @($results.ToArray())
}

Export-ModuleMember -Function New-LizardVerificationPlan, Read-LizardVerificationPlan, Invoke-LizardVerificationPlan
