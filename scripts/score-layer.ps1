param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$OutputDir,
  [int]$MinScore = 0,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $LayerRoot '.tmp\quality' }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

function Read-JsonFile { param([string]$Path) Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
function Get-RelativePath {
  param([string]$Path)
  $resolved = (Resolve-Path -LiteralPath $Path).Path
  $resolved.Substring($LayerRoot.Length).TrimStart('\').Replace('\', '/')
}
function Get-HealthBand {
  param([int]$Score)
  if ($Score -ge 90) { return 'excellent' }
  if ($Score -ge 80) { return 'strong' }
  if ($Score -ge 70) { return 'ready' }
  if ($Score -ge 60) { return 'watch' }
  'weak'
}
function Get-RiskRank {
  param([string]$Severity)
  switch ($Severity) {
    'critical' { 4 }
    'high' { 3 }
    'medium' { 2 }
    'low' { 1 }
    default { 0 }
  }
}
function Get-RiskLabel {
  param([object[]]$Findings)
  $label = 'low'; $rank = 1
  foreach ($finding in @($Findings)) {
    $current = Get-RiskRank ([string]$finding.severity)
    if ($current -gt $rank) { $rank = $current; $label = [string]$finding.severity }
  }
  $label
}
function New-Dimension {
  param([string]$Id, [int]$Score, [int]$MaxScore, [string]$Note)
  if ($Score -lt 0) { $Score = 0 }
  if ($Score -gt $MaxScore) { $Score = $MaxScore }
  [ordered]@{ id = $Id; score = $Score; max_score = $MaxScore; note = $Note }
}
function Get-Frontmatter {
  param([string[]]$Lines)
  $result = [ordered]@{ valid = $false; values = @{}; body_start = 0 }
  if ($Lines.Count -lt 3 -or $Lines[0] -ne '---') { return $result }
  $end = -1
  for ($i = 1; $i -lt $Lines.Count; $i++) { if ($Lines[$i] -eq '---') { $end = $i; break } }
  if ($end -lt 0) { return $result }
  $values = @{}
  foreach ($line in $Lines[1..($end - 1)]) {
    if ($line.Trim() -eq '') { continue }
    if ($line -match '^([A-Za-z0-9_-]+):\s*(.*)$') { $values[$Matches[1]] = $Matches[2].Trim() }
  }
  $result.valid = $true; $result.values = $values; $result.body_start = $end + 1
  $result
}
function Get-RiskFindings {
  param([string]$Kind, [string]$Name, [string]$Path, [string]$Text, [object]$Signals)
  $findings = New-Object System.Collections.Generic.List[object]
  foreach ($signal in @($Signals.signals)) {
    if ($Text -match ([string]$signal.pattern)) {
      $findings.Add([ordered]@{
        kind = $Kind; name = $Name; path = $Path; id = [string]$signal.id
        severity = [string]$signal.severity; message = [string]$signal.message
      }) | Out-Null
    }
  }
  @($findings.ToArray())
}

function Measure-Skill {
  param([System.IO.DirectoryInfo]$Directory, [object]$RiskSignals)
  $skillPath = Join-Path $Directory.FullName 'SKILL.md'
  $lines = Get-Content -LiteralPath $skillPath
  $text = ($lines -join "`n")
  $frontmatter = Get-Frontmatter -Lines $lines
  $values = $frontmatter.values
  $description = if ($values.ContainsKey('description')) { [string]$values['description'] } else { '' }
  $dimensions = New-Object System.Collections.Generic.List[object]

  $metadata = 0
  if ($frontmatter.valid) { $metadata += 4 }
  if ($values.ContainsKey('name') -and $values['name'] -eq $Directory.Name) { $metadata += 4 }
  if ($description.Length -ge 60) { $metadata += 5 } elseif ($description.Length -gt 0) { $metadata += 2 }
  if ($values.ContainsKey('description')) { $metadata += 2 }
  $dimensions.Add((New-Dimension 'metadata' $metadata 15 'frontmatter identity and description quality')) | Out-Null

  $activation = 0
  if ($description -match '(?i)\buse\s+(when|for)\b|\bwhen\s+to\s+use\b|\btrigger') { $activation = 15 }
  elseif ($text -match '(?i)\bwhen\b|\btrigger') { $activation = 8 }
  $dimensions.Add((New-Dimension 'activation' $activation 15 'clear use triggers')) | Out-Null

  $bulletCount = ([regex]::Matches($text, '(?m)^\s*-\s+')).Count
  $procedure = 0
  if ($text -match '(?im)^##\s+(Rules|Workflow|Procedure|Steps|Process|Protocol)\b') { $procedure += 12 }
  if ($bulletCount -ge 4) { $procedure += 8 } elseif ($bulletCount -ge 2) { $procedure += 4 }
  $dimensions.Add((New-Dimension 'procedure' $procedure 20 'actionable rules or workflow')) | Out-Null

  $verification = 0
  if ($text -match '(?im)^##\s+(Verification|Validation|Testing|Checks)\b') { $verification += 9 }
  if ($text -match '(?i)\b(test|typecheck|lint|build|validate|verify|review|audit|check)\b') { $verification += 6 }
  $dimensions.Add((New-Dimension 'verification' $verification 15 'explicit checks or validation language')) | Out-Null

  $safety = 0
  if ($text -match '(?i)\b(safety|risk|approval|secret|credential|permission|destructive|rollback|do not|preserve|avoid)\b') { $safety += 15 }
  $dimensions.Add((New-Dimension 'safety' $safety 15 'risk and permission discipline')) | Out-Null

  $support = 0
  if (Test-Path -LiteralPath (Join-Path $Directory.FullName 'references')) { $support += 4 }
  if (Test-Path -LiteralPath (Join-Path $Directory.FullName 'scripts')) { $support += 3 }
  if (Test-Path -LiteralPath (Join-Path $Directory.FullName 'tests')) { $support += 3 }
  if ($text -match '(?i)\bexample\b') { $support += 2 }
  $dimensions.Add((New-Dimension 'supporting-material' $support 10 'references, examples, scripts, or tests')) | Out-Null

  $portability = 10
  if ($text -match '[A-Za-z]:\\|/Users/|/home/') { $portability -= 5 }
  if ($text -match '(?i)\bonly\s+works\s+in\b') { $portability -= 3 }
  $dimensions.Add((New-Dimension 'portability' $portability 10 'avoids local machine assumptions')) | Out-Null

  $score = 0
  foreach ($dimension in @($dimensions.ToArray())) { $score += [int]$dimension.score }
  $findings = Get-RiskFindings -Kind 'skill' -Name $Directory.Name -Path (Get-RelativePath $skillPath) -Text $text -Signals $RiskSignals
  [ordered]@{
    kind = 'skill'; name = $Directory.Name; path = Get-RelativePath $skillPath
    score = $score; health = Get-HealthBand $score; risk = Get-RiskLabel $findings
    dimensions = @($dimensions.ToArray()); findings = @($findings)
  }
}

function Measure-Adapter {
  param([System.IO.DirectoryInfo]$Directory, [object]$RiskSignals)
  $manifestPath = Join-Path $Directory.FullName 'adapter.json'
  $adapter = Read-JsonFile $manifestPath
  $instructionPath = Join-Path $Directory.FullName ([string]$adapter.instruction.src).Replace('/', '\')
  $text = if (Test-Path -LiteralPath $instructionPath) { Get-Content -LiteralPath $instructionPath -Raw } else { '' }
  $dimensions = New-Object System.Collections.Generic.List[object]

  $metadata = 0
  if ($adapter.name -eq $Directory.Name) { $metadata += 6 }
  if ($adapter.description) { $metadata += 5 }
  if ($adapter.instruction.src -and $adapter.instruction.dst) { $metadata += 6 }
  if ($adapter.skillMirrors) { $metadata += 3 }
  $dimensions.Add((New-Dimension 'metadata' $metadata 20 'adapter manifest completeness')) | Out-Null

  $safety = 0
  if ($text -match '(?i)\bapproval|permission|do not|overwrite|destructive|safety|secret\b') { $safety += 20 }
  if ($adapter.instruction.sidecar) { $safety += 5 }
  $dimensions.Add((New-Dimension 'safety' $safety 25 'adapter instruction safety')) | Out-Null

  $memory = 0
  if ($text -match '(?i)\bmemory|project-profile|preferences|lessons|decisions\b') { $memory = 15 }
  $dimensions.Add((New-Dimension 'memory' $memory 15 'memory and profile startup discipline')) | Out-Null

  $handoff = 0
  if ($text -match '(?i)\bhandoff|multi-model|Codex|Claude|Gemini|Cursor\b') { $handoff = 15 }
  $dimensions.Add((New-Dimension 'handoff' $handoff 15 'cross-harness or handoff awareness')) | Out-Null

  $verification = 0
  if ($text -match '(?i)\bverification|checks|tests|build|validate|before finalizing\b') { $verification = 10 }
  $dimensions.Add((New-Dimension 'verification' $verification 10 'verification guidance')) | Out-Null

  $portability = 15
  if ($text -match '[A-Za-z]:\\|/Users/|/home/') { $portability -= 7 }
  if (($adapter.instruction.dst -as [string]) -match '^([A-Za-z]:|/)' ) { $portability -= 8 }
  $dimensions.Add((New-Dimension 'portability' $portability 15 'portable destination conventions')) | Out-Null

  $score = 0
  foreach ($dimension in @($dimensions.ToArray())) { $score += [int]$dimension.score }
  $combinedText = ((Get-Content -LiteralPath $manifestPath -Raw) + "`n" + $text)
  $findings = Get-RiskFindings -Kind 'adapter' -Name $Directory.Name -Path (Get-RelativePath $manifestPath) -Text $combinedText -Signals $RiskSignals
  [ordered]@{
    kind = 'adapter'; name = $Directory.Name; path = Get-RelativePath $manifestPath
    score = $score; health = Get-HealthBand $score; risk = Get-RiskLabel $findings
    dimensions = @($dimensions.ToArray()); findings = @($findings)
  }
}

function Measure-Profile {
  param([System.IO.FileInfo]$File, [object]$RiskSignals)
  $profile = Read-JsonFile $File.FullName
  $text = Get-Content -LiteralPath $File.FullName -Raw
  $dimensions = New-Object System.Collections.Generic.List[object]

  $metadata = 0
  foreach ($field in @('profile', 'riskLevel', 'memoryMode', 'projectSize')) { if ($profile.PSObject.Properties.Name -contains $field) { $metadata += 5 } }
  $dimensions.Add((New-Dimension 'metadata' $metadata 20 'profile identity and operating envelope')) | Out-Null

  $skills = @($profile.skills).Count
  $skillScore = if ($skills -ge 4) { 20 } elseif ($skills -ge 2) { 14 } elseif ($skills -eq 1) { 8 } else { 0 }
  $dimensions.Add((New-Dimension 'skills' $skillScore 20 'curated skill coverage')) | Out-Null

  $harnesses = @($profile.harnesses).Count
  $harnessScore = if ($harnesses -ge 3) { 20 } elseif ($harnesses -eq 2) { 15 } elseif ($harnesses -eq 1) { 10 } else { 0 }
  $dimensions.Add((New-Dimension 'harnesses' $harnessScore 20 'harness coverage')) | Out-Null

  $modelCount = if ($profile.modelProfiles) { @($profile.modelProfiles.PSObject.Properties).Count } else { 0 }
  $modelScore = if ($modelCount -ge 3) { 15 } elseif ($modelCount -gt 0) { 8 } else { 0 }
  $dimensions.Add((New-Dimension 'model-routing' $modelScore 15 'model role mapping')) | Out-Null

  $verificationCount = @($profile.verification).Count
  $verificationScore = 0
  if ($profile.riskLevel -eq 'low') { $verificationScore = 15 }
  elseif ($verificationCount -ge 2) { $verificationScore = 15 }
  elseif ($verificationCount -eq 1) { $verificationScore = 8 }
  $dimensions.Add((New-Dimension 'verification' $verificationScore 15 'risk-adjusted verification checks')) | Out-Null

  $notesScore = if (-not [string]::IsNullOrWhiteSpace([string]$profile.notes)) { 10 } else { 0 }
  $dimensions.Add((New-Dimension 'notes' $notesScore 10 'profile intent and adaptation notes')) | Out-Null

  $score = 0
  foreach ($dimension in @($dimensions.ToArray())) { $score += [int]$dimension.score }
  $findings = Get-RiskFindings -Kind 'profile' -Name ([string]$profile.profile) -Path (Get-RelativePath $File.FullName) -Text $text -Signals $RiskSignals
  [ordered]@{
    kind = 'profile'; name = [string]$profile.profile; path = Get-RelativePath $File.FullName
    score = $score; health = Get-HealthBand $score; risk = Get-RiskLabel $findings
    dimensions = @($dimensions.ToArray()); findings = @($findings)
  }
}

$rubric = Read-JsonFile (Join-Path $LayerRoot 'registry\quality-rubric.json')
$riskSignals = Read-JsonFile (Join-Path $LayerRoot 'registry\risk-signals.json')
if ($MinScore -le 0) { $MinScore = [int]$rubric.minimumScore }

$skills = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'skills') -Directory | Sort-Object Name | ForEach-Object {
  $skills.Add((Measure-Skill -Directory $_ -RiskSignals $riskSignals)) | Out-Null
}
$adapters = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'adapters') -Directory | Sort-Object Name | ForEach-Object {
  $adapters.Add((Measure-Adapter -Directory $_ -RiskSignals $riskSignals)) | Out-Null
}
$profiles = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'profiles') -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
  $profiles.Add((Measure-Profile -File $_ -RiskSignals $riskSignals)) | Out-Null
}

$allArtifacts = @($skills.ToArray()) + @($adapters.ToArray()) + @($profiles.ToArray())
$allFindings = New-Object System.Collections.Generic.List[object]
foreach ($artifact in @($allArtifacts)) { foreach ($finding in @($artifact.findings)) { $allFindings.Add($finding) | Out-Null } }

$gateFailures = New-Object System.Collections.Generic.List[string]
foreach ($artifact in @($allArtifacts)) {
  if ([int]$artifact.score -lt $MinScore) { $gateFailures.Add("$($artifact.kind) '$($artifact.name)' scored $($artifact.score), below $MinScore.") | Out-Null }
  foreach ($finding in @($artifact.findings)) {
    if ($finding.severity -eq 'critical') { $gateFailures.Add("$($artifact.kind) '$($artifact.name)' has critical risk signal '$($finding.id)'.") | Out-Null }
  }
}

$totalScore = 0
$minimum = 0
if ($allArtifacts.Count -gt 0) {
  $minimum = [int]$allArtifacts[0].score
  foreach ($artifact in @($allArtifacts)) {
    $scoreValue = [int]$artifact.score
    $totalScore += $scoreValue
    if ($scoreValue -lt $minimum) { $minimum = $scoreValue }
  }
  $average = [Math]::Round(($totalScore / $allArtifacts.Count), 2)
} else {
  $average = 0
}
$criticalCount = @($allFindings.ToArray() | Where-Object { $_.severity -eq 'critical' }).Count
$highCount = @($allFindings.ToArray() | Where-Object { $_.severity -eq 'high' }).Count

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  layer_root = $LayerRoot
  minimum_score = $MinScore
  strict = $Strict.IsPresent
  gate = if ($gateFailures.Count -eq 0) { 'pass' } else { 'fail' }
  summary = [ordered]@{
    artifacts = $allArtifacts.Count; skills = $skills.Count; adapters = $adapters.Count; profiles = $profiles.Count
    average_score = $average; minimum_score = $minimum; critical_findings = $criticalCount; high_findings = $highCount
  }
  gate_failures = @($gateFailures.ToArray())
  skills = @($skills.ToArray())
  adapters = @($adapters.ToArray())
  profiles = @($profiles.ToArray())
  findings = @($allFindings.ToArray())
}

$jsonPath = Join-Path $OutputDir 'layer-quality-report.json'
$mdPath = Join-Path $OutputDir 'layer-quality-report.md'
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Lizard Agent Layer Quality Report') | Out-Null
$md.Add('') | Out-Null
$md.Add("Generated: $($report.generated_at)") | Out-Null
$md.Add("Gate: $($report.gate)") | Out-Null
$md.Add("Minimum score: $MinScore") | Out-Null
$md.Add('') | Out-Null
$md.Add('## Summary') | Out-Null
$md.Add('') | Out-Null
$md.Add("- Artifacts: $($report.summary.artifacts)") | Out-Null
$md.Add("- Skills: $($report.summary.skills)") | Out-Null
$md.Add("- Adapters: $($report.summary.adapters)") | Out-Null
$md.Add("- Profiles: $($report.summary.profiles)") | Out-Null
$md.Add("- Average score: $($report.summary.average_score)") | Out-Null
$md.Add("- Minimum artifact score: $($report.summary.minimum_score)") | Out-Null
$md.Add("- Critical findings: $criticalCount") | Out-Null
$md.Add("- High findings: $highCount") | Out-Null
$md.Add('') | Out-Null
foreach ($section in @(@{title='Skills'; items=@($skills.ToArray())}, @{title='Adapters'; items=@($adapters.ToArray())}, @{title='Profiles'; items=@($profiles.ToArray())})) {
  $md.Add("## $($section.title)") | Out-Null
  $md.Add('') | Out-Null
  $md.Add('| Name | Score | Health | Risk |') | Out-Null
  $md.Add('| --- | ---: | --- | --- |') | Out-Null
  foreach ($item in @($section.items)) { $md.Add("| $($item.name) | $($item.score) | $($item.health) | $($item.risk) |") | Out-Null }
  $md.Add('') | Out-Null
}
if ($gateFailures.Count -gt 0) {
  $md.Add('## Gate Failures') | Out-Null
  $md.Add('') | Out-Null
  foreach ($failure in @($gateFailures.ToArray())) { $md.Add("- $failure") | Out-Null }
  $md.Add('') | Out-Null
}
if ($allFindings.Count -gt 0) {
  $md.Add('## Risk Findings') | Out-Null
  $md.Add('') | Out-Null
  $md.Add('| Severity | Artifact | Signal | Message |') | Out-Null
  $md.Add('| --- | --- | --- | --- |') | Out-Null
  foreach ($finding in @($allFindings.ToArray())) { $md.Add("| $($finding.severity) | $($finding.kind)/$($finding.name) | $($finding.id) | $($finding.message) |") | Out-Null }
  $md.Add('') | Out-Null
}
$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

Write-Host "Quality gate: $($report.gate)"
Write-Host "Artifacts: $($report.summary.artifacts), average score: $average, minimum score: $minimum"
Write-Host "Report: $jsonPath"
Write-Host "Markdown: $mdPath"
if ($Strict -and $gateFailures.Count -gt 0) {
  foreach ($failure in @($gateFailures.ToArray())) { Write-Host "FAIL $failure" }
  exit 1
}

