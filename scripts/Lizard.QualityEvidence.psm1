Set-StrictMode -Version 2.0

function ConvertTo-EvidenceRelativePath {
  param([string]$Path)
  if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path) -or $Path -match '^[A-Za-z]:' -or $Path.Replace('\', '/') -match '(^|/)\.\.(/|$)') {
    throw "BEHAVIOR_EVIDENCE_UNSAFE_PATH: $Path"
  }
  return $Path.Replace('\', '/')
}

function Get-FocusedTestResult {
  param($FocusedReport, [string]$TestPath)
  if ($null -eq $FocusedReport -or -not ($FocusedReport.PSObject.Properties.Name -contains 'tests')) { return $null }
  @($FocusedReport.tests | Where-Object { ([string]$_.test).Replace('\', '/') -eq $TestPath } | Select-Object -First 1)[0]
}

function Get-LizardBehavioralEvidence {
  param(
    [Parameter(Mandatory = $true)][string]$LayerRoot,
    [Parameter(Mandatory = $true)][System.IO.DirectoryInfo]$SkillDirectory,
    [AllowNull()]$FocusedReport,
    [Parameter(Mandatory = $true)][string]$CurrentHostId
  )

  $evidencePath = Join-Path $SkillDirectory.FullName 'evidence.json'
  $result = [ordered]@{
    declared = $false
    valid = $false
    gate = 'not-declared'
    score = 0
    current_host = $CurrentHostId
    current_host_covered = $false
    positive_declared = 0
    positive_passed = 0
    negative_declared = 0
    negative_passed = 0
    fixtures = @()
    failures = @()
    provenance = $null
    compatibility = $null
  }
  if (-not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) { return $result }

  $result.declared = $true
  $failures = New-Object System.Collections.Generic.List[string]
  $fixtureResults = New-Object System.Collections.Generic.List[object]
  try {
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if ([int]$evidence.schema_version -ne 1) { $failures.Add('Evidence schema_version must be 1.') | Out-Null }
    if ([string]$evidence.skill -ne $SkillDirectory.Name) { $failures.Add("Evidence skill '$($evidence.skill)' does not match '$($SkillDirectory.Name)'.") | Out-Null }

    $reviewPath = ConvertTo-EvidenceRelativePath -Path ([string]$evidence.provenance.review_record)
    $reviewFullPath = Join-Path $LayerRoot $reviewPath
    $provenanceValid = -not [string]::IsNullOrWhiteSpace([string]$evidence.provenance.owner) -and
      $null -ne ([DateTimeOffset]::Parse([string]$evidence.provenance.reviewed_at)) -and
      (Test-Path -LiteralPath $reviewFullPath -PathType Leaf)
    if (-not $provenanceValid) { $failures.Add('Evidence provenance or review record is invalid.') | Out-Null }

    $hosts = @($evidence.compatibility.hosts | ForEach-Object { [string]$_ })
    $modelClasses = @($evidence.compatibility.model_classes | ForEach-Object { [string]$_ })
    $result.current_host_covered = $hosts -contains $CurrentHostId
    if (-not $result.current_host_covered) { $failures.Add("Current host '$CurrentHostId' is not covered by evidence compatibility.") | Out-Null }
    if ($modelClasses.Count -eq 0) { $failures.Add('Evidence must declare at least one model class.') | Out-Null }

    foreach ($fixture in @($evidence.fixtures)) {
      $kind = [string]$fixture.kind
      $testPath = ConvertTo-EvidenceRelativePath -Path ([string]$fixture.test_path)
      $testFullPath = Join-Path $LayerRoot $testPath
      $testExists = Test-Path -LiteralPath $testFullPath -PathType Leaf
      $assertionFound = $false
      if ($testExists) {
        $assertionFound = (Get-Content -LiteralPath $testFullPath -Raw).Contains([string]$fixture.assertion_pattern)
      }
      $focusedResult = Get-FocusedTestResult -FocusedReport $FocusedReport -TestPath $testPath
      $suitePassed = $null -ne $focusedResult -and [string]$focusedResult.status -eq 'pass'
      $passed = $testExists -and $assertionFound -and $suitePassed
      if ($kind -eq 'positive') {
        $result.positive_declared++
        if ($passed) { $result.positive_passed++ }
      } elseif ($kind -eq 'negative') {
        $result.negative_declared++
        if ($passed) { $result.negative_passed++ }
      }
      if (-not $passed) { $failures.Add("Fixture '$($fixture.id)' lacks a present assertion in a passing focused suite.") | Out-Null }
      $fixtureResults.Add([ordered]@{
        id = [string]$fixture.id
        kind = $kind
        test_path = $testPath
        test_exists = $testExists
        assertion_found = $assertionFound
        suite_passed = $suitePassed
        passed = $passed
      }) | Out-Null
    }

    if ($result.positive_declared -eq 0) { $failures.Add('At least one positive fixture is required.') | Out-Null }
    if ($result.negative_declared -eq 0) { $failures.Add('At least one negative fixture is required.') | Out-Null }

    $score = 10
    if ($result.positive_declared -gt 0) { $score += 10 }
    if ($result.positive_declared -gt 0 -and $result.positive_passed -eq $result.positive_declared) { $score += 20 }
    if ($result.negative_declared -gt 0) { $score += 10 }
    if ($result.negative_declared -gt 0 -and $result.negative_passed -eq $result.negative_declared) { $score += 20 }
    if ($result.current_host_covered) { $score += 15 }
    if ($modelClasses.Count -gt 0) { $score += 5 }
    if ($provenanceValid) { $score += 10 }
    $result.score = $score
    $result.valid = $failures.Count -eq 0
    $result.gate = if ($result.valid) { 'pass' } else { 'fail' }
    $result.provenance = $evidence.provenance
    $result.compatibility = $evidence.compatibility
  } catch {
    $failures.Add("Evidence evaluation failed: $($_.Exception.Message)") | Out-Null
    $result.gate = 'fail'
  }
  $result.fixtures = @($fixtureResults.ToArray())
  $result.failures = @($failures.ToArray())
  return $result
}

Export-ModuleMember -Function 'Get-LizardBehavioralEvidence'
