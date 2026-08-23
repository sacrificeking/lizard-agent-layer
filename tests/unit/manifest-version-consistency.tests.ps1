param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force

$installSource = Get-Content -LiteralPath (Join-Path $LayerRoot 'scripts\install.ps1') -Raw
$updateSource = Get-Content -LiteralPath (Join-Path $LayerRoot 'scripts\update-target.ps1') -Raw

function Get-SingleSchemaVersion {
  param([string]$Source, [string]$Pattern, [string]$Label)
  $matches = [regex]::Matches($Source, $Pattern)
  Assert-Equal 1 $matches.Count "$Label must have exactly one authoritative assignment."
  return [int]$matches[0].Groups[1].Value
}

$manifestSchema = Get-SingleSchemaVersion -Source $installSource -Pattern "\`$doc\['schema_version'\]\s*=\s*(\d+)" -Label 'Install manifest schema'
$minimumReader = Get-SingleSchemaVersion -Source $installSource -Pattern "\`$doc\['minimum_reader_schema_version'\]\s*=\s*(\d+)" -Label 'Install minimum reader schema'
$writerSchema = Get-SingleSchemaVersion -Source $installSource -Pattern "\`$doc\['writer_schema_version'\]\s*=\s*(\d+)" -Label 'Install writer schema'
$historyTarget = Get-SingleSchemaVersion -Source $updateSource -Pattern 'to_manifest_schema\s*=\s*(\d+)' -Label 'Update history target schema'
$reportTarget = Get-SingleSchemaVersion -Source $updateSource -Pattern 'target_manifest_schema\s*=\s*(\d+)' -Label 'Update report target schema'

foreach ($entry in @($manifestSchema, $minimumReader, $writerSchema, $historyTarget, $reportTarget)) {
  Assert-Equal 4 $entry 'Every manifest writer and emitted target-schema claim must remain on schema v4.'
}

Write-Host 'PASS tests\unit\manifest-version-consistency.tests.ps1'
