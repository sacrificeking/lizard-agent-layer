param(
  [string]$TargetPath = (Get-Location).Path,
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$Pattern,
  [switch]$Strict,
  [switch]$Json,
  [string]$OutputDir,
  [switch]$AllowTargetReportWrite
)

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.LoopEvidence.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.LoopRuntime.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
$TargetRoot = Resolve-SafeRoot -Path $TargetPath -RequireExisting
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$EffectiveOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) { Join-Path $LayerRoot ".tmp\loops\audit-$stamp" } elseif ([System.IO.Path]::IsPathRooted($OutputDir)) { $OutputDir } else { Join-Path (Get-Location).Path $OutputDir }
if (-not $AllowTargetReportWrite) { Assert-PathOutsideRoot -Path $EffectiveOutputDir -ExcludedRoot $TargetRoot -Label 'OutputDir' }
$EffectiveOutputDir = Initialize-SafeDirectory -Path $EffectiveOutputDir

$Failures = New-Object System.Collections.Generic.List[string]
$Warnings = New-Object System.Collections.Generic.List[string]
$Checks = New-Object System.Collections.Generic.List[object]

function Add-Failure { param([string]$Message) $Failures.Add($Message) | Out-Null; $Checks.Add([ordered]@{ status = 'fail'; message = $Message }) | Out-Null }
function Add-Warning { param([string]$Message) $Warnings.Add($Message) | Out-Null; $Checks.Add([ordered]@{ status = 'warn'; message = $Message }) | Out-Null }
function Add-Pass { param([string]$Message) $Checks.Add([ordered]@{ status = 'pass'; message = $Message }) | Out-Null }
function Read-JsonFile {
  param([string]$Path)
  try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
  catch { Add-Failure "Invalid JSON: $Path ($($_.Exception.Message))"; return $null }
}
function Test-RelativeFile {
  param([string]$Relative, [string]$Label)
  if ([string]::IsNullOrWhiteSpace($Relative)) { Add-Failure "$Label path is empty."; return $false }
  if ([System.IO.Path]::IsPathRooted($Relative) -or $Relative -match '^[A-Za-z]:') { Add-Failure "$Label path must be relative: $Relative"; return $false }
  $path = Join-Path $TargetRoot ($Relative.Replace('/', '\'))
  if (Test-Path -LiteralPath $path) { Add-Pass "$Label exists: $Relative"; return $true }
  Add-Failure "$Label is missing: $Relative"
  return $false
}

$versionPath = Join-Path $LayerRoot 'VERSION'
$currentVersion = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw).Trim() } else { '0.0.0-dev' }
$manifestPath = Join-Path $TargetRoot '.agent\loops\lizard-agent-layer.loop-install.json'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = Read-JsonFile $manifestPath
  if ($manifest) { Add-Pass 'Loop install manifest exists.' }
} else {
  Add-Failure 'Missing .agent/loops/lizard-agent-layer.loop-install.json. Run loop-init.ps1 after installing the loop-engineering pack.'
}

$patternName = if (-not [string]::IsNullOrWhiteSpace($Pattern)) { $Pattern } elseif ($manifest -and $manifest.pattern) { [string]$manifest.pattern } else { 'daily-triage' }
$patternPath = Join-Path $LayerRoot ("loops\{0}.json" -f $patternName)
$patternDoc = $null
if (Test-Path -LiteralPath $patternPath) {
  $patternDoc = Read-JsonFile $patternPath
  if ($patternDoc) { Add-Pass "Loop pattern exists in layer: $patternName" }
} else {
  Add-Failure "Loop pattern is missing in layer: $patternName"
}

if ($manifest) {
  foreach ($field in @('layer_version', 'pattern', 'readiness_level', 'risk_level', 'state_file', 'budget_file', 'run_log_file', 'constraints_file', 'runtime_budget_file', 'runtime_state_file', 'runtime_events_file', 'runtime_lease_file', 'skills', 'human_gates')) {
    if (-not ($manifest.PSObject.Properties.Name -contains $field)) { Add-Failure "Loop manifest missing '$field'." }
  }
  if ($manifest.layer_version -and $manifest.layer_version -ne $currentVersion) { Add-Warning "Installed loop layer version $($manifest.layer_version) differs from current $currentVersion." }
  if ($manifest.readiness_level -and $manifest.readiness_level -notin @('L0', 'L1', 'L2', 'L3')) { Add-Failure "Invalid readiness level in manifest: $($manifest.readiness_level)" }
  if ($manifest.risk_level -and $manifest.risk_level -notin @('low', 'medium', 'high')) { Add-Failure "Invalid risk level in manifest: $($manifest.risk_level)" }
  Test-RelativeFile '.agent\loops\LOOP.md' 'Loop control document' | Out-Null
  Test-RelativeFile ([string]$manifest.state_file) 'Loop state file' | Out-Null
  Test-RelativeFile ([string]$manifest.budget_file) 'Loop budget file' | Out-Null
  Test-RelativeFile ([string]$manifest.run_log_file) 'Loop run log file' | Out-Null
  Test-RelativeFile ([string]$manifest.constraints_file) 'Loop constraints file' | Out-Null
  Test-RelativeFile ([string]$manifest.runtime_budget_file) 'Executable loop budget' | Out-Null
  Test-RelativeFile ([string]$manifest.runtime_state_file) 'Executable loop state' | Out-Null
  Test-RelativeFile ([string]$manifest.runtime_events_file) 'Append-only loop events' | Out-Null
  Test-RelativeFile ([string]$manifest.runtime_lease_file) 'Loop lease' | Out-Null
  try {
    $runtimeContext = Resolve-LizardLoopRuntimeContext -TargetPath $TargetRoot -Pattern $patternName
    Get-LizardLoopRuntimeDocuments -Context $runtimeContext | Out-Null
    $eventChain = Test-LizardLoopEventChain -Context $runtimeContext
    Add-Pass "Loop runtime documents and event chain are valid ($($eventChain.count) events)."
  } catch { Add-Failure "Loop runtime rejected: $($_.Exception.Message)" }
  if (($manifest.PSObject.Properties.Name -contains 'worktree_policy_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.worktree_policy_file)) { Test-RelativeFile ([string]$manifest.worktree_policy_file) 'Loop worktree policy file' | Out-Null }
  if (($manifest.PSObject.Properties.Name -contains 'assisted_plan_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.assisted_plan_file)) { Test-RelativeFile ([string]$manifest.assisted_plan_file) 'Loop assisted fix plan file' | Out-Null }
  if (($manifest.PSObject.Properties.Name -contains 'verifier_file') -and -not [string]::IsNullOrWhiteSpace([string]$manifest.verifier_file)) {
    $verifierRelative = [string]$manifest.verifier_file
    Test-RelativeFile $verifierRelative 'Loop verifier report file' | Out-Null
    $verifierFullPath = Join-Path $TargetRoot $verifierRelative.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $verifierEvidencePath = [System.IO.Path]::ChangeExtension($verifierFullPath, '.evidence.json')
    $verifierText = if (Test-Path -LiteralPath $verifierFullPath -PathType Leaf) { Get-Content -LiteralPath $verifierFullPath -Raw } else { '' }
    $declaredStatusMatch = [regex]::Match($verifierText, '(?m)^Status:\s*(NEEDS_REVIEW|PASS|WARN|FAIL|INVALID)\s*$')
    $declaredStatus = if ($declaredStatusMatch.Success) { [string]$declaredStatusMatch.Groups[1].Value } else { $null }
    if (Test-Path -LiteralPath $verifierEvidencePath -PathType Leaf) {
      try {
        $evidenceEnvelope = Read-LizardEvidenceEnvelope -Path $verifierEvidencePath -SchemaVersion 1
        $evidence = $evidenceEnvelope.payload
        Add-Pass "Verifier evidence hash is valid: $($evidenceEnvelope.payload_hash)"
        if ([string]$evidence.effective_status -eq 'INVALID') { Add-Failure 'Verifier evidence has INVALID effective status.' }
        if ([string]::IsNullOrWhiteSpace([string]$evidence.verifier)) { Add-Failure 'Verifier evidence is missing verifier identity.' }
        if ([string]$evidence.effective_status -ne 'NEEDS_REVIEW') {
          if ([string]::IsNullOrWhiteSpace([string]$evidence.implementer)) { Add-Failure 'Verifier verdict is missing implementer identity.' }
          elseif (([string]$evidence.verifier).Equals([string]$evidence.implementer, [System.StringComparison]::OrdinalIgnoreCase)) { Add-Failure 'Verifier evidence violates role separation.' }
          if (@($evidence.commands).Count -eq 0) { Add-Failure 'Verifier verdict contains no command results.' }
        }
        if ([string]$evidence.effective_status -in @('PASS', 'WARN')) {
          foreach ($command in @($evidence.commands)) { if ([int]$command.exit_code -ne 0) { Add-Failure "Passing verifier evidence contains failed command: $($command.command)" } }
        }
        if ([string]::IsNullOrWhiteSpace([string]$evidence.head_sha) -or [string]::IsNullOrWhiteSpace([string]$evidence.git_state_hash)) { Add-Failure 'Verifier evidence is not bound to HEAD and git state hashes.' }
        if ($declaredStatus -ne [string]$evidence.effective_status) { Add-Failure "Verifier Markdown status '$declaredStatus' does not match evidence status '$($evidence.effective_status)'." }
        $packetHashMatch = [regex]::Match($verifierText, '(?m)^Evidence packet hash:\s*([a-f0-9]{64})\s*$')
        if (-not $packetHashMatch.Success -or [string]$packetHashMatch.Groups[1].Value -ne [string]$evidenceEnvelope.payload_hash) { Add-Failure 'Verifier Markdown is not bound to the current evidence packet hash.' }
        if ([string]::IsNullOrWhiteSpace([string]$evidence.lifecycle_path)) { Add-Failure 'Verifier evidence is missing lifecycle path.' }
        else {
          $lifecycleEnvelope = Read-LizardEvidenceEnvelope -Path ([string]$evidence.lifecycle_path) -SchemaVersion 1
          if ([string]$lifecycleEnvelope.payload_hash -ne [string]$evidence.lifecycle_hash) { Add-Failure 'Verifier lifecycle hash no longer matches its contract.' }
          if ([string]$lifecycleEnvelope.payload.operation_id -ne [string]$evidence.operation_id) { Add-Failure 'Verifier operation ID does not match lifecycle contract.' }
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$evidence.worktree_root) -and (Test-Path -LiteralPath ([string]$evidence.worktree_root) -PathType Container)) {
          $currentEvidence = Get-LizardGitStateEvidence -WorktreePath ([string]$evidence.worktree_root)
          if ([string]$currentEvidence.state_hash -ne [string]$evidence.git_state_hash) { Add-Failure 'Verifier evidence is stale because the worktree state changed after verification.' }
          else { Add-Pass 'Verifier git state hash still matches the worktree.' }
          foreach ($file in @($evidence.evidence_files)) {
            $candidate = Resolve-SafeTargetDestination -AuthorizedRoot ([string]$evidence.worktree_root) -DestinationPath (Join-Path ([string]$evidence.worktree_root) ([string]$file.path).Replace('/', [System.IO.Path]::DirectorySeparatorChar))
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { Add-Failure "Verifier evidence file is missing: $($file.path)" }
            elseif ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne [string]$file.sha256) { Add-Failure "Verifier evidence file changed: $($file.path)" }
          }
        } else { Add-Warning 'Verifier worktree is unavailable; current git state cannot be recomputed.' }
      } catch { Add-Failure "Verifier evidence rejected: $($_.Exception.Message)" }
    } elseif ($declaredStatus -in @('PASS', 'WARN', 'FAIL')) {
      Add-Failure "Verifier Markdown declares $declaredStatus without a hashed evidence sidecar."
    }
  }
  foreach ($skill in @($manifest.skills)) {
    $skillName = [string]$skill
    $candidates = @(
      ".agent\skills\$skillName\SKILL.md",
      ".agents\skills\$skillName\SKILL.md",
      ".claude\skills\$skillName\SKILL.md",
      ".gemini\skills\$skillName\SKILL.md",
      ".cursor\skills\$skillName\SKILL.md"
    )
    $found = $false
    foreach ($candidate in $candidates) {
      if (Test-Path -LiteralPath (Join-Path $TargetRoot $candidate)) { $found = $true; break }
    }
    if ($found) { Add-Pass "Loop skill installed: $skillName" } else { Add-Failure "Loop skill not installed in any known mirror: $skillName" }
  }
}

if ($patternDoc) {
  if ($patternDoc.readinessLevel -eq 'L2') {
    Add-Pass "Pattern $patternName is L2 assisted; strict audit checks worktree and verifier gates."
    foreach ($requiredGate in @('human_review_before_write', 'human_approval_before_worktree_apply', 'human_review_before_merge', 'verifier_required_before_done')) {
      if (@($patternDoc.humanGates) -notcontains $requiredGate) { Add-Failure "L2 pattern $patternName does not declare gate: $requiredGate" }
    }
    foreach ($requiredSkill in @('worktree-isolation', 'minimal-fix', 'loop-verifier')) {
      if (@($patternDoc.skills) -notcontains $requiredSkill) { Add-Failure "L2 pattern $patternName does not include required skill: $requiredSkill" }
    }
    if (@($patternDoc.deniedActions) -notcontains 'auto-merge') { Add-Failure "L2 pattern $patternName must deny auto-merge." }
  } elseif ($patternDoc.readinessLevel -ne 'L1') {
    Add-Warning "Pattern $patternName is $($patternDoc.readinessLevel); current hardening expects L1 or reviewed L2 only."
  }
  if (@($patternDoc.allowedActions) -contains 'write') { Add-Warning "Pattern $patternName allows broad write action; use specific assisted actions and verify human gates." }
  foreach ($requiredGate in @('human_review_before_write', 'human_review_before_release')) {
    if (@($patternDoc.humanGates) -notcontains $requiredGate) { Add-Warning "Pattern $patternName does not declare gate: $requiredGate" }
  }
}

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  target = $TargetRoot
  current_layer_version = $currentVersion
  pattern = $patternName
  strict = $Strict.IsPresent
  failures = @($Failures.ToArray())
  warnings = @($Warnings.ToArray())
  checks = @($Checks.ToArray())
}
$reportPath = Join-Path $EffectiveOutputDir 'loop-audit-report.json'
Set-SafeContent -AuthorizedRoot $EffectiveOutputDir -Path $reportPath -Value ($report | ConvertTo-Json -Depth 10)

if ($Json) {
  $report | ConvertTo-Json -Depth 10
} else {
  Write-Host 'lizard-agent-layer loop audit'
  Write-Host "Target: $TargetRoot"
  Write-Host "Pattern: $patternName"
  Write-Host "Failures: $($Failures.Count)"
  Write-Host "Warnings: $($Warnings.Count)"
  Write-Host "Report: $reportPath"
  foreach ($failure in $Failures) { Write-Host "FAIL $failure" }
  foreach ($warning in $Warnings) { Write-Host "WARN $warning" }
}

if ($Failures.Count -gt 0 -or ($Strict -and $Warnings.Count -gt 0)) { exit 1 }
