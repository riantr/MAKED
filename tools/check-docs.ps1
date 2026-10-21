# Check the documents against the tree.
#
#   .\tools\check-docs.ps1
#
# The PowerShell twin of tools/check-docs.sh. It exists for the same reason
# the other twins exist: the CI runner is ubuntu and carries bash, so a gate
# written only in PowerShell is a gate that does not run where the build
# runs.
#
# The two are kept in step deliberately. Both implement one invariant:
#
#   **the number the document states IS the number the tree has**
#
# The README has a gate for its numbers (tools/check-readme.ps1). This is the
# same invariant applied to the other documents a reader is sent to:
#
#   architecture/      how the system is put together
#   AGENT.md           how to drive MAKED from another agent
#   packaging/RUN.txt  the note that ships inside the release archive
#
# Four kinds of claim are checked.
#
# The COUNTS are derived from the tree and compared with what the documents
# say.
#
# The REFERENCES are checked for existence and for range. A reference to a
# file that is not there is a broken pointer, and so is a reference to a line
# past the end of one. A reference to a line that is still IN RANGE but no
# longer says what the claim says it says is the dangerous one -- it looks
# verified -- and no script can catch that; it is why the documents carry
# the claim in words next to the pointer.
#
# The SETS are compared by membership. The tools the discovery document
# declares, the files MAKED runs on, the HTTP endpoints it lists, the
# environment variables the server reads: a set with one entry too many and a
# set with one entry too few fail the same way, because both send a reader
# to something that is not there. The comparison is by membership and not by
# a sorted string, so the two twins cannot disagree about the answer by
# disagreeing about the order.
#
# The WORDS are counts too. "the seven tools" is a claim exactly as much as
# "37 API routes" is, and a number word can be mapped to a number.
#
# It reads only. It never writes to the source tree.
#
# Exit codes:
#   0  every claim in the documents matches the tree
#   1  a claim in the documents does not match the tree

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

$agentDoc = 'AGENT.md'
$runNote = 'packaging/RUN.txt'

$evidence = 'architecture/system-model.evidence.md'
$deps = 'architecture/dependencies.evidence.md'
$depsMd = 'architecture/dependencies.md'
$summary = 'architecture/system-model.summary.md'
$deploy = 'architecture/deployment.evidence.md'

$failures = 0

function Write-Fail($message) {
  Write-Output ("  " + $message)
  Write-Output "*** FAIL ***"
  $script:failures++
}

function Write-Ok($label, $value) {
  Write-Output ("  ok      {0,-22} {1}" -f $label, $value)
}

# --- sets --------------------------------------------------------------------
#
# A set is a list of lines. Two sets are the same when they have the same
# members and the same size, and the order they are written in says nothing
# about it.

function Get-NonEmpty($items) {
  @($items | Where-Object { $_ -ne '' })
}

# A set, in ONE order: the ordinal one, which is the order the bytes are
# in. The bash twin sorts with LC_ALL=C, which is the same order, so the
# two twins print the same message when a set does not match -- and a
# message that differs between the twins is a message nobody can trust.
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

# Two sets that have to be the same.
function Test-Sets($label, $expected, $stated) {
  $e = Get-NonEmpty $expected
  $s = Get-NonEmpty $stated
  $missing = @($e | Where-Object { $s -cnotcontains $_ })
  $extra = @($s | Where-Object { $e -cnotcontains $_ })
  if ($missing.Count -eq 0 -and $extra.Count -eq 0 -and $e.Count -eq $s.Count) {
    Write-Ok $label $e.Count
    return
  }
  Write-Fail ("{0,-22} the tree says [{1}], the document says [{2}]" -f $label, ($e -join ' '), ($s -join ' '))
}

# Every member of the first set has to be a member of the second.
function Test-Subset($label, $subset, $superset) {
  $sub = Get-NonEmpty $subset
  $sup = Get-NonEmpty $superset
  $missing = @($sub | Where-Object { $sup -cnotcontains $_ })
  if ($missing.Count -eq 0) {
    Write-Ok $label $sub.Count
    return
  }
  Write-Fail ("{0,-22} the document is missing [{1}]" -f $label, ($missing -join ' '))
}

# --- how the tree is counted ------------------------------------------------

# A route is one registration: app.get(...), app.post(...), and the rest.
# The count is the number of registrations, not the number of distinct
# paths, because a path registered for two verbs is two registrations and
# the handler behind them is two handlers.
function Count-Routes {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  ([regex]::Matches($text, 'app\.(get|post|put|delete|patch)\(')).Count
}

# The same routes as "METHOD path". The file is read as one line first,
# because one registration spreads its path over two lines, and a path that
# is on the next line is still a path.
function Get-TreeEndpoints {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, 'app\.(get|post|put|delete|patch)\(\s*"([^"]+)"')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value.ToUpper(), $m.Groups[2].Value)
  }
  $out
}

# The columns of the `pages` table. The CREATE TABLE statement is a block of
# #| lines -- MoonBit's string literal for the SQL -- and every line that
# names a column says TEXT or INTEGER. Counting those lines counts the
# columns.
function Count-PageColumns {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/database.mbt'), $enc)
  $lines = $text -split "`n"
  $inside = $false
  $count = 0
  foreach ($line in $lines) {
    if (-not $inside) {
      if ($line -match 'CREATE TABLE IF NOT EXISTS pages') { $inside = $true }
      continue
    }
    # Every line of the statement is a #| line; the statement ends at the
    # first line that is not one.
    if ($line -notmatch '^\s*#\|') { break }
    if ($line -match 'TEXT|INTEGER') { $count++ }
  }
  $count
}

# The fields of the `Page` struct. It is the only `struct Page` in the file
# and it ends at the first closing brace at the start of a line.
function Count-PageFields {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/pages.mbt'), $enc)
  $lines = $text -split "`n"
  $inside = $false
  $count = 0
  foreach ($line in $lines) {
    if (-not $inside) {
      if ($line -match '^pub\(all\) struct Page \{') { $inside = $true }
      continue
    }
    if ($line -match '^\}') { break }
    if ($line -match '^[ \t]+[a-z_]+[ \t]*:') { $count++ }
  }
  $count
}

# The pages the server serves. Three places produce one:
#
#   - the ring domains, one tuple each
#   - the list of the other three seeded pages, one tuple each
#   - the index page and the not-found page, one constructor each
#
# The three counts are added because the three shapes are three lists, and a
# counter that read only one of them would be wrong by the other two.
function Count-SeedPages {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/pages.mbt'), $enc)
  $ring = ([regex]::Matches($text, '(?m)^ *\("[a-z]+", "[A-Z]')).Count
  $list = ([regex]::Matches($text, '(?m)^ *"[a-z]+",$')).Count
  $singles = ([regex]::Matches($text, '(?m)^ *slug: "')).Count
  $ring + $list + $singles
}

# A MoonBit test is a `test "name" {` block or an `async test "name" {`
# one. Both shapes exist in this tree.
function Count-TestBlocks($dir) {
  $pattern = '(?m)^[ \t]*(async[ \t]+)?test[ \t]+"[^"\r\n]*"[ \t]*\{'
  $total = 0
  foreach ($f in (Get-ChildItem (Join-Path $PWD $dir) -Filter '*.mbt' -File)) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    $total += ([regex]::Matches($text, $pattern)).Count
  }
  $total
}

# --- what the documents say -------------------------------------------------

# A number the documents state.
#
# The pattern matches the whole FRAGMENT the number sits in, and the number
# is then the only run of digits in that fragment.
#
# The fragment is matched whole rather than through a capture group. A
# greedy leading `.*` eats INTO the number: "37 API routes" leaves "7" for
# the capture group, because the engine tries the longest `.*` first and "7"
# is the longest prefix that still leaves a digit before " API routes". A
# gate that reads 7 where the document says 37 is a gate that cannot be
# trusted.
#
# The context around the number carries no digits of its own. That is what
# makes "the only run of digits in the fragment" the right answer.
function Get-DocNumber($pattern, $file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) { return '' }
  $digits = [regex]::Match($m.Value, '[0-9]+')
  if (-not $digits.Success) { return '' }
  $digits.Value
}

# A number spelled out in words. "the seven tools" is a claim exactly as
# much as "37 API routes" is, and a word can be mapped to a number.
#
# The map is the twelve words a count below a hundred is written with. A
# count outside that range is a sentence the gate cannot read, and the gate
# says so rather than passing it.
$numberWords = @{
  'one' = '1'; 'two' = '2'; 'three' = '3'; 'four' = '4'; 'five' = '5'; 'six' = '6'
  'seven' = '7'; 'eight' = '8'; 'nine' = '9'; 'ten' = '10'; 'eleven' = '11'; 'twelve' = '12'
}

# A count the document spells out in words. Every "<word> <noun>" in the
# document has to be the count the tree has.
function Test-WordCount($label, $noun, $expected, $doc) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
  $pattern = '\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) ' + $noun + '\b'
  $words = @()
  foreach ($m in [regex]::Matches($text, $pattern)) {
    $word = $m.Groups[1].Value
    if ($words -cnotcontains $word) { $words += $word }
  }
  if ($words.Count -eq 0) {
    Write-Fail ("{0,-22} the document does not state the count in words" -f $label)
    return
  }
  $bad = @()
  foreach ($word in $words) {
    $number = ''
    if ($numberWords.ContainsKey($word)) { $number = $numberWords[$word] }
    if ($number -eq '' -or $number -ne "$expected") { $bad += $word }
  }
  if ($bad.Count -gt 0) {
    Write-Fail ("{0,-22} the document says [{1}], the tree has {2}" -f $label, ($bad -join ' '), $expected)
    return
  }
  Write-Ok $label $expected
}

function Test-Count($label, $actual, $expected) {
  if ($null -eq $actual -or $actual -lt 0) {
    Write-Fail ("{0,-22} could not be derived from the tree" -f $label)
    return
  }
  if ([string]::IsNullOrEmpty($expected)) {
    Write-Fail ("{0,-22} no document states it" -f $label)
    return
  }
  if ($expected -ne "$actual") {
    Write-Fail ("{0,-22} the tree has {1}, the document says {2}" -f $label, $actual, $expected)
    return
  }
  Write-Ok $label $actual
}

# --- the counts -------------------------------------------------------------

Test-Count 'API routes' `
  (Count-Routes) `
  (Get-DocNumber '[0-9]+ API routes' $evidence)

# The same routes, counted the second way. The count above is a count of
# LINES that carry a registration; this one is a count of the paths the
# registrations name. One registration spreads its path over two lines, so
# the two counts are the same number -- and if they are not, the path
# extraction has broken, and every endpoint check built on it would pass
# against nothing.
Test-Count 'route paths' `
  (Get-TreeEndpoints).Count `
  (Count-Routes)

Test-Count 'pages columns' `
  (Count-PageColumns) `
  (Get-DocNumber 'pages` table with [0-9]+ columns' $evidence)

Test-Count 'Page fields' `
  (Count-PageFields) `
  (Get-DocNumber 'Page struct with [0-9]+ fields' $evidence)

Test-Count 'seed pages' `
  (Count-SeedPages) `
  (Get-DocNumber '[|] [0-9]+ seed pages' $evidence)

Test-Count 'frontend tests' `
  (Count-TestBlocks 'frontend') `
  (Get-DocNumber 'frontend/frontend_test\.mbt` [|] [0-9]+ tests' $evidence)

Test-Count 'backend tests' `
  (Count-TestBlocks 'backend/database_test.mbt') `
  (Get-DocNumber 'backend/database_test\.mbt` [|] [0-9]+ tests' $evidence)

# The summary states the two suites together.
Test-Count 'tests (summary)' `
  ((Count-TestBlocks 'backend') + (Count-TestBlocks 'frontend')) `
  (Get-DocNumber '[0-9]+ tests across backend and frontend' $summary)

# --- the dependency versions ------------------------------------------------
#
# The version each dependency is pinned to is stated in three documents, and
# it is stated in moon.mod. All four have to agree: a document that names a
# version the manifest does not pin is a document that sends a reader to a
# version that is not the one this project uses.

$moonMod = [System.IO.File]::ReadAllText((Join-Path $PWD 'moon.mod'), $enc)
$pins = [regex]::Matches($moonMod, '(?m)^ *"([^"]+)@([^"]+)"')
foreach ($pin in $pins) {
  $module = $pin.Groups[1].Value
  $version = $pin.Groups[2].Value
  $label = "dep $($module.Split('/')[-1])"
  $bad = $false
  foreach ($doc in @($deps, $depsMd, $evidence)) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
    $atForm = $text.Contains("$module@$version")
    $tableForm = [regex]::IsMatch($text, "\| $([regex]::Escape($module)) \| $([regex]::Escape($version)) \|")
    if (-not ($atForm -or $tableForm)) {
      Write-Fail ("{0,-22} {1} does not state {2}" -f $label, $doc, $version)
      $bad = $true
    }
  }
  if (-not $bad) {
    Write-Ok $label "$module@$version"
  }
}

# --- the references ---------------------------------------------------------
#
# Every `file.ext:line` or `file.ext:line-line` in the architecture
# documents has to point at a file that exists and a line that is in it. A
# pointer to a line past the end of the file is a pointer to nothing.
#
# This catches the mechanical half of the rot. It cannot catch a reference
# that is in range but has drifted -- that is why the documents say what the
# claim IS next to the pointer, and why a reader who finds one wrong can put
# it back.

function Test-References($doc) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
  $refs = [regex]::Matches($text, '`([A-Za-z0-9_./-]+\.(?:mbt|moon\.pkg|ps1|sh|mod|dsl|dot|md)):(\d+)(?:-(\d+))?`')
  $seen = @{}
  # The count is of DISTINCT references, the way the bash twin counts them:
  # two references that point at the same line are one reference, and two
  # references that point at different lines of the same file are two.
  $distinct = @{}
  $bad = $false
  foreach ($ref in $refs) {
    $file = $ref.Groups[1].Value
    $last = if ($ref.Groups[3].Success) { [int]$ref.Groups[3].Value } else { [int]$ref.Groups[2].Value }
    if (-not $distinct.ContainsKey($ref.Value)) { $distinct[$ref.Value] = $true }
    $key = "$file`:$last"
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $path = Join-Path $PWD $file
    if (-not (Test-Path $path)) {
      Write-Fail ("{0,-22} {1} names a file that is not there" -f $doc, $file)
      $bad = $true
      continue
    }
    $count = ([System.IO.File]::ReadAllLines($path)).Count
    if ($last -gt $count) {
      Write-Fail ("{0,-22} {1} points past the end of the file ({2} lines)" -f $doc, $key, $count)
      $bad = $true
    }
  }
  if (-not $bad) {
    Write-Ok "references $(Split-Path -Leaf $doc)" $distinct.Count
  }
}

foreach ($doc in @($evidence, $deps, $deploy, 'architecture/flows.evidence.md')) {
  Test-References $doc
}

# --- the facts that are not counts -----------------------------------------
#
# The deployment document used to claim there was no Dockerfile, no compose
# file and no CI. Those are not numbers; they are the presence or absence of
# a file, and they are checked the same way -- by looking.

function Test-Exists($label, $path) {
  if (Test-Path $path) {
    Write-Ok $label $path
  } else {
    Write-Fail ("{0,-22} {1} is not there" -f $label, $path)
  }
}

Test-Exists 'Dockerfile' 'Dockerfile'
Test-Exists 'compose file' 'docker-compose.yml'
Test-Exists 'CI workflow' '.github/workflows/ci.yml'
Test-Exists 'publish workflow' '.github/workflows/publish.yml'

# --- the documents that describe the past -------------------------------------
#
# Four documents were written to record the analysis that produced the
# migration slices, and every claim in them was true then and is false now.
# They are kept as they were written -- the reasoning is the point -- but a
# reader has to be TOLD, so each one carries a header that says so.
#
# The gate checks the header, because a header is easy to lose in an edit,
# and a claim that is history without saying so is a lie.

function Test-PastHeader($doc) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
  if ($text.Contains('This document describes the past.')) {
    Write-Ok 'past header' $doc
  } else {
    Write-Fail ("{0,-22} {1} does not say that it describes the past" -f 'past header', $doc)
  }
}

foreach ($doc in @('architecture/evolution.md', 'architecture/evolution.evidence.md', 'evolution-summary.md', 'architecture-evolution-roadmap.md')) {
  Test-PastHeader $doc
}

# --- AGENT.md: the document for another agent -------------------------------
#
# The discovery document at `GET /api/agent` is what an agent reads, and
# AGENT.md is what a person reads before pointing an agent at it. Both carry
# the same facts -- the tools, the protocol, the files, the endpoints -- so
# the facts are derived ONCE, from the discovery document, and both are
# checked against them.
#
# The discovery document is the source rather than the tree because the
# discovery document is what the server ANSWERS with. A tool the server does
# not have is a tool the discovery document must not offer, and the check
# that the server has it is the handler switch in cmd/mcp/main.mbt.

# The tools the discovery document declares. The `name:` field is what makes
# a tool a tool; the `tool:` field of the endpoint list is a reference to
# one, and is not a declaration.
function Get-CodeTools {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, 'name: "(maked_[a-z_]+)"')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

# The same tools as AGENT.md's table gives them. A tool row starts with the
# tool name in backticks; the endpoint table's rows start with a verb, so
# they are never mistaken for tool rows.
function Get-DocTools {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '(?m)^\| `(maked_[a-z_]+)`')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

# The endpoints the discovery document lists, as "METHOD path".
function Get-CodeEndpoints {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, '"method": "([A-Z]+)", *"path": "([^"]+)"')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
  }
  Sort-Set $out
}

# The same endpoints as AGENT.md's table gives them.
function Get-DocEndpoints {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '(?m)^\| `(GET|POST|PUT|DELETE|PATCH)` \| `(/api/[^`]+)`')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
  }
  Sort-Set $out
}

# The tools AGENT.md's endpoint table points at.
function Get-DocEndpointTools {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '(?m)^\| `(GET|POST|PUT|DELETE|PATCH)` \| `(/api/[^`]+)` \| `(maked_[a-z_]+)`')) {
    $out += $m.Groups[3].Value
  }
  Sort-Set $out
}

# The variables that name the files MAKED runs on, from the discovery
# document.
function Get-CodeFileVars {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '"variable": "(MAKED_[A-Z_]+)"')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

# The same variables as the backend actually reads them. The discovery
# document has to offer what the code asks for: a file the code reads and
# the document does not name is a file nobody can point the code at.
function Get-CodeEnvReads {
  $out = @()
  foreach ($f in (Get-ChildItem (Join-Path $PWD 'backend') -Filter '*.mbt' -File)) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    foreach ($m in [regex]::Matches($text, 'get_env_var\("(MAKED_[A-Z_]+)"\)')) {
      $out += $m.Groups[1].Value
    }
  }
  Sort-Set $out
}

# The same variables as AGENT.md's table gives them. The SHAPE of the row is
# what identifies it -- the variable sits in the second column -- so the
# table is found by its shape and not by the heading above it, which is
# itself a claim the word check makes.
function Get-DocFileVars {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '(?m)^\| [^|]+ \| `(MAKED_[A-Z_]+)` \|')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

# The protocol version the discovery document names.
function Get-CodeProtocol {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $m = [regex]::Match($text, '"mcp": "(\d{4}-\d{2}-\d{2})"')
  if (-not $m.Success) { return '' }
  $m.Groups[1].Value
}

# Every date-shaped version in AGENT.md. They all have to be the one the
# server speaks: an agent that reads a version the server does not answer
# to is an agent that cannot call it.
function Get-DocProtocols {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '\d{4}-\d{2}-\d{2}')) {
    $out += $m.Groups[0].Value
  }
  Sort-Set $out
}

$codeTools = Get-CodeTools
$docTools = Get-DocTools

Test-Sets 'agent tools' $codeTools $docTools

Test-WordCount 'agent tools (words)' 'tools' $codeTools.Count $agentDoc

$codeFileVars = Get-CodeFileVars
$docFileVars = Get-DocFileVars

Test-Sets 'agent files' $codeFileVars $docFileVars

Test-WordCount 'agent files (words)' 'files' $codeFileVars.Count $agentDoc

# The discovery document has to offer the variables the code reads.
Test-Sets 'agent files (code)' $codeFileVars (Get-CodeEnvReads)

# Every protocol version the document states has to be the one the server
# speaks, and it has to state it at all.
$protocol = Get-CodeProtocol
if ([string]::IsNullOrEmpty($protocol)) {
  Write-Fail ("{0,-22} the tree does not name a protocol version" -f 'agent protocol')
} else {
  $docProtocols = Get-DocProtocols
  $wrong = @($docProtocols | Where-Object { $_ -cne $protocol })
  $missing = @($protocol | Where-Object { $docProtocols -cnotcontains $_ })
  if ($wrong.Count -gt 0) {
    Write-Fail ("{0,-22} the document names [{1}], the tree names {2}" -f 'agent protocol', ($wrong -join ' '), $protocol)
  } elseif ($missing.Count -gt 0) {
    Write-Fail ("{0,-22} the document does not name {1}" -f 'agent protocol', $protocol)
  } else {
    Write-Ok 'agent protocol' $protocol
  }
}

$codeEndpoints = Get-CodeEndpoints
$docEndpoints = Get-DocEndpoints

Test-Sets 'agent endpoints' $codeEndpoints $docEndpoints

# Every endpoint the discovery document lists has to be a route the server
# really registers, with the same verb.
Test-Subset 'agent endpoints live' $codeEndpoints (Get-TreeEndpoints)

# The discovery endpoint itself is the way in, so it has to be a route.
Test-Subset 'discovery route' 'GET /api/agent' (Get-TreeEndpoints)

# Every tool the endpoint table points at has to be a tool the server has.
Test-Subset 'endpoint tools' (Get-DocEndpointTools) $codeTools

# The agent's server is not in the published release, and the document says
# so. One of the two is a lie the moment the other changes, so the two are
# checked against each other: the release workflow is what decides whether
# the server is shipped, and the document has to say the same thing.
$publishText = [System.IO.File]::ReadAllText((Join-Path $PWD '.github/workflows/publish.yml'), $enc)
$agentText = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
$runText = [System.IO.File]::ReadAllText((Join-Path $PWD $runNote), $enc)
$publishMcp = ([regex]::Matches($publishText, 'cmd/mcp')).Count
$docNotShipped = ([regex]::Matches($agentText, [regex]::Escape('in the published release artifacts'))).Count
if ($publishMcp -gt 0 -and $docNotShipped -gt 0) {
  Write-Fail ("{0,-22} the document says the agent server is not released, and the release workflow builds it" -f 'release claim')
} elseif ($publishMcp -eq 0 -and $docNotShipped -eq 0) {
  Write-Fail ("{0,-22} the release workflow does not build the agent server, and the document does not say so" -f 'release claim')
} else {
  Write-Ok 'release claim' 'not in the release'
}

# The port the agent's server speaks HTTP on is named by a variable, and the
# document has to name the same one the code reads.
$mcpText = [System.IO.File]::ReadAllText((Join-Path $PWD 'cmd/mcp/main.mbt'), $enc)
if ($agentText.Contains('MAKED_MCP_PORT') -and $mcpText.Contains('MAKED_MCP_PORT')) {
  Write-Ok 'agent port variable' 'MAKED_MCP_PORT'
} else {
  Write-Fail ("{0,-22} MAKED_MCP_PORT is not in both the document and the server" -f 'agent port variable')
}

# --- packaging/RUN.txt: the note in the archive -----------------------------
#
# The note is what a reader has after the toolchain is gone, so the variables
# it lists are the only ones they will find. A variable the server reads and
# the note does not name is a setting nobody can turn.

# The settings the server reads, with their defaults.
function Get-CodeSettings {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'cmd/server/main.mbt'), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, 'env_or\("(MAKED_[A-Z_]+)", "([^"]*)"\)')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
  }
  Sort-Set $out
}

# The same settings as the note gives them. The line has to END with the
# default, so a sentence that mentions a variable in passing is not read as
# a setting.
function Get-DocSettings {
  $out = @()
  foreach ($line in ($runText -split "`r?`n")) {
    $m = [regex]::Match($line, '^ *MAKED_[A-Z_]+ +[^()]*\(default ([^)]*)\)\s*$')
    if ($m.Success) {
      $name = [regex]::Match($line, '^ *(MAKED_[A-Z_]+)').Groups[1].Value
      $out += ("{0} {1}" -f $name, $m.Groups[1].Value)
    }
  }
  Sort-Set $out
}

# The variables the note names that are not settings: the ones that name
# files. The settings are subtracted, so a variable mentioned in a sentence
# is not mistaken for a file.
function Get-DocRunFiles($settings) {
  $names = @()
  foreach ($setting in $settings) {
    $names += ($setting -split ' ')[0]
  }
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $runNote), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, 'MAKED_[A-Z_]+')) {
    $variable = $m.Groups[0].Value
    if ($names -cnotcontains $variable -and $out -cnotcontains $variable) {
      $out += $variable
    }
  }
  Sort-Set $out
}

$codeSettings = Get-CodeSettings
$docSettings = Get-DocSettings

Test-Sets 'run note settings' $codeSettings $docSettings

Test-Sets 'run note files' $codeFileVars (Get-DocRunFiles $codeSettings)

# The executable the note tells the reader to run is the one the release
# workflow packages.
if ($publishText.Contains('stage/maked/server') -and $runText.Contains('server.exe') -and $runText.Contains('./server')) {
  Write-Ok 'run note executable' './server'
} else {
  Write-Fail ("{0,-22} the note and the release workflow disagree about the executable" -f 'run note executable')
}

# --- .githooks/README.md: the note beside the hook ---------------------------
#
# The hook and the note beside it have to agree. A note that names a command
# the hook does not run sends a reader to a gate that is not there, and a
# hook that runs a command the note does not name is a gate the reader does
# not know is there.

# The commands the hook runs: the lines that are neither blank nor a comment.
function Get-CodeHookCommands {
  $out = @()
  $path = Join-Path $PWD '.githooks/pre-commit'
  if (Test-Path $path) {
    foreach ($line in (([System.IO.File]::ReadAllText($path, $enc)) -split "`n")) {
      if ($line -match '^[ \t]*(#|$)') { continue }
      $out += $line.Trim()
    }
  }
  Sort-Set $out
}

# The commands the note states, in the section that says what the hook runs.
function Get-DocHookCommands {
  $out = @()
  $path = Join-Path $PWD '.githooks/README.md'
  if (Test-Path $path) {
    $inside = $false
    foreach ($line in (([System.IO.File]::ReadAllText($path, $enc)) -split "`n")) {
      if ($line -match '^#+ What It Runs') { $inside = $true; continue }
      if ($inside -and $line -match '^#') { break }
      if (-not $inside) { continue }
      foreach ($m in [regex]::Matches($line, '`([^`]+)`')) { $out += $m.Groups[1].Value }
    }
  }
  Sort-Set $out
}

Test-Sets 'hook commands' (Get-CodeHookCommands) (Get-DocHookCommands)

Write-Output ""
if ($failures -gt 0) {
  Write-Output ("{0} claim(s) in the documents do not match the tree." -f $failures)
  Write-Output "*** FAIL ***"
  Write-Output ""
  Write-Output "The documents state a claim and the tree has another. Fix the documents,"
  Write-Output "or fix the tree -- but make the two agree before saying anything about"
  Write-Output "either of them."
  exit 1
}
Write-Output "Every claim in the documents matches the tree."
exit 0
