param([string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)))

$ErrorActionPreference = 'Stop'
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
Import-Module (Join-Path $LayerRoot 'tests\TestHelpers.psm1') -Force
Import-Module (Join-Path $LayerRoot 'scripts\Lizard.Manifest.psm1') -Force

$testRoot = Join-Path $LayerRoot '.tmp\tests'
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
$fixture = Join-Path $testRoot ("manifest-v3-{0}" -f ([Guid]::NewGuid().ToString('N')))
$installScript = Join-Path $LayerRoot 'scripts\install.ps1'
$diffScript = Join-Path $LayerRoot 'scripts\manifest-diff.ps1'
New-Item -ItemType Directory -Path $fixture -Force | Out-Null

function New-Target {
  param([string]$Name)
  $target = Join-Path $fixture $Name
  New-Item -ItemType Directory -Path $target -Force | Out-Null
  return $target
}

function Read-Manifest {
  param([string]$Target)
  Get-Content -LiteralPath (Join-Path $Target '.agent\lizard-agent-layer.install.json') -Raw | ConvertFrom-Json
}

function Find-Artifact {
  param($Manifest, [string]$Path)
  @($Manifest.artifacts | Where-Object { [string]$_.path -eq $Path } | Select-Object -First 1)[0]
}

try {
  $ownedTarget = New-Target 'ownership'
  $protocolRoot = Join-Path $ownedTarget '.agent\protocols'
  New-Item -ItemType Directory -Path $protocolRoot -Force | Out-Null
  $userFile = Join-Path $protocolRoot 'permissions.md'
  Set-Content -LiteralPath $userFile -Value 'project-owned-canary' -Encoding UTF8
  $install = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $ownedTarget, '-Profile', 'minimal', '-Apply')
  Assert-Equal 0 $install.exit_code 'Fresh v3 install with a pre-existing file must succeed.'
  $manifest = Read-Manifest $ownedTarget
  Assert-Equal 3 ([int]$manifest.schema_version) 'Installer must emit manifest schema v3.'
  $userArtifact = Find-Artifact $manifest '.agent/protocols/permissions.md'
  Assert-Equal 'user-owned' ([string]$userArtifact.ownership) 'Pre-existing files must remain user-owned.'
  $layerArtifact = Find-Artifact $manifest '.agent/protocols/handoff.md'
  Assert-Equal 'layer-owned' ([string]$layerArtifact.ownership) 'Newly installed files must be layer-owned.'
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$layerArtifact.installed_hash)) 'Layer-owned files require an installed hash.'

  Set-Content -LiteralPath $userFile -Value 'project-owned-customized' -Encoding UTF8
  $forceManaged = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $ownedTarget, '-Profile', 'minimal', '-Apply', '-ForceManaged')
  Assert-Equal 0 $forceManaged.exit_code 'ForceManaged must complete while preserving user-owned conflicts.'
  Assert-True ((Get-Content -LiteralPath $userFile -Raw) -match 'project-owned-customized') 'ForceManaged must not replace user-owned content.'
  $manifest = Read-Manifest $ownedTarget
  Assert-True (@($manifest.conflicts | Where-Object { $_ -match 'permissions.md' }).Count -gt 0) 'Preserved ForceManaged conflicts must be recorded.'

  $tamperTarget = New-Target 'tamper'
  $install = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $tamperTarget, '-Profile', 'minimal', '-Harnesses', 'generic-agents-md,codex', '-Apply')
  Assert-Equal 0 $install.exit_code 'Combined compatible adapter install must succeed.'
  $manifest = Read-Manifest $tamperTarget
  Assert-Equal 'codex' ([string]$manifest.adapters[0]) 'Codex must win declared AGENTS.md precedence.'
  Assert-True (@($manifest.adapter_aliases | Where-Object { $_.adapter -eq 'generic-agents-md' -and $_.satisfied_by -eq 'codex' }).Count -eq 1) 'Generic adapter must be recorded as a Codex compatibility alias.'

  $tamperedPath = Join-Path $tamperTarget '.agent\protocols\handoff.md'
  $tamperedInstructionPath = Join-Path $tamperTarget 'AGENTS.md'
  $tamperedMirrorPath = Join-Path $tamperTarget '.agents\skills\git-safety\SKILL.md'
  Add-Content -LiteralPath $tamperedPath -Value 'tamper' -Encoding UTF8
  Add-Content -LiteralPath $tamperedInstructionPath -Value 'tamper' -Encoding UTF8
  Add-Content -LiteralPath $tamperedMirrorPath -Value 'tamper' -Encoding UTF8
  $diffDir = Join-Path $fixture 'tamper-diff'
  $diff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $tamperTarget, '-LayerRoot', $LayerRoot, '-OutputDir', $diffDir, '-Strict')
  Assert-False ($diff.exit_code -eq 0) 'Strict diff must reject modified layer-owned content.'
  $diffReport = Get-Content -LiteralPath (Join-Path $diffDir 'manifest-diff.json') -Raw | ConvertFrom-Json
  Assert-True (@($diffReport.differences | Where-Object { $_.kind -eq 'content-modified' -and $_.value -eq '.agent/protocols/handoff.md' }).Count -eq 1) 'Tamper report must name the exact modified artifact.'
  Assert-True (@($diffReport.differences | Where-Object { $_.kind -eq 'adapter-identity-mismatch' -and $_.value -eq 'codex' }).Count -eq 1) 'Tampered instruction identity must invalidate the effective adapter.'
  Assert-True (@($diffReport.differences | Where-Object { $_.kind -eq 'mirror-mismatch' -and $_.value -eq 'skill:git-safety:SKILL.md' }).Count -eq 1) 'Tampered harness mirror must invalidate mirror equality.'
  $tamperedHash = Get-LizardSha256 $tamperedPath
  $tamperedInstructionHash = Get-LizardSha256 $tamperedInstructionPath
  $tamperedMirrorHash = Get-LizardSha256 $tamperedMirrorPath
  $forceTamper = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $tamperTarget, '-Profile', 'minimal', '-Harnesses', 'generic-agents-md,codex', '-Apply', '-ForceManaged')
  Assert-Equal 0 $forceTamper.exit_code 'ForceManaged must fail closed per artifact without aborting the reviewed install.'
  Assert-Equal $tamperedHash (Get-LizardSha256 $tamperedPath) 'ForceManaged must preserve locally modified layer-owned files.'
  Assert-Equal $tamperedInstructionHash (Get-LizardSha256 $tamperedInstructionPath) 'ForceManaged must preserve a locally modified adapter instruction.'
  Assert-Equal $tamperedMirrorHash (Get-LizardSha256 $tamperedMirrorPath) 'ForceManaged must preserve a locally modified harness mirror.'

  $legacyTarget = New-Target 'legacy-v2'
  $install = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $legacyTarget, '-Profile', 'minimal', '-Apply')
  Assert-Equal 0 $install.exit_code 'Legacy migration fixture setup must install.'
  $v3 = Read-Manifest $legacyTarget
  $v2 = [ordered]@{
    schema_version = 2; layer = 'lizard-agent-layer'; layer_version = [string]$v3.layer_version; profile = [string]$v3.profile
    requested_packs = @($v3.requested_packs); packs = @($v3.packs); harnesses = @($v3.harnesses); skills = @($v3.skills)
    managed_paths = @($v3.managed_paths); owned_paths = @($v3.owned_paths); risk_level = [string]$v3.risk_level
  }
  $legacyManifestPath = Join-Path $legacyTarget '.agent\lizard-agent-layer.install.json'
  $v2 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $legacyManifestPath -Encoding UTF8
  $legacyDiffDir = Join-Path $fixture 'legacy-diff'
  $legacyDiff = Invoke-TestPowerShell -ScriptPath $diffScript -Arguments @('-TargetPath', $legacyTarget, '-LayerRoot', $LayerRoot, '-OutputDir', $legacyDiffDir, '-Strict')
  Assert-False ($legacyDiff.exit_code -eq 0) 'Legacy manifests must never pass strict integrity checks.'
  $legacyDiffReport = Get-Content -LiteralPath (Join-Path $legacyDiffDir 'manifest-diff.json') -Raw | ConvertFrom-Json
  Assert-Equal 'integrity-unknown' ([string]$legacyDiffReport.status) 'Legacy strict diff must report integrity-unknown.'
  $legacyFile = Join-Path $legacyTarget '.agent\protocols\permissions.md'
  Set-Content -LiteralPath $legacyFile -Value 'legacy-customization' -Encoding UTF8
  $migration = Invoke-TestPowerShell -ScriptPath $installScript -Arguments @('-TargetPath', $legacyTarget, '-Profile', 'minimal', '-Apply', '-ForceManaged')
  Assert-Equal 0 $migration.exit_code 'Conservative v2-to-v3 migration must succeed.'
  Assert-True ((Get-Content -LiteralPath $legacyFile -Raw) -match 'legacy-customization') 'Ambiguous v2 content must remain untouched.'
  $migrated = Read-Manifest $legacyTarget
  Assert-Equal 3 ([int]$migrated.schema_version) 'Legacy manifest must migrate to v3.'
  Assert-Equal 2 ([int]$migrated.migrated_from_schema_version) 'Migration provenance must record schema v2.'
  Assert-Equal 'user-owned' ([string](Find-Artifact $migrated '.agent/protocols/permissions.md').ownership) 'Ambiguous legacy content must migrate as user-owned.'

  $collisionA = [pscustomobject]@{ name = 'one'; adapter_dir = $fixture; manifest = [pscustomobject]@{ instruction = [pscustomobject]@{ dst = 'AGENTS.md' }; skillMirrors = @() } }
  $collisionB = [pscustomobject]@{ name = 'two'; adapter_dir = $fixture; manifest = [pscustomobject]@{ instruction = [pscustomobject]@{ dst = 'AGENTS.md' }; skillMirrors = @() } }
  Assert-ThrowsCode { Resolve-LizardAdapterComposition -Adapters @($collisionA, $collisionB) | Out-Null } 'ADAPTER_DESTINATION_CONFLICT' 'Undeclared adapter destination collisions must fail preflight.'
  $overlapB = [pscustomobject]@{ name = 'two'; adapter_dir = $fixture; manifest = [pscustomobject]@{ instruction = [pscustomobject]@{ dst = 'AGENTS.md/nested' }; skillMirrors = @() } }
  Assert-ThrowsCode { Resolve-LizardAdapterComposition -Adapters @($collisionA, $overlapB) | Out-Null } 'ADAPTER_DESTINATION_OVERLAP' 'Instruction ancestor overlaps must fail preflight.'

  $adapterEntries = @()
  Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'adapters') -Directory | Sort-Object Name | ForEach-Object {
    $adapterEntries += [pscustomobject]@{ name = $_.Name; adapter_dir = $_.FullName; manifest = (Get-Content -LiteralPath (Join-Path $_.FullName 'adapter.json') -Raw | ConvertFrom-Json) }
  }
  for ($i = 0; $i -lt $adapterEntries.Count; $i++) {
    for ($j = $i + 1; $j -lt $adapterEntries.Count; $j++) {
      $forward = Resolve-LizardAdapterComposition -Adapters @($adapterEntries[$i], $adapterEntries[$j])
      $reverse = Resolve-LizardAdapterComposition -Adapters @($adapterEntries[$j], $adapterEntries[$i])
      $forwardWinners = @($forward.effective_instructions | ForEach-Object { "$($_.destination):$($_.name)" } | Sort-Object) -join ','
      $reverseWinners = @($reverse.effective_instructions | ForEach-Object { "$($_.destination):$($_.name)" } | Sort-Object) -join ','
      Assert-Equal $forwardWinners $reverseWinners "Adapter composition must be order-independent for $($adapterEntries[$i].name) and $($adapterEntries[$j].name)."
    }
  }

  Write-Host 'PASS manifest v3 integration tests'
} finally {
  Clear-TestDirectory -Path $fixture -AllowedRoot $testRoot
}
