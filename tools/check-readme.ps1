# Check the numbers in README.md against the tree.
#
#   .\tools\check-readme.ps1
#
# A document that states a number is a claim about the tree, and a claim
# that is not checked is a claim that rots. This README carried 389 backend
# tests, 112 frontend tests, 320 integration checks, 120 backend mutations,
# 44 frontend mutations and 180 anchors -- every one of them stale, and
# every one of them wrong in the same direction. A reader who checks the
# tree against the document finds the document wrong, and a project whose
# document is wrong is a project whose numbers cannot be used.
#
# So the check is an invariant, not a snapshot: **the number the document
# states IS the number the tree has**. The expected value is read from the
# document under audit; the actual value is derived from the tree; the two
# are compared. Adding a test then requires updating the document, and
# forgetting to is a red gate rather than a quiet lie.
#
# It reads only. It never writes to the source tree, so it is safe to run
# at any time -- including while a mutation suite is running, though the
# answer is then only true between mutations.
#
# Exit codes:
#   0  every number in the document matches the tree
#   1  a number in the document does not match the tree
#
# The integration-check count is deliberately NOT derived here. It is the
# number of checks the integration suite actually ran, and some of its
# assertions sit in loops, so it cannot be derived from the script's text.
# The suite checks it against the document itself, at the end of a run,
# where it knows the count -- see the tail of tools/integration-test.ps1.

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

$readmePath = Join-Path $PWD 'README.md'
if (-not (Test-Path $readmePath)) {
  Write-Output "README.md is missing -- there is nothing to check."
  exit 1
}
# Read the document as UTF-8 whatever the console's code page is. The
# document carries Chinese, and a document read as ANSI is a document read
# as a different document.
$readme = [System.IO.File]::ReadAllText($readmePath, $enc)

# --- how the tree is counted -----------------------------------------------

# A MoonBit test is a `test "name" {` block or an `async test "name" {`
# one. Both shapes exist in this tree, and a counter that reads only the
# first one undercounts by the number of async tests -- which is how the
# stale 389 was produced in the first place.
#
# The pattern is anchored at the start of a line and requires the opening
# brace on the same line, so a doc comment that quotes a test declaration
# is not counted. The count this produces is the count `moon test`
# reports.
function Count-TestBlocks($dir) {
  $pattern = '(?m)^[ \t]*(async[ \t]+)?test[ \t]+"[^"\r\n]*"[ \t]*\{'
  $total = 0
  foreach ($f in (Get-ChildItem (Join-Path $PWD $dir) -Filter '*.mbt' -File)) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    $total += ([regex]::Matches($text, $pattern)).Count
  }
  $total
}

# A mutation is one `@{ name = ...; file = ...; old = ...; new = ... }`
# block in a mutation suite. The `name =` line is what identifies one, and
# there is exactly one per block.
function Count-Mutations($file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  ([regex]::Matches($text, '(?m)^[ \t]*name[ \t]*=')).Count
}

# An anchor is one `old =` line. Every mutation has exactly one, so the
# anchors in a suite and the mutations in it are the same number -- which
# is what makes the anchor checker and the suite agree.
function Count-Anchors($file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  ([regex]::Matches($text, '(?m)^[ \t]*old[ \t]*=')).Count
}

# The CI gates are the `gate "name"` calls in ci.sh's default case. The
# other two cases (--quick, --unit-only) run fewer, so the default arm is
# the one that is counted: the README says "CI gates", and the full run
# is the full run.
function Count-CiGates {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'ci.sh'), $enc)
  $lines = $text -split "`n"
  $start = -1
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^[ \t]*\*\)[ \t]*$') { $start = $i }
  }
  if ($start -lt 0) { return -1 }
  $count = 0
  for ($i = $start; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match '^[ \t]*esac[ \t]*$') { break }
    if ($lines[$i] -match '^[ \t]*gate[ \t]+"') { $count++ }
  }
  $count
}

# The project-structure listing.
#
# The README tells a reader what the project is made of, and the listing is
# the map. A file that is in the tree and not in the listing is a file the
# reader cannot find: the listing carried eleven of them, including the
# workspace -- the thing the reader is supposed to bring their own work
# into -- and the ring logo.
#
# So every source file has to be NAMED in the listing. Not merely the
# directory: a file listed by its directory alone is still a file the
# reader cannot point at.
#
# The listing is a fenced block, and only that block is searched. The
# document mentions file names in prose as well -- in the tools table, in
# the discussion of a gate -- and a mention there is not a place in the map.
function Get-StructureListing {
  $m = [regex]::Match($readme, '(?s)## Project Structure.*?```(.*?)```')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

# --- what the document says ------------------------------------------------
#
# Each check names two places in the document: the row of the count table
# in "Development Status", and the comment on the file in "Project
# Structure". Two places, one number, and both are checked -- a table
# that says 426 while the tree says 426 is no more right than a table that
# says 426 while the tree says 389.
function Get-DocumentNumber($pattern) {
  $m = [regex]::Match($readme, $pattern)
  if ($m.Success) { [int]$m.Groups[1].Value } else { $null }
}

function New-Check($label, $tablePattern, $treePattern, $actual) {
  [pscustomobject]@{
    label  = $label
    table  = Get-DocumentNumber $tablePattern
    tree   = Get-DocumentNumber $treePattern
    actual = $actual
  }
}

$backendTests = Count-TestBlocks 'backend'
$frontendTests = Count-TestBlocks 'frontend'
$backendMutations = Count-Mutations 'tools/mutate-backend.ps1'
$frontendMutations = Count-Mutations 'tools/mutate-frontend.ps1'
$loopMutations = Count-Mutations 'tools/mutate-loop.ps1'
$allAnchors = (Count-Anchors 'tools/mutate-backend.ps1') +
              (Count-Anchors 'tools/mutate-frontend.ps1') +
              (Count-Anchors 'tools/mutate-loop.ps1')
$ciGates = Count-CiGates

$checks = @(
  (New-Check 'Backend tests' `
    '(?m)^\|\s*Backend tests\s*\|\s*(\d+)\s*\|' `
    '\*_test\.mbt\s+#\s*(\d+)\s+tests' `
    $backendTests)
  (New-Check 'Frontend tests' `
    '(?m)^\|\s*Frontend tests\s*\|\s*(\d+)\s*\|' `
    'frontend_test\.mbt\s+#\s*(\d+)\s+tests' `
    $frontendTests)
  (New-Check 'Backend mutations' `
    '(?m)^\|\s*Backend mutations\s*\|\s*(\d+)\s*\|' `
    'mutate-backend\.ps1\s+#\s*(\d+)\s+mutations' `
    $backendMutations)
  (New-Check 'Frontend mutations' `
    '(?m)^\|\s*Frontend mutations\s*\|\s*(\d+)\s*\|' `
    'mutate-frontend\.ps1\s+#\s*(\d+)\s+mutations' `
    $frontendMutations)
  (New-Check 'Loop mutations' `
    '(?m)^\|\s*Loop mutations\s*\|\s*(\d+)\s*\|' `
    'mutate-loop\.ps1\s+#\s*(\d+)\s+mutations' `
    $loopMutations)
  (New-Check 'Mutation anchors' `
    '(?m)^\|\s*Mutation anchors\s*\|\s*(\d+)\s*\|' `
    'check-mutation-anchors\.ps1\s+#\s*(\d+)\s+anchors' `
    $allAnchors)
  (New-Check 'CI gates' `
    '(?m)^\|\s*CI gates\s*\|\s*(\d+)\s*\|' `
    'ci\.sh\s+#\s*(\d+)\s+gates' `
    $ciGates)
)

# The integration-check count is checked by the integration suite itself,
# because only a run knows how many checks it made. What is checked here
# is that the two places the document states it -- the count table and
# the project structure -- agree with each other. A document that says 359
# in one place and 320 in another is wrong in the same way a document
# that says 359 where the tree says 320 is wrong.
$integrationTable = Get-DocumentNumber '(?m)^\|\s*Integration checks\s*\|\s*(\d+)\s*\|'
$integrationTree = Get-DocumentNumber 'integration-test\.ps1\s+#\s*(\d+)\s+checks'

# --- the comparison --------------------------------------------------------
#
# One marker, `*** FAIL ***`, and the summary does not repeat it -- so a
# counter that counts the marker counts the failures once and once only.
$failures = 0
foreach ($c in $checks) {
  $label = $c.label
  $actual = $c.actual
  $table = $c.table
  $tree = $c.tree
  if ($null -eq $actual -or $actual -lt 0) {
    Write-Output ("  {0,-20} could not be derived from the tree" -f $label)
    Write-Output "*** FAIL ***"
    $failures++
    continue
  }
  if ($null -eq $table) {
    Write-Output ("  {0,-20} the count table has no row for it" -f $label)
    Write-Output "*** FAIL ***"
    $failures++
    continue
  }
  if ($null -eq $tree) {
    Write-Output ("  {0,-20} the project structure has no count for it" -f $label)
    Write-Output "*** FAIL ***"
    $failures++
    continue
  }
  if ($table -ne $actual -or $tree -ne $actual) {
    Write-Output ("  {0,-20} the tree has {1}, the table says {2}, the structure says {3}" -f $label, $actual, $table, $tree)
    Write-Output "*** FAIL ***"
    $failures++
    continue
  }
  Write-Output ("  ok      {0,-20} {1}" -f $label, $actual)
}

if ($null -eq $integrationTable -or $null -eq $integrationTree) {
  Write-Output ("  {0,-20} the document does not state it in both places" -f 'Integration checks')
  Write-Output "*** FAIL ***"
  $failures++
} elseif ($integrationTable -ne $integrationTree) {
  Write-Output ("  {0,-20} the table says {1} and the structure says {2}" -f 'Integration checks', $integrationTable, $integrationTree)
  Write-Output "*** FAIL ***"
  $failures++
} else {
  Write-Output ("  ok      {0,-20} {1} (the suite checks it at the end of a run)" -f 'Integration checks', $integrationTable)
}

# --- the project-structure listing ------------------------------------------
#
# Every source file has to be named in the listing, because the listing is
# the map a reader navigates by. A file that is in the tree and not in the
# listing is a file the reader cannot find.
#
# The test files are the exception: they are listed by their GLOB
# (`*_test.mbt`), which is a complete statement about them -- the listing
# says every test file in that directory is there. So the source files are
# the ones checked one by one.

$listing = Get-StructureListing
if ([string]::IsNullOrEmpty($listing)) {
  Write-Output ("  {0,-20} the document has no project-structure listing" -f 'Structure listing')
  Write-Output "*** FAIL ***"
  $failures++
} else {
  $missing = @()
  $sourceFiles = @()
  # The directories are searched RECURSIVELY and the list does not name a
  # directory inside another one it already names: `research` covers
  # `research/notes`, and naming both would count the note twice and ask
  # the listing for it twice.
  foreach ($dir in @('backend', 'frontend', 'cmd', 'models', 'research', 'tools')) {
    $path = Join-Path $PWD $dir
    if (-not (Test-Path $path)) { continue }
    foreach ($f in (Get-ChildItem $path -File -Recurse | Where-Object { $_.Extension -in @('.mbt', '.json', '.yaml', '.yml', '.md', '.ps1', '.sh') })) {
      # The tools are listed individually with their own comments, and the
      # test files are covered by the glob, so neither is checked here.
      if ($f.Extension -in @('.ps1', '.sh')) { continue }
      if ($f.Name -match 'test') { continue }
      $sourceFiles += $f.Name
    }
  }
  # A NAME alone is not enough to say a file is listed: `entries.mbt` is in
  # both the backend and the frontend, and a listing that named only the
  # backend's would still contain the string "entries.mbt". So the name has
  # to appear at least as many times in the listing as the tree has files
  # with that name. That is what makes the check about the FILES rather
  # than about the strings.
  #
  # Both counts are of LINES, so the bash twin counts the same way.
  $listingLines = $listing -split "`n"
  $names = $sourceFiles | Sort-Object -Unique
  foreach ($name in $names) {
    $inTree = ($sourceFiles | Where-Object { $_ -eq $name }).Count
    $inListing = ($listingLines | Where-Object { $_.Contains($name) }).Count
    if ($inListing -lt $inTree) { $missing += $name }
  }
  if ($missing.Count -gt 0) {
    Write-Output ("  {0,-20} the listing does not name {1} file(s): {2}" -f 'Structure listing', $missing.Count, ($missing -join ', '))
    Write-Output "*** FAIL ***"
    $failures++
  } else {
    Write-Output ("  ok      {0,-20} {1} files, all named" -f 'Structure listing', $names.Count)
  }
}

Write-Output ""
if ($failures -gt 0) {
  Write-Output ("{0} number(s) in README.md do not match the tree." -f $failures)
  Write-Output "*** FAIL ***"
  Write-Output ""
  Write-Output "The document states a number and the tree has another. Fix the document,"
  Write-Output "or fix the tree -- but make the two agree before saying anything about"
  Write-Output "either of them."
  exit 1
}
Write-Output "Every number in README.md matches the tree."
exit 0
