param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Apply
)

$ErrorActionPreference = "Stop"
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$SkillsRoot = Join-Path $TargetRoot '.agent\skills'
if (-not (Test-Path -LiteralPath $SkillsRoot)) { throw "Missing .agent\skills in target: $TargetRoot" }

$indexLines = New-Object System.Collections.Generic.List[string]
$manifestLines = New-Object System.Collections.Generic.List[string]
$indexLines.Add('# Skill Index') | Out-Null
$indexLines.Add('') | Out-Null

Get-ChildItem -LiteralPath $SkillsRoot -Directory | Sort-Object Name | ForEach-Object {
  $skillPath = Join-Path $_.FullName 'SKILL.md'
  if (-not (Test-Path -LiteralPath $skillPath)) { return }
  $name = $_.Name
  $indexLines.Add("## $name") | Out-Null
  $indexLines.Add(('Source: `.agent/skills/{0}/SKILL.md`' -f $name)) | Out-Null
  $indexLines.Add('') | Out-Null
  $manifest = [ordered]@{ name = $name; source = ".agent/skills/$name/SKILL.md" }
  $manifestLines.Add(($manifest | ConvertTo-Json -Compress)) | Out-Null
}

$indexContent = $indexLines -join "`n"
$manifestContent = $manifestLines -join "`n"

if ($Apply) {
  Set-Content -LiteralPath (Join-Path $SkillsRoot '_index.md') -Value $indexContent -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $SkillsRoot '_manifest.jsonl') -Value $manifestContent -Encoding UTF8
  Write-Host "Synced manifest in $SkillsRoot"
} else {
  Write-Host 'Preview generated _index.md:'
  Write-Host $indexContent
  Write-Host ''
  Write-Host 'Preview generated _manifest.jsonl:'
  Write-Host $manifestContent
  Write-Host ''
  Write-Host 'Preview only. Re-run with -Apply to write files.'
}
