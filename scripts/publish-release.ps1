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

# 8. GitHub Releases CLI Integration
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($null -ne $gh) {
  $null = & $gh.Source release view $tagName 2>$null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "GitHub Release '$tagName' already exists."
  } else {
    if (-not $DryRun.IsPresent) {
      Write-Host "Publishing GitHub Release for '$tagName' via gh CLI..."
      & $gh.Source release create $tagName --title $Title --notes $releaseNotes --target $CandidateSha
      Write-Host "Successfully published GitHub Release: $tagName"
    } else {
      Write-Host "[DRY RUN] Would publish GitHub Release for $tagName via gh CLI"
    }
  }
} else {
  Write-Host "Note: When tag '$tagName' is pushed, .github/workflows/release.yml will automatically publish the release."
}
