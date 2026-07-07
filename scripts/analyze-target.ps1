param(
  [string]$TargetPath = (Get-Location).Path,
  [switch]$Json,
  [int]$MaxFiles = 20000
)

$ErrorActionPreference = "Stop"
$TargetRoot = (Resolve-Path -LiteralPath $TargetPath).Path
$signals = New-Object System.Collections.Generic.List[string]
$reasons = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Signal { param([string]$Signal) if (-not $signals.Contains($Signal)) { $signals.Add($Signal) | Out-Null } }
function Add-Reason { param([string]$Reason) if (-not $reasons.Contains($Reason)) { $reasons.Add($Reason) | Out-Null } }
function Add-Warning { param([string]$Warning) if (-not $warnings.Contains($Warning)) { $warnings.Add($Warning) | Out-Null } }
function Has-Path { param([string]$Relative) return Test-Path -LiteralPath (Join-Path $TargetRoot $Relative) }
function Read-JsonSafe {
  param([string]$Relative)
  $path = Join-Path $TargetRoot $Relative
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json }
  catch { Add-Warning "$Relative exists but is not valid JSON: $($_.Exception.Message)"; return $null }
}
function Get-RepositoryFiles {
  param([string]$Root, [int]$Limit)
  $skipDirs = @('node_modules', '.git', 'dist', 'build', '.tmp', '.next', '.turbo', '.cache', 'coverage', 'vendor')
  $skipLookup = @{}
  foreach ($dirName in $skipDirs) { $skipLookup[$dirName] = $true }
  $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
  $stack = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
  $stack.Push((Get-Item -LiteralPath $Root))

  while ($stack.Count -gt 0 -and $files.Count -lt $Limit) {
    $dir = $stack.Pop()
    try {
      foreach ($file in Get-ChildItem -LiteralPath $dir.FullName -File -Force -ErrorAction Stop) {
        $files.Add($file) | Out-Null
        if ($files.Count -ge $Limit) { break }
      }
      if ($files.Count -ge $Limit) { break }
      foreach ($child in Get-ChildItem -LiteralPath $dir.FullName -Directory -Force -ErrorAction Stop) {
        if (-not $skipLookup.ContainsKey($child.Name)) { $stack.Push($child) }
      }
    } catch {
      Add-Warning "Skipped unreadable directory '$($dir.FullName)': $($_.Exception.Message)"
    }
  }

  if ($files.Count -ge $Limit) { Add-Warning "File scan reached MaxFiles=$Limit; marker detection may be incomplete." }
  return @($files)
}

$package = Read-JsonSafe 'package.json'
if ($null -ne $package) {
  Add-Signal 'node'
  $depNames = @()
  foreach ($bucket in @('dependencies', 'devDependencies', 'peerDependencies')) {
    if ($package.PSObject.Properties.Name -contains $bucket) {
      $depNames += @($package.$bucket.PSObject.Properties.Name)
    }
  }
  foreach ($dep in $depNames) {
    switch -Regex ($dep) {
      '^react$' { Add-Signal 'react'; Add-Reason 'package.json depends on React.' }
      '^vite$' { Add-Signal 'vite'; Add-Reason 'package.json uses Vite.' }
      '^typescript$' { Add-Signal 'typescript'; Add-Reason 'package.json uses TypeScript.' }
      '^@supabase/supabase-js$|^supabase$' { Add-Signal 'supabase'; Add-Reason 'package.json references Supabase packages.' }
      '^next$' { Add-Signal 'nextjs'; Add-Reason 'package.json uses Next.js.' }
    }
  }
}

if (Has-Path 'supabase') { Add-Signal 'supabase'; Add-Reason 'supabase/ directory exists.' }
if (Has-Path 'supabase\functions') { Add-Signal 'edge-functions'; Add-Reason 'supabase/functions directory exists.' }
if (Has-Path 'supabase\migrations') { Add-Signal 'database-migrations'; Add-Reason 'supabase/migrations directory exists.' }
if (Has-Path 'src') { Add-Signal 'src-tree' }
if (Has-Path 'vite.config.ts' -or Has-Path 'vite.config.js') { Add-Signal 'vite'; Add-Reason 'Vite config exists.' }
if (Has-Path 'tsconfig.json' -or Has-Path 'tsconfig.app.json') { Add-Signal 'typescript'; Add-Reason 'TypeScript config exists.' }
if (Has-Path 'DESIGN.md') { Add-Signal 'design-system'; Add-Reason 'DESIGN.md exists.' }
if (Has-Path 'AGENTS.md') { Add-Signal 'existing-agents'; Add-Reason 'AGENTS.md already exists; install should use sidecar merge behavior.' }
if (Has-Path 'CLAUDE.md') { Add-Signal 'existing-claude'; Add-Reason 'CLAUDE.md already exists; install should use sidecar merge behavior.' }
if (Has-Path 'GEMINI.md') { Add-Signal 'existing-gemini'; Add-Reason 'GEMINI.md already exists; install should use sidecar merge behavior.' }
if (Has-Path '.cursor') { Add-Signal 'cursor'; Add-Reason '.cursor directory exists.' }

$repoFiles = Get-RepositoryFiles -Root $TargetRoot -Limit $MaxFiles
$relativePaths = @($repoFiles | ForEach-Object { $_.FullName.Substring($TargetRoot.Length).TrimStart([char[]]@('\', '/')) })
$financeMarkers = @('finance', 'crypto', 'defi', 'market', 'stock', 'dca', 'lending', 'staking', 'airdrop', 'yield')
$markerHits = 0
foreach ($marker in $financeMarkers) {
  $escaped = [regex]::Escape($marker)
  $match = $relativePaths | Where-Object { $_ -match $escaped } | Select-Object -First 1
  if ($match) { $markerHits++ }
}
if ($markerHits -ge 2) { Add-Signal 'finance'; Add-Reason "Finance/market marker paths detected ($markerHits marker groups)." }

$profile = 'minimal'
$risk = 'low'
$harnesses = New-Object System.Collections.Generic.List[string]
$skills = New-Object System.Collections.Generic.List[string]
foreach ($h in @('generic-agents-md')) { $harnesses.Add($h) | Out-Null }

if ($signals.Contains('react') -or $signals.Contains('vite') -or $signals.Contains('typescript') -or $signals.Contains('supabase')) {
  $profile = 'standard'
  $risk = 'medium'
  $harnesses.Clear(); foreach ($h in @('codex', 'claude-code', 'gemini')) { $harnesses.Add($h) | Out-Null }
}
if (($signals.Contains('supabase') -and ($signals.Contains('react') -or $signals.Contains('vite'))) -or ($signals.Contains('finance') -and $signals.Contains('database-migrations'))) {
  $profile = 'supabase-react-finance'
  $risk = 'high'
  $harnesses.Clear(); foreach ($h in @('codex', 'claude-code', 'gemini')) { $harnesses.Add($h) | Out-Null }
}
if ($signals.Contains('cursor') -and -not $harnesses.Contains('cursor')) { $harnesses.Add('cursor') | Out-Null }

switch ($profile) {
  'minimal' { foreach ($s in @('git-safety', 'research-audit')) { $skills.Add($s) | Out-Null } }
  'standard' { foreach ($s in @('git-safety', 'release', 'dependency-upgrade', 'research-audit')) { $skills.Add($s) | Out-Null } }
  'supabase-react-finance' { foreach ($s in @('git-safety', 'release', 'dependency-upgrade', 'design-system', 'frontend-react', 'supabase', 'edge-functions', 'data-quality', 'research-audit')) { $skills.Add($s) | Out-Null } }
}

$result = [ordered]@{
  target = $TargetRoot
  recommendedProfile = $profile
  riskLevel = $risk
  recommendedHarnesses = @($harnesses)
  recommendedSkills = @($skills)
  signals = @($signals)
  reasons = @($reasons)
  warnings = @($warnings)
  previewCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\install.ps1 -TargetPath `"$TargetRoot`" -Profile $profile -Harnesses $($harnesses -join ',')"
}

if ($Json) {
  $result | ConvertTo-Json -Depth 8
  exit 0
}

Write-Host "lizard-agent-layer target analysis"
Write-Host "Target: $TargetRoot"
Write-Host "Recommended profile: $profile"
Write-Host "Risk level: $risk"
Write-Host "Recommended harnesses: $($harnesses -join ', ')"
Write-Host "Recommended skills: $($skills -join ', ')"
Write-Host ""
Write-Host "Signals:"
foreach ($signal in $signals) { Write-Host "  - $signal" }
Write-Host ""
Write-Host "Reasons:"
foreach ($reason in $reasons) { Write-Host "  - $reason" }
if ($warnings.Count -gt 0) {
  Write-Host ""
  Write-Host "Warnings:"
  foreach ($warning in $warnings) { Write-Host "  - $warning" }
}
Write-Host ""
Write-Host "Preview command:"
Write-Host "  $($result.previewCommand)"
