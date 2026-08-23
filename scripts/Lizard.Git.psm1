Set-StrictMode -Version 2.0

function Invoke-LizardGitCapture {
  param([string[]]$ArgumentList)
  $previous = $ErrorActionPreference
  try {
    $ErrorActionPreference = 'Continue'
    $output = @(& git @ArgumentList 2>&1)
    $exitCode = [int]$LASTEXITCODE
  } finally { $ErrorActionPreference = $previous }
  return [pscustomobject]@{ exit_code = $exitCode; output = @($output) }
}

function Assert-LizardGitToken {
  param([Parameter(Mandatory = $true)][string]$Value, [Parameter(Mandatory = $true)][string]$Label)
  if ([string]::IsNullOrWhiteSpace($Value) -or $Value.StartsWith('-', [System.StringComparison]::Ordinal) -or $Value.Length -gt 1024 -or $Value -match '[\x00-\x20\x7f]') {
    throw "GIT_REF_INVALID: $Label is empty, option-like, contains whitespace/control characters, or is oversized."
  }
}

function Assert-LizardGitBranchName {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$Branch)
  Assert-LizardGitToken -Value $Branch -Label 'Branch'
  $result = Invoke-LizardGitCapture -ArgumentList @('check-ref-format', '--branch', $Branch)
  if ($result.exit_code -ne 0) { throw "GIT_BRANCH_INVALID: Branch does not satisfy git check-ref-format --branch." }
  return $Branch
}

function Assert-LizardGitBaseReference {
  [CmdletBinding()]
  param([Parameter(Mandatory = $true)][string]$BaseRef)
  Assert-LizardGitToken -Value $BaseRef -Label 'BaseRef'
  if ($BaseRef -eq 'HEAD' -or $BaseRef -match '^[a-fA-F0-9]{40}$') { return $BaseRef }
  $result = Invoke-LizardGitCapture -ArgumentList @('check-ref-format', '--allow-onelevel', $BaseRef)
  if ($result.exit_code -ne 0) { throw 'GIT_BASE_REF_INVALID: BaseRef must be HEAD, a full object ID, or a ref name without revision expressions.' }
  return $BaseRef
}

function Resolve-LizardGitCommit {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$BaseRef
  )
  $validated = Assert-LizardGitBaseReference -BaseRef $BaseRef
  $result = Invoke-LizardGitCapture -ArgumentList @('-C', $RepositoryRoot, 'rev-parse', '--verify', '--end-of-options', ("{0}^{{commit}}" -f $validated))
  if ($result.exit_code -ne 0) { throw "GIT_BASE_REF_NOT_FOUND: BaseRef does not resolve to a commit." }
  $sha = [string]($result.output | Select-Object -First 1)
  if ($sha -notmatch '^[a-fA-F0-9]{40}$') { throw 'GIT_COMMIT_ID_INVALID: Git returned a malformed commit object ID.' }
  return $sha.ToLowerInvariant()
}

Export-ModuleMember -Function @('Assert-LizardGitBaseReference', 'Assert-LizardGitBranchName', 'Resolve-LizardGitCommit')
