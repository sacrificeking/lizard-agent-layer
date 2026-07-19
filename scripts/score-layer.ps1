param(
  [string]$LayerRoot = (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)),
  [string]$OutputDir,
  [int]$MinScore = 0,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$LayerRoot = (Resolve-Path -LiteralPath $LayerRoot).Path
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $ScriptDir 'Lizard.SafeFs.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.Host.psm1') -Force
Import-Module (Join-Path $ScriptDir 'Lizard.QualityEvidence.psm1') -Force
$LayerRoot = Resolve-SafeRoot -Path $LayerRoot -RequireExisting
if ([string]::IsNullOrWhiteSpace($OutputDir)) { $OutputDir = Join-Path $LayerRoot '.tmp\quality' }
$OutputDir = Initialize-SafeDirectory -Path $OutputDir

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

function Get-SkillSupportAssets {
  param([System.IO.DirectoryInfo]$Directory)
  $references = Test-Path -LiteralPath (Join-Path $Directory.FullName 'references')
  $examples = Test-Path -LiteralPath (Join-Path $Directory.FullName 'examples')
  $scripts = Test-Path -LiteralPath (Join-Path $Directory.FullName 'scripts')
  $tests = Test-Path -LiteralPath (Join-Path $Directory.FullName 'tests')
  [ordered]@{
    references = $references
    examples = $examples
    scripts = $scripts
    tests = $tests
    has_any = ($references -or $examples -or $scripts -or $tests)
  }
}
function Get-SkillMaturity {
  param(
    [int]$DocumentationScore,
    [object]$SupportAssets,
    [bool]$HasVerification,
    [bool]$HasSafety,
    [object]$BehavioralEvidence,
    [object]$BehavioralPolicy
  )
  $behaviorPassed = $BehavioralEvidence.declared -and $BehavioralEvidence.gate -eq 'pass'
  if ($DocumentationScore -ge 90 -and $behaviorPassed -and [int]$BehavioralEvidence.score -ge [int]$BehavioralPolicy.minimum_certified_score -and $SupportAssets.references) { return 'certified' }
  if ($DocumentationScore -ge 80 -and $behaviorPassed -and [int]$BehavioralEvidence.score -ge [int]$BehavioralPolicy.minimum_hardened_score -and $SupportAssets.has_any) { return 'hardened' }
  if ($DocumentationScore -ge 75 -and $HasVerification -and $HasSafety) { return 'ready' }
  if ($DocumentationScore -ge 65) { return 'baseline' }
  'weak'
}
function Measure-Skill {
  param([System.IO.DirectoryInfo]$Directory, [object]$RiskSignals, $FocusedReport, [string]$CurrentHostId, [object]$BehavioralPolicy)
  $skillPath = Join-Path $Directory.FullName 'SKILL.md'
  $lines = Get-Content -LiteralPath $skillPath
  $text = ($lines -join "`n")
  $frontmatter = Get-Frontmatter -Lines $lines
  $values = $frontmatter.values
  $description = if ($values.ContainsKey('description')) { [string]$values['description'] } else { '' }
  $dimensions = New-Object System.Collections.Generic.List[object]
  $supportAssets = Get-SkillSupportAssets -Directory $Directory

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

  $hasVerification = $verification -gt 0
  $hasSafety = $safety -gt 0
  $support = 0
  if ($supportAssets.references) { $support += 4 }
  if ($supportAssets.scripts) { $support += 3 }
  if ($supportAssets.tests) { $support += 3 }
  if ($supportAssets.examples -or $text -match '(?i)\bexample\b') { $support += 2 }
  $dimensions.Add((New-Dimension 'supporting-material' $support 10 'references, examples, scripts, or tests')) | Out-Null

  $portability = 10
  if ($text -match '[A-Za-z]:\\|/Users/|/home/') { $portability -= 5 }
  if ($text -match '(?i)\bonly\s+works\s+in\b') { $portability -= 3 }
  $dimensions.Add((New-Dimension 'portability' $portability 10 'avoids local machine assumptions')) | Out-Null

  $documentationScore = 0
  foreach ($dimension in @($dimensions.ToArray())) { $documentationScore += [int]$dimension.score }
  $findings = Get-RiskFindings -Kind 'skill' -Name $Directory.Name -Path (Get-RelativePath $skillPath) -Text $text -Signals $RiskSignals
  $behavioralEvidence = Get-LizardBehavioralEvidence -LayerRoot $LayerRoot -SkillDirectory $Directory -FocusedReport $FocusedReport -CurrentHostId $CurrentHostId
  $maturity = Get-SkillMaturity -DocumentationScore $documentationScore -SupportAssets $supportAssets -HasVerification $hasVerification -HasSafety $hasSafety -BehavioralEvidence $behavioralEvidence -BehavioralPolicy $BehavioralPolicy
  [ordered]@{
    kind = 'skill'; name = $Directory.Name; path = Get-RelativePath $skillPath
    score = $documentationScore; documentation_score = $documentationScore; behavioral_readiness_score = [int]$behavioralEvidence.score
    health = Get-HealthBand $documentationScore; risk = Get-RiskLabel $findings; maturity = $maturity
    support_assets = $supportAssets
    behavioral_evidence = $behavioralEvidence
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

  $stagedScore = 0
  if (-not [string]::IsNullOrWhiteSpace([string]$profile.routingPolicy)) { $stagedScore += 7 }
  if ([string]$profile.modelMode -in @('inherit-current', 'inventory-routing')) { $stagedScore += 8 }
  $dimensions.Add((New-Dimension 'staged-execution' $stagedScore 15 'portable phase policy and explicit model mode')) | Out-Null

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
$maturityLevels = Read-JsonFile (Join-Path $LayerRoot 'registry\maturity-levels.json')
$behavioralPolicy = Read-JsonFile (Join-Path $LayerRoot 'registry\behavioral-readiness.json')
$focusedReportPath = Join-Path $LayerRoot '.tmp\tests\focused-test-report.json'
$focusedReport = if (Test-Path -LiteralPath $focusedReportPath -PathType Leaf) { Read-JsonFile $focusedReportPath } else { $null }
$currentHostId = Get-LizardHostId
if ($MinScore -le 0) { $MinScore = [int]$rubric.minimumScore }

$skills = New-Object System.Collections.Generic.List[object]
Get-ChildItem -LiteralPath (Join-Path $LayerRoot 'skills') -Directory | Sort-Object Name | ForEach-Object {
  $skills.Add((Measure-Skill -Directory $_ -RiskSignals $riskSignals -FocusedReport $focusedReport -CurrentHostId $currentHostId -BehavioralPolicy $behavioralPolicy)) | Out-Null
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
  if ($artifact.kind -eq 'skill' -and $artifact.behavioral_evidence.declared -and $artifact.behavioral_evidence.gate -ne 'pass') {
    foreach ($failure in @($artifact.behavioral_evidence.failures)) {
      $gateFailures.Add("skill '$($artifact.name)' behavioral evidence failed: $failure") | Out-Null
    }
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
$maturityCounts = [ordered]@{ certified = 0; hardened = 0; ready = 0; baseline = 0; weak = 0 }
$behaviorDeclared = 0
$behaviorPassed = 0
$behaviorTotal = 0
$declaredBehaviorTotal = 0
foreach ($skill in @($skills.ToArray())) {
  $level = [string]$skill.maturity
  if (-not $maturityCounts.Contains($level)) { $maturityCounts[$level] = 0 }
  $maturityCounts[$level] = [int]$maturityCounts[$level] + 1
  $behaviorTotal += [int]$skill.behavioral_readiness_score
  if ($skill.behavioral_evidence.declared) {
    $behaviorDeclared++
    $declaredBehaviorTotal += [int]$skill.behavioral_readiness_score
    if ($skill.behavioral_evidence.gate -eq 'pass') { $behaviorPassed++ }
  }
}
$averageBehavioral = if ($skills.Count -gt 0) { [Math]::Round(($behaviorTotal / $skills.Count), 2) } else { 0 }
$averageDeclaredBehavioral = if ($behaviorDeclared -gt 0) { [Math]::Round(($declaredBehaviorTotal / $behaviorDeclared), 2) } else { 0 }

$report = [ordered]@{
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  layer_root = $LayerRoot
  minimum_score = $MinScore
  strict = $Strict.IsPresent
  gate = if ($gateFailures.Count -eq 0) { 'pass' } else { 'fail' }
  summary = [ordered]@{
    artifacts = $allArtifacts.Count; skills = $skills.Count; adapters = $adapters.Count; profiles = $profiles.Count
    average_score = $average; minimum_score = $minimum; critical_findings = $criticalCount; high_findings = $highCount
    average_documentation_score = $average; average_behavioral_readiness_score = $averageBehavioral
    average_declared_behavioral_readiness_score = $averageDeclaredBehavioral
    skills_with_behavioral_evidence = $behaviorDeclared; behavioral_evidence_passed = $behaviorPassed
    skill_maturity = $maturityCounts
  }
  gate_failures = @($gateFailures.ToArray())
  skills = @($skills.ToArray())
  adapters = @($adapters.ToArray())
  profiles = @($profiles.ToArray())
  findings = @($allFindings.ToArray())
  maturity_levels = $maturityLevels
  behavioral_readiness_policy = $behavioralPolicy
  behavioral_evidence_context = [ordered]@{
    current_host = $currentHostId
    focused_report_path = if ($focusedReport) { $focusedReportPath } else { $null }
    focused_report_generated_at = if ($focusedReport) { [string]$focusedReport.generated_at } else { $null }
  }
}

$jsonPath = Join-Path $OutputDir 'layer-quality-report.json'
$mdPath = Join-Path $OutputDir 'layer-quality-report.md'
Set-SafeContent -AuthorizedRoot $OutputDir -Path $jsonPath -Value ($report | ConvertTo-Json -Depth 10)

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
$md.Add("- Average documentation score: $($report.summary.average_documentation_score)") | Out-Null
$md.Add("- Average behavioral readiness: $($report.summary.average_behavioral_readiness_score)") | Out-Null
$md.Add("- Average declared behavioral readiness: $($report.summary.average_declared_behavioral_readiness_score)") | Out-Null
$md.Add("- Behavioral evidence: $behaviorPassed/$behaviorDeclared declared skills passing") | Out-Null
$md.Add("- Minimum artifact score: $($report.summary.minimum_score)") | Out-Null
$md.Add("- Critical findings: $criticalCount") | Out-Null
$md.Add("- High findings: $highCount") | Out-Null
$md.Add("- Skill maturity: certified $($maturityCounts.certified), hardened $($maturityCounts.hardened), ready $($maturityCounts.ready), baseline $($maturityCounts.baseline), weak $($maturityCounts.weak)") | Out-Null
$md.Add('') | Out-Null
foreach ($section in @(@{title='Skills'; items=@($skills.ToArray())}, @{title='Adapters'; items=@($adapters.ToArray())}, @{title='Profiles'; items=@($profiles.ToArray())})) {
  $md.Add("## $($section.title)") | Out-Null
  $md.Add('') | Out-Null
  if ($section.title -eq 'Skills') {
    $md.Add('| Name | Documentation | Behavioral | Health | Maturity | Risk |') | Out-Null
    $md.Add('| --- | ---: | ---: | --- | --- | --- |') | Out-Null
    foreach ($item in @($section.items)) { $md.Add("| $($item.name) | $($item.documentation_score) | $($item.behavioral_readiness_score) | $($item.health) | $($item.maturity) | $($item.risk) |") | Out-Null }
  } else {
    $md.Add('| Name | Score | Health | Risk |') | Out-Null
    $md.Add('| --- | ---: | --- | --- |') | Out-Null
    foreach ($item in @($section.items)) { $md.Add("| $($item.name) | $($item.score) | $($item.health) | $($item.risk) |") | Out-Null }
  }
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
Set-SafeContent -AuthorizedRoot $OutputDir -Path $mdPath -Value $md

Write-Host "Quality gate: $($report.gate)"
Write-Host "Artifacts: $($report.summary.artifacts), average score: $average, minimum score: $minimum"
Write-Host "Report: $jsonPath"
Write-Host "Markdown: $mdPath"
if ($Strict -and $gateFailures.Count -gt 0) {
  foreach ($failure in @($gateFailures.ToArray())) { Write-Host "FAIL $failure" }
  exit 1
}






