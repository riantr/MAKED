# Check the claims in README.md against the tree.
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
# So the check is an invariant, not a snapshot: **what the document states
# IS what the tree has**. The expected value is read from the document
# under audit; the actual value is derived from the tree; the two are
# compared. Adding a test then requires updating the document, and
# forgetting to is a red gate rather than a quiet lie.
#
# There are four kinds of claim here now, and each is checked in the way
# that fits it:
#
# The NUMBERS -- the test, mutation, anchor and gate counts -- are read out
# of the document and compared with counts derived from the tree.
#
# The COUNTS IN WORDS -- "seven tools", "ten pages", "Six jobs" -- are read
# the same way, because a count written as a word is a count like any other,
# and a gate that only reads digits lets the words rot.
#
# The LISTING -- the project structure -- has to name every source file, and
# a name has to appear as many times as the tree has files with that name.
#
# The VARIABLES -- the environment variables the server reads, and the
# defaults they have -- are derived from the code and compared with the
# table the document states, because that table is the first thing a reader
# copies from.
#
# It reads only. It never writes to the source tree, so it is safe to run
# at any time -- including while a mutation suite is running, though the
# answer is then only true between mutations.
#
# Exit codes:
#   0  every claim in the document matches the tree
#   1  a claim in the document does not match the tree
#
# A claim the document states in ONE place: the expected value from the tree,
# the stated value from the document, and the two compared.
function Test-Claim($label, $expected, $stated) {
  if ($null -eq $stated -or "$stated" -eq '') {
    Write-Output ("  {0,-20} the document does not state it" -f $label)
    Write-Output "*** FAIL ***"
    $script:failures++
    return
  }
  if ("$stated" -ne "$expected") {
    Write-Output ("  {0,-20} the tree has {1}, the document says {2}" -f $label, $expected, $stated)
    Write-Output "*** FAIL ***"
    $script:failures++
    return
  }
  Write-Output ("  ok      {0,-20} {1}" -f $label, $expected)
}

# The integration-check count is deliberately NOT derived here. It is the
# number of checks the integration suite actually ran, and some of its
# assertions sit in loops, so it cannot be derived from the script's text.
# The suite checks it against the document itself, at the end of a run,
# where it knows the count -- see the tail of tools/integration-test.ps1.

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

# The counter of the claims that do not match. It is set here, before
# anything can fail, because a check that ran before it was set would have
# its failure counted into a variable that is about to be reset.
$failures = 0

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

# The mutation accounting: how many mutations there are, and what became of
# them. The headline says that every one of them has to be accounted for --
# all but one killed by the tests, and the one that was not deliberately
# equivalent.
#
# The three suites' counts are derived above. The total is their sum, the
# expected-equivalent mutations are the ones the suites mark as such, and
# the killed ones are the rest. A mutation the harness does not kill and
# does not expect to survive is a survivor, and a survivor is a failure the
# suite reports -- so the two numbers have to add up to the total.
function Count-EquivalentMutations {
  $total = 0
  foreach ($f in @('tools/mutate-backend.ps1', 'tools/mutate-frontend.ps1', 'tools/mutate-loop.ps1')) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $f), $enc)
    $total += ([regex]::Matches($text, '(?m)^[ \t]*equivalent = \$true[ \t]*\r?$')).Count
  }
  $total
}

$equivalentMutations = Count-EquivalentMutations
$totalMutations = $backendMutations + $frontendMutations + $loopMutations
$killedMutations = $totalMutations - $equivalentMutations

Test-Claim 'Mutation total' $totalMutations (Get-DocumentNumber '\*\*([0-9]+) mutations\*\*')
# The number is read with a character in front of it that is not a digit, so
# that the capture cannot start in the middle of the number and take the
# last digit of it. The bash twin uses the same pattern.
Test-Claim 'Mutation killed' $killedMutations (Get-DocumentNumber '[^0-9]([0-9]+) killed by the tests')

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

# --- the variable table -----------------------------------------------------
#
# The README tells a reader which environment variables the server reads and
# what each one defaults to. That is a claim about the code, and it is the
# one a reader acts on first: it is the table they copy from.
#
# The variables are derived from the code -- the server's own settings, the
# files the backend reads, and the port the agent's server speaks on -- and
# the table has to list exactly those, with the default the code has. A
# variable the code reads and the table does not name is a setting nobody
# can turn; a default the table states and the code does not have is a
# setting that does something else.
#
# A variable with no default in the code is written `*(unset)*` in the
# document, because that is what it is: the code falls back to the built-in
# one, and the document says so.

# A set, in ONE order: the ordinal one, which is the order the bytes are
# in. The bash twin sorts with LC_ALL=C, which is the same order, so the
# two twins print the same message when a set does not match.
function Sort-Set($items) {
  [string[]]$out = @($items | Where-Object { $_ -ne '' })
  if ($out.Count -gt 1) {
    [Array]::Sort($out, [System.StringComparer]::Ordinal)
    $unique = @()
    foreach ($item in $out) {
      if ($unique.Count -eq 0 -or $unique[-1] -cne $item) { $unique += $item }
    }
    $out = $unique
  }
  $out
}

# Two lists compared by MEMBERSHIP: the same members and the same size.
# Comparing sorted strings would make the twins disagree the moment one of
# them sorted differently, and a message that differs between the twins is a
# message nobody can trust.
function Test-SameMembers($a, $b) {
  $e = @($a | Where-Object { $_ -ne '' })
  $s = @($b | Where-Object { $_ -ne '' })
  if ($e.Count -ne $s.Count) { return $false }
  foreach ($item in $e) {
    if ($s -cnotcontains $item) { return $false }
  }
  return $true
}

function Get-CodeVariables {
  $out = @()
  foreach ($file in @('cmd/server/main.mbt', 'cmd/mcp/main.mbt')) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
    foreach ($m in [regex]::Matches($text, 'env_or\("(MAKED_[A-Z_]+)", "([^"]*)"\)')) {
      # An empty default is an unset one.
      $default = if ($m.Groups[2].Value -eq '') { 'unset' } else { $m.Groups[2].Value }
      $out += ("{0} {1}" -f $m.Groups[1].Value, $default)
    }
  }
  # The files the backend reads. They have no default: unset means the
  # built-in one.
  foreach ($f in (Get-ChildItem (Join-Path $PWD 'backend') -Filter '*.mbt' -File)) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    foreach ($m in [regex]::Matches($text, 'get_env_var\("(MAKED_[A-Z_]+)"\)')) {
      $out += ("{0} unset" -f $m.Groups[1].Value)
    }
  }
  Sort-Set $out
}

# The same, as the README's table states them.
function Get-DocVariables {
  $out = @()
  foreach ($line in ($readme -split "`r?`n")) {
    $m = [regex]::Match($line, '^\|\s*`(MAKED_[A-Z_]+)`\s*\|\s*([^|]*)\|')
    if ($m.Success) {
      $default = $m.Groups[2].Value.Trim().Replace('`', '')
      if ($default -eq '*(unset)*') { $default = 'unset' }
      $out += ("{0} {1}" -f $m.Groups[1].Value, $default)
    }
  }
  Sort-Set $out
}

# The files the README's own example commands point at. A reader copies
# those commands; a path that is not there is a command that fails on the
# first try.
function Get-DocExamplePaths {
  $out = @()
  foreach ($m in [regex]::Matches($readme, 'MAKED_(?:MODEL|RESEARCH|SOCIETY|CORPUS)=([^ \\\r\n]+)')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

$codeVariables = Get-CodeVariables
$docVariables = Get-DocVariables

if ($codeVariables.Count -eq 0) {
  Write-Output ("  {0,-20} no environment variable could be derived from the code" -f 'Variables')
  Write-Output "*** FAIL ***"
  $failures++
} elseif (Test-SameMembers $codeVariables $docVariables) {
  Write-Output ("  ok      {0,-20} {1}" -f 'Variables', $codeVariables.Count)
} else {
  Write-Output ("  {0,-20} the tree says [{1}], the table says [{2}]" -f 'Variables', ($codeVariables -join ' '), ($docVariables -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
}

$examplePaths = Get-DocExamplePaths
$missingPaths = @()
foreach ($path in $examplePaths) {
  if (-not (Test-Path (Join-Path $PWD $path))) { $missingPaths += $path }
}
if ($missingPaths.Count -gt 0) {
  Write-Output ("  {0,-20} the example commands name files that are not there: {1}" -f 'Example paths', ($missingPaths -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
} else {
  Write-Output ("  ok      {0,-20} {1}" -f 'Example paths', $examplePaths.Count)
}

# --- the API map ------------------------------------------------------------
#
# The README carries a table of every route the server registers, and that
# table is the map a reader navigates by. A route the table does not name is
# a route nobody can find, and a row the server does not serve is a promise
# the server does not keep.
#
# The routes are derived from the registrations in backend/api.mbt -- the
# same derivation the documents gate uses -- and the two sets are compared.
#
# The README's OTHER mentions of a path are checked as well. A path in
# prose carries a concrete value where the route has a parameter, as in
# /api/loop/reset/knowledge, and it has to resolve to a route that takes a
# parameter there.

function Get-TreeRoutes {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, 'app\.(get|post|put|delete|patch)\(\s*"([^"]+)"')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value.ToUpper(), $m.Groups[2].Value)
  }
  Sort-Set $out
}

# The README's API table, as "METHOD path".
function Get-DocApiTable {
  $out = @()
  foreach ($line in ($readme -split "`r?`n")) {
    $m = [regex]::Match($line, '^\|\s*`(GET|POST|PUT|DELETE|PATCH)`\s*\|\s*`(/api/[^`]+)`')
    if ($m.Success) {
      $out += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
    }
  }
  Sort-Set $out
}

# Every path the README mentions, wherever it mentions it.
function Get-DocApiPaths {
  $out = @()
  foreach ($m in [regex]::Matches($readme, '/api/[A-Za-z0-9/:_.-]*')) {
    $path = $m.Groups[0].Value
    $path = $path -replace '[.,)]+$', ''
    $path = $path -replace '\?.*$', ''
    $out += $path
  }
  Sort-Set $out
}

$treeRoutes = Get-TreeRoutes
$docApiTable = Get-DocApiTable

if ($treeRoutes.Count -eq 0) {
  Write-Output ("  {0,-20} no route could be derived from the code" -f 'API routes')
  Write-Output "*** FAIL ***"
  $failures++
} elseif (Test-SameMembers $treeRoutes $docApiTable) {
  Write-Output ("  ok      {0,-20} {1}" -f 'API routes', $treeRoutes.Count)
} else {
  Write-Output ("  {0,-20} the tree has [{1}], the table has [{2}]" -f 'API routes', ($treeRoutes -join ' '), ($docApiTable -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
}

# The routes as patterns, so that a concrete value in a path can match the
# parameter of a route. A parameter becomes "any segment but the slash".
$routePatterns = @()
foreach ($route in $treeRoutes) {
  $path = $route.Substring($route.IndexOf(' ') + 1)
  $routePatterns += [regex]::Replace($path, ':[A-Za-z_]+', '[^/]+')
}

$unresolved = @()
foreach ($path in (Get-DocApiPaths)) {
  $matched = $false
  foreach ($pattern in $routePatterns) {
    if ($path -cmatch "^$pattern$") { $matched = $true; break }
  }
  if (-not $matched) { $unresolved += $path }
}
if ($unresolved.Count -gt 0) {
  Write-Output ("  {0,-20} the document names paths the server does not serve: {1}" -f 'API paths', ($unresolved -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
} else {
  Write-Output ("  ok      {0,-20} {1}" -f 'API paths', (Get-DocApiPaths).Count)
}

# --- the protocol version ---------------------------------------------------
#
# The README states which version of the Model Context Protocol MAKED speaks,
# in a sentence and in three example commands. All of them have to be the
# version the server answers to: an agent that reads a version the server
# does not speak cannot call it.

function Get-CodeProtocol {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $m = [regex]::Match($text, '"mcp": "(\d{4}-\d{2}-\d{2})"')
  if (-not $m.Success) { return '' }
  $m.Groups[1].Value
}

function Get-DocProtocols {
  $out = @()
  foreach ($m in [regex]::Matches($readme, '\d{4}-\d{2}-\d{2}')) {
    $out += $m.Groups[0].Value
  }
  Sort-Set $out
}

$protocol = Get-CodeProtocol
if ([string]::IsNullOrEmpty($protocol)) {
  Write-Output ("  {0,-20} the tree does not name a protocol version" -f 'Protocol version')
  Write-Output "*** FAIL ***"
  $failures++
} else {
  $wrong = @(Get-DocProtocols | Where-Object { $_ -cne $protocol })
  if ($wrong.Count -gt 0) {
    Write-Output ("  {0,-20} the document names [{1}], the tree names {2}" -f 'Protocol version', ($wrong -join ' '), $protocol)
    Write-Output "*** FAIL ***"
    $failures++
  } else {
    Write-Output ("  ok      {0,-20} {1}" -f 'Protocol version', $protocol)
  }
}

# --- the versions the document names ---------------------------------------
#
# The README names the versions of the libraries MAKED is built on, with a
# link to each one, and it names its own version. A library version the
# manifest does not pin is a version the reader would install, and it is not
# the one this project runs; a version of MAKED's own that is not the
# manifest's is a version that was never published.
#
# The module path decides which of the two it is: a path under the module's
# own name is MAKED, and anything else is a library.

function Get-DocVersions {
  $out = @()
  foreach ($m in [regex]::Matches($readme, '[A-Za-z_][A-Za-z0-9_./-]*@[0-9]+\.[0-9]+\.[0-9]+')) {
    # The link's own prefix is not part of the module path.
    $out += ($m.Groups[0].Value -replace '^mooncakes\.io/docs/', '')
  }
  Sort-Set $out
}

$moonMod = [System.IO.File]::ReadAllText((Join-Path $PWD 'moon.mod'), $enc)
$moduleName = [regex]::Match($moonMod, '(?m)^name = "([^"]+)"').Groups[1].Value
$moduleVersion = [regex]::Match($moonMod, '(?m)^version = "([^"]+)"').Groups[1].Value
$dependencyPins = @()
foreach ($m in [regex]::Matches($moonMod, '(?m)^ *"([^"]+)@([^"]+)"')) {
  $dependencyPins += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
}

$wrongVersion = @()
foreach ($stated in (Get-DocVersions)) {
  $parts = $stated -split '@'
  $module = $parts[0]
  $version = $parts[1]
  if ($module -eq $moduleName -or $module.StartsWith("$moduleName/")) {
    if ($version -cne $moduleVersion) { $wrongVersion += $stated }
  } else {
    if ($dependencyPins -cnotcontains "$module $version") { $wrongVersion += $stated }
  }
}
if ($wrongVersion.Count -gt 0) {
  Write-Output ("  {0,-20} the document names versions the manifest does not pin: {1}" -f 'Referenced versions', ($wrongVersion -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
} else {
  Write-Output ("  ok      {0,-20} {1}" -f 'Referenced versions', (Get-DocVersions).Count)
}

# --- the counts the document spells out -------------------------------------
#
# The README says some of its counts in words -- "seven tools", "ten pages",
# "Six jobs" -- and a gate that reads only digits lets those rot. A count
# written as a word is a claim like any other: the tree has a number, the
# document has a word, and the two have to be the same number.
#
# The counts are derived from the tree:
#
#   the domains    the ring's domains, from backend/pages.mbt
#   the tools      the agent's server, from backend/agent.mbt
#   the files      the MAKED_* variables the backend reads
#   the pages      the pages the server seeds
#   the packages   the library packages -- the ones that are not executables
#   the platforms  the release matrix
#   the jobs       the jobs in the CI workflow
#   the suites     the mutation suites
#   the languages  the variants of the Lang enum
#   the example    the example machine that ships, section by section
#
# A word that is not a number -- "of tools", "own positions" -- is not a
# count, and it is passed over: the pattern is here to find the count, not to
# police the prose around it.

# The word and the number it stands for.
$wordNumbers = @{
  'one' = 1; 'two' = 2; 'three' = 3; 'four' = 4; 'five' = 5; 'six' = 6
  'seven' = 7; 'eight' = 8; 'nine' = 9; 'ten' = 10; 'eleven' = 11
  'twelve' = 12; 'thirteen' = 13; 'fourteen' = 14; 'fifteen' = 15
  'sixteen' = 16; 'seventeen' = 17; 'eighteen' = 18; 'nineteen' = 19
  'twenty' = 20
}

# The ring's domains, and the names it gives them.
function Get-RingDomains {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/pages.mbt'), $enc)
  $m = [regex]::Match($text, '(?s)pub fn ring_domains\(\)[^{]*\{.*?\n\}')
  if (-not $m.Success) { return @() }
  $out = @()
  foreach ($d in [regex]::Matches($m.Value, '\("([a-z]+)",')) { $out += $d.Groups[1].Value }
  $out
}

# The tools the agent's server offers.
function Get-ToolCount {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  ([regex]::Matches($text, 'name: "maked_[a-z_]+"')).Count
}

# The files the backend reads.
function Get-FileCount {
  $seen = @{}
  $count = 0
  foreach ($f in (Get-ChildItem (Join-Path $PWD 'backend') -Filter '*.mbt' -File)) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    foreach ($m in [regex]::Matches($text, 'get_env_var\("(MAKED_[A-Z_]+)"\)')) {
      $name = $m.Groups[1].Value
      if (-not $seen.ContainsKey($name)) { $seen[$name] = $true; $count++ }
    }
  }
  $count
}

# The pages the server holds: the ring's pages, the utility pages, the index
# and the not-found page.
function Get-PageShape {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/pages.mbt'), $enc)
  $static = ([regex]::Matches($text, '(?m)^        "[a-z0-9-]+",[ \t]*$')).Count
  $fixed = ([regex]::Matches($text, 'slug: "(index|404)"')).Count
  @($static, $fixed)
}

# The library packages -- the ones that are not executables. The executables
# are applications; the packages are what a reader can depend on. The
# module's own manifest is not a package either.
function Get-PackageCount {
  $count = 0
  foreach ($dir in (Get-ChildItem $PWD -Directory)) {
    if ($dir.Name -in @('_build', '.mooncakes', '.git')) { continue }
    foreach ($m in (Get-ChildItem $dir.FullName -Filter 'moon.pkg' -File -Recurse)) {
      $text = [System.IO.File]::ReadAllText($m.FullName, $enc)
      if ($text -notmatch 'pkgtype\(kind: "executable"\)') { $count++ }
    }
  }
  $count
}

# The platforms a release is built for.
function Get-PlatformCount {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD '.github/workflows/publish.yml'), $enc)
  ([regex]::Matches($text, '(?m)^[ \t]*- os: ')).Count
}

# The jobs in the CI workflow.
function Get-JobCount {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD '.github/workflows/ci.yml'), $enc)
  $count = 0
  $inside = $false
  foreach ($line in ($text -split "`n")) {
    if ($line -match '^jobs:') { $inside = $true; continue }
    if ($inside -and $line -match '^  [A-Za-z0-9_-]+:') { $count++ }
  }
  $count
}

# The mutation suites.
function Get-SuiteCount {
  (Get-ChildItem (Join-Path $PWD 'tools') -Filter 'mutate-*.ps1' -File).Count
}

# The languages the backend answers in.
function Get-LanguageCount {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/i18n.mbt'), $enc)
  $m = [regex]::Match($text, '(?s)pub enum Lang \{.*?\n\}')
  if (-not $m.Success) { return 0 }
  $body = $m.Value -replace '(?s)^pub enum Lang \{', '' -replace '(?s)\n\}$', ''
  $count = 0
  foreach ($line in ($body -split "`n")) {
    if ($line -match '^[ \t]*(//|$)') { continue }
    $count++
  }
  $count
}

# The example machine that ships with the repository, section by section.
function Get-ExampleShape {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'models/product-iteration.json'), $enc)
  $section = ''
  $counts = @{}
  foreach ($line in ($text -split "`n")) {
    if ($line -match '^  "([a-z]+)": \[') {
      $section = $Matches[1]
      if (-not $counts.ContainsKey($section)) { $counts[$section] = 0 }
      continue
    }
    if ($line -match '^    \{' -and $counts.ContainsKey($section)) { $counts[$section]++ }
  }
  @((Get-CountOrZero $counts 'domains'),
    (Get-CountOrZero $counts 'positions'),
    (Get-CountOrZero $counts 'slots'))
}

function Get-CountOrZero($table, $key) {
  if ($table.ContainsKey($key)) { return $table[$key] }
  0
}

$ringDomains = @(Get-RingDomains)
$domainCount = $ringDomains.Count
$domainNames = $ringDomains
$toolCount = Get-ToolCount
$fileCount = Get-FileCount
$pageShape = Get-PageShape
$pageCount = $domainCount + $pageShape[0] + $pageShape[1]
$packageCount = Get-PackageCount
$platformCount = Get-PlatformCount
$jobCount = Get-JobCount
$suiteCount = Get-SuiteCount
$languageCount = Get-LanguageCount
$exampleShape = Get-ExampleShape

# The claims, the counts the tree has, and the patterns that find the counts
# in the document. A pattern is the text before the number word and the text
# after it, with a bar between the two.
#
# The claims are read back in the order they are written here, and the
# patterns of a claim are read in the order they are written too, so that the
# two twins see the words in the same order and print the same message.
$claims = @(
  [pscustomobject]@{ label = 'Domains';           expected = $domainCount;        patterns = @('|-domain ring', 'the | domains in ring order', 'the | domain in ring order', 'The | domains are') }
  [pscustomobject]@{ label = 'Tools';             expected = $toolCount;          patterns = @('| tool') }
  [pscustomobject]@{ label = 'Files';             expected = $fileCount;          patterns = @('| files MAKED runs on', '| file MAKED runs on', '### The | files', '### The | file') }
  [pscustomobject]@{ label = 'Pages';             expected = $pageCount;          patterns = @('the | pages the server holds', 'the | page the server holds', 'the | public pages', 'the | public page') }
  [pscustomobject]@{ label = 'Packages';          expected = $packageCount;       patterns = @('ships | packages', 'ships | package') }
  [pscustomobject]@{ label = 'Platforms';         expected = $platformCount;      patterns = @('build for | platforms', 'build for | platform') }
  [pscustomobject]@{ label = 'Jobs';              expected = $jobCount;           patterns = @('| jobs, all of which', '| job, all of which') }
  [pscustomobject]@{ label = 'Suites';            expected = $suiteCount;         patterns = @('across the | suites', 'across the | suite') }
  [pscustomobject]@{ label = 'Languages';         expected = $languageCount;      patterns = @('| languages', '| language') }
  [pscustomobject]@{ label = 'Example domains';   expected = $exampleShape[0];    patterns = @('| domains,') }
  [pscustomobject]@{ label = 'Example positions'; expected = $exampleShape[1];    patterns = @('| positions,') }
  [pscustomobject]@{ label = 'Example slots';     expected = $exampleShape[2];    patterns = @('| slots', '| slot') }
  [pscustomobject]@{ label = 'Mutation equivalents'; expected = $equivalentMutations; patterns = @('| deliberately equivalent') }
)

foreach ($claim in $claims) {
  $words = @()
  foreach ($pattern in $claim.patterns) {
    $parts = [regex]::Split($pattern, '\|')
    $re = $parts[0] + '([A-Za-z]+)' + $parts[1]
    foreach ($m in [regex]::Matches($readme, $re)) { $words += $m.Groups[1].Value }
  }
  $stated = ''
  $broken = ''
  foreach ($word in $words) {
    $w = $word.ToLowerInvariant()
    if (-not $wordNumbers.ContainsKey($w)) { continue }
    if ($stated -eq '') { $stated = $w }
    if ($wordNumbers[$w] -ne $claim.expected -and $broken -eq '') { $broken = $w }
  }
  if ($broken -ne '') {
    Write-Output ("  {0,-20} {1}: the tree has {2}, the document says {3}" -f 'Number words', $claim.label, $claim.expected, $broken)
    Write-Output "*** FAIL ***"
    $failures++
  } elseif ($stated -eq '') {
    Write-Output ("  {0,-20} {1}: the document does not state the count" -f 'Number words', $claim.label)
    Write-Output "*** FAIL ***"
    $failures++
  } else {
    Write-Output ("  ok      {0,-20} {1}: {2} ({3})" -f 'Number words', $claim.label, $stated, $claim.expected)
  }
}

# The names the document gives the ring's domains, against the names the tree
# gives them. A count of five is not the same claim as the five names.
function Get-DocDomainNames {
  $out = @()
  foreach ($m in [regex]::Matches($readme, 'The [A-Za-z]+ domains are ([^.]*)')) {
    foreach ($s in [regex]::Matches($m.Groups[1].Value, '`([a-z]+)`')) { $out += $s.Groups[1].Value }
  }
  Sort-Set $out
}

$docDomainNames = Get-DocDomainNames
if ($domainNames.Count -eq 0 -or $docDomainNames.Count -eq 0) {
  Write-Output ("  {0,-20} the domain names could not be found on both sides" -f 'Domain names')
  Write-Output "*** FAIL ***"
  $failures++
} elseif (Test-SameMembers $domainNames $docDomainNames) {
  Write-Output ("  ok      {0,-20} {1}" -f 'Domain names', ($docDomainNames -join ' '))
} else {
  Write-Output ("  {0,-20} the tree names [{1}], the document names [{2}]" -f 'Domain names', ($domainNames -join ' '), ($docDomainNames -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
}

# --- the hooks ---------------------------------------------------------------
#
# The repository ships a git hook, and a hook the README does not mention is a
# hook a reader never finds. The files in .githooks are derived from the
# tree, the paths the README names are derived from the document, and the two
# sets have to be the same.

function Get-TreeHooks {
  $out = @()
  $dir = Join-Path $PWD '.githooks'
  if (Test-Path $dir) {
    foreach ($f in (Get-ChildItem $dir -File)) { $out += $f.Name }
  }
  Sort-Set $out
}

function Get-DocHooks {
  $out = @()
  foreach ($m in [regex]::Matches($readme, '\.githooks/([A-Za-z0-9_.-]+)')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

$treeHooks = Get-TreeHooks
$docHooks = Get-DocHooks

if ($treeHooks.Count -eq 0) {
  Write-Output ("  {0,-20} the tree has no hooks to name" -f 'Git hooks')
  Write-Output "*** FAIL ***"
  $failures++
} elseif (Test-SameMembers $treeHooks $docHooks) {
  Write-Output ("  ok      {0,-20} {1}" -f 'Git hooks', $treeHooks.Count)
} else {
  Write-Output ("  {0,-20} the tree has [{1}], the document names [{2}]" -f 'Git hooks', ($treeHooks -join ' '), ($docHooks -join ' '))
  Write-Output "*** FAIL ***"
  $failures++
}

Write-Output ""
if ($failures -gt 0) {
  Write-Output ("{0} claim(s) in README.md do not match the tree." -f $failures)
  Write-Output "*** FAIL ***"
  Write-Output ""
  Write-Output "The document states a claim and the tree has another. Fix the document,"
  Write-Output "or fix the tree -- but make the two agree before saying anything about"
  Write-Output "either of them."
  exit 1
}
Write-Output "Every claim in README.md matches the tree."
exit 0
