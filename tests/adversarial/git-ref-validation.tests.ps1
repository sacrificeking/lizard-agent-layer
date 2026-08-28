param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests/TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Git.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp/tests'
$fixture = Join-Path $testRoot ("git-ref-validation-{0}" -f ([Guid]::NewGuid().ToString('N')))
$target = Join-Path $fixture 'target'
$output = Join-Path $fixture 'output'
try {
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  & git -C $target init --quiet
  & git -C $target config user.email 'git-ref-tests@example.invalid'
  & git -C $target config user.name 'git ref tests'
  Set-Content -LiteralPath (Join-Path $target 'README.md') -Value '# git ref validation' -Encoding UTF8
  & git -C $target add -- README.md
  & git -C $target commit --quiet -m initial
  Assert-Equal 0 ([int]$LASTEXITCODE) 'Git fixture commit failed.'
  $head = [string](& git -C $target rev-parse HEAD | Select-Object -First 1)

  Assert-Equal 'feature/valid-01' (Assert-LizardGitBranchName -Branch 'feature/valid-01') 'Valid branch was changed.'
  Assert-Equal 'HEAD' (Assert-LizardGitBaseReference -BaseRef HEAD) 'HEAD base ref was changed.'
  Assert-Equal $head.ToLowerInvariant() (Resolve-LizardGitCommit -RepositoryRoot $target -BaseRef $head) 'Full commit ID did not resolve exactly.'

  foreach ($branch in @('-main', '--help', 'bad..branch', 'bad branch', 'bad~branch', 'bad^branch', 'bad.lock')) {
    Assert-ThrowsCode { Assert-LizardGitBranchName -Branch $branch | Out-Null } $(if ($branch.StartsWith('-') -or $branch -match '\s') { 'GIT_REF_INVALID' } else { 'GIT_BRANCH_INVALID' }) "Invalid branch '$branch' must fail closed."
  }
  foreach ($baseRef in @('-HEAD', '--help', 'HEAD~1', 'HEAD^', 'main..other', 'bad ref')) {
    Assert-ThrowsCode { Assert-LizardGitBaseReference -BaseRef $baseRef | Out-Null } $(if ($baseRef.StartsWith('-') -or $baseRef -match '\s') { 'GIT_REF_INVALID' } else { 'GIT_BASE_REF_INVALID' }) "Invalid base ref '$baseRef' must fail closed."
  }

  $script = Join-Path $LayerRoot 'scripts/loop-worktree.ps1'
  $optionBranch = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Branch', '--help', '-WorktreePath', (Join-Path $fixture 'worktree'), '-OutputDir', $output)
  Assert-False ($optionBranch.exit_code -eq 0) 'Option-like branch must fail before Git inspection.'
  Assert-True ($optionBranch.output -match 'GIT_REF_INVALID') 'Option-like branch must expose the stable validation code.'
  Assert-False (Test-Path -LiteralPath $output) 'Invalid branch must fail before report writes.'

  $revisionExpression = Invoke-TestPowerShell -ScriptPath $script -Arguments @('-TargetPath', $target, '-Branch', 'feature/test', '-BaseRef', 'HEAD~1', '-WorktreePath', (Join-Path $fixture 'worktree'), '-OutputDir', $output)
  Assert-False ($revisionExpression.exit_code -eq 0) 'Revision-expression base ref must fail before Git inspection.'
  Assert-True ($revisionExpression.output -match 'GIT_BASE_REF_INVALID') 'Revision-expression base ref must expose the stable validation code.'
  Assert-False (Test-Path -LiteralPath $output) 'Invalid base ref must fail before report writes.'

  Write-Host 'PASS tests\adversarial\git-ref-validation.tests.ps1'
} finally {
  if (Test-Path -LiteralPath $fixture) { Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot }
}
