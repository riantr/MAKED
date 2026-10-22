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
$agentsDoc = 'AGENTS.md'
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
  $counts = Get-SeedPageCounts
  ($counts[0] + $counts[1] + $counts[2])
}

# The three counts the seed is made of, read in ONE pass: a pass is a
# process, and a process on this machine costs a tenth of a second.
function Get-SeedPageCounts {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/pages.mbt'), $enc)
  $ring = ([regex]::Matches($text, '(?m)^ *\("[a-z]+", "[A-Z]')).Count
  $list = ([regex]::Matches($text, '(?m)^ *"[a-z]+",$')).Count
  $singles = ([regex]::Matches($text, '(?m)^ *slug: "')).Count
  @($ring, $list, $singles)
}

# The pages seed_pages() returns: the ring domains and the other three. The
# index page and the not-found page are made on their own and seeded
# separately, so they are not part of this count.
function Count-SeedPagesOnly {
  $counts = Get-SeedPageCounts
  ($counts[0] + $counts[1])
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
  # The document is flattened first, because a phrase the editor wrapped is
  # one phrase to a reader and two to a matcher.
  $text = ([System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)) -replace "`n", ' '
  $text = $text -replace ' +', ' '
  # The match is case-insensitive, because a count at the start of a sentence
  # is capitalised and the count is the same count.
  $pattern = '(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) ' + $noun + '\b'
  $words = @()
  foreach ($m in [regex]::Matches($text, $pattern)) {
    # The word is lower-cased before it is looked up, because a count at the
    # start of a sentence is capitalised and the count is the same count. The
    # bash twin lower-cases it too, so the two twins judge the same word the
    # same way and print it the same way.
    $word = $m.Groups[1].Value.ToLowerInvariant()
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
  # The words that are wrong, in ONE order: the ordinal one, which is the
  # order the bytes are in. The bash twin sorts with LC_ALL=C, which is the
  # same order, so the two twins print the same message when a count in
  # words is wrong -- and a message that differs between the twins is a
  # message nobody can trust.
  $bad = Sort-Set $bad
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

# --- the links the documents carry --------------------------------------------
#
# A document that links at a file that is not there sends the reader to
# nothing, and the reader cannot tell that the link is broken -- it looks
# exactly like a link that works. The references above check the pointers
# written as `file.ext:line`; this one checks the pointers written as
# markdown links.
#
# The links are read from every document the repository ships, apart from the
# README: the README has a gate of its own, and a fact is watched in one
# place only. The vendored dependency cache and the build output are pruned --
# they are not documents of this project, and a broken link in somebody else's
# cache is not this project's rot.
#
# A link is RELATIVE when it does not begin with a scheme, so a link to a
# page on the web is left alone. A fragment is dropped: `page.md#section`
# points at a place inside a file, and it is the file that has to be there.
#
# The link is resolved against the DIRECTORY OF THE DOCUMENT, which is where a
# reader's browser resolves it from. A document that was moved has to have its
# links moved with it, and that is the whole of this check.

function Get-DocFiles {
  $out = @()
  $stack = New-Object System.Collections.Stack
  $stack.Push($PWD.Path)
  while ($stack.Count -gt 0) {
    $dir = [string]$stack.Pop()
    foreach ($item in @(Get-ChildItem -Path $dir -Force -ErrorAction SilentlyContinue)) {
      if ($item.PSIsContainer) {
        if ($item.Name -eq '.mooncakes' -or $item.Name -eq '_build' -or
            $item.Name -eq '.git' -or $item.Name -eq 'node_modules') { continue }
        $stack.Push($item.FullName)
      } else {
        $ext = $item.Extension.ToLowerInvariant()
        if ($ext -ne '.md' -and $ext -ne '.txt') { continue }
        $rel = $item.FullName.Substring($PWD.Path.Length + 1).Replace('\', '/')
        $out += $rel
      }
    }
  }
  Sort-Set $out
}

function Get-DocLinks {
  $out = @()
  foreach ($doc in (Get-DocFiles)) {
    if ($doc -ceq 'README.md') { continue }
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
    $dir = [System.IO.Path]::GetDirectoryName($doc)
    if ([string]::IsNullOrEmpty($dir)) { $dir = '.' }
    foreach ($m in [regex]::Matches($text, '\]\(([^)]+)\)')) {
      $link = $m.Groups[1].Value
      # A link may carry a title after the path: `page.md "the title"`. The
      # path is what has to be there.
      if ($link -notmatch '^\s*(\S*)') { continue }
      $link = $Matches[1]
      if ($link.StartsWith('#')) { continue }
      if ($link -match '^[a-zA-Z][a-zA-Z0-9+.-]*:') { continue }
      $hash = $link.IndexOf('#')
      if ($hash -ge 0) { $link = $link.Substring(0, $hash) }
      if ($link -eq '') { continue }
      $out += ("{0} {1} {2}" -f $doc, $dir, $link)
    }
  }
  $out
}

$brokenLinks = @()
$linkCount = 0
foreach ($entry in (Get-DocLinks)) {
  $parts = $entry.Split(' ')
  $linkDoc = $parts[0]
  $linkDir = $parts[1]
  $linkText = $parts[2]
  $linkCount++
  $target = Join-Path (Join-Path $PWD $linkDir) $linkText
  if (-not (Test-Path $target)) {
    $brokenLinks += ("{0} -> {1}" -f $linkDoc, $linkText)
  }
}
if ($brokenLinks.Count -gt 0) {
  Write-Fail ("{0,-22} these links point at files that are not there: {1}" -f 'Document links', ($brokenLinks -join ' '))
} else {
  Write-Ok 'Document links' $linkCount
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

# --- the port the container publishes ------------------------------------------
#
# The port is one number in this project, and it is written in five places:
# the server's default, the Dockerfile's environment, the Dockerfile's EXPOSE
# line, the compose file's environment, and the mapping the compose file
# publishes. They all have to be the same one.
#
# The Dockerfile sets MAKED_PORT itself, so a container keeps working even
# when the server's default moves -- which is exactly why the drift is
# invisible. The reader is told to open one port and the container listens
# on another, and the symptom is a browser that waits and then says the
# connection was refused.
#
# The server's default is the source: it is the port the server listens on
# when nothing sets it, and every other number has to be that one.

function Get-CodeDefaultPort {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'cmd/server/main.mbt'), $enc)
  $m = [regex]::Match($text, 'env_or\("MAKED_PORT", "([0-9]+)"\)')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

# The ports the Dockerfile writes: the one it sets, the one it exposes, and
# the mapping in the command its own header tells the reader to run.
function Get-DockerfilePorts {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'Dockerfile'), $enc)
  foreach ($m in [regex]::Matches($text, 'MAKED_PORT=([0-9]+)')) { $out += $m.Groups[1].Value }
  foreach ($m in [regex]::Matches($text, '(?m)^EXPOSE ([0-9]+)')) { $out += $m.Groups[1].Value }
  foreach ($m in [regex]::Matches($text, '\-p ([0-9]+):([0-9]+)')) {
    $out += $m.Groups[1].Value
    $out += $m.Groups[2].Value
  }
  $out
}

# The ports the compose file writes: the one it sets and the two sides of
# the mapping it publishes.
function Get-ComposePorts {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'docker-compose.yml'), $enc)
  foreach ($m in [regex]::Matches($text, 'MAKED_PORT: "([0-9]+)"')) { $out += $m.Groups[1].Value }
  foreach ($m in [regex]::Matches($text, '"([0-9]+):([0-9]+)"')) {
    $out += $m.Groups[1].Value
    $out += $m.Groups[2].Value
  }
  $out
}

$defaultPort = Get-CodeDefaultPort
$wrongPort = @()
foreach ($port in (@(Get-DockerfilePorts) + @(Get-ComposePorts))) {
  if ($port -cne $defaultPort) { $wrongPort += $port }
}
if ([string]::IsNullOrEmpty($defaultPort)) {
  Write-Fail ("{0,-22} the server does not name a default port" -f 'container port')
} elseif ($wrongPort.Count -gt 0) {
  Write-Fail ("{0,-22} the server uses {1}, and these ports are not it: {2}" -f 'container port', $defaultPort, ($wrongPort -join ' '))
} else {
  Write-Ok 'container port' $defaultPort
}

# --- what the Dockerfile says about itself -------------------------------------
#
# The Dockerfile's header is a document like any other: it tells the reader
# how to run the image, and it states two things about the file that have
# to be true.
#
# The healthcheck asks the server a question, and the question has to be
# one the server answers. A healthcheck that asks for a route that is not
# there fails every time, and the container is reported unhealthy while the
# server inside it is working perfectly.
#
# The two stages have to be built on the same image, and the file says so:
# a binary built against a newer glibc than the runtime image has fails at
# start-up with a version error that reads like a corrupt download.

$dockerfile = [System.IO.File]::ReadAllText((Join-Path $PWD 'Dockerfile'), $enc)

$healthcheckPaths = @()
foreach ($m in [regex]::Matches($dockerfile, '/api/[a-z0-9/_-]+')) { $healthcheckPaths += $m.Groups[0].Value }
$healthcheckPaths = @(Sort-Set $healthcheckPaths)

$routePaths = @()
foreach ($endpoint in (Get-TreeEndpoints)) { $routePaths += ($endpoint -split ' ')[1] }

if ($healthcheckPaths.Count -eq 0) {
  Write-Fail ("{0,-22} the Dockerfile asks the server nothing" -f 'healthcheck')
} else {
  $unknownPath = @()
  foreach ($path in $healthcheckPaths) {
    if ($routePaths -cnotcontains $path) { $unknownPath += $path }
  }
  if ($unknownPath.Count -gt 0) {
    Write-Fail ("{0,-22} the server does not serve: {1}" -f 'healthcheck', ($unknownPath -join ' '))
  } else {
    Write-Ok 'healthcheck' ($healthcheckPaths -join ' ')
  }
}

$baseImages = @()
foreach ($m in [regex]::Matches($dockerfile, '(?m)^FROM (\S+)')) { $baseImages += $m.Groups[1].Value }
$baseImages = @(Sort-Set $baseImages)

if ($baseImages.Count -eq 0) {
  Write-Fail ("{0,-22} no base image could be derived from the Dockerfile" -f 'base image')
} elseif ($baseImages.Count -gt 1) {
  Write-Fail ("{0,-22} the stages are built on different images: [{1}]" -f 'base image', ($baseImages -join ' '))
} else {
  Write-Ok 'base image' $baseImages[0]
}

# --- the documents that describe the past -------------------------------------
#
# Seven documents were written to record the analysis that produced the
# migration slices, and every claim in them was true then and is false now.
# They are kept as they were written -- the reasoning is the point -- but a
# reader has to be TOLD, so each one carries a header that says so.
#
# Three of them are graphs, and a header in a graph is invisible once the
# graph is rendered, so each of those carries the marker twice: once in the
# source, where a reader opens the file, and once as the graph's own title,
# where a reader opens the picture.
#
# The gate checks the header, because a header is easy to lose in an edit,
# and a claim that is history without saying so is a lie.
#
# The marker is also how a document opts out of the count checks: the graphs
# that say they describe the past are the ones that are not counted against
# the tree. That is the right way round -- the document says what it is --
# but it means the marker has to be checked against something. A graph that
# claimed to be history and was not one of the seven would slip out of the
# count checks without anybody noticing, so the gate knows which documents
# are history, and the two sets have to be the same set.
#
# The documents are read once: the marker is looked for in each of them, and
# the answer is used for the header check and for the check that the two sets
# are the same set.

# The documents the gate knows as history.
$pastDocs = @(
  'architecture/evolution.md'
  'architecture/evolution.evidence.md'
  'architecture/evolution.dot'
  'architecture/evolution-summary.md'
  'architecture/evolution-roadmap.md'
  'architecture/current-vs-target.dot'
  'architecture/migration-dependency.dot'
)

# The documents that carry the marker, as the tree says it. Every document
# in the architecture folder is a candidate: the marker is what makes one of
# them history.
function Get-MarkedDocuments {
  $out = @()
  foreach ($file in @(Get-ChildItem -Path 'architecture' -File |
      Where-Object { $_.Extension -eq '.md' -or $_.Extension -eq '.dot' })) {
    $text = [System.IO.File]::ReadAllText($file.FullName, $enc)
    if ($text.Contains('This document describes the past.')) {
      $out += ('architecture/' + $file.Name)
    }
  }
  Sort-Set $out
}

$markedDocs = @(Get-MarkedDocuments)

function Test-PastHeader($doc) {
  # The marker has already been looked for: the answer is in $markedDocs.
  if ($markedDocs -ccontains $doc) {
    Write-Ok 'past header' $doc
  } else {
    Write-Fail ("{0,-22} {1} does not say that it describes the past" -f 'past header', $doc)
  }
}

foreach ($doc in $pastDocs) {
  Test-PastHeader $doc
}

# The three graphs say it in their title as well, because a title is what a
# reader sees once the graph is rendered. A graph that keeps the marker in
# its source and loses it from its picture has lost it for half its readers,
# and the source comment does not travel with the SVG.
function Test-PastTitle($doc) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
  if ([regex]::IsMatch($text, 'label="This document describes the past\.')) {
    Write-Ok 'past title' $doc
  } else {
    Write-Fail ("{0,-22} {1} does not say in its title that it describes the past" -f 'past title', $doc)
  }
}

# The graphs are the documents on the list that are graphs.
foreach ($doc in $pastDocs) {
  if ($doc.EndsWith('.dot')) { Test-PastTitle $doc }
}

# Every document that carries the marker is one the gate knows as history. A
# document that is not on the list has slipped out of the count checks.
$unknownPast = @($markedDocs | Where-Object { $pastDocs -cnotcontains $_ })
if ($unknownPast.Count -eq 0) {
  Write-Ok 'past documents' $markedDocs.Count
} else {
  Write-Fail ("{0,-22} the tree says [{1}] describes the past, and the gate does not know it" -f 'past documents', ($unknownPast -join ' '))
}

# The number of documents that describe the past, as AGENTS.md states it. The
# word is read like any other count: "SEVEN of them describe the PAST" is a
# claim about the tree, and the tree has seven. It was four once, and the
# three graphs that joined the history were never counted.
Test-WordCount 'agent guide past' 'of them describe the PAST' $markedDocs.Count $agentsDoc

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

# The arguments each tool takes, as "tool argument" pairs.
#
# The tool says which schema it has, and the schema says which arguments it
# has, so the two are followed rather than copied. The schema functions come
# first in the file and the tool specs after, so one pass is enough: the
# schemas are collected as they are met, and the tool specs are answered from
# what was collected.
function Get-CodeToolArgs {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $props = @{}
  $tool = ''
  $fn = ''
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^fn (agent_[a-z_]*)\(\) -> Json \{') {
      $fn = $Matches[1]
      $inside = $true
      $props[$fn] = @()
      continue
    }
    if ($inside -and $line -match '^\}') { $inside = $false }
    if ($inside -and $line -match '^      "([a-z_]+)": \{$') {
      $props[$fn] += $Matches[1]
      continue
    }
    if ($line -match '^      name: "(maked_[a-z_]+)",') { $tool = $Matches[1]; continue }
    if ($line -match '^      arguments: (agent_[a-z_]*)\(\),') {
      $schema = $Matches[1]
      foreach ($arg in @($props[$schema])) { $out += ("{0} {1}" -f $tool, $arg) }
    }
  }
  Sort-Set $out
}

# The arguments AGENT.md's table gives each tool, as "tool argument" pairs.
# The arguments sit in the second column, and a tool that takes none says so
# with a dash rather than with an empty cell.
function Get-DocToolArgs {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  foreach ($m in [regex]::Matches($text, '(?m)^\| `(maked_[a-z_]+)` \| ([^|]*)\|')) {
    $tool = $m.Groups[1].Value
    foreach ($a in [regex]::Matches($m.Groups[2].Value, '`([^`]+)`')) {
      $out += ("{0} {1}" -f $tool, $a.Groups[1].Value)
    }
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

# The endpoints the discovery document lists, each with the tool that answers
# it, as "METHOD path tool".
#
# The tool follows the path in the source, so the two are read together
# rather than matched up afterwards. A table that sends a reader to the wrong
# tool for a path is a table that answers a different question than the one
# it names.
function Get-CodeEndpointMappings {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, '"method": "([A-Z]+)", *"path": "([^"]+)", *"tool": "(maked_[a-z_]+)"')) {
    $out += ("{0} {1} {2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
  }
  Sort-Set $out
}

# The same endpoints as AGENT.md's table gives them, each with the tool it
# names.
function Get-DocEndpointMappings {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '(?m)^\| `(GET|POST|PUT|DELETE|PATCH)` \| `(/api/[^`]+)` \| `(maked_[a-z_]+)`')) {
    $out += ("{0} {1} {2}" -f $m.Groups[1].Value, $m.Groups[2].Value, $m.Groups[3].Value)
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

# The formats the discovery document pairs with the variables it names, as
# "variable format".
#
# The discovery document is what the server ANSWERS with, so a format it
# names wrongly is a format it tells an agent to write and then refuses.
function Get-CodeFileFormats {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  foreach ($m in [regex]::Matches($flat, '"variable": "(MAKED_[A-Z_]+)", *"format": "([^"]+)"')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
  }
  Sort-Set $out
}

# The formats the backend actually accepts, paired with the variable that
# names the file, as "variable format".
#
# Each backend file owns ONE format constant and reads ONE environment
# variable, so the pair is read from the file that holds both: the model file
# declares the format a model is written in and is the file MAKED_MODEL names.
# A file that owns more than one of either is not paired -- the gate would
# rather say it cannot tell than guess.
function Get-BackendFileFormats {
  $out = @()
  foreach ($file in @(Get-ChildItem (Join-Path $PWD 'backend') -Filter '*.mbt' -File)) {
    $text = [System.IO.File]::ReadAllText($file.FullName, $enc)
    $formats = @()
    foreach ($m in [regex]::Matches($text, 'pub const [A-Z_]+_FORMAT : String = "([^"]+)"')) {
      $formats += $m.Groups[1].Value
    }
    $vars = @()
    foreach ($m in [regex]::Matches($text, 'get_env_var\("(MAKED_[A-Z_]+)"\)')) {
      $vars += $m.Groups[1].Value
    }
    $vars = @($vars | Sort-Object -Unique)
    if ($formats.Count -eq 1 -and $vars.Count -eq 1) {
      $out += ("{0} {1}" -f $vars[0], $formats[0])
    }
  }
  Sort-Set $out
}
# The files the discovery document names, each with the variable that names
# it, as "file variable".
#
# The file is what the document calls it -- "the machine", "the corpus" --
# and the variable is the one that points at it. Both are read from the
# discovery document, which is what the server answers with.
function Get-CodeFileNames {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  foreach ($m in [regex]::Matches($flat, '"what": "([^"]+)", *"variable": "(MAKED_[A-Z_]+)"')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value.ToLowerInvariant(), $m.Groups[2].Value)
  }
  Sort-Set $out
}

# The same files as AGENT.md's table gives them, each with the variable it
# names.
#
# The row is read as a pair: the first column names the file, and the
# variable in the second column is the one that points at it.
function Get-DocFileNames {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  foreach ($m in [regex]::Matches($text, '(?m)^\| ([^|]+) \| `(MAKED_[A-Z_]+)` \|')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value.Trim().ToLowerInvariant(), $m.Groups[2].Value)
  }
  Sort-Set $out
}
# The entry point the discovery document names, and the one the document
# states. An agent that calls the wrong one gets nowhere, so the method the
# server tells it to call and the method AGENT.md tells it to call have to
# be the same.
function Get-CodeEntryPoint {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $m = [regex]::Match($text, '"entry_point": "([^"]+)"')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

# The entry point the document states. The sentence is found by its own
# shape -- "entry point is" -- so a method named in some other part of the
# document is not read as a claim about this one. The lines are joined
# first, because the sentence can wrap.
function Get-DocEntryPoint {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $flat = ($text -replace "`r?`n", ' ') -replace ' +', ' '
  $m = [regex]::Match($flat, 'entry point is `([^`]+)`')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
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
$codeToolArgs = Get-CodeToolArgs
$docToolArgs = Get-DocToolArgs

Test-Sets 'agent tools' $codeTools $docTools

# The arguments the document gives each tool have to be the arguments the
# tool takes. An agent that reads a table without an argument will not send
# it, and the answer it gets back is not the answer it asked for.
Test-Sets 'agent arguments' $codeToolArgs $docToolArgs

Test-WordCount 'agent tools (words)' 'tools' $codeTools.Count $agentDoc

$codeFileVars = Get-CodeFileVars
$docFileVars = Get-DocFileVars

Test-Sets 'agent files' $codeFileVars $docFileVars

Test-WordCount 'agent files (words)' 'files' $codeFileVars.Count $agentDoc

# The discovery document has to offer the variables the code reads.
Test-Sets 'agent files (code)' $codeFileVars (Get-CodeEnvReads)

# And the format it pairs with each of them has to be the one the loader
# accepts. The document is what the server answers with, so a format it
# names wrongly is a format it tells an agent to write and then refuses --
# and the variables being right does not make the formats right.
Test-Sets 'agent file formats' (Get-CodeFileFormats) (Get-BackendFileFormats)

# The document has to name the RIGHT variable for each file. The variables
# are checked as a set above, and a set does not say which file each one
# names: a table that gives the machine the corpus's variable still has the
# same four variables in it, and a reader who follows it points MAKED_MODEL
# at the wrong file.
Test-Sets 'agent file names' (Get-CodeFileNames) (Get-DocFileNames)

# Every protocol version the document states has to be the one the server
# speaks, and it has to state it at all.
$codeEntryPoint = Get-CodeEntryPoint
$docEntryPoint = Get-DocEntryPoint
if ([string]::IsNullOrEmpty($codeEntryPoint)) {
  Write-Fail ("{0,-22} the tree does not name an entry point" -f 'agent entry point')
} elseif ([string]::IsNullOrEmpty($docEntryPoint)) {
  Write-Fail ("{0,-22} the document does not state the entry point" -f 'agent entry point')
} elseif ($codeEntryPoint -cne $docEntryPoint) {
  Write-Fail ("{0,-22} the tree says {1}, the document says {2}" -f 'agent entry point', $codeEntryPoint, $docEntryPoint)
} else {
  Write-Ok 'agent entry point' $codeEntryPoint
}

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
$codeEndpointMappings = Get-CodeEndpointMappings
$docEndpointMappings = Get-DocEndpointMappings

Test-Sets 'agent endpoints' $codeEndpoints $docEndpoints

# Every endpoint the discovery document lists has to be a route the server
# really registers, with the same verb.
Test-Subset 'agent endpoints live' $codeEndpoints (Get-TreeEndpoints)

# The discovery endpoint itself is the way in, so it has to be a route.
Test-Subset 'discovery route' 'GET /api/agent' (Get-TreeEndpoints)

# Every tool the endpoint table points at has to be a tool the server has.
Test-Subset 'endpoint tools' (Get-DocEndpointTools) $codeTools

# And the table has to point at the RIGHT tool for each path. The endpoint
# list and the tool names are checked on their own above, and neither of them
# says which tool answers which path -- so a table that sends a reader to the
# wrong tool passes both of them.
Test-Sets 'endpoint mapping' $codeEndpointMappings $docEndpointMappings

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
# The path the agent's server speaks HTTP on. The code hands the path to the
# server, and the document has to name the same one: an agent that posts to a
# path the server does not serve gets nothing back.
#
# The claim is found by its own shape -- the sentence that says the server
# speaks HTTP, and the path at the end of it -- so a path named somewhere
# else in the document is not read as a claim about this one.
function Get-CodeAgentPath {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'cmd/mcp/main.mbt'), $enc)
  $m = [regex]::Match($text, 'run_http\([^)]*path="([^"]+)"')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

function Get-DocAgentPath {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $flat = ($text -replace "`r?`n", ' ') -replace ' +', ' '
  $m = [regex]::Match($flat, 'speaks HTTP[^.]*at `([^`]+)`')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

$codeAgentPath = Get-CodeAgentPath
$docAgentPath = Get-DocAgentPath
if ([string]::IsNullOrEmpty($codeAgentPath)) {
  Write-Fail ("{0,-22} the tree does not name the path the agent server serves" -f 'agent server path')
} elseif ([string]::IsNullOrEmpty($docAgentPath)) {
  Write-Fail ("{0,-22} the document does not state the path" -f 'agent server path')
} elseif ($codeAgentPath -cne $docAgentPath) {
  Write-Fail ("{0,-22} the tree says {1}, the document says {2}" -f 'agent server path', $codeAgentPath, $docAgentPath)
} else {
  Write-Ok 'agent server path' $codeAgentPath
}

# --- the language switch the guide states ---------------------------------------
#
# AGENT.md tells an agent which language codes it may send, and the code is
# the source of the answer: Lang::code() gives the code each language
# answers to, and lang_from_query() says what an absent parameter means.
# Nothing compared the two, so a guide that named a code the server does
# not recognise would have been no more wrong than a README that did.
#
# The sentence is found by its own shape -- the words that introduce the
# codes -- and the codes are the quoted ones in it. The last one is the
# default's, because that is where the sentence puts it.

function Get-CodeLangPairs {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/i18n.mbt'), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^pub fn Lang::code\(') { $inside = $true; continue }
    if ($inside -and $line -match '^\}') { break }
    if ($inside -and $line -match '^\s*([A-Z][A-Za-z]*) => "([^"]+)"') {
      $out += ($Matches[1] + ' ' + $Matches[2])
    }
  }
  $out
}

function Get-CodeLangDefault {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/i18n.mbt'), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^pub fn lang_from_query\(') { $inside = $true; continue }
    if ($inside -and $line -match 'None => ([A-Z][A-Za-z]*)') { return $Matches[1] }
  }
  ''
}

# The code a language answers to.
function Get-LangCodeOf($variant, $pairs) {
  foreach ($pair in $pairs) {
    $parts = $pair -split ' '
    if ($parts[0] -ceq $variant) { return $parts[1] }
  }
  ''
}

# The codes the guide states.
function Get-DocLangCodes {
  $text = ([System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)) -replace "`n", ' '
  $text = $text -replace ' +', ' '
  $out = @()
  foreach ($m in [regex]::Matches($text, 'is the language to answer in[^.]*\.')) {
    foreach ($c in [regex]::Matches($m.Value, '`"([a-z]+)"`')) { $out += $c.Groups[1].Value }
  }
  ($out -join ' ')
}

$codeLangPairs = @(Get-CodeLangPairs)
$codeLangDefault = Get-CodeLangDefault
$docLangCodes = Get-DocLangCodes
$codeLangCodesList = (Sort-Set @($codeLangPairs | ForEach-Object { ($_ -split ' ')[1] })) -join ' '
$docLangDefaultCode = ''
$docLangCodeList = @($docLangCodes -split ' ') | Where-Object { $_ -ne '' }
if ($docLangCodeList.Count -gt 0) {
  $docLangDefaultCode = $docLangCodeList[-1]
  if ($docLangCodeList.Count -gt 1) {
    $docLangCodesList = (Sort-Set @($docLangCodeList[0..($docLangCodeList.Count - 2)])) -join ' '
  } else {
    $docLangCodesList = ''
  }
}
$codeLangDefaultCode = Get-LangCodeOf $codeLangDefault $codeLangPairs

if ($codeLangCodesList -eq '') {
  Write-Fail ("{0,-22} no language could be derived from the code" -f 'agent language switch')
} elseif ($docLangCodes -eq '') {
  Write-Fail ("{0,-22} the document does not state the language codes" -f 'agent language switch')
} elseif ($docLangCodesList -cne $codeLangCodesList) {
  Write-Fail ("{0,-22} the tree says [{1}], the document says [{2}]" -f 'agent language switch', $codeLangCodesList, $docLangCodesList)
} elseif ($docLangDefaultCode -cne $codeLangDefaultCode) {
  Write-Fail ("{0,-22} an absent parameter means [{1}], the document says [{2}]" -f 'agent language switch', $codeLangDefaultCode, $docLangDefaultCode)
} else {
  Write-Ok 'agent language switch' $codeLangCodesList
}
# --- the protocol fields the guide states ---------------------------------------
#
# AGENT.md tells an agent how to wire itself up, and the fields every
# request's `params._meta` has to carry are the contract: an agent that
# spells one of them differently has every request it makes refused. The
# guide states them and MAKED's own discovery document states them, and
# nothing compared the two -- so a guide that spelled a field name
# differently would have gone unnoticed, and every request an agent made
# with it would have been refused.
#
# The discovery document is the source, because the discovery document is
# what the server ANSWERS with. Its note is where the protocol fields are
# written down, so that is where they are read from.
#
# The fields are found by the namespace they live in, which is specific
# enough to be read out of the whole guide: a name in another namespace is
# the name of something else.

function Get-CodeProtocolFields {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/agent.mbt'), $enc)
  $m = [regex]::Match($text, '(?s)"protocol": \{(.*?)\n[ \t]*\},')
  if (-not $m.Success) { return @() }
  $out = @()
  foreach ($t in [regex]::Matches($m.Groups[1].Value, '`(io\.modelcontextprotocol/[A-Za-z]+)`')) { $out += $t.Groups[1].Value }
  Sort-Set $out
}

function Get-DocProtocolFields {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  $out = @()
  foreach ($t in [regex]::Matches($text, '`(io\.modelcontextprotocol/[A-Za-z]+)`')) { $out += $t.Groups[1].Value }
  Sort-Set $out
}

$codeProtocolFields = @(Get-CodeProtocolFields)
$docProtocolFields = @(Get-DocProtocolFields)

if ($codeProtocolFields.Count -eq 0 -or $docProtocolFields.Count -eq 0) {
  Write-Fail ("{0,-22} the protocol fields could not be found on both sides" -f 'agent protocol fields')
} else {
  Test-Sets 'agent protocol fields' $codeProtocolFields $docProtocolFields
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

# --- AGENTS.md and ci.sh: the counts an agent reads before it touches the tree
#
# AGENTS.md is the first file an agent opens in this repository, and it tells
# that agent how the project is verified: how many gates there are, and how
# many of them a push is checked against. Those are counts, and a count in the
# first document an agent reads is the one that sends it down the wrong road.
#
# The gate count comes from ci.sh's own gate list -- the `gate "name"` calls
# in its full mode -- and the workflow count from the steps the CI workflow's
# gates job runs. ci.sh's own header states both, and so does AGENTS.md, and
# both have to state the tree's.
#
# The scripts the workflow runs also have to be a subset of the scripts a
# ci.sh gate runs. A step in the workflow that runs something ci.sh does not
# run is a check the local run does not have, and an agent that has run ci.sh
# believes it has run everything the pipeline runs.

# The gates in ci.sh's full run: the `gate "name"` calls in its default arm.
function Get-CiGateCount {
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
    if ($lines[$i] -match '^[ \t]*gate "') { $count++ }
  }
  $count
}

# The scripts a ci.sh gate runs.
function Get-CiScripts {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'ci.sh'), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, 'bash tools/([A-Za-z0-9_.-]+\.sh)')) { $out += $m.Groups[1].Value }
  Sort-Set $out
}

# The scripts the CI workflow's gates job runs.
function Get-WorkflowScripts {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD '.github/workflows/ci.yml'), $enc)
  $lines = $text -split "`n"
  $inside = $false
  $out = @()
  foreach ($line in $lines) {
    if (-not $inside) {
      if ($line -match '^  gates:[ \t]*$') { $inside = $true }
      continue
    }
    if ($line -match '^  [A-Za-z0-9_-]+:[ \t]*$') { break }
    foreach ($m in [regex]::Matches($line, 'bash tools/([A-Za-z0-9_.-]+\.sh)')) { $out += $m.Groups[1].Value }
  }
  Sort-Set $out
}

# The number a document states next to a phrase. The document is flattened
# first, because a sentence the editor wrapped is one sentence to a reader
# and two to a matcher.
function Get-FlatNumber($text, $pattern) {
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) { return '' }
  $digits = [regex]::Match($m.Value, '[0-9]+')
  if (-not $digits.Success) { return '' }
  $digits.Value
}

# A number a document states, against the tree's.
function Test-StatedNumber($label, $actual, $stated, $document) {
  if ([string]::IsNullOrEmpty($stated)) {
    Write-Fail ("{0,-22} {1} does not state it" -f $label, $document)
    return
  }
  if ("$stated" -ne "$actual") {
    Write-Fail ("{0,-22} the tree has {1}, {2} says {3}" -f $label, $actual, $document, $stated)
    return
  }
  Write-Ok $label $actual
}

# The scripts the workflow runs have to be a subset of the scripts a ci.sh
# gate runs. A step the local run does not have is a check the reader
# believes they have.
function Test-WorkflowScripts($label, $subset, $superset) {
  $sub = Get-NonEmpty $subset
  $sup = Get-NonEmpty $superset
  $missing = @($sub | Where-Object { $sup -cnotcontains $_ })
  if ($missing.Count -eq 0) {
    Write-Ok $label $sub.Count
    return
  }
  Write-Fail ("{0,-22} the workflow runs [{1}], which ci.sh does not run" -f $label, ($missing -join ' '))
}

$ciGates = Get-CiGateCount
$ciScripts = @(Get-CiScripts)
$workflowScripts = @(Get-WorkflowScripts)
$ciFlat = (([System.IO.File]::ReadAllText((Join-Path $PWD 'ci.sh'), $enc)) -replace "`n", ' ') -replace ' +', ' '
$agentsFlat = (([System.IO.File]::ReadAllText((Join-Path $PWD 'AGENTS.md'), $enc)) -replace "`n", ' ') -replace ' +', ' '

# The mutations the three suites carry: one `name =` line each.
function Get-MutationCount($file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  ([regex]::Matches($text, '(?m)^[ \t]*name[ \t]*=')).Count
}

# The mutations in all three suites together. This is the number the guide
# says the batteries re-run the suites.
function Get-MutationTotal {
  $total = 0
  foreach ($suite in @('tools/mutate-backend.ps1', 'tools/mutate-frontend.ps1', 'tools/mutate-loop.ps1')) {
    $total += Get-MutationCount $suite
  }
  $total
}

$mutationTotal = Get-MutationTotal

# The tools the discovery document offers, as the guide spells the count out.
Test-WordCount 'agent guide tools' 'tools' $codeTools.Count $agentsDoc

Test-StatedNumber 'agent guide mutations' $mutationTotal `
  (Get-FlatNumber $agentsFlat 're-run the suites ([0-9]+) times') 'AGENTS.md'
# --- the pipeline and the batteries: how the project is built and verified ----
#
# The README is the package's front page, and the contributor's guide is
# AGENTS.md. The claims about the pipeline, the hook and the batteries
# belong to the contributor, so they live in the contributor's guide and the
# gate watches them there. A fact is watched in one place only, and the
# place moved with the claim.
#
# The job names come from the CI workflow. The COUNT is a count in words as
# well as a count in a list: a job that is renamed leaves the count right
# and the name wrong, and a reader watching the pipeline for "Build (js)" is
# watching for a job that is not there.

function Get-CodeJobNames {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD '.github/workflows/ci.yml'), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^jobs:') { $inside = $true; continue }
    if ($inside -and $line -match '^    name: (.+)$') { $out += $Matches[1] }
  }
  Sort-Set $out
}

function Get-DocJobNames {
  $out = @()
  $grab = 0
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentsDoc), $enc)
  foreach ($line in ($text -split "`r?`n")) {
    if ($grab -eq 0 -and $line -match 'jobs, all of which have to be green') { $grab = 2 }
    if ($grab -eq 0) { continue }
    foreach ($m in [regex]::Matches($line, '\*\*([^*]+)\*\*')) { $out += $m.Groups[1].Value }
    $grab--
  }
  Sort-Set $out
}

function Get-CodeJobCount {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD '.github/workflows/ci.yml'), $enc)
  $count = 0
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^jobs:') { $inside = $true; continue }
    if ($inside -and $line -match '^  [A-Za-z0-9_-]+:') { $count++ }
  }
  $count
}

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
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentsDoc), $enc)
  foreach ($m in [regex]::Matches($text, '\.githooks/([A-Za-z0-9_.-]+)')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

$jobCount = Get-CodeJobCount

Test-WordCount 'agent guide jobs' 'jobs' $jobCount $agentsDoc

Test-Sets 'CI jobs' (Get-CodeJobNames) (Get-DocJobNames)

# The hook the guide names, and the note beside it. A hook the guide does
# not mention is a hook a reader never finds.
Test-Sets 'Git hooks' (Get-TreeHooks) (Get-DocHooks)

# --- architecture/deployment.md: the topology a reader deploys ----------------
#
# The deployment document states the variables the server reads, with their
# defaults, and points at the lines of the server that read them. Both are
# claims about the tree: a default the document states and the code does not
# have is a setting that does something else, and a pointer past the end of
# the file is a pointer to nothing.
#
# The defaults are the ones the code gives, and they are the same defaults
# the note in the release archive gives, so the two documents and the code
# all have to agree.

# A number the document states next to a phrase. Every place the document
# states it has to state the same number, and it has to state it at least
# once: a phrase that is gone is a number nothing checks any more.
function Test-ClaimNumber($label, $pattern, $expected, $doc) {
  $text = ([System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)) -replace "`n", ' '
  $text = $text -replace ' +', ' '
  $stated = 0
  $bad = @()
  foreach ($m in [regex]::Matches($text, $pattern)) {
    $stated = 1
    $number = $m.Groups[1].Value
    if ("$number" -ne "$expected") { $bad += $number }
  }
  if ($bad.Count -gt 0) {
    Write-Fail ("{0,-22} the tree has {1}, the document says [{2}]" -f $label, $expected, ($bad -join ' '))
    return
  }
  if ($stated -eq 0) {
    Write-Fail ("{0,-22} the document does not state it" -f $label)
    return
  }
  Write-Ok $label $expected
}

$deployMd = 'architecture/deployment.md'

# The settings the deployment document states: the variable and the default
# in the first two columns of its table.
function Get-DocDeploySettings {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $deployMd), $enc)
  foreach ($m in [regex]::Matches($text, '\| `(MAKED_[A-Z_]+)` \| `([^`]+)` \|')) {
    $out += ("{0} {1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
  }
  Sort-Set $out
}

Test-Sets 'deployment settings' $codeSettings (Get-DocDeploySettings)

Test-References $deployMd

# --- architecture/system-model.md: the shape the system is drawn with -------
#
# The system model says how big the system is: how many domains it organises
# content around, and how many pages it serves. Both are counts, and both
# are the tree's.
#
# They are written in words, and a word is a count too. The match is
# case-insensitive, because a count at the start of a sentence is
# capitalised -- "Ten public pages" is the same claim as "ten public pages".

$systemModelMd = 'architecture/system-model.md'

# The ring's domains: the tuples ring_domains() names.
function Get-RingDomainCount {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/pages.mbt'), $enc)
  $m = [regex]::Match($text, '(?s)pub fn ring_domains\(\)[^{]*\{.*?\n\}')
  if (-not $m.Success) { return -1 }
  ([regex]::Matches($m.Value, '\("([a-z]+)",')).Count
}

$ringDomains = Get-RingDomainCount
$pageCount = Count-SeedPages

Test-WordCount 'system model domains' 'domains' $ringDomains $systemModelMd
Test-WordCount 'system model ring domains' 'ring domains' $ringDomains $systemModelMd
Test-WordCount 'system model pages' 'public pages' $pageCount $systemModelMd

# The two entry points the model's table names have to be there.
Test-Exists 'system model backend' 'cmd/server/main.mbt'
Test-Exists 'system model frontend' 'cmd/web/main.mbt'

# --- architecture/flows.md: the paths the requests take ----------------------
#
# The flow document traces what happens on the way in and out, and it counts
# as it goes: the routes the API builds, the pages the seed makes, the
# columns a page row has. All three are the tree's, and a flow that says
# "registers 37 routes" when the server registers thirty-eight is a flow a
# reader cannot follow.
#
# The pages are counted two ways, because there are two different numbers
# about them: seed_pages() returns the ring domains and the other three, and
# the server seeds those plus an index page and a not-found page. The count
# the flow document states is the count of the function.

$flowsMd = 'architecture/flows.md'

Test-ClaimNumber 'flow routes' 'registers ([0-9]+) routes' `
  (Count-Routes) $flowsMd
Test-ClaimNumber 'flow seed pages' 'seed_pages\(\)[^0-9]+([0-9]+) pages via UPSERT' `
  (Count-SeedPagesOnly) $flowsMd
Test-ClaimNumber 'flow page bodies' '\(([0-9]+) pages, hardcoded HTML bodies\)' `
  (Count-SeedPagesOnly) $flowsMd
Test-ClaimNumber 'flow page columns' 'bind\(([0-9]+) params\)' `
  (Count-PageColumns) $flowsMd

Test-StatedNumber 'ci.sh header gates' $ciGates `
  (Get-FlatNumber $ciFlat 'runs all ([0-9]+) of them') "ci.sh's header"
Test-StatedNumber 'agent guide gates' $ciGates `
  (Get-FlatNumber $agentsFlat 'holds ([0-9]+) gates') 'AGENTS.md'
Test-StatedNumber 'ci.sh header workflow' $workflowScripts.Count `
  (Get-FlatNumber $ciFlat 'runs the ([0-9]+) of them that a push is checked against') `
  "ci.sh's header"
Test-StatedNumber 'agent guide workflow' $workflowScripts.Count `
  (Get-FlatNumber $agentsFlat 'runs the ([0-9]+) that a push is checked against') `
  'AGENTS.md'

Test-WorkflowScripts 'workflow scripts' $workflowScripts $ciScripts

# --- architecture/*.dot: the graphs against the tree -------------------------
#
# The graphs are pictures of the tree, and a picture rots the way a document
# rots. The component graph kept the seven backend modules the project
# started with and still said four API endpoints when the server registers
# thirty-seven; the flow graph still said four routes in the step that builds
# the API.
#
# Two claims are checked. The MODULES are the tree's: the component graph
# names every module the project has, and every module it names is one the
# project has. The COUNT is the tree's: every graph that says how many routes
# the API builds says the number the server registers.
#
# The escapes are read before the names are taken. A label in a DOT file
# separates its lines with a backslash and an n, and that n is a letter: a
# name that follows an escape would be read as part of it. So the escapes
# become spaces first, and the names are read out of what is left.

$systemModelDot = 'architecture/system-model.dot'

# The modules the tree has, as package/module. A test file is not a module:
# the graph shows what the system is made of, not what it is checked with.
function Get-TreeModules {
  $out = @()
  foreach ($pkg in @('backend', 'frontend', 'cmd/server', 'cmd/web', 'cmd/mcp')) {
    foreach ($f in (Get-ChildItem (Join-Path $PWD $pkg) -Filter '*.mbt' -File)) {
      $name = $f.Name
      if ($name.EndsWith('_test.mbt') -or $name.EndsWith('_wbtest.mbt')) { continue }
      $out += ("{0}/{1}" -f $pkg, $name)
    }
  }
  Sort-Set $out
}

# The modules the component graph names, the same way. The escapes go first:
# a backslash and an n is two characters, and the n is a letter the next name
# would be read as part of.
function Get-GraphModules {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $systemModelDot), $enc)
  $flat = $text -replace '\\n', ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, '[A-Za-z0-9_]+(/[A-Za-z0-9_]+)*\.mbt')) {
    $out += $m.Value
  }
  Sort-Set $out
}

Test-Sets 'component graph modules' (Get-TreeModules) (Get-GraphModules)

# The graphs that describe the present. A graph that says it describes the
# past is history, and history keeps the numbers it had: the past is
# allowed to be the past.
function Get-CurrentGraphs {
  $out = @()
  [string[]]$files = @(Get-ChildItem (Join-Path $PWD 'architecture') -Filter '*.dot' -File |
    ForEach-Object { 'architecture/' + $_.Name })
  if ($files.Count -gt 1) {
    [Array]::Sort($files, [System.StringComparer]::Ordinal)
  }
  foreach ($file in $files) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
    if (-not $text.Contains('This document describes the past.')) { $out += $file }
  }
  $out
}

# The route counts the graphs state: the file, and the number it says.
function Get-GraphRouteClaims {
  $out = @()
  foreach ($f in (Get-CurrentGraphs)) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $f), $enc)
    foreach ($m in [regex]::Matches($text, '[0-9]+ (JSON endpoints|routes)')) {
      $out += ("{0} {1}" -f $f, $m.Value)
    }
  }
  $out
}

# Every graph that states a route count has to state the tree's.
function Test-GraphRoutes($claims, $actual) {
  $before = $script:failures
  $count = 0
  foreach ($claim in $claims) {
    if ($claim -eq '') { continue }
    $count++
    $parts = $claim -split ' '
    $file = $parts[0]
    $number = $parts[1]
    if ($number -cne $actual) {
      Write-Fail ("{0,-22} the tree has {1}, {2} says {3}" -f 'graph routes', $actual, $file, $number)
    }
  }
  if ($count -eq 0) {
    Write-Fail ("{0,-22} no graph states the route count" -f 'graph routes')
    return
  }
  if ($script:failures -eq $before) {
    Write-Ok 'graph routes' $actual
  }
}

Test-GraphRoutes (Get-GraphRouteClaims) ("$(Count-Routes)")

# --- architecture/dependencies.dot: the dependency graph against the tree ---
#
# The dependency graph says what depends on what. It was a picture of the
# project on the first day: seven backend modules, a frontend of four, no
# agent's server, and none of the packages the tree actually leans on -- not
# the model the whole loop runs on, not the regression it reports, not the
# protocol the agent speaks.
#
# Three claims are checked. The PACKAGES are the tree's: every package the
# tree has is named, and every package named is one the tree has. The
# IMPORTS are the tree's: every external import path the tree declares is
# named, and every path named is one the tree declares. The PINS are the
# tree's: every version the graph states is the version the manifest pins.
#
# A claim is read off the FIRST line of a label, because that is where the
# import path is written. The lines under it say what the package is for,
# and a line that happens to mention a path is a sentence, not a claim.

$dependenciesDot = 'architecture/dependencies.dot'

# The first line of every label in the graph.
function Get-GraphLabelHeads {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $dependenciesDot), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, 'label="([^"]*)"')) {
    $value = $m.Groups[1].Value
    $cut = $value.IndexOf('\n')
    if ($cut -ge 0) { $value = $value.Substring(0, $cut) }
    $out += $value
  }
  $out
}

# The packages the graph names: a first line that is a package name.
function Get-GraphPackages {
  $out = @()
  foreach ($head in (Get-GraphLabelHeads)) {
    if ($head -cmatch '^[a-z]+(/[a-z]+)?/$') { $out += $head }
  }
  Sort-Set $out
}

# The packages the tree has: the directories that hold a moon.pkg.
function Get-TreePackages {
  $out = @()
  foreach ($root in @('backend', 'frontend', 'cmd')) {
    foreach ($f in (Get-ChildItem (Join-Path $PWD $root) -Recurse -Filter 'moon.pkg' -File)) {
      $rel = $f.FullName.Substring($PWD.Path.Length + 1).Replace('\', '/')
      $dir = $rel.Substring(0, $rel.Length - '/moon.pkg'.Length)
      $out += ($dir + '/')
    }
  }
  Sort-Set $out
}

Test-Sets 'graph packages' (Get-TreePackages) (Get-GraphPackages)

# The external imports the graph names: a first line that is an import path.
function Get-GraphImports {
  $out = @()
  foreach ($head in (Get-GraphLabelHeads)) {
    if ($head -cmatch '^[A-Za-z][A-Za-z0-9_-]*(/[A-Za-z0-9_.-]+)+(@[0-9]+\.[0-9]+\.[0-9]+)?$') {
      $out += ($head -replace '@[0-9]+\.[0-9]+\.[0-9]+$', '')
    }
  }
  Sort-Set $out
}

# The import blocks of the manifests, without their comments.
function Get-ManifestBlocks {
  $out = @()
  foreach ($file in @('moon.mod', 'backend/moon.pkg', 'frontend/moon.pkg',
                      'cmd/server/moon.pkg', 'cmd/web/moon.pkg', 'cmd/mcp/moon.pkg')) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
    $text = [regex]::Replace($text, '(?m)^\s*//.*$', '')
    foreach ($m in [regex]::Matches($text, '(?s)import\s*\{(.*?)\}')) {
      $out += $m.Groups[1].Value
    }
  }
  $out
}

# The external imports the tree declares. The core packages and the
# project's own packages are left out: they are not dependencies on anything
# outside the tree.
function Get-TreeImports {
  $out = @()
  foreach ($block in (Get-ManifestBlocks)) {
    foreach ($p in [regex]::Matches($block, '"([A-Za-z][A-Za-z0-9_-]*/[A-Za-z0-9_./-]+(@[0-9][0-9.]*)?)"')) {
      $path = $p.Groups[1].Value
      if ($path -match '^moonbitlang/core/') { continue }
      if ($path -match '^riantr/MAKED(/|$)') { continue }
      $out += ($path -replace '@[0-9][0-9.]*$', '')
    }
  }
  Sort-Set $out
}

Test-Sets 'graph imports' (Get-TreeImports) (Get-GraphImports)

# The versions the graph states: name@version.
function Get-GraphPins {
  $out = @()
  foreach ($head in (Get-GraphLabelHeads)) {
    foreach ($m in [regex]::Matches($head, '[A-Za-z0-9_-]+@[0-9]+\.[0-9]+\.[0-9]+')) {
      $out += $m.Value
    }
  }
  Sort-Set $out
}

# The versions the manifests pin: the last segment of the path, and the
# version.
function Get-TreePins {
  $out = @()
  foreach ($block in (Get-ManifestBlocks)) {
    foreach ($p in [regex]::Matches($block, '"([A-Za-z][A-Za-z0-9_-]*/[A-Za-z0-9_./-]+)@([0-9][0-9.]*)"')) {
      $parts = $p.Groups[1].Value.Split('/')
      $out += ($parts[$parts.Length - 1] + '@' + $p.Groups[2].Value)
    }
  }
  Sort-Set $out
}

Test-Sets 'graph pins' (Get-TreePins) (Get-GraphPins)

# --- the graphs and the model: the API they promise, the settings they name ---
#
# The contract note in the dependency graph and the handler list in the
# deployment graph both say what the API looks like from the outside. Both
# had stopped saying /api/model, which the server has registered since the
# model became a file the reader brings.
#
# The deployment graph also names the variables the server reads, and the
# model DSL names a route and a number of domains. All three are the tree's.

$deployDot = 'architecture/deployment.dot'
$systemModelDsl = 'architecture/system-model.dsl'

# The API families the tree serves: the first two segments of every route.
function Get-TreeApiFamilies {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, 'app\.(get|post|put|delete|patch)\("(/api/[^"]+)"')) {
    $segments = $m.Groups[2].Value.Split('/')
    $out += ('/api/' + $segments[2])
  }
  Sort-Set $out
}

# The API families a graph names.
function Get-GraphApiFamilies($file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '/api/[a-z-]+')) {
    $out += $m.Value
  }
  Sort-Set $out
}

Test-Sets 'contract endpoints' (Get-TreeApiFamilies) (Get-GraphApiFamilies $dependenciesDot)
Test-Sets 'topology endpoints' (Get-TreeApiFamilies) (Get-GraphApiFamilies $deployDot)

# The variables the server reads.
function Get-CodeVariableNames {
  $out = @()
  foreach ($setting in $codeSettings) {
    $parts = $setting -split ' '
    if ($parts.Count -gt 0 -and $parts[0] -ne '') { $out += $parts[0] }
  }
  Sort-Set $out
}

# The variables the deployment graph names.
function Get-GraphVariables {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $deployDot), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, 'MAKED_[A-Z_]+')) {
    $out += $m.Value
  }
  Sort-Set $out
}

Test-Sets 'topology variables' (Get-CodeVariableNames) (Get-GraphVariables)

# Every route the server registers.
function Get-TreeRoutes {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  $flat = $text -replace "`r?`n", ' '
  $out = @()
  foreach ($m in [regex]::Matches($flat, 'app\.(get|post|put|delete|patch)\("(/api/[^"]+)"')) {
    $out += $m.Groups[2].Value
  }
  Sort-Set $out
}

# The routes the model names.
function Get-DslRoutes {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $systemModelDsl), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '/api/[A-Za-z0-9/:_.-]+')) {
    $out += $m.Value
  }
  Sort-Set $out
}

# Every route the model names has to be a route the server registers.
function Test-DslRoutes($named, $actual) {
  # The list is walked by hand, because a function that returns an empty
  # array hands its caller a null, and a null is not a route.
  $missing = @()
  $count = 0
  foreach ($route in @($named)) {
    if ($null -eq $route) { continue }
    if ($route -eq '') { continue }
    $count++
    if ($actual -cnotcontains $route) { $missing += $route }
  }
  if ($missing.Count -gt 0) {
    Write-Fail ("{0,-22} the model names [{1}], the server does not register them" -f 'dsl routes', ($missing -join ' '))
    return
  }
  Write-Ok 'dsl routes' $count
}

Test-DslRoutes (Get-DslRoutes) (Get-TreeRoutes)

# The number of domains the model states, in words. The model writes it as
# "Five-domain", so the word is the one in front of the hyphen.
function Get-DslDomainWords {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $systemModelDsl), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '(?i)\b(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)-domain')) {
    $word = $m.Groups[1].Value.ToLowerInvariant()
    if ($out -cnotcontains $word) { $out += $word }
  }
  Sort-Set $out
}

function Test-DslDomains($words, $expected) {
  if ($words.Count -eq 0) {
    Write-Fail ("{0,-22} the model does not state the count in words" -f 'dsl domains')
    return
  }
  $bad = @()
  foreach ($word in $words) {
    $number = ''
    if ($numberWords.ContainsKey($word)) { $number = $numberWords[$word] }
    if ($number -eq '' -or $number -ne "$expected") { $bad += $word }
  }
  if ($bad.Count -gt 0) {
    Write-Fail ("{0,-22} the model says [{1}], the tree has {2}" -f 'dsl domains', ($bad -join ' '), $expected)
    return
  }
  Write-Ok 'dsl domains' $expected
}

Test-DslDomains (Get-DslDomainWords) $ringDomains

# --- architecture/flows.dot: the flow graph traces what the server does -----
#
# The flow graph traces five paths through the server, and it counts as it
# goes: eight pages are seeded, and it names the routes it walks. Those are
# the tree's numbers, and the flow document beside it already says them --
# but the graph is a document too, and it was not being checked.
#
# The count checks skip the graphs that say they describe the past: history
# is allowed to be history, and only the present has to be right.

$flowsDot = 'architecture/flows.dot'

# The page counts a graph states.
function Get-GraphPageClaims($file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  $out = @()
  foreach ($m in [regex]::Matches($text, '[0-9]+ [Pp]ages?')) {
    $out += ([regex]::Match($m.Value, '[0-9]+')).Value
  }
  Sort-Set $out
}

# Every page count the graph states is the tree's count.
function Test-GraphPages($label, $file, $expected) {
  $claims = Get-GraphPageClaims $file
  $numbers = @()
  foreach ($number in @($claims)) {
    if ($null -eq $number) { continue }
    if ($number -eq '') { continue }
    $numbers += $number
  }
  if ($numbers.Count -eq 0) {
    Write-Fail ("{0,-22} the graph does not state the page count" -f $label)
    return
  }
  $bad = @()
  foreach ($number in $numbers) {
    if ($number -cne "$expected") { $bad += $number }
  }
  if ($bad.Count -gt 0) {
    Write-Fail ("{0,-22} the tree has {1}, the graph says [{2}]" -f $label, $expected, ($bad -join ' '))
    return
  }
  Write-Ok $label $expected
}

Test-GraphPages 'flow graph pages' $flowsDot (Count-SeedPagesOnly)

# Every family the flow graph names is a family the server serves.
function Test-GraphFamiliesLive($label, $named, $actual) {
  $missing = @()
  $count = 0
  foreach ($family in @($named)) {
    if ($null -eq $family) { continue }
    if ($family -eq '') { continue }
    $count++
    if ($actual -cnotcontains $family) { $missing += $family }
  }
  if ($missing.Count -gt 0) {
    Write-Fail ("{0,-22} the graph names [{1}], which the server does not serve" -f $label, ($missing -join ' '))
    return
  }
  Write-Ok $label $count
}

Test-GraphFamiliesLive 'flow graph endpoints' (Get-GraphApiFamilies $flowsDot) (Get-TreeApiFamilies)

# The component graph says in words how many public pages there are.
Test-WordCount 'component graph pages' 'public pages' $pageCount $systemModelDot

# --- models/product-iteration.yaml: the machine file states its own size -----
#
# The example machine says in its header how big it is: three domains, seven
# positions, four slots, twenty-eight rules. Those numbers were true when
# they were written, and nothing checked them, so the day the machine grew
# a slot the header would have kept saying four and the reader would have
# believed it.
#
# The numbers are now checked against the file they describe. The header
# says them in digits, because a header that a gate can read is a header
# that a gate can keep right.

$modelYaml = 'models/product-iteration.yaml'

# The number of entries in one section of the machine file. The sections are
# the top-level keys, and an entry is a line that starts with a dash.
function Get-ModelSectionCount($section) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $modelYaml), $enc)
  $count = 0
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^[a-z_]+:') {
      $inside = ($line -eq ($section + ':'))
      continue
    }
    if ($inside -and $line -match '^  - ') { $count++ }
  }
  $count
}

# The number the header states next to a phrase. The header is the comment
# at the top of the file, so only the comments are read.
function Get-ModelClaim($phrase) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $modelYaml), $enc)
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -notmatch '^\s*#') { continue }
    $m = [regex]::Match($line, '([0-9]+) ' + [regex]::Escape($phrase))
    if ($m.Success) { return $m.Groups[1].Value }
  }
  ''
}

function Test-ModelClaim($label, $phrase, $section) {
  Test-StatedNumber $label (Get-ModelSectionCount $section) (Get-ModelClaim $phrase) 'the machine file'
}

Test-ModelClaim 'model domains' 'domains' 'domains'
Test-ModelClaim 'model positions' 'positions' 'positions'
Test-ModelClaim 'model slots' 'slots' 'slots'
Test-ModelClaim 'model rules' 'rules' 'rules'
Test-ModelClaim 'model outcomes' 'outcomes' 'outcomes'

# The files the header names. A header that points at a file that is not
# there sends the reader to nothing, and the file it names is the machine's
# twin -- the one the header says is the same machine.
function Get-ModelNamedFiles {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $modelYaml), $enc)
  $out = @()
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -notmatch '^\s*#') { continue }
    foreach ($m in [regex]::Matches($line, '[A-Za-z0-9_.-]+/[A-Za-z0-9_./-]+\.[A-Za-z0-9]+')) {
      $out += $m.Value
    }
  }
  Sort-Set $out
}

function Test-ModelFiles($named) {
  # The list is walked by hand, because a function that returns an empty
  # array hands its caller a null, and a null counted as a file is a file
  # that is not there. The bash twin counts empty lines as nothing.
  $files = @()
  foreach ($file in @($named)) {
    if ($null -eq $file) { continue }
    if ($file -eq '') { continue }
    $files += $file
  }
  $missing = @()
  foreach ($file in $files) {
    if (-not (Test-Path (Join-Path $PWD $file))) { $missing += $file }
  }
  if ($missing.Count -gt 0) {
    Write-Fail ("{0,-22} the machine file names [{1}], which are not there" -f 'model files', ($missing -join ' '))
    return
  }
  Write-Ok 'model files' $files.Count
}

Test-ModelFiles (Get-ModelNamedFiles)

# --- research/product-iteration.yaml: the table says which machine it fits ---
#
# The mapping table says which machine it is for. Its header names the
# machine, the slots, and the built-in model it is NOT for -- and none of
# that was checked, so a table that had drifted away from its machine still
# looked right in the header.
#
# Four claims are checked:
#
#   - the files the header points at are there
#   - the slots the table's rules drive are the machine's slots
#   - the slots the header names are the machine's slots
#   - the built-in model's slots have other names
#
# The machine is the one the table's header names, and the machine file's
# own name says how it is read: a .yaml file is YAML and everything else is
# JSON. The built-in model's slots are MAKED's own names for pyroduct's
# slots, and they are read from the one function that maps them.

$researchTable = 'research/product-iteration.yaml'

# A list with the empties taken out. A function that returns nothing hands
# its caller a null, and a null that is counted as a member is a member
# that was never there. The comma keeps an empty list an empty list.
function Get-CleanList($items) {
  $out = @()
  foreach ($item in @($items)) {
    if ($null -eq $item) { continue }
    if ($item -eq '') { continue }
    $out += $item
  }
  ,$out
}

# A set, in ONE order: the ordinal one, which is the order the bytes are
# in. The bash twin sorts with LC_ALL=C, which is the same order, so the
# two twins print the same message when a set does not match -- and a
# message that differs between the twins is a message nobody can trust.
function Sort-ResearchSet($items) {
  [string[]]$out = @($items | Where-Object { $null -ne $_ -and $_ -ne '' })
  if ($out.Count -gt 1) {
    [Array]::Sort($out, [System.StringComparer]::Ordinal)
    $unique = @()
    foreach ($item in $out) {
      if ($unique.Count -eq 0 -or $unique[-1] -cne $item) { $unique += $item }
    }
    $out = $unique
  }
  ,$out
}

# The files the table's header points at: the machine it fits and the
# table itself. They are named the way a reader names them.
function Get-ResearchNamedFiles {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $researchTable), $enc)
  $out = @()
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -notmatch '^\s*#') { continue }
    foreach ($m in [regex]::Matches($line, 'MAKED_(?:MODEL|RESEARCH)=([A-Za-z0-9_./-]+)')) {
      $out += $m.Groups[1].Value
    }
  }
  Sort-ResearchSet $out
}

# The machine the table fits, as the header names it.
function Get-ResearchNamedModel {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $researchTable), $enc)
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -notmatch '^\s*#') { continue }
    $m = [regex]::Match($line, 'MAKED_MODEL=([A-Za-z0-9_./-]+)')
    if ($m.Success) { return $m.Groups[1].Value }
  }
  ''
}

# The slots the header names. The header lists them on one line, so the
# list is read from that line and split on the commas.
function Get-ResearchHeaderSlots {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $researchTable), $enc)
  $out = @()
  foreach ($line in ($text -split "`r?`n")) {
    $m = [regex]::Match($line, '^\s*#\s+slots:\s*(.*)$')
    if (-not $m.Success) { continue }
    foreach ($part in ($m.Groups[1].Value -split ',')) {
      $out += $part.Trim()
    }
  }
  Sort-ResearchSet $out
}

# The slots the table's rules drive. The fallback drives one too.
function Get-ResearchTableSlots {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $researchTable), $enc)
  $out = @()
  foreach ($line in ($text -split "`r?`n")) {
    $m = [regex]::Match($line, '^\s+slot:\s*([A-Za-z0-9_-]+)\s*$')
    if ($m.Success) { $out += $m.Groups[1].Value }
  }
  Sort-ResearchSet $out
}

# The slots a machine file defines. The file's name says how it is read.
function Get-MachineSlotIds($path) {
  if ($null -eq $path -or $path -eq '') { return ,([string[]]@()) }
  $full = Join-Path $PWD $path
  if (-not (Test-Path $full)) { return ,([string[]]@()) }
  if ($path -match '\.(yaml|yml)$') { return Get-MachineYamlSlotIds $path }
  return Get-MachineJsonSlotIds $path
}

# The slots a JSON machine file defines. The block is found by its key and
# ends at the bracket that closes it, and the indentation of the closing
# bracket says which one that is: a bracket inside a string would not do.
function Get-MachineJsonSlotIds($path) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $path), $enc)
  $out = @()
  $inside = $false
  $openIndent = 0
  foreach ($line in ($text -split "`r?`n")) {
    if (-not $inside) {
      $open = [regex]::Match($line, '^([ ]*)"slots"\s*:\s*\[')
      if ($open.Success) {
        $inside = $true
        $openIndent = $open.Groups[1].Value.Length
      }
      continue
    }
    $close = [regex]::Match($line, '^([ ]*)\],?[ ]*$')
    if ($close.Success) {
      if ($close.Groups[1].Value.Length -le $openIndent) { $inside = $false }
      continue
    }
    $id = [regex]::Match($line, '"id"\s*:\s*"([^"]+)"')
    if ($id.Success) { $out += $id.Groups[1].Value }
  }
  Sort-ResearchSet $out
}

# The slots a YAML machine file defines. The section runs from its key to
# the next key at the left margin.
function Get-MachineYamlSlotIds($path) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $path), $enc)
  $out = @()
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^slots:\s*$') { $inside = $true; continue }
    if ($inside -and $line -match '^[^\s#]') { $inside = $false }
    if ($inside) {
      $id = [regex]::Match($line, '^\s*-\s+id:\s*([A-Za-z0-9_-]+)\s*$')
      if ($id.Success) { $out += $id.Groups[1].Value }
    }
  }
  Sort-ResearchSet $out
}

# The built-in model's slots: MAKED's own names for pyroduct's slots, and
# they are written down in the one function that maps them.
function Get-BuiltinModelSlots {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/model.mbt'), $enc)
  $out = @()
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^pub fn slot_id_of') { $inside = $true; continue }
    if ($inside -and $line -match '^\}') { $inside = $false }
    if ($inside -and $line -match '=>') {
      $m = [regex]::Match($line, '"([^"]+)"')
      if ($m.Success) { $out += $m.Groups[1].Value }
    }
  }
  Sort-ResearchSet $out
}

# The members of one set that are also in the other. The comparison is by
# membership, so the order the two sets are written in says nothing.
function Get-InCommon($source, $other) {
  $s = Get-CleanList $source
  $o = Get-CleanList $other
  $out = @()
  foreach ($item in $s) {
    if ($o -ccontains $item) { $out += $item }
  }
  ,$out
}

# The files the header points at have to be there. A pointer to nothing
# sends the reader to nothing.
function Test-ResearchFiles($named) {
  $files = Get-CleanList $named
  $missing = @()
  foreach ($file in $files) {
    if (-not (Test-Path (Join-Path $PWD $file))) { $missing += $file }
  }
  if ($missing.Count -gt 0) {
    Write-Fail ("{0,-22} the table names [{1}], which are not there" -f 'research files', ($missing -join ' '))
    return
  }
  Write-Ok 'research files' $files.Count
}

$researchFiles = Get-ResearchNamedFiles
$researchModel = Get-ResearchNamedModel
$researchHeaderSlots = Get-ResearchHeaderSlots
$researchTableSlots = Get-ResearchTableSlots
$researchMachineSlots = Get-MachineSlotIds $researchModel
$builtinModelSlots = Get-BuiltinModelSlots

Test-ResearchFiles $researchFiles

# The slots the table drives are the machine's slots. The tree says the
# machine's slots; the table says the slots it drives.
Test-Sets 'research slots' $researchMachineSlots $researchTableSlots

# The slots the header names are the machine's slots too. The header is
# prose, and prose rots.
Test-Sets 'research header slots' $researchMachineSlots $researchHeaderSlots

# The table must not fit the built-in model either: the header says the
# built-in model's slots have other names, and this is where that is
# checked. A name the two models share is a name the header is wrong about.
$researchCommon = Get-InCommon $researchTableSlots $builtinModelSlots
if ($researchCommon.Count -eq 0) {
  Write-Ok 'research builtin slots' $builtinModelSlots.Count
} else {
  Write-Fail ("{0,-22} the table and the built-in model share [{1}]" -f 'research builtin slots', ($researchCommon -join ' '))
}

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
