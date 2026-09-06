[CmdletBinding()]
param(
  [string]$Version = '',
  [string]$LayerRoot = '',
  [string]$CandidateSha = '',
  [string]$Title = '',
  [switch]$Push,
  [switch]$DryRun,
  [switch]$SkipReadinessCheck
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($LayerRoot)) {
  $LayerRoot = Split-Path -Parent $PSScriptRoot
}
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path

Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Json.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts/Lizard.Host.psm1') -Force

$PowerShellHost = Get-LizardPowerShellHostPath
$PowerShellFilePrefix = Get-LizardPowerShellFilePrefix

# 1. Resolve Target Version
$versionFile = Join-Path $LayerRoot 'VERSION'
if ([string]::IsNullOrWhiteSpace($Version)) {
  if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    $Version = (Get-Content -LiteralPath $versionFile -Raw).Trim()
  } else {
    throw "VERSION_FILE_MISSING: VERSION file not found at $versionFile"
  }
}
$tagName = "v$Version"

# 2. Resolve Candidate Commit SHA
if ([string]::IsNullOrWhiteSpace($CandidateSha)) {
  $CandidateSha = (& git -C $LayerRoot rev-parse HEAD).Trim()
}

# 3. Validate Release Readiness Gate
if (-not $SkipReadinessCheck.IsPresent) {
  Write-Host "Running release readiness verification for version $Version (commit $CandidateSha)..."
  $readinessScript = Join-Path $LayerRoot 'scripts/release-readiness.ps1'
  & $PowerShellHost @PowerShellFilePrefix $readinessScript -ExpectedVersion $Version -CandidateSha $CandidateSha -RequireCleanWorkingTree
  if ($LASTEXITCODE -ne 0) {
    throw "RELEASE_READINESS_FAILED: Candidate commit $CandidateSha did not pass release readiness checks."
  }
}

# 4. Extract Release Notes for Version from CHANGELOG.md
$changelogFile = Join-Path $LayerRoot 'CHANGELOG.md'
if (-not (Test-Path -LiteralPath $changelogFile -PathType Leaf)) {
  throw "CHANGELOG_MISSING: CHANGELOG.md not found at $changelogFile"
}
$changelogContent = Get-Content -LiteralPath $changelogFile -Raw
$escapedVersion = [regex]::Escape($Version)
$pattern = "(?s)## $escapedVersion\s*-\s*[^\r\n]*\r?\n(.*?)(?=\r?\n## |\Z)"
$releaseNotes = if ($changelogContent -match $pattern) {
  $matches[1].Trim()
} else {
  "Release $tagName"
}

# 5. Determine Release Title
if ([string]::IsNullOrWhiteSpace($Title)) {
  # Look for a top-level feature name or use standard format
  $Title = "$tagName"
}

# 6. Ensure Local Git Tag Exists
$existingTags = & git -C $LayerRoot tag -l $tagName
if ($existingTags -notcontains $tagName) {
  Write-Host "Creating annotated Git tag '$tagName' at commit $CandidateSha..."
  if (-not $DryRun.IsPresent) {
    & git -C $LayerRoot tag -a $tagName $CandidateSha -m "Release $tagName"
    if ($LASTEXITCODE -ne 0) {
      throw "GIT_TAG_FAILED: Failed to create Git tag $tagName"
    }
  } else {
    Write-Host "[DRY RUN] Would create Git tag $tagName"
  }
} else {
  Write-Host "Git tag '$tagName' already exists."
}

# 7. Push Tag If Requested
if ($Push.IsPresent) {
  Write-Host "Pushing tag '$tagName' to origin..."
  if (-not $DryRun.IsPresent) {
    & git -C $LayerRoot push origin $tagName
    if ($LASTEXITCODE -ne 0) {
      throw "GIT_PUSH_FAILED: Failed to push tag $tagName to origin"
    }
  } else {
    Write-Host "[DRY RUN] Would push tag $tagName to origin"
  }
}

# 8. GitHub Releases API Integration
function Get-GitHubAuthToken {
  if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) { return $env:GH_TOKEN }
  if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) { return $env:GITHUB_TOKEN }
  try {
    $credInfo = "protocol=https`nhost=github.com`n`n" | git credential fill 2>$null
    if ($credInfo) {
      foreach ($line in ($credInfo -split "`r?`n")) {
        if ($line -match '^password=(.+)$') { return $matches[1] }
      }
    }
  } catch {}
  return $null
}

$githubToken = Get-GitHubAuthToken
if ([string]::IsNullOrWhiteSpace($githubToken)) {
  Write-Warning "No GitHub token found (checked GH_TOKEN, GITHUB_TOKEN, git credential helper). GitHub Release cannot be published via API directly."
  Write-Host "Note: When the tag is pushed to GitHub, .github/workflows/release.yml will automatically publish the release."
  return
}

$repoOwner = 'sacrificeking'
$repoName = 'lizard-agent-layer'
$headers = @{
  'Authorization' = "Bearer $githubToken"
  'Accept' = 'application/vnd.github+json'
  'User-Agent' = 'PowerShell-Lizard-Release-Publisher'
}

$releaseUrl = "https://api.github.com/repos/$repoOwner/$repoName/releases/tags/$tagName"
$existingRelease = $null
try {
  $existingRelease = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get -ErrorAction Stop
} catch {
  # 404 means release does not exist yet
}

if ($null -ne $existingRelease) {
  Write-Host "GitHub Release '$tagName' already exists: $($existingRelease.html_url)"
} else {
  Write-Host "Publishing GitHub Release for '$tagName'..."
  $payload = @{
    tag_name = $tagName
    target_commitish = $CandidateSha
    name = $Title
    body = $releaseNotes
    draft = $false
    prerelease = $false
  } | ConvertTo-Json -Depth 5

  if (-not $DryRun.IsPresent) {
    $newRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/$repoOwner/$repoName/releases" -Method Post -Headers $headers -Body $payload -ContentType 'application/json; charset=utf-8'
    Write-Host "Successfully published GitHub Release: $($newRelease.html_url)"
  } else {
    Write-Host "[DRY RUN] Would publish GitHub Release for $tagName"
  }
}
