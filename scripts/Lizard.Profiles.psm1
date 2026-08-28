Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Lizard.Json.psm1')

function Get-LizardBuiltinProfileIds {
  [CmdletBinding()]
  param(
    [string]$LayerRoot = (Split-Path -Parent $PSScriptRoot)
  )

  $profilesDir = Join-Path $LayerRoot 'profiles'
  if (-not (Test-Path -LiteralPath $profilesDir)) {
    throw "PROFILES_DIRECTORY_NOT_FOUND: Profiles directory '$profilesDir' does not exist."
  }

  $profileFiles = @(Get-ChildItem -LiteralPath $profilesDir -Filter '*.json' -File | Sort-Object -Property Name)
  if ($profileFiles.Count -eq 0) {
    throw "PROFILES_EMPTY: No profile definitions found in '$profilesDir'."
  }

  $seenIds = New-Object System.Collections.Generic.HashSet[string]
  $ids = New-Object System.Collections.Generic.List[string]

  foreach ($file in $profileFiles) {
    $expectedId = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
    $content = Get-Content -LiteralPath $file.FullName -Raw
    $profileDoc = ConvertFrom-LizardJson -InputObject $content

    $declaredId = $null
    if ($profileDoc.PSObject.Properties['profile']) {
      $declaredId = [string]$profileDoc.profile
    } elseif ($profileDoc.PSObject.Properties['id']) {
      $declaredId = [string]$profileDoc.id
    } elseif ($profileDoc.PSObject.Properties['name']) {
      $declaredId = [string]$profileDoc.name
    } else {
      $declaredId = $expectedId
    }

    if ($declaredId -ne $expectedId) {
      throw "PROFILE_ID_FILENAME_MISMATCH: Profile in '$($file.Name)' declared id '$declaredId' but filename expects '$expectedId'."
    }

    if ($seenIds.Contains($declaredId)) {
      throw "PROFILE_DUPLICATE_ID: Duplicate profile ID '$declaredId' found in '$($file.Name)'."
    }

    $seenIds.Add($declaredId) | Out-Null
    $ids.Add($declaredId) | Out-Null
  }

  return @($ids | Sort-Object)
}

function Get-LizardSupportedHarnessIds {
  [CmdletBinding()]
  param(
    [string]$LayerRoot = (Split-Path -Parent $PSScriptRoot)
  )

  $adaptersDir = Join-Path $LayerRoot 'adapters'
  if (-not (Test-Path -LiteralPath $adaptersDir)) {
    throw "ADAPTERS_DIRECTORY_NOT_FOUND: Adapters directory '$adaptersDir' does not exist."
  }

  $adapterDirs = @(Get-ChildItem -LiteralPath $adaptersDir -Directory | Sort-Object -Property Name)
  if ($adapterDirs.Count -eq 0) {
    throw "ADAPTERS_EMPTY: No adapter definitions found in '$adaptersDir'."
  }

  $harnesses = @($adapterDirs | ForEach-Object { $_.Name } | Sort-Object)
  return $harnesses
}

Export-ModuleMember -Function Get-LizardBuiltinProfileIds, Get-LizardSupportedHarnessIds
