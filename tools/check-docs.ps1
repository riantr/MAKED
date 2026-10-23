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
  $refs = [regex]::Matches($text, '`([A-Za-z0-9_./-]+\.(?:mbt|moon\.pkg|ps1|sh|mod|dsl|dot|md)|Dockerfile):(\d+)(?:-(\d+))?`')
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
    # The key is the reference AS WRITTEN, minus the backticks: a range stays
    # a range. The bash twin keys the same way, so the two check the same
    # references, skip the same repeats and say the same thing when one of
    # them points at nothing.
    $key = ($ref.Value -replace '`', '')
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

# --- the export formats the guide shows ----------------------------------------
#
# The guide shows the export URL an agent can call, and the format value in it
# has to be one the server answers. An export that asks for a format the
# handler does not know comes back as a 400 with "unknown_format".
#
# The tree is the handler, and the comparison is one way: the handler knows
# more formats than the guide shows.

function Get-CodeExportFormats {
  $out = @()
  $lines = [System.IO.File]::ReadAllLines((Join-Path $PWD 'backend/api.mbt'), $enc)
  $inside = $false
  foreach ($line in $lines) {
    if ($line -cmatch 'app\.get\("/api/sessions/:id/export"') { $inside = $true }
    if ($inside -and $line -ceq '  })') { break }
    if ($inside) {
      foreach ($m in [regex]::Matches($line, 'Some\("([a-z]+)"\)')) {
        $out += $m.Groups[1].Value
      }
    }
  }
  Sort-Set $out
}

function Get-DocExportFormats {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $agentDoc), $enc)
  foreach ($m in [regex]::Matches($text, 'format=([a-z]+)')) {
    $out += $m.Groups[1].Value
  }
  Sort-Set $out
}

$codeExportFormats = @(Get-CodeExportFormats)
$docExportFormats = @(Get-DocExportFormats)
$exportFormatsMissing = @($docExportFormats | Where-Object { $codeExportFormats -cnotcontains $_ })

if ($exportFormatsMissing.Count -eq 0) {
  Write-Ok 'agent export formats' $docExportFormats.Count
} else {
  Write-Fail ("{0,-22} the guide asks for [{1}], and the server does not answer it" -f 'agent export formats', ($exportFormatsMissing -join ' '))
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

# --- the paths the build writes, and the health check the image declares ------
#
# The deployment document says where the build puts its output, and it used to
# name a path the build never produces: the server is written under
# _build/native/release/build/cmd/server/, not under _build/native/release/cmd/.
#
# The tree is the scripts. They are the things that copy a file and run a
# file, so they are the things that name the paths -- and a path a script
# names is a path the build writes. The gate scripts are left out of the
# scan: they read the tree, they do not build from it, and a gate that named
# a path would be legitimising the very path it is here to catch.
#
# The comparison is one way. A document does not have to list every file the
# build writes, but every path it does list has to be one the tree writes.

function Get-TreeBuildOutputs {
  $out = @()
  $files = @()
  foreach ($root in @('build.ps1', 'Dockerfile')) {
    if (Test-Path $root) { $files += (Get-Item $root) }
  }
  foreach ($dir in @('tools', '.github')) {
    if (Test-Path $dir) {
      $files += @(Get-ChildItem -Path $dir -Recurse -File | Where-Object {
        $_.Name -notlike 'check-*.sh' -and $_.Name -notlike 'check-*.ps1'
      })
    }
  }
  foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    foreach ($m in [regex]::Matches($text, '_build/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*')) {
      $out += $m.Value
    }
  }
  Sort-Set $out
}

function Get-DocBuildOutputs {
  $out = @()
  foreach ($doc in @($deployMd, $deploy, $agentDoc, $agentsDoc)) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
    foreach ($m in [regex]::Matches($text, '_build/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*')) {
      $out += $m.Value
    }
  }
  Sort-Set $out
}

# Every path the document states has to be a path the tree builds.
function Test-BuildOutputs($label, $stated, $built) {
  $s = Get-NonEmpty $stated
  $b = Get-NonEmpty $built
  $missing = @($s | Where-Object { $b -cnotcontains $_ })
  if ($missing.Count -eq 0) {
    Write-Ok $label $s.Count
    return
  }
  Write-Fail ("{0,-22} the document states [{1}], and the tree builds no such path" -f $label, ($missing -join ' '))
}

Test-BuildOutputs 'Build outputs' (Get-DocBuildOutputs) (Get-TreeBuildOutputs)

# --- the health check the image declares -------------------------------------
#
# The deployment document listed "No health check endpoint" as a gap. The image
# declares one: the Dockerfile's HEALTHCHECK polls GET /api/status, and the
# server serves that route.
#
# The document's health claim is read from the sentences that talk about the
# health check and not from the whole document: a path named in an unrelated
# sentence is not the health check. The sentences are cut on the full stop, so
# a sentence that wraps across two lines is still one sentence.
#
# The absence claim is checked separately, because a document can state the
# right endpoint and still go on saying there is no way to monitor liveness.

function Get-CodeHealthPaths {
  $out = @()
  $lines = [System.IO.File]::ReadAllLines((Join-Path $PWD 'Dockerfile'), $enc)
  for ($i = 0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^HEALTHCHECK') {
      for ($j = $i; $j -lt ($i + 4) -and $j -lt $lines.Length; $j++) {
        foreach ($m in [regex]::Matches($lines[$j], 'https?://[^"\s]+')) {
          $out += ($m.Value -replace '^https?://[^/]+', '')
        }
      }
      break
    }
  }
  Sort-Set $out
}

function Get-DocHealthPaths {
  $out = @()
  $text = ([System.IO.File]::ReadAllText((Join-Path $PWD $deployMd), $enc)) -replace "`r?`n", ' '
  $text = $text -replace ' +', ' '
  foreach ($sentence in ($text -split '\. ')) {
    if ($sentence -notmatch '(?i)health') { continue }
    foreach ($m in [regex]::Matches($sentence, '/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)*')) {
      $out += ($m.Value -replace '\.+$', '')
    }
  }
  Sort-Set $out
}

# The endpoint the image health-checks has to be one the document states.
function Test-HealthPaths($label, $code, $doc) {
  $c = Get-NonEmpty $code
  $d = Get-NonEmpty $doc
  $missing = @($c | Where-Object { $d -cnotcontains $_ })
  if ($missing.Count -eq 0) {
    Write-Ok $label $c.Count
    return
  }
  Write-Fail ("{0,-22} the image health-checks [{1}], the document states [{2}]" -f $label, ($missing -join ' '), ($d -join ' '))
}

$codeHealthPaths = Get-CodeHealthPaths
$docHealthPaths = Get-DocHealthPaths

if ($codeHealthPaths.Count -eq 0) {
  Write-Fail ("{0,-22} the image declares no health check to compare the document with" -f 'Health check')
} else {
  Test-HealthPaths 'Health check' $codeHealthPaths $docHealthPaths
}

# The gaps table must not keep a row that denies a health check. The row is
# found by its own shape -- a table row whose first cell denies something and
# names the health check -- so a sentence about the health check elsewhere in
# the document is not read as one.
$deployText = [System.IO.File]::ReadAllText((Join-Path $PWD $deployMd), $enc)
$docHealthGaps = @($deployText -split "`r?`n" | Where-Object { $_ -match '(?i)^\|[^|]*\bno\b[^|]*health' }).Count

if ($docHealthGaps -eq 0) {
  Write-Ok 'Health check gap' $docHealthGaps
} else {
  Write-Fail ("{0,-22} the document lists {1} gap row(s) that deny a health check" -f 'Health check gap', $docHealthGaps)
}

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

# --- the packages the project has ---------------------------------------------
#
# The dependency documents say how many packages the project is made of, and
# the list they wrote down is the one the project started with: the agent's
# server (cmd/mcp) was added after they were written.
#
# The tree is the manifests. Every moon.pkg is a package, the module's own
# one included -- the documents count it, so the tree is counted the same way.
#
# The COUNT and the LIST are checked, and they are checked in each document
# separately: the count is what a reader takes away, and the list is what a
# reader reads to find a package.

function Get-TreeProjectPackages {
  $out = @()
  foreach ($root in @('backend', 'frontend', 'cmd')) {
    foreach ($f in (Get-ChildItem (Join-Path $PWD $root) -Recurse -Filter 'moon.pkg' -File)) {
      $rel = $f.FullName.Substring($PWD.Path.Length + 1).Replace('\', '/')
      $out += ($rel -replace '/moon\.pkg$', '')
    }
  }
  if (Test-Path (Join-Path $PWD 'moon.pkg')) { $out += 'root' }
  Sort-Set $out
}

# The list the evidence document states: the names after "project packages: ".
function Get-DocProjectPackages {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $evidence), $enc)
  foreach ($m in [regex]::Matches($text, 'project packages: ([^|]+)')) {
    foreach ($part in ($m.Groups[1].Value -split ',')) {
      $name = $part.Trim()
      if ($name -ne '') { $out += $name }
    }
  }
  Sort-Set $out
}

# The packages the dependency table names: the first cell of every row of the
# internal dependencies table.
function Get-DocDependencyPackages {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $depsMd), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^\|\s*Package\s*\|') { $inside = $true; continue }
    if (-not $inside) { continue }
    if ($line -notmatch '^\|') { break }
    $cell = ($line -replace '^\|\s*', '') -replace '\s*\|.*$', ''
    $cell = $cell -replace '`', ''
    $cell = $cell -replace '/$', ''
    if ($cell -ceq 'root moon.pkg') { $cell = 'root' }
    if ($cell -cmatch '^[a-z]+(/[a-z]+)?$') { $out += $cell }
  }
  Sort-Set $out
}

$treeProjectPackages = Get-TreeProjectPackages
$treeProjectPackageCount = @($treeProjectPackages).Count

Test-WordCount 'dependency package count' 'packages' $treeProjectPackageCount $depsMd
Test-WordCount 'project package count' 'project packages' $treeProjectPackageCount $evidence

Test-Sets 'dependency package list' $treeProjectPackages (Get-DocDependencyPackages)
Test-Sets 'project package list' $treeProjectPackages (Get-DocProjectPackages)

# --- the edges inside the project ----------------------------------------------
#
# The dependency document says which package depends on which, in three
# places: the diagram, the internal dependencies table, and the coupling
# assessment. The tree says it too, in the manifests: a package that imports
# another one of the project's packages depends on it.
#
# The tree's edge is a pair of package names, and each of the three places is
# read into that shape, because the three do not spell it the same way.
#
# Every place is read. A document that says the right thing in the table and
# the wrong thing in the diagram has a wrong diagram.

function Get-TreeInternalEdges {
  $out = @()
  foreach ($root in @('backend', 'frontend', 'cmd')) {
    foreach ($f in (Get-ChildItem (Join-Path $PWD $root) -Recurse -Filter 'moon.pkg' -File)) {
      $pkg = $f.FullName.Substring($PWD.Path.Length + 1).Replace('\', '/')
      $pkg = $pkg -replace '/moon\.pkg$', ''
      $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
      foreach ($m in [regex]::Matches($text, '"riantr/MAKED/([a-z]+(?:/[a-z]+)?)"')) {
        $out += ("{0} {1}" -f $pkg, $m.Groups[1].Value)
      }
    }
  }
  Sort-Set $out
}

# The edges the internal dependencies table states: the package in the first
# cell and the package it depends on in the second.
function Get-DocTableEdges {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $depsMd), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^\|\s*Package\s*\|') { $inside = $true; continue }
    if (-not $inside) { continue }
    if ($line -notmatch '^\|') { break }
    $cells = ($line -replace '^\|\s*', '') -split '\|'
    $first = ($cells[0] -replace '`', '').Trim() -replace '/$', ''
    if ($first -ceq 'root moon.pkg') { $first = 'root' }
    $second = ($cells[1] -replace '`', '').Trim()
    if ($first -cmatch '^[a-z]+(/[a-z]+)?$' -and $second -cmatch '^[a-z]+(/[a-z]+)?$') {
      $out += ("{0} {1}" -f $first, $second)
    }
  }
  Sort-Set $out
}

# The edges the diagram states: a line inside a fenced block that starts with
# a package name and names the package it depends on after the arrow. The
# fence is what keeps the prose out: a sentence that starts with a word and
# carries two more words looks exactly like an edge to a pattern.
function Get-DocDiagramEdges {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $depsMd), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -ceq '```') { $inside = -not $inside; continue }
    if (-not $inside) { continue }
    $m = [regex]::Match($line, '^[a-z]+(/[a-z]+)? +[^ ]+ +[a-z]+(/[a-z]+)?')
    if ($m.Success) {
      $out += ($m.Value -replace ' +[^ ]+ +', ' ')
    }
  }
  Sort-Set $out
}

$treeInternalEdges = @(Get-TreeInternalEdges)

Test-Sets 'package dependencies' $treeInternalEdges (Get-DocTableEdges)
Test-Sets 'dependency diagram' $treeInternalEdges (Get-DocDiagramEdges)

# --- the logo's tests ----------------------------------------------------------
#
# The blast radius of the mark says how many tests pin it. It said six, and
# there are four: the test blocks that name node_xy, node_percent or nodes.
# A count that is wrong here is a count that sends a reader looking for six
# tests and finding four.
#
# The tests are counted as BLOCKS, not as assertions and not as lines: a block
# starts at a test declaration and ends at the brace that closes it. The
# file's own header names the same three functions, so a reader that counted
# by name alone would count the comment as well.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

function Get-TreeLogoTests {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'frontend/frontend_test.mbt'), $enc)
  $count = 0
  $inside = $false
  $body = ''
  foreach ($line in ($text -split "`n")) {
    if (-not $inside) {
      if ($line.StartsWith('test "')) { $inside = $true; $body = $line }
      continue
    }
    $body = $body + "`n" + $line
    if ($line -ceq '}') {
      if ($body -cmatch 'node_xy|node_percent|nodes\(\)') { $count = $count + 1 }
      $inside = $false
      $body = ''
    }
  }
  $count
}

$treeLogoTests = Get-TreeLogoTests

Test-ClaimNumber 'logo tests' 'node_xy, node_percent, nodes tests \(([0-9]+) tests\)' `
  $treeLogoTests $depsMd

# --- the ring's geometry --------------------------------------------------------
#
# The evidence document states the ring's geometry in one cell: how many nodes
# the ring has, how far the ring reaches, and how big the square the mark is
# drawn in. All three are the tree's -- the logo file holds them as
# constants, and the test file pins them as literals -- and a reader who took
# the numbers and drew the mark would draw a different one.
#
# The viewBox is written the way a viewBox is written, "200x200", so the
# tree's single VIEW constant is what both halves of that have to be.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The nodes the mark draws: the tuples in nodes().
function Get-TreeLogoNodes {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'frontend/logo.mbt'), $enc)
  ([regex]::Matches($text, '(?m)^\s*\("[A-Z]", "#[0-9a-fA-F]+"')).Count
}

# The value of a constant in the logo file.
function Get-TreeLogoConst($name) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'frontend/logo.mbt'), $enc)
  $m = [regex]::Match($text, "const $name : Int32 = ([0-9]+)")
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

$treeLogoNodes = Get-TreeLogoNodes
$treeLogoRadius = Get-TreeLogoConst 'RING_R'
$treeLogoView = Get-TreeLogoConst 'VIEW'

Test-ClaimNumber 'logo nodes' '([0-9]+) nodes clockwise from top' `
  $treeLogoNodes $evidence
Test-ClaimNumber 'ring radius' 'radius ([0-9]+), viewBox' `
  $treeLogoRadius $evidence
Test-ClaimNumber 'logo viewBox' 'viewBox ([0-9]+x[0-9]+)' `
  ("{0}x{0}" -f $treeLogoView) $evidence

# --- the keys the page carries ------------------------------------------------
#
# The change impact table says which key the backend writes and which key the
# frontend reads, one row per key, and those two columns are the contract
# between the two halves of the project: a key the backend stopped writing is
# a field the frontend silently reads as its fallback, and a key the frontend
# stopped reading is a field nobody sees.
#
# The tree is the contract. The backend's keys are the ones Page::to_json
# writes, and the frontend's keys are the ones page_from_json reads. The
# document has to state the same two sets, because the table is where a
# reader looks to see what a change to the page shape will move.
#
# The two columns are read separately, because they are two claims: the
# backend's keys and the frontend's keys are the same set today, and a
# document that says so in one column and not in the other is wrong in one of
# them.

# The lines of a function body: from the line that starts it to the line that
# closes the value it returns. The closing line is the one indented by two
# spaces, which is where the block the keys live in ends.
function Get-FunctionLines($path, $startPattern) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $path), $enc)
  $out = @()
  $inside = $false
  foreach ($line in ($text -split "`n")) {
    if ($line -match $startPattern) { $inside = $true }
    if (-not $inside) { continue }
    if ($line -match '^  \}') { break }
    $out += $line
  }
  $out
}

# The keys the backend writes: the ones Page::to_json puts in the JSON.
function Get-TreePageJsonKeys {
  $out = @()
  foreach ($line in (Get-FunctionLines 'backend/pages.mbt' 'pub fn Page::to_json')) {
    foreach ($m in [regex]::Matches($line, '"([a-z_]+)":')) {
      $out += $m.Groups[1].Value
    }
  }
  Sort-Set $out
}

# The keys the frontend reads: the ones page_from_json asks the JSON for.
function Get-TreePageDecoderKeys {
  $out = @()
  foreach ($line in (Get-FunctionLines 'frontend/page.mbt' 'fn page_from_json')) {
    foreach ($m in [regex]::Matches($line, 'get_(?:string|bool|int)\(json, "([a-z_]+)"')) {
      $out += $m.Groups[1].Value
    }
  }
  Sort-Set $out
}

# The keys the change impact table says the backend writes: the second cell
# of every row of that table.
function Get-DocPageJsonKeys {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $deps), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^\|\s*Backend function\s*\|') { $inside = $true; continue }
    if (-not $inside) { continue }
    if ($line -notmatch '^\|') { break }
    $cells = ($line -replace '^\|\s*', '') -split '\|'
    $cell = ($cells[1] -replace '[\s"`]', '')
    if ($cell -cmatch '^[a-z_]+$') { $out += $cell }
  }
  Sort-Set $out
}

# The keys the same table says the frontend reads: the quoted key inside the
# consumer in the third cell.
function Get-DocPageDecoderKeys {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $deps), $enc)
  $inside = $false
  foreach ($line in ($text -split "`r?`n")) {
    if ($line -match '^\|\s*Backend function\s*\|') { $inside = $true; continue }
    if (-not $inside) { continue }
    if ($line -notmatch '^\|') { break }
    $cells = ($line -replace '^\|\s*', '') -split '\|'
    $m = [regex]::Match([string]$cells[2], '"([a-z_]+)"')
    if ($m.Success) { $out += $m.Groups[1].Value }
  }
  Sort-Set $out
}

$treePageJsonKeys = @(Get-TreePageJsonKeys)
$treePageDecoderKeys = @(Get-TreePageDecoderKeys)

Test-Sets 'page json keys' $treePageJsonKeys (Get-DocPageJsonKeys)
Test-Sets 'page decoder keys' $treePageDecoderKeys (Get-DocPageDecoderKeys)

# --- the order the chain runs in ----------------------------------------------
#
# A request to the server meets three things before it reaches a handler: the
# static file middleware, the SPA fallback middleware and the route module.
# The order they meet is not the order they are written in. moonback appends
# every middleware to one list, chains that list in declaration order with the
# first registered outermost, and hands the router to the chain as the
# handler -- so the chain runs
#
#   static_files -> spa_fallback -> routes
#
# while the code registers them the other way round: the routes first, then
# the two middlewares. The documents had the registration order and called it
# the runtime order, which sent a reader looking for the router before the
# static files -- the opposite of what happens.
#
# The rule was read from moonback 0.8.9: module.mbt appends each middleware to
# the app's list, middleware.mbt chains that list in declaration order and
# compose() puts the current middleware in front, and app.mbt gives the chain
# the router as the handler. The pin is watched, so a different moonback
# cannot change the answer without the rule being read again.

$chainRuleMoonback = '0.8.9'
$chainFlows = 'architecture/flows.md'

# The parts of the chain, in the order the tree runs them.
#
# The registrations are read in the order the file writes them. A middleware
# registered with add_middleware is one of the chain, in the order it was
# registered; the module registered with use_ is the route module, and the
# router is the last thing a request meets. The word used for each is the
# tree's: the function it was built from, when the file builds it from one.
function Get-TreeChainOrder {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'cmd/server/main.mbt'), $enc)
  $middlewares = @()
  $route = ''
  foreach ($line in ($text -split "`n")) {
    $m = [regex]::Match($line, 'ctx\.(use_|add_middleware)\(([a-z_]+)\)')
    if (-not $m.Success) { continue }
    $name = $m.Groups[2].Value
    $built = [regex]::Match($text, "let $name = @[A-Za-z_.]+\.([a-z_]+)\(")
    $word = if ($built.Success) { $built.Groups[1].Value } else { $name }
    if ($m.Groups[1].Value -ceq 'use_') { $route = $word } else { $middlewares += $word }
  }
  $parts = @()
  $parts += $middlewares
  if ($route -ne '') { $parts += $route }
  $parts -join ' '
}

# The version of moonback the project pins.
function Get-MoonbackPin {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'moon.mod'), $enc)
  $m = [regex]::Match($text, '"moonbitlang/moonback@([^"]+)"')
  if ($m.Success) { $m.Groups[1].Value } else { '' }
}

# The parts a text names, in the order the text names them.
#
# Each part is placed where the text first says it, and the parts are then
# read in that order. A text that names them in the wrong order comes out in
# the wrong order, and a text that says one part twice keeps it where it
# first said it.
function Get-DocChainOrder($text, $parts) {
  $found = @()
  foreach ($name in ($parts -split ' ')) {
    if ($name -eq '') { continue }
    $pos = $text.IndexOf($name)
    if ($pos -ge 0) { $found += [PSCustomObject]@{ Pos = $pos; Name = $name } }
  }
  $names = @($found | Sort-Object -Property Pos | ForEach-Object { $_.Name })
  $names -join ' '
}

# The chain the flow document traces: the numbered list under the line that
# says the chain runs outermost first.
#
# The list is the run of items numbered 1, 2, 3 in a row. The next list in the
# document starts at 1 again, so the run ends where the numbering stops
# counting up -- which is how the reader knows it has read one list and not
# two.
function Get-DocFlowChain {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $chainFlows), $enc)
  $out = @()
  $inside = $false
  $want = 1
  foreach ($line in ($text -split "`n")) {
    if (-not $inside) {
      if ($line.Contains('moonback middleware chain (outermost first)')) { $inside = $true }
      continue
    }
    $m = [regex]::Match($line, '^\s+([0-9]+)\.')
    if ($m.Success) {
      $num = [int]$m.Groups[1].Value
      if ($num -ne $want) { break }
      $want = $want + 1
      $out += $line
      continue
    }
    if ($line -match '^\s') { continue }
    break
  }
  $out -join "`n"
}

# Every place that states the order must state the tree's order.
#
# A table cell that names every part of the chain states the order they run
# in, so it has to state the tree's. The flow document says it in a list
# rather than a table, so that list is read as well.
function Test-ChainOrder($label, $expected, $docs) {
  $bad = $false
  foreach ($doc in $docs) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
    foreach ($line in ($text -split "`r?`n")) {
      if (-not $line.StartsWith('|')) { continue }
      $cell = $line.Substring(1)
      $bar = $cell.IndexOf('|')
      if ($bar -ge 0) { $cell = $cell.Substring(0, $bar) }
      $all = $true
      foreach ($name in ($expected -split ' ')) {
        if ($name -eq '') { continue }
        if (-not $cell.Contains($name)) { $all = $false }
      }
      if (-not $all) { continue }
      $order = Get-DocChainOrder $cell $expected
      if ($order -cne $expected) {
        Write-Fail ("{0,-22} {1} states [{2}], the tree runs [{3}]" -f $label, (Split-Path -Leaf $doc), $order, $expected)
        $bad = $true
      }
    }
  }
  $order = Get-DocChainOrder (Get-DocFlowChain) $expected
  if ($order -cne $expected) {
    Write-Fail ("{0,-22} {1} states [{2}], the tree runs [{3}]" -f $label, (Split-Path -Leaf $chainFlows), $order, $expected)
    $bad = $true
  }
  if (-not $bad) { Write-Ok $label $expected }
}

$treeChainOrder = Get-TreeChainOrder
$chainMoonbackPin = Get-MoonbackPin

if ($chainMoonbackPin -ceq $chainRuleMoonback) {
  Write-Ok 'chain rule' ("moonback {0}" -f $chainMoonbackPin)
} else {
  Write-Fail ("{0,-22} the chain rule was read from moonback {1} and moon.mod now pins {2} -- read the rule again" -f 'chain rule', $chainRuleMoonback, $chainMoonbackPin)
}

Test-ChainOrder 'middleware order' $treeChainOrder @($evidence, 'architecture/flows.evidence.md', $deploy)

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

# --- the keys the bootstrap carries -------------------------------------------
#
# The server writes four keys into the body of GET /api/bootstrap, and the
# flow document shows that body to the reader. It showed three of them and
# called the last one "session", which is not a key at all, and left out
# entry_domains -- so a reader planning a change to the payload was planning
# it against a shape the server never sends.
#
# The place is found by its own shape: a line that shows a JSON object
# literal -- a brace, a quoted name with a colon, a closing brace -- and that
# names more than one of the tree's keys. The client asking for a page names
# one key and is not the payload; the list of SQLite columns names two and
# shows no literal.

# The keys the server writes into the bootstrap body.
function Get-TreeBootstrapKeys {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  $inRoute = $false
  $inside = $false
  $names = @()
  foreach ($line in ($text -split "`n")) {
    if ($line -match 'app\.get\("/api/bootstrap"') { $inRoute = $true }
    if ($inRoute -and $line -match 'let body : Json = \{') { $inside = $true }
    if ($inside -and $line -match '^\s*\}$') { break }
    if ($inside) {
      foreach ($m in [regex]::Matches($line, '"([a-z_]+)":')) {
        $names += $m.Groups[1].Value
      }
    }
  }
  (Sort-Set $names) -join ' '
}

# The keys a place states: the quoted names that carry a colon, which is the
# shape a JSON object literal has.
function Get-DocBootstrapKeys($text) {
  $names = @()
  foreach ($m in [regex]::Matches($text, '"([a-z_]+)":')) {
    $names += $m.Groups[1].Value
  }
  (Sort-Set $names) -join ' '
}

# Every place that states the payload must state the tree's keys, and a
# document that stops stating the payload altogether is a document that has
# lost the claim.
function Test-BootstrapKeys($label, $expected, $docs) {
  $bad = $false
  foreach ($doc in $docs) {
    $text = [System.IO.File]::ReadAllText((Join-Path $PWD $doc), $enc)
    $found = $false
    foreach ($line in ($text -split "`r?`n")) {
      # the shape: a JSON object literal
      if ($line -notmatch '\{.*"[a-z_]+":.*\}') { continue }
      # and more than one of the tree's keys
      $count = 0
      foreach ($name in ($expected -split ' ')) {
        if ($name -eq '') { continue }
        if ($line.Contains($name)) { $count = $count + 1 }
      }
      if ($count -lt 2) { continue }
      $found = $true
      $names = Get-DocBootstrapKeys $line
      $missing = @()
      $extra = @()
      foreach ($name in ($expected -split ' ')) {
        if ($name -eq '') { continue }
        if (" $names " -cnotlike "* $name *") { $missing += $name }
      }
      foreach ($name in ($names -split ' ')) {
        if ($name -eq '') { continue }
        if (" $expected " -cnotlike "* $name *") { $extra += $name }
      }
      if ($missing.Count -gt 0 -or $extra.Count -gt 0) {
        Write-Fail ("{0,-22} {1} states [{2}], the tree writes [{3}]" -f $label, (Split-Path -Leaf $doc), $names, $expected)
        $bad = $true
      }
    }
    if (-not $found) {
      Write-Fail ("{0,-22} {1} does not state the bootstrap payload" -f $label, (Split-Path -Leaf $doc))
      $bad = $true
    }
  }
  if (-not $bad) { Write-Ok $label $expected }
}

$treeBootstrapKeys = Get-TreeBootstrapKeys

Test-BootstrapKeys 'bootstrap keys' $treeBootstrapKeys @($flowsMd, 'architecture/flows.evidence.md')

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

# --- the log ------------------------------------------------------------------
#
# The request log is the one line the logging middleware writes after the
# handler returns. The tree writes it with eprintln, and eprintln writes to
# stderr; println writes to stdout. A document that says the log goes to
# stdout sends the reader to a stream the server never writes to.
#
# Four facts come out of the tree:
#
#   $logStream      the stream the request log goes to
#   $logPrintLine   the line the request log is written on
#   $logAddLine     the line the app adds the middleware on
#   $logDefLine     the line the middleware is defined on
#
# The documents are checked against all four. The stream is checked in every
# claim that names one. The line is checked in every row that cites the file
# the log is written in.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:logStream = ''
$script:logPrintLine = 0
$script:logAddLine = 0
$script:logDefLine = 0
$script:logBadStream = $false
$script:logBadSite = $false

function Get-TreeLogLines {
  $path = Join-Path $PWD 'backend/maked_app.mbt'
  $lines = [System.IO.File]::ReadAllLines($path, $enc)
  $stream = ''; $print = 0; $add = 0; $def = 0
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    $n = $i + 1
    if ($add -eq 0 -and $l.Contains('add_middleware(logging_middleware())')) { $add = $n }
    if ($def -eq 0 -and $l.Contains('fn logging_middleware()')) { $def = $n }
    if ($print -eq 0 -and $l.Contains('req.verb()')) {
      if ($l.Contains('eprintln(')) { $stream = 'stderr'; $print = $n }
      elseif ($l.Contains('println(')) { $stream = 'stdout'; $print = $n }
    }
  }
  @{ stream = $stream; print = $print; add = $add; def = $def }
}

# The design documents: every markdown file and every graph.
[string[]]$archDocs = @(
  Get-ChildItem -Path (Join-Path $PWD 'architecture') -File |
    Where-Object { $_.Extension -eq '.md' -or $_.Extension -eq '.dot' } |
    ForEach-Object { 'architecture/' + $_.Name }
)
[Array]::Sort($archDocs, [System.StringComparer]::Ordinal)

# The claims a document makes.
#
# A claim is a paragraph: the run of lines a reader reads as one sentence. A
# table row is a claim of its own, because a table says one thing per row. A
# graph says one thing per line, because a graph has no paragraphs.
function Get-DocClaims($path) {
  $lines = [System.IO.File]::ReadAllLines((Join-Path $PWD $path), $enc)
  $isDot = $path.EndsWith('.dot')
  $claims = @()
  $claim = ''
  $claimLine = 0
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    $n = $i + 1
    if ($isDot) {
      $claims += ,@{ line = $n; text = $l }
      continue
    }
    if ($l.StartsWith('|')) {
      if ($claim -ne '') { $claims += ,@{ line = $claimLine; text = $claim }; $claim = '' }
      $claims += ,@{ line = $n; text = $l }
      $claimLine = $n
      continue
    }
    if ($l.Trim() -eq '') {
      if ($claim -ne '') { $claims += ,@{ line = $claimLine; text = $claim }; $claim = '' }
      continue
    }
    if ($claim -ne '') { $claim = $claim + ' ' + $l } else { $claim = $l; $claimLine = $n }
  }
  if ($claim -ne '') { $claims += ,@{ line = $claimLine; text = $claim } }
  $claims
}

# The stream a claim names, if it names one.
#
# The tree's words for the log are the call that writes it (eprintln, or
# println) and the streams those calls write to (stderr, or stdout). A claim
# that names one of them names the stream the log goes to. eprintln writes to
# stderr, so it is taken out before the streams are read.
#
# A claim that names BOTH streams is a claim that tells them apart, and it is
# left alone: a sentence about the start-up banner on stdout and the request
# log on stderr is two true things.
function Get-ClaimStream($claim) {
  if ($claim -cnotmatch 'stdout|stderr|println') { return '' }
  $rest = $claim.Replace('eprintln', '')
  $out = ($rest -cmatch 'stdout') -or ($rest -cmatch 'println')
  $err = ($claim -cmatch 'stderr') -or ($claim -cmatch 'eprintln')
  if ($out -and -not $err) { return 'stdout' }
  if ($err -and -not $out) { return 'stderr' }
  ''
}

# The numbers a row cites, and whether one of them is the line asked for.
#
# A citation is a line, a range of lines, or a few of both: "65", "11-29",
# "16, 61". A row that cites the file the log is written in has to cite the
# line the log is written on.
function Test-CitationCovers($text, $target) {
  foreach ($m in [regex]::Matches($text, '([0-9]+)(?:-([0-9]+))?')) {
    $a = [int]$m.Groups[1].Value
    $b = $a
    if ($m.Groups[2].Success) { $b = [int]$m.Groups[2].Value }
    if ($a -le $target -and $target -le $b) { return $true }
  }
  $false
}

# One claim, checked against the tree.
function Test-LogClaim($doc, $line, $claim) {
  # the stream the claim names
  $stated = Get-ClaimStream $claim
  if ($stated -ne '' -and $stated -ne $script:logStream) {
    Write-Fail ("{0,-22} {1} line {2} says the log goes to {3}, the tree writes it to {4}" -f 'log stream', $doc, $line, $stated, $script:logStream)
    $script:logBadStream = $true
  }

  # the line the claim points at: only a table row carries a citation
  if (-not $claim.StartsWith('|')) { return }
  if ($claim -cnotmatch 'backend/maked_app\.mbt:') { return }
  $cited = $claim -replace '^.*backend/maked_app\.mbt:', ''
  $cited = ($cited -split '`')[0]
  $cited = ($cited -split '\|')[0]
  $cited = $cited.Replace(' ', '')

  # the claim states where the log is written
  if ($claim -imatch 'print') {
    if (-not (Test-CitationCovers $cited $script:logPrintLine)) {
      Write-Fail ("{0,-22} {1} line {2} cites [{3}], the tree writes the request log on line {4}" -f 'log site', $doc, $line, $cited, $script:logPrintLine)
      $script:logBadSite = $true
    }
  }

  # the claim states where the middleware lives: the line the app adds it on,
  # the line it is defined on, or the line it writes the log on
  if ($claim -imatch 'logging[ _]middleware') {
    $covers = (Test-CitationCovers $cited $script:logAddLine) -or
              (Test-CitationCovers $cited $script:logDefLine) -or
              (Test-CitationCovers $cited $script:logPrintLine)
    if (-not $covers) {
      Write-Fail ("{0,-22} {1} line {2} cites [{3}], the tree has the middleware on lines {4}, {5} and {6}" -f 'log site', $doc, $line, $cited, $script:logAddLine, $script:logDefLine, $script:logPrintLine)
      $script:logBadSite = $true
    }
  }
}

$logFacts = Get-TreeLogLines
$script:logStream = $logFacts.stream
$script:logPrintLine = $logFacts.print
$script:logAddLine = $logFacts.add
$script:logDefLine = $logFacts.def

if ($script:logStream -eq '' -or $script:logPrintLine -eq 0) {
  Write-Fail ("{0,-22} the tree does not write a request log, or it does not write it the way this gate reads it" -f 'log stream')
  $script:logBadStream = $true
  $script:logBadSite = $true
} else {
  foreach ($doc in $archDocs) {
    # A document that describes the past is a record of the past. Its claims
    # are about the tree as it was, so they are not checked against the tree
    # as it is.
    if ($markedDocs -ccontains $doc) { continue }
    foreach ($claim in (Get-DocClaims $doc)) {
      Test-LogClaim $doc $claim.line $claim.text
    }
  }
}

if (-not $script:logBadStream) { Write-Ok 'log stream' $script:logStream }
if (-not $script:logBadSite) { Write-Ok 'log site' ("maked_app.mbt:{0}" -f $script:logPrintLine) }

# --- the environment variables -------------------------------------------------
#
# The server reads four environment variables, and it reads all four in one
# file: cmd/server/main.mbt. A row that points at that file and names the
# variables is stating the set the server reads, and a partial set is a set
# that is wrong: a reader who sets MAKED_PORT and MAKED_DB because the
# document listed them is left guessing about MAKED_HOST.
#
# The names come out of the tree. An env_or call names the variable it reads.
#
# The shorthand MAKED_PORT/HOST/DB/DIST is expanded into the four names it
# stands for, so a row that uses it is read like any other.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:envVars = @()
$script:envBadVars = $false
$script:envBadSite = $false

function Get-TreeEnvVars {
  $path = Join-Path $PWD 'cmd/server/main.mbt'
  $lines = [System.IO.File]::ReadAllLines($path, $enc)
  $out = @()
  foreach ($l in $lines) {
    if ($l.Contains('env_or("')) {
      $rest = $l.Substring($l.IndexOf('env_or("') + 8)
      $name = $rest.Substring(0, $rest.IndexOf('"'))
      $out += $name
    }
  }
  $out
}

# The lines the tree mentions a variable on.
#
# A variable is mentioned where it is read, and where the server talks about
# it -- the warning it prints when the host is not the default, for one. A row
# that points at the file has to point at a line the variable is on.
function Get-EnvVarMentions($name) {
  $path = Join-Path $PWD 'cmd/server/main.mbt'
  $lines = [System.IO.File]::ReadAllLines($path, $enc)
  $out = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Contains($name)) { $out += ($i + 1) }
  }
  $out
}

# The environment variables a claim names.
#
# The names are the tree's: MAKED_ and then capitals. A shorthand list --
# MAKED_PORT/HOST/DB/DIST -- is expanded into the names it stands for, one
# name at a time, because the prefix carries over.
function Get-ClaimVars($claim) {
  $out = @()
  $text = $claim
  while ($true) {
    $m = [regex]::Match($text, 'MAKED_[A-Z_]+')
    if (-not $m.Success) { break }
    $name = $m.Value
    $out += $name
    $text = $text.Substring($m.Index + $m.Length)
    while ($text.StartsWith('/')) {
      $text = $text.Substring(1)
      $w = [regex]::Match($text, '^[A-Z_]+')
      if (-not $w.Success) { break }
      $out += ('MAKED_' + $w.Value)
      $text = $text.Substring($w.Length)
    }
  }
  $out
}

# One claim, checked against the tree.
function Test-EnvClaim($doc, $line, $claim) {
  $cites = $false
  if ($claim.Contains('cmd/server/main.mbt:')) { $cites = $true }
  elseif (-not $claim.Contains('env_or')) { return }

  $vars = @(Get-ClaimVars $claim)
  $serverVars = @()
  $otherVars = @()
  foreach ($v in $vars) {
    if ($script:envVars -ccontains $v) { $serverVars += $v } else { $otherVars += $v }
  }

  # a claim that points at the server's file must not name a variable the
  # server does not read
  if ($cites -and $otherVars.Count -gt 0) {
    Write-Fail ("{0,-22} {1} line {2} names [{3}], and the server does not read them" -f 'env vars', $doc, $line, ($otherVars -join ' '))
    $script:envBadVars = $true
  }

  # a claim that names two or more of them is stating the set
  if ($serverVars.Count -ge 2 -and $serverVars.Count -ne $script:envVars.Count) {
    Write-Fail ("{0,-22} {1} line {2} names [{3}], the server reads [{4}]" -f 'env vars', $doc, $line, ($serverVars -join ' '), ($script:envVars -join ' '))
    $script:envBadVars = $true
  }

  # the claim has to point at a line the variable is on
  if (-not $cites) { return }
  $cited = $claim -replace '^.*cmd/server/main\.mbt:', ''
  $cited = ($cited -split '`')[0]
  $cited = ($cited -split '\|')[0]
  $cited = $cited.Replace(' ', '')

  foreach ($v in $serverVars) {
    $mentions = @(Get-EnvVarMentions $v)
    $covered = $false
    foreach ($target in $mentions) {
      if (Test-CitationCovers $cited $target) { $covered = $true; break }
    }
    if (-not $covered) {
      Write-Fail ("{0,-22} {1} line {2} cites [{3}], the tree mentions {4} on lines {5}" -f 'env var site', $doc, $line, $cited, $v, ($mentions -join ' '))
      $script:envBadSite = $true
    }
  }
}

$script:envVars = @(Get-TreeEnvVars)
if ($script:envVars.Count -eq 0) {
  Write-Fail ("{0,-22} the tree does not read any environment variable, or it does not read them the way this gate reads them" -f 'env vars')
  $script:envBadVars = $true
  $script:envBadSite = $true
} else {
  foreach ($doc in $archDocs) {
    # A document that describes the past is a record of the past. Its claims
    # are about the tree as it was, so they are not checked against the tree
    # as it is.
    if ($markedDocs -ccontains $doc) { continue }
    foreach ($claim in (Get-DocClaims $doc)) {
      Test-EnvClaim $doc $claim.line $claim.text
    }
  }
}

if (-not $script:envBadVars) { Write-Ok 'env vars' ($script:envVars -join ' ') }
if (-not $script:envBadSite) { Write-Ok 'env var site' 'cmd/server/main.mbt' }

# --- who stages the browser bundle ---------------------------------------------
#
# The browser bundle is one file: frontend/dist/main.js. The tree stages it in
# three places -- the build script, the CI workflow and the image -- and a
# document that says one of them is the only one sends a contributor to a
# place where the bundle is not, and states a fact about the build that is
# wrong.
#
# The tree's answer is read from the tree's build scripts: a file that copies
# the bundle the tree builds (web.js) to the path the server serves. The
# release workflow copies the bundle into the release archive instead, and
# that path is a longer one, so it is not one of them.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:stageFiles = @()
$script:stageNames = @()
$script:stageCandidates = @()
$script:stageBad = $false

function Get-TreeStageFiles {
  $files = @()
  foreach ($root in @('build.ps1', 'Dockerfile', 'tools', '.github')) {
    $path = Join-Path $PWD $root
    if (-not (Test-Path $path)) { continue }
    $item = Get-Item $path
    if ($item.PSIsContainer) {
      $files += @(Get-ChildItem -Path $path -File -Recurse |
        Where-Object { $_.Name -notlike 'check-*.sh' -and $_.Name -notlike 'check-*.ps1' })
    } else {
      $files += $item
    }
  }
  $out = @()
  $candidates = @()
  foreach ($f in $files) {
    $text = [System.IO.File]::ReadAllText($f.FullName, $enc)
    if ($text -notmatch 'web\.js') { continue }
    $rel = $f.FullName.Substring($PWD.Path.Length + 1).Replace('\', '/')
    $candidates += $rel.Split('/')[-1]
    if ($text -notmatch '[^A-Za-z0-9_/]frontend/dist/main\.js') { continue }
    $out += $rel
  }
  $script:stageCandidates = @(Sort-Set $candidates)
  Sort-Set $out
}

# The staging files a claim names.
#
# A document names a file by its name: "ci.yml", not the whole path. The
# names are read from the candidates -- every build file that knows about the
# bundle -- so that a document naming a place the tree does not stage it is
# caught as well as one naming too few.
function Get-ClaimStageFiles($claim) {
  $out = @()
  foreach ($base in $script:stageCandidates) {
    if ($claim.Contains($base)) { $out += $base }
  }
  $out
}

# One claim, checked against the tree.
function Test-StageClaim($doc, $line, $claim) {
  # the claim has to be about the place the bundle is staged
  if (-not $claim.Contains('frontend/dist/main.js')) { return }
  $named = @(Get-ClaimStageFiles $claim)
  if ($named.Count -eq 0) { return }
  # a claim that names one of them is naming the places, and it has to name
  # all of them
  if ($named.Count -ne $script:stageFiles.Count) {
    Write-Fail ("{0,-22} {1} line {2} names [{3}], the tree stages the bundle in [{4}]" -f 'bundle staging', $doc, $line, ($named -join ' '), ($script:stageNames -join ' '))
    $script:stageBad = $true
  }
}

$script:stageFiles = @(Get-TreeStageFiles)
$script:stageNames = @(Sort-Set @($script:stageFiles | ForEach-Object { $_.Split('/')[-1] }))

if ($script:stageFiles.Count -eq 0) {
  Write-Fail ("{0,-22} the tree does not stage the browser bundle, or it does not stage it the way this gate reads it" -f 'bundle staging')
  $script:stageBad = $true
} else {
  foreach ($doc in @($archDocs + $agentsDoc)) {
    # A document that describes the past is a record of the past. Its claims
    # are about the tree as it was, so they are not checked against the tree
    # as it is.
    if ($markedDocs -ccontains $doc) { continue }
    foreach ($claim in (Get-DocClaims $doc)) {
      Test-StageClaim $doc $claim.line $claim.text
    }
  }
}

if (-not $script:stageBad) { Write-Ok 'bundle staging' ($script:stageNames -join ' ') }

# --- the node colours ---------------------------------------------------------
#
# The mark draws five nodes, and the tree names the colour each one keeps in
# the logo file's own comment: the sentence that starts "Each node keeps the
# colour" and ends at the first full stop. The colours are a human gloss --
# the tree pins the hexes, not the words -- so the words are read out of the
# tree and compared with the words the documents use.
#
# A claim is a colour claim when it talks about colours at all. A claim that
# does not is left alone: "A page is served" is not a claim about the colour
# of a node, and reading it as one would be reading a word as a thing.
#
# A claim that names two or more of the colours is stating the list, and the
# list has to be the tree's list: one colour too few leaves a reader guessing
# what the last node looks like. A claim that names one of them is stating
# that one, and it only has to be true.
#
# A claim that points at the logo file has to point at a line the tree names
# the colours on.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:codeLetters = @()
$script:codeColorPairs = @()
$script:codeNodeColors = ''
$script:codeColorWords = @()
$script:codeColorLines = @()
$script:colorBadWords = $false
$script:colorBadSite = $false

# A claim that talks about colours says so in so many words.
$colorTrigger = '([^A-Za-z0-9_])(colou?rs?)([^A-Za-z0-9_]|$)'

function Get-TreeNodeColors {
  $path = Join-Path $PWD 'frontend/logo.mbt'
  $text = [System.IO.File]::ReadAllText($path, $enc)
  $letters = @()
  foreach ($m in [regex]::Matches($text, '\("([A-Z])",')) { $letters += $m.Groups[1].Value }
  if ($letters.Count -eq 0) { return }
  $script:codeLetters = $letters
  $flat = $text -replace "\r?\n", ' '
  $sm = [regex]::Match($flat, 'Each node keeps the colour[^.]*\.')
  if (-not $sm.Success) { return }
  $class = '[' + ($letters -join '') + ']'
  $re = '([^A-Za-z0-9_])(' + $class + ') ([a-z]+)'
  $pairs = @()
  foreach ($m in [regex]::Matches(' ' + $sm.Value, $re)) {
    $pairs += ($m.Groups[2].Value + ' ' + $m.Groups[3].Value)
  }
  if ($pairs.Count -eq 0) { return }
  $script:codeColorPairs = $pairs
  $script:codeNodeColors = ($pairs -join ' ')
  $words = @()
  foreach ($pair in $pairs) { $words += $pair.Split(' ')[1] }
  $script:codeColorWords = $words
  $lines = [System.IO.File]::ReadAllLines($path, $enc)
  $out = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    foreach ($pair in $pairs) {
      if ($lines[$i].Contains($pair)) { $out += ($i + 1); break }
    }
  }
  $script:codeColorLines = $out
}

# The colours a claim states.
function Get-ClaimColors($claim) {
  $out = @()
  if ($script:codeLetters.Count -eq 0) { return $out }
  $class = '[' + ($script:codeLetters -join '') + ']'
  $re = '([^A-Za-z0-9_])(' + $class + ') ([a-z]+)'
  foreach ($m in [regex]::Matches(' ' + $claim, $re)) {
    $out += ($m.Groups[2].Value + ' ' + $m.Groups[3].Value)
  }
  $out
}

# One claim, checked against the tree.
function Test-ColorClaim($doc, $line, $claim) {
  # the claim has to be about the colours at all
  if ((' ' + $claim) -notmatch $colorTrigger) { return }
  $pairs = @(Get-ClaimColors $claim)
  if ($pairs.Count -eq 0) { return }
  # every colour the claim states has to be one the tree states
  $wrong = @($pairs | Where-Object { $script:codeColorPairs -cnotcontains $_ })
  if ($wrong.Count -gt 0) {
    Write-Fail ("{0,-22} {1} line {2} states [{3}], the tree says [{4}]" -f 'node colors', $doc, $line, ($wrong -join ' '), $script:codeNodeColors)
    $script:colorBadWords = $true
    return
  }
  # a claim that names two or more of them is stating the list, and the list
  # has to be the whole list
  if ($pairs.Count -ge 2 -and $pairs.Count -ne $script:codeColorPairs.Count) {
    Write-Fail ("{0,-22} {1} line {2} states [{3}], the tree says [{4}]" -f 'node colors', $doc, $line, ($pairs -join ' '), $script:codeNodeColors)
    $script:colorBadWords = $true
    return
  }
  # and the pointer has to land on a line the tree names the colours on
  if (-not $claim.Contains('frontend/logo.mbt:')) { return }
  $cited = $claim -replace '^.*frontend/logo\.mbt:', ''
  $cited = ($cited -split '`')[0]
  $cited = ($cited -split '\|')[0]
  $cited = $cited.Replace(' ', '')

  foreach ($target in $script:codeColorLines) {
    if (-not (Test-CitationCovers $cited $target)) {
      Write-Fail ("{0,-22} {1} line {2} cites [{3}], the tree names the colours on lines {4}" -f 'node color site', $doc, $line, $cited, ($script:codeColorLines -join ' '))
      $script:colorBadSite = $true
      return
    }
  }
}

Get-TreeNodeColors

if ($script:codeNodeColors -eq '') {
  Write-Fail ("{0,-22} the tree does not name the node colours, or it does not name them the way this gate reads them" -f 'node colors')
  $script:colorBadWords = $true
  $script:colorBadSite = $true
} else {
  foreach ($doc in @($archDocs + $agentsDoc)) {
    # A document that describes the past is a record of the past. Its claims
    # are about the tree as it was, so they are not checked against the tree
    # as it is.
    if ($markedDocs -ccontains $doc) { continue }
    foreach ($claim in (Get-DocClaims $doc)) {
      Test-ColorClaim $doc $claim.line $claim.text
    }
  }
}

if (-not $script:colorBadWords) { Write-Ok 'node colors' $script:codeNodeColors }
if (-not $script:colorBadSite) { Write-Ok 'node color site' ('logo.mbt:' + ($script:codeColorLines -join ' ')) }

# --- the pointers reach the code they name -------------------------------------
#
# A row that cites a file and names a function of that file is pointing at
# that function. A citation that lands outside it points at something else,
# and the reader who follows it lands in the wrong place -- usually at a
# neighbour that looks close enough to be believed.
#
# A function's block runs from the line that defines it to the line before the
# next definition, because that is the range a reader thinks of as "the
# function". A row that names more than one function of the file is about the
# relationship between them, and the pointer may be to either, so such a row
# is left alone.
#
# The history fallback is the one name the tree says NOT to use, and it says
# so in a comment. A document that says the same has to point at that
# comment.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:pointerBad = $false
$script:fallbackBad = $false
$script:pointerChecked = 0

# The definitions of the file being read.
$script:defFile = ''
$script:defLines = @()
$script:defNames = @()
$script:defCount = 0
$script:defStart = 0
$script:defEnd = 0

# The source a claim cites: the file and the lines it cites.
$script:citeFile = ''
$script:citeSpec = ''
$script:citeText = ''
$citeRe = '`([A-Za-z0-9_./-]+\.mbt):([0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)`'

# The lines the tree mentions the history fallback on.
$script:historyLines = @()

function Get-FileDefinitions($file) {
  if ($script:defFile -ceq $file) { return }
  $script:defFile = $file
  $script:defLines = @()
  $script:defNames = @()
  $lines = [System.IO.File]::ReadAllLines((Join-Path $PWD $file), $enc)
  $script:defCount = $lines.Count
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $l = $lines[$i]
    if ($l -notmatch '^\s*(pub(\([a-z]+\))?\s+)?(async\s+)?fn\s+([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?)') { continue }
    $script:defLines += ($i + 1)
    $script:defNames += $Matches[4]
  }
}

# The block a function occupies.
function Get-FunctionRange($name) {
  $script:defStart = 0
  $script:defEnd = 0
  for ($i = 0; $i -lt $script:defNames.Count; $i++) {
    if ($script:defNames[$i] -ceq $name) {
      $script:defStart = $script:defLines[$i]
      if ($i + 1 -lt $script:defNames.Count) {
        $script:defEnd = $script:defLines[$i + 1] - 1
      } else {
        $script:defEnd = $script:defCount
      }
      return
    }
  }
}

function Get-CitedSource($claim) {
  $script:citeFile = ''
  $script:citeSpec = ''
  $script:citeText = ''
  $m = [regex]::Match($claim, $citeRe)
  if (-not $m.Success) { return }
  $script:citeFile = $m.Groups[1].Value
  $script:citeSpec = $m.Groups[2].Value
  $script:citeText = $claim.Replace($m.Value, '')
}

# The words a claim is made of.
#
# A name that carries a dot is one name: "main.js" is a file, and the
# function "main" is not it.
function Get-ClaimTokens($text) {
  $out = @()
  foreach ($m in [regex]::Matches($text, '[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?(\.[A-Za-z_][A-Za-z0-9_]*)*')) { $out += $m.Value }
  $out
}

function Get-HistoryLines {
  $path = Join-Path $PWD 'backend/maked_app.mbt'
  $lines = [System.IO.File]::ReadAllLines($path, $enc)
  $out = @()
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Contains('history_fallback')) { $out += ($i + 1) }
  }
  $script:historyLines = $out
}

# One claim, checked against the tree.
function Test-PointerClaim($doc, $line, $claim) {
  Get-CitedSource $claim
  if ($script:citeFile -eq '') { return }
  if (-not (Test-Path (Join-Path $PWD $script:citeFile))) { return }
  $script:pointerChecked++
  $tokens = @(Get-ClaimTokens $script:citeText)
  Get-FileDefinitions $script:citeFile
  # the functions of that file the claim names
  $count = 0
  $named = ''
  foreach ($fn in $script:defNames) {
    if ($tokens -ccontains $fn) { $count++; $named = $fn }
  }
  # the claim that says the history fallback is not used points at that note
  if ($tokens -ccontains 'history_fallback') {
    Get-HistoryLines
    $covered = $false
    foreach ($target in $script:historyLines) {
      if (Test-CitationCovers $script:citeSpec $target) { $covered = $true; break }
    }
    if (-not $covered) {
      Write-Fail ("{0,-22} {1} line {2} cites [{3}:{4}], but the tree says it on lines {5}" -f 'fallback site', $doc, $line, $script:citeFile, $script:citeSpec, ($script:historyLines -join ' '))
      $script:fallbackBad = $true
    }
  }
  # a claim that names one function of the file has to point inside it
  if ($count -ne 1) { return }
  Get-FunctionRange $named
  if ($script:defStart -le 0) { return }
  $covered = $false
  foreach ($part in ($script:citeSpec -split ',')) {
    $p = $part.Trim()
    if ($p -match '^([0-9]+)-([0-9]+)$') { $a = [int]$Matches[1]; $b = [int]$Matches[2] }
    else { $a = [int]$p; $b = $a }
    if ($a -le $script:defEnd -and $script:defStart -le $b) { $covered = $true; break }
  }
  if (-not $covered) {
    Write-Fail ("{0,-22} {1} line {2} cites [{3}:{4}], but {5} is on lines {6}-{7}" -f 'code pointer', $doc, $line, $script:citeFile, $script:citeSpec, $named, $script:defStart, $script:defEnd)
    $script:pointerBad = $true
  }
}

Get-HistoryLines

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-PointerClaim $doc $claim.line $claim.text
  }
}

if (-not $script:pointerBad) { Write-Ok 'code pointer' ("{0} pointers" -f $script:pointerChecked) }
if (-not $script:fallbackBad) { Write-Ok 'fallback site' ('maked_app.mbt:' + ($script:historyLines -join ' ')) }

# --- the names the tree has ----------------------------------------------------
#
# A document that puts a name in backticks is telling the reader where to
# look: "the body is inserted with `Attrs::inner_html`" points into the code,
# and a reader who searches the tree for it has to find it. A name the tree
# does not have is a name nobody can follow, and it is usually a name that
# was renamed or removed and the document never heard.
#
# The names are the tree's own: every tracked file that is not a document. A
# document is not part of the vocabulary, because a name that only the
# documents use is exactly the name that is not in the code. The gates
# themselves are not part of it either: a name a gate mentions is not a name
# the tree has.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:treeNames = $null
$script:treeNameCount = 0
$script:codeNamesBad = $false

# A name in the tree: a word, with an optional type qualifier.
$nameRe = '([A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?)'
# The name a piece of backticked text starts with.
$nameFirstRe = '^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)?'
# A piece of backticked text.
$tickRe = '`([^`]+)`'

function Get-TreeNames {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($rel in @(& git ls-files 2>$null)) {
    if ($rel -eq '') { continue }
    if ($rel.StartsWith('architecture/')) { continue }
    if ($rel -ceq 'README.md' -or $rel -ceq 'AGENTS.md' -or $rel -ceq 'AGENT.md') { continue }
    if ($rel.EndsWith('.md') -or $rel.EndsWith('.dot')) { continue }
    if ($rel -ceq 'tools/check-docs.sh' -or $rel -ceq 'tools/check-docs.ps1') { continue }
    $full = Join-Path $PWD $rel
    if (-not (Test-Path $full)) { continue }
    try { $text = [System.IO.File]::ReadAllText($full, $enc) } catch { continue }
    foreach ($m in [regex]::Matches($text, $nameRe)) { $null = $set.Add($m.Value) }
  }
  $script:treeNames = $set
  $script:treeNameCount = $set.Count
}

# One claim, checked against the names the tree has.
function Test-NameClaim($doc, $line, $claim) {
  Get-CitedSource $claim
  if ($script:citeFile -eq '') { return }
  foreach ($m in [regex]::Matches($script:citeText, $tickRe)) {
    $tick = $m.Groups[1].Value.Trim()
    $nm = [regex]::Match($tick, $nameFirstRe)
    if (-not $nm.Success) { continue }
    $name = $nm.Value
    if (-not $script:treeNames.Contains($name)) {
      Write-Fail ("{0,-22} {1} line {2} names [{3}], and the tree has no such name" -f 'code names', $doc, $line, $name)
      $script:codeNamesBad = $true
    }
  }
}

Get-TreeNames

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-NameClaim $doc $claim.line $claim.text
  }
}

if (-not $script:codeNamesBad) { Write-Ok 'code names' ("{0} names" -f $script:treeNameCount) }

# --- the defaults the variables fall back to ----------------------------------
#
# A variable the server reads has a default, and the default is the tree's:
# env_or("MAKED_PORT", "8080") pins the name and the value together. A
# document that says "MAKED_PORT (default 8080)" is stating that value, and a
# document that says 8081 is sending a reader to a port the server will not
# listen on.
#
# The default a claim states is the one that follows the variable: the text
# between a variable and the next variable is the text about that variable.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:envDefaults = @()
$script:envDefaultBad = $false

function Get-TreeEnvDefaults {
  $path = Join-Path $PWD 'cmd/server/main.mbt'
  $lines = [System.IO.File]::ReadAllLines($path, $enc)
  $out = @()
  foreach ($l in $lines) {
    if (-not $l.Contains('env_or("')) { continue }
    $rest = $l.Substring($l.IndexOf('env_or("') + 8)
    $name = $rest.Substring(0, $rest.IndexOf('"'))
    $rest = $rest.Substring($rest.IndexOf('"') + 1)
    if (-not $rest.Contains(', "')) { continue }
    $rest = $rest.Substring($rest.IndexOf(', "') + 3)
    $value = $rest.Substring(0, $rest.IndexOf('"'))
    $out += ($name + '=' + $value)
  }
  $out
}

# The default a claim states after a variable.
function Get-DefaultAfter($claim, $var) {
  $idx = $claim.IndexOf($var)
  if ($idx -lt 0) { return '' }
  $rest = $claim.Substring($idx + $var.Length)
  $next = $rest.IndexOf('MAKED_')
  if ($next -ge 0) { $rest = $rest.Substring(0, $next) }
  $m = [regex]::Match($rest, 'default\s+([^\s),]+)')
  if (-not $m.Success) { return '' }
  $m.Groups[1].Value
}

# One claim, checked against the defaults the tree pins.
function Test-EnvDefaultClaim($doc, $line, $claim) {
  foreach ($var in @(Get-ClaimVars $claim)) {
    $stated = Get-DefaultAfter $claim $var
    if ($stated -eq '') { continue }
    $tree = ''
    foreach ($pair in $script:envDefaults) {
      if ($pair.Substring(0, $pair.IndexOf('=')) -ceq $var) {
        $tree = $pair.Substring($pair.IndexOf('=') + 1)
        break
      }
    }
    if ($tree -eq '') { continue }
    if ($stated -cne $tree) {
      Write-Fail ("{0,-22} {1} line {2} says {3} falls back to [{4}], the tree falls back to [{5}]" -f 'env default', $doc, $line, $var, $stated, $tree)
      $script:envDefaultBad = $true
    }
  }
}

$script:envDefaults = @(Get-TreeEnvDefaults)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-EnvDefaultClaim $doc $claim.line $claim.text
  }
}

if (-not $script:envDefaultBad) { Write-Ok 'env default' ($script:envDefaults -join ' ') }

# --- the calls the tree makes ---------------------------------------------------
#
# A claim that names a call the tree makes -- "@fs.read_file" -- is pointing
# at that call, and a pointer that lands on another line points at something
# else. The call has to be on a line the citation reaches.
#
# A claim that says a package has no HTTP client code is making a promise
# about that package's network behaviour, and the tree has to keep it: the
# package's own source has to have no client call in it.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:callBad = $false
$script:httpBad = $false
$script:callChecked = 0
$script:codePkgs = @()

function Get-TreePackages {
  $out = @()
  foreach ($rel in @(& git ls-files 2>$null)) {
    if (-not ($rel -match '(^|/)moon\.pkg$')) { continue }
    if ($rel -ceq 'moon.pkg') { continue }
    $out += ($rel -replace '/moon\.pkg$', '')
  }
  $out
}

# The lines the cited file makes a call on.
function Get-CallLines($file, $call) {
  $out = @()
  if (-not (Test-Path $file)) { return $out }
  $lines = [System.IO.File]::ReadAllLines($file, $enc)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i].Contains($call)) { $out += ($i + 1) }
  }
  $out
}

# The client calls a package makes, in the package's own source.
function Get-PackageClientCalls($pkg) {
  $out = @()
  foreach ($file in @(Get-ChildItem -Path (Join-Path $PWD $pkg) -Filter '*.mbt' -File -ErrorAction SilentlyContinue)) {
    if ($file.Name.EndsWith('_test.mbt')) { continue }
    $text = [System.IO.File]::ReadAllText($file.FullName, $enc)
    if ($text -match '@http\.(get|post|put|delete|head|patch)\(') {
      $out += ($file.FullName.Substring($PWD.Path.Length + 1).Replace('\', '/'))
    }
  }
  $out
}

# One claim, checked against the calls the tree makes.
function Test-CallClaim($doc, $line, $claim) {
  Get-CitedSource $claim
  if ($script:citeFile -eq '') { return }
  $file = Join-Path $PWD $script:citeFile
  if (-not (Test-Path $file)) { return }
  foreach ($m in [regex]::Matches($script:citeText, $tickRe)) {
    $tick = $m.Groups[1].Value.Trim()
    if (-not $tick.StartsWith('@')) { continue }
    $call = ($tick -split '\(')[0]
    $call = ($call -split ' ')[0]
    $script:callChecked++
    $hits = @(Get-CallLines $file $call)
    if ($hits.Count -eq 0) {
      Write-Fail ("{0,-22} {1} line {2} names [{3}], and {4} never says it" -f 'call site', $doc, $line, $call, $script:citeFile)
      $script:callBad = $true
      continue
    }
    $covered = $false
    foreach ($target in $hits) {
      if (Test-CitationCovers $script:citeSpec $target) { $covered = $true; break }
    }
    if (-not $covered) {
      Write-Fail ("{0,-22} {1} line {2} cites [{3}:{4}], but [{5}] is on lines {6}" -f 'call site', $doc, $line, $script:citeFile, $script:citeSpec, $call, ($hits -join ' '))
      $script:callBad = $true
    }
  }
}

# One claim, checked against the client calls the packages make.
function Test-HttpClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  if ($lower -cnotmatch 'no http client') { return }
  $rest = $lower.Substring($lower.IndexOf('no http client') + 14)
  $pkg = ''
  foreach ($word in ($rest -split '\s+')) {
    $w = ($word -replace '[.,;)\]]+$', '')
    if ($script:codePkgs -ccontains $w) { $pkg = $w; break }
  }
  if ($pkg -eq '') { return }
  $calls = @(Get-PackageClientCalls $pkg)
  if ($calls.Count -gt 0) {
    Write-Fail ("{0,-22} {1} line {2} says {3} has no HTTP client code, but {4} calls one" -f 'http client', $doc, $line, $pkg, ($calls -join ' '))
    $script:httpBad = $true
  }
}

$script:codePkgs = @(Get-TreePackages)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-CallClaim $doc $claim.line $claim.text
    Test-HttpClaim $doc $claim.line $claim.text
  }
}

if (-not $script:callBad) { Write-Ok 'call site' ("{0} calls" -f $script:callChecked) }
if (-not $script:httpBad) { Write-Ok 'http client' ($script:codePkgs -join ' ') }

# --- the targets a package supports ---------------------------------------------
#
# A claim that says a package is "<target>-only" is making a promise about the
# platforms that package runs on, and the package's own moon.pkg says which
# platforms those are. The two have to agree: a document that says the frontend
# is js-only while the tree says "js+native" is a document that costs a reader
# an afternoon.
#
# A claim that says a package is a "<target> executable" says the same thing
# about a package that has to be run, and the manifest has to say it is one.
#
# A claim that says what a package is built with has to name a target that
# package declares.
#
# A claim that cites a manifest has to cite the line the tree declares the
# targets on, and it has to be that package's own manifest.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:targetBad = $false
$script:targetSiteBad = $false
$script:moduleBad = $false
$script:targetChecked = 0
$script:targetSiteChecked = 0
$script:moduleChecked = 0
$script:pkgTargets = @{}
$script:moduleTargets = ''
$script:moduleTargetLine = 0

# The manifest a claim cites, and the module manifest a claim cites.
$pkgCiteRe = '`([A-Za-z0-9_./-]+/moon\.pkg):([0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)`'
$modCiteRe = '`moon\.mod:([0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*)`'

# The targets each package of the tree declares.
function Get-PkgTargets {
  $out = @{}
  foreach ($rel in @(& git ls-files 2>$null)) {
    if ($rel -notmatch '(^|/)moon\.pkg$') { continue }
    if ($rel -ceq 'moon.pkg') { continue }
    $pkg = ($rel -replace '/moon\.pkg$', '')
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    $m = [regex]::Match($text, 'supported_targets\s*=\s*"([^"]*)"')
    if (-not $m.Success) { continue }
    $out[$pkg] = $m.Groups[1].Value
  }
  $out
}

# The targets one package declares.
function Get-PkgTarget($pkg) {
  if ($script:pkgTargets.ContainsKey($pkg)) { return $script:pkgTargets[$pkg] }
  ''
}

# Is a target one of the ones a package declares?
function Test-PkgHasTarget($pkg, $want) {
  foreach ($part in (@((Get-PkgTarget $pkg) -split '\+'))) {
    if ($part -ceq $want) { return $true }
  }
  $false
}

# The line a package declares its targets on.
function Get-PkgTargetLine($pkg) {
  $file = Join-Path $PWD ($pkg + '/moon.pkg')
  if (-not (Test-Path $file)) { return 0 }
  $lines = [System.IO.File]::ReadAllLines($file, $enc)
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match 'supported_targets\s*=') { return ($i + 1) }
  }
  0
}

# Is a package an executable? The manifest says so.
function Test-PkgExecutable($pkg) {
  $file = Join-Path $PWD ($pkg + '/moon.pkg')
  if (-not (Test-Path $file)) { return $false }
  $text = [System.IO.File]::ReadAllText($file, $enc)
  ($text -match 'pkgtype\(kind:\s*"executable"\)')
}

# The site of a target claim: the manifest it cites, and the line it cites.
function Test-TargetSite($doc, $line, $pkg, $cfile, $cspec) {
  if ($cfile -eq '') { return }
  $script:targetSiteChecked++
  if ($cfile -cne ($pkg + '/moon.pkg')) {
    Write-Fail ("{0,-22} {1} line {2} is about {3}, but cites {4}" -f 'target site', $doc, $line, $pkg, $cfile)
    $script:targetSiteBad = $true
    return
  }
  $targetLine = Get-PkgTargetLine $pkg
  if ($targetLine -eq 0) {
    Write-Fail ("{0,-22} {1} line {2} cites {3}, but the tree declares no targets there" -f 'target site', $doc, $line, $cfile)
    $script:targetSiteBad = $true
    return
  }
  if (-not (Test-CitationCovers $cspec $targetLine)) {
    Write-Fail ("{0,-22} {1} line {2} cites {3}:{4}, but the targets are declared on line {5}" -f 'target site', $doc, $line, $cfile, $cspec, $targetLine)
    $script:targetSiteBad = $true
  }
}

# One claim, checked against the targets the tree declares.
function Test-TargetClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()

  # The manifest the claim cites, if it cites exactly one.
  $cfile = ''
  $cspec = ''
  $cites = @([regex]::Matches($claim, $pkgCiteRe))
  if ($cites.Count -eq 1) {
    $cfile = $cites[0].Groups[1].Value
    $cspec = $cites[0].Groups[2].Value
  }

  foreach ($pkg in $script:codePkgs) {
    # "<pkg> is <target>-only": the package supports that target and nothing else.
    $onlyRe = '(^|[^A-Za-z0-9_/.-])' + [regex]::Escape($pkg) + ' is ([A-Za-z_+-]+)-only'
    foreach ($m in [regex]::Matches($lower, $onlyRe)) {
      $t = $m.Groups[2].Value
      $script:targetChecked++
      $declared = Get-PkgTarget $pkg
      if ($declared -cne $t) {
        Write-Fail ("{0,-22} {1} line {2} says {3} is {4}-only, but the tree says {5}" -f 'supported target', $doc, $line, $pkg, $t, $declared)
        $script:targetBad = $true
      }
      Test-TargetSite $doc $line $pkg $cfile $cspec
    }

    # "<pkg> is a <target> executable": the manifest has to say it is one.
    $execRe = '(^|[^A-Za-z0-9_/.-])' + [regex]::Escape($pkg) + ' is ([A-Za-z_+-]+) executable'
    foreach ($m in [regex]::Matches($lower, $execRe)) {
      $t = $m.Groups[2].Value
      $script:targetChecked++
      if (-not (Test-PkgHasTarget $pkg $t)) {
        Write-Fail ("{0,-22} {1} line {2} says {3} is a {4} executable, but the tree says {5}" -f 'supported target', $doc, $line, $pkg, $t, (Get-PkgTarget $pkg))
        $script:targetBad = $true
      }
      if (-not (Test-PkgExecutable $pkg)) {
        Write-Fail ("{0,-22} {1} line {2} says {3} is an executable, but {4}/moon.pkg does not say so" -f 'supported target', $doc, $line, $pkg, $pkg)
        $script:targetBad = $true
      }
      Test-TargetSite $doc $line $pkg $cfile $cspec
    }
  }

  # "built with `--target <target>`": the target has to be one the package declares.
  foreach ($m in [regex]::Matches($lower, $tickRe)) {
    $token = $m.Groups[1].Value
    if (-not $token.StartsWith('--target ')) { continue }
    $t = $token.Substring(9)
    if (@('native', 'js', 'wasm', 'wasm-gc', 'all') -cnotcontains $t) { continue }
    if ($cfile -eq '') { continue }
    $pkg = ($cfile -replace '/moon\.pkg$', '')
    $script:targetChecked++
    if (-not (Test-PkgHasTarget $pkg $t)) {
      Write-Fail ("{0,-22} {1} line {2} says {3} is built with --target {4}, but the tree says {5}" -f 'supported target', $doc, $line, $pkg, $t, (Get-PkgTarget $pkg))
      $script:targetBad = $true
    }
    Test-TargetSite $doc $line $pkg $cfile $cspec
  }
}

# Two target lists, compared as sets.
function Test-TargetSetEqual($a, $b) {
  $x = @($a -split '\+' | Sort-Object)
  $y = @($b -split '\+' | Sort-Object)
  if ($x.Count -ne $y.Count) { return $false }
  for ($i = 0; $i -lt $x.Count; $i++) {
    if ($x[$i] -cne $y[$i]) { return $false }
  }
  $true
}

# One claim, checked against the targets the module declares.
function Test-ModuleClaim($doc, $line, $claim) {
  foreach ($m in [regex]::Matches($claim, $tickRe)) {
    $token = $m.Groups[1].Value
    if ($token -notmatch '\+') { continue }
    $ok = $true
    foreach ($p in @($token -split '\+')) {
      if (@('native', 'js', 'wasm', 'wasm-gc', 'all') -cnotcontains $p) { $ok = $false }
    }
    if (-not $ok) { continue }
    $script:moduleChecked++
    if (-not (Test-TargetSetEqual $token $script:moduleTargets)) {
      Write-Fail ("{0,-22} {1} line {2} says the module targets {3}, but the tree says {4}" -f 'module targets', $doc, $line, $token, $script:moduleTargets)
      $script:moduleBad = $true
    }
    $mc = [regex]::Match($claim, $modCiteRe)
    if ($mc.Success) {
      $modspec = $mc.Groups[1].Value
      if (-not (Test-CitationCovers $modspec $script:moduleTargetLine)) {
        Write-Fail ("{0,-22} {1} line {2} cites moon.mod:{3}, but the targets are declared on line {4}" -f 'module targets', $doc, $line, $modspec, $script:moduleTargetLine)
        $script:moduleBad = $true
      }
    }
  }
}

$script:pkgTargets = Get-PkgTargets
$moduleFile = Join-Path $PWD 'moon.mod'
if (Test-Path $moduleFile) {
  $moduleText = [System.IO.File]::ReadAllText($moduleFile, $enc)
  $mm = [regex]::Match($moduleText, 'supported_targets\s*=\s*"([^"]*)"')
  if ($mm.Success) { $script:moduleTargets = $mm.Groups[1].Value }
  $moduleLines = [System.IO.File]::ReadAllLines($moduleFile, $enc)
  for ($i = 0; $i -lt $moduleLines.Count; $i++) {
    if ($moduleLines[$i] -match 'supported_targets\s*=') { $script:moduleTargetLine = ($i + 1); break }
  }
}

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-TargetClaim $doc $claim.line $claim.text
    Test-ModuleClaim $doc $claim.line $claim.text
  }
}

if (-not $script:targetBad) { Write-Ok 'supported target' ("{0} claims" -f $script:targetChecked) }
if (-not $script:targetSiteBad) { Write-Ok 'target site' ("{0} citations" -f $script:targetSiteChecked) }
if (-not $script:moduleBad) { Write-Ok 'module targets' ("{0} claims" -f $script:moduleChecked) }

# --- the calls that leave the machine -----------------------------------------
#
# A claim that says the tree makes no external network call is making a
# promise about the network: nothing goes out to a host the reader does not
# know about. The tree has to keep that promise, or the document has to stop
# making it. A claim that says how many external calls there are has to say
# the number the tree has.
#
# A call leaves the machine when the URL it fetches can be an address that is
# not the machine's own. A call that fetches a path -- "/api/pages" -- talks to
# a server that is already running. A call that fetches a name -- "url" -- can
# be anything, so the package that makes it decides: a package that names an
# address that is not the machine's own (not a loopback address, and not an XML
# namespace, which is a name and not an address) can reach out.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:externalBad = $false
$script:externalChecked = 0
$script:outboundPkgs = @()
$script:outboundCalls = 0

# A claim that denies an external call, and a claim that makes one.
$noExternalRe = '(no (external|outbound|remote)[a-z ]*(call|connection|request)|not call any external)'
$hasExternalRe = '(external|outbound)[a-z ]*(call|connection|request)'
# The number a claim states next to the call phrase.
$countExternalRe = '(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve) (outbound|external)[a-z ]*(call|connection|request)'

# The addresses a package names.
function Get-PkgHosts($pkg) {
  $out = @()
  foreach ($file in @(Get-ChildItem -Path (Join-Path $PWD $pkg) -Filter '*.mbt' -File -ErrorAction SilentlyContinue)) {
    if ($file.Name.EndsWith('_test.mbt')) { continue }
    $text = [System.IO.File]::ReadAllText($file.FullName, $enc)
    $ns = @()
    foreach ($m in [regex]::Matches($text, 'xmlns="(https?://[^"]*)"')) {
      $ns += $m.Groups[1].Value
    }
    foreach ($m in [regex]::Matches($text, '"https?://[^"]*"')) {
      $url = $m.Value.Replace('"', '')
      if ($ns -ccontains $url) { continue }
      if ($url.Contains('127.0.0.1') -or $url.Contains('localhost')) { continue }
      $out += $url
    }
  }
  $out | Select-Object -Unique
}

# Does this call leave the machine?
function Test-CallLeaves($line, $hosts) {
  $token = $line
  $i = $token.IndexOf('@http.')
  if ($i -ge 0) { $token = $token.Substring($i + 6) }
  $i = $token.IndexOf('(')
  if ($i -ge 0) { $token = $token.Substring($i + 1) }
  $i = $token.IndexOf(' ')
  if ($i -ge 0) { $token = $token.Substring(0, $i) }
  $token = ($token -replace '[^A-Za-z0-9_"/:.\-+].*$', '')
  if ($token.StartsWith('"/')) { return $false }
  if ($token.StartsWith('"http://') -or $token.StartsWith('"https://')) { return $true }
  if ($token.StartsWith('"')) { return $false }
  ($hosts.Count -gt 0)
}

# The calls that leave the machine, and the packages that make them.
function Get-OutboundCalls {
  $pkgs = @()
  $calls = 0
  foreach ($pkg in $script:codePkgs) {
    $hosts = @(Get-PkgHosts $pkg)
    foreach ($file in @(Get-ChildItem -Path (Join-Path $PWD $pkg) -Filter '*.mbt' -File -ErrorAction SilentlyContinue)) {
      if ($file.Name.EndsWith('_test.mbt')) { continue }
      $lines = [System.IO.File]::ReadAllLines($file.FullName, $enc)
      foreach ($line in $lines) {
        if ($line -notmatch '@http\.(get|post|put|delete|head|patch)\(') { continue }
        if (-not (Test-CallLeaves $line $hosts)) { continue }
        $calls++
        if ($pkgs -cnotcontains $pkg) { $pkgs += $pkg }
      }
    }
  }
  @{ packages = $pkgs; calls = $calls }
}

# One claim, checked against the calls the tree makes.
function Test-ExternalClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  if ($lower -match $noExternalRe) {
    $script:externalChecked++
    if ($script:outboundPkgs.Count -gt 0) {
      Write-Fail ("{0,-22} {1} line {2} says there are no external network calls, but {3} reaches out" -f 'external call', $doc, $line, ($script:outboundPkgs -join ' '))
      $script:externalBad = $true
    }
    return
  }
  if ($lower -match $hasExternalRe) {
    $script:externalChecked++
    if ($script:outboundPkgs.Count -eq 0) {
      Write-Fail ("{0,-22} {1} line {2} says there is an external network call, but no package reaches out" -f 'external call', $doc, $line)
      $script:externalBad = $true
      return
    }
    $cm = [regex]::Match($lower, $countExternalRe)
    if ($cm.Success) {
      $word = $cm.Groups[1].Value
      $stated = $numberWords[$word]
      if ("$stated" -cne "$($script:outboundCalls)") {
        Write-Fail ("{0,-22} {1} line {2} says {3} outbound calls, but the tree has {4}" -f 'external call', $doc, $line, $word, $script:outboundCalls)
        $script:externalBad = $true
      }
    }
  }
}

$outbound = Get-OutboundCalls
$script:outboundPkgs = @($outbound.packages)
$script:outboundCalls = $outbound.calls

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-ExternalClaim $doc $claim.line $claim.text
  }
}

if (-not $script:externalBad) {
  Write-Ok 'external call' ("{0} calls in {1}" -f $script:outboundCalls, ($script:outboundPkgs -join ' '))
}

# --- the CORS the tree does not have ------------------------------------------
#
# A claim that says the tree has no CORS is making a promise to the browser:
# the page and the API are the same origin, so the browser is never asked for
# cross-origin permission. The tree has to keep that promise.
#
# CORS is two things in the tree: a header, and a middleware. A header that
# allows an origin is an Access-Control header, and a middleware is an import
# of a package whose path names CORS. Neither may appear while a document
# says there is none.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:corsBad = $false
$script:corsChecked = 0
$script:corsPlaces = @()

# A claim that denies CORS, and a claim that makes one.
$noCorsRe = 'no cors([^a-z]|$)'
$hasCorsRe = '([^a-z])cors([^a-z]|$)'

# The places the tree would have to change to grow a CORS.
function Get-CorsPlaces {
  $out = @()
  foreach ($rel in @(& git ls-files '*.mbt' 2>$null)) {
    if ($rel.EndsWith('_test.mbt')) { continue }
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    if ($text.ToLower().Contains('access-control')) { $out += $rel }
  }
  foreach ($rel in @(& git ls-files '*moon.pkg' 2>$null)) {
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    foreach ($m in [regex]::Matches($text, '"[^"]*cors[^"]*"')) {
      $out += $rel
      break
    }
  }
  $out | Select-Object -Unique
}

# One claim, checked against the CORS the tree has.
function Test-CorsClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  if ($lower -notmatch $hasCorsRe) { return }
  $script:corsChecked++
  if ($lower -match $noCorsRe) {
    if ($script:corsPlaces.Count -gt 0) {
      Write-Fail ("{0,-22} {1} line {2} says there is no CORS, but {3} has one" -f 'cors', $doc, $line, ($script:corsPlaces -join ' '))
      $script:corsBad = $true
    }
    return
  }
  if ($script:corsPlaces.Count -eq 0) {
    Write-Fail ("{0,-22} {1} line {2} says there is CORS, but the tree has none" -f 'cors', $doc, $line)
    $script:corsBad = $true
  }
}

$script:corsPlaces = @(Get-CorsPlaces)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-CorsClaim $doc $claim.line $claim.text
  }
}

if (-not $script:corsBad) { Write-Ok 'cors' ("{0} claims" -f $script:corsChecked) }

# --- the metrics the tree computes --------------------------------------------
#
# A claim that says the tree has no metrics is making a claim about the tree:
# the runs are not measured. The tree does measure them -- the four measures of
# a run live in `backend/metrics.mbt` and ride in the session payload -- so a
# document that says there are none is wrong about a thing a reader can see
# in the API.
#
# A claim that says the tree has metrics has to be true too.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:metricBad = $false
$script:metricChecked = 0
$script:metricFiles = @()

# A claim that denies metrics, and a claim that makes them.
$noMetricRe = 'no metrics?([^a-z]|$)'
$hasMetricRe = '([^a-z])metrics?([^a-z]|$)'

# The metrics the tree has: a tracked source file that names them.
function Get-MetricFiles {
  $out = @()
  foreach ($rel in @(& git ls-files '*.mbt' 2>$null)) {
    if ($rel -notmatch '(?i)metric') { continue }
    if ($rel.EndsWith('_test.mbt')) { continue }
    $out += $rel
  }
  $out
}

# One claim, checked against the metrics the tree has.
function Test-MetricClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  if ($lower -notmatch $hasMetricRe) { return }
  $script:metricChecked++
  if ($lower -match $noMetricRe) {
    if ($script:metricFiles.Count -gt 0) {
      Write-Fail ("{0,-22} {1} line {2} says there are no metrics, but {3} computes them" -f 'metrics', $doc, $line, ($script:metricFiles -join ' '))
      $script:metricBad = $true
    }
    return
  }
  if ($script:metricFiles.Count -eq 0) {
    Write-Fail ("{0,-22} {1} line {2} says the tree has metrics, but it has none" -f 'metrics', $doc, $line)
    $script:metricBad = $true
  }
}

$script:metricFiles = @(Get-MetricFiles)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-MetricClaim $doc $claim.line $claim.text
  }
}

if (-not $script:metricBad) { Write-Ok 'metrics' ("{0} claims" -f $script:metricChecked) }

# --- the impact tables' callers -----------------------------------------------
#
# A row that names an affected file and the symbols in it is saying: if this
# symbol changes, this file breaks. That is only true if the file uses the
# symbol. A file that does not use it is not affected by it, and a reader who
# trusts the table will look in the wrong place.
#
# The row has to name a source file of the tree to be checked at all: a row
# whose first cell is a directory, an environment variable or a symbol is
# saying something else.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:impactBad = $false
$script:impactChecked = 0
$script:impactSources = @()

# The source files the tree has.
function Get-ImpactSources {
  @(& git ls-files '*.mbt' '*.ps1' 2>$null)
}

# One row, checked against the file it names.
function Test-ImpactClaim($doc, $line, $claim) {
  if (-not $claim.StartsWith('|')) { return }
  $rest = $claim.Substring(1)
  $first = ($rest -split '\|')[0].Trim()
  if (-not ($first.StartsWith('`') -and $first.EndsWith('`'))) { return }
  $path = $first.Substring(1, $first.Length - 2)
  if ($path -notmatch '\.(mbt|ps1)$') { return }
  if ($script:impactSources -cnotcontains $path) { return }
  $file = Join-Path $PWD $path
  if (-not (Test-Path $file)) { return }
  $body = [System.IO.File]::ReadAllText($file, $enc)
  # every symbol the row names, in the cells after the first
  $rest = ($rest -split '\|', 2)[1]
  if ($null -eq $rest) { return }
  foreach ($m in [regex]::Matches($rest, $tickRe)) {
    $symbol = $m.Groups[1].Value
    $symbol = ($symbol -split '\(')[0]
    $symbol = ($symbol -split ' ')[0]
    $last = ($symbol -split '::')[-1]
    $last = ($last -split '\.')[-1]
    if ($last -eq '') { continue }
    $script:impactChecked++
    if (-not $body.Contains($last)) {
      Write-Fail ("{0,-22} {1} line {2} says {3} breaks on {4}, but {3} does not use it" -f 'impact caller', $doc, $line, $path, $symbol)
      $script:impactBad = $true
    }
  }
}

$script:impactSources = @(Get-ImpactSources)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-ImpactClaim $doc $claim.line $claim.text
  }
}

if (-not $script:impactBad) { Write-Ok 'impact caller' ("{0} symbols" -f $script:impactChecked) }

# --- the edge the tree does not have -----------------------------------------
#
# A claim that says the deployment needs no reverse proxy and no TLS is making
# a promise about the edge: the browser reaches the server over plain HTTP,
# with nothing in between and nothing to terminate. The tree has to keep that
# promise -- a proxy config or a certificate in the tree would mean the
# deployment is not the one the documents describe.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:proxyBad = $false
$script:proxyChecked = 0
$script:tlsBad = $false
$script:tlsChecked = 0
$script:proxyPlaces = @()
$script:tlsPlaces = @()

# A claim that denies a reverse proxy, and a claim that denies TLS.
$noProxyRe = 'no [a-z, ]{0,60}reverse proxy'
$noTlsRe = 'no [a-z, ]{0,60}tls'

# The places the tree would have to change to grow an edge.
function Get-EdgePlaces {
  $proxy = @()
  $tls = @()
  foreach ($rel in @(& git ls-files 2>$null)) {
    if (($rel -clike '*nginx*') -or ($rel -clike '*Caddyfile*') -or ($rel -clike '*caddyfile*') -or ($rel -clike '*traefik*') -or ($rel -clike '*haproxy*') -or ($rel -clike '*.htaccess')) { $proxy += $rel }
    if (($rel -clike '*.pem') -or ($rel -clike '*.crt') -or ($rel -clike '*.cer') -or ($rel -clike '*.key') -or ($rel -clike '*.pfx') -or ($rel -clike '*.p12')) { $tls += $rel }
  }
  return @{ proxy = $proxy; tls = $tls }
}

# One claim, checked against the edge the tree has.
function Test-EdgeClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  if ($lower -match $noProxyRe) {
    $script:proxyChecked++
    if ($script:proxyPlaces.Count -gt 0) {
      Write-Fail ("{0,-22} {1} line {2} says there is no reverse proxy, but {3} is one" -f 'proxy', $doc, $line, ($script:proxyPlaces -join ' '))
      $script:proxyBad = $true
    }
  }
  if ($lower -match $noTlsRe) {
    $script:tlsChecked++
    if ($script:tlsPlaces.Count -gt 0) {
      Write-Fail ("{0,-22} {1} line {2} says there is no TLS, but {3} is a certificate" -f 'tls', $doc, $line, ($script:tlsPlaces -join ' '))
      $script:tlsBad = $true
    }
  }
}

$edge = Get-EdgePlaces
$script:proxyPlaces = @($edge.proxy)
$script:tlsPlaces = @($edge.tls)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-EdgeClaim $doc $claim.line $claim.text
  }
}

if (-not $script:proxyBad) { Write-Ok 'proxy' ("{0} claims" -f $script:proxyChecked) }
if (-not $script:tlsBad) { Write-Ok 'tls' ("{0} claims" -f $script:tlsChecked) }

# --- the coupling the table states -------------------------------------------
#
# A coupling row that counts the calls says how tightly two packages are
# tied together: "Eight function calls: install_from_environment, ...". The
# count and the list are a claim about the tree, and the tree can be asked.
#
# A call into a package is one of three things: a qualified call
# (@maked.create_app), a method on a value that package returned
# (app.to_module), or a method chained straight onto one
# (@maked.current_corpus().describe). A method on some other receiver
# (ctx.add_middleware, which is moonback's) is not a call into that package
# -- so the tree says eight where a naive reading of the names says nine.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:couplingBad = $false
$script:couplingChecked = 0
$script:couplingPkgs = @()

# The packages the tree has.
function Get-CouplingPackages {
  $out = @()
  foreach ($rel in @(& git ls-files 2>$null)) {
    if ($rel -notmatch '(^|/)moon\.pkg$') { continue }
    $dir = ($rel -replace '/moon\.pkg$', '')
    if ($dir -ceq 'moon.pkg') { continue }
    $out += $dir
  }
  $out
}

# The public functions a package has.
function Get-PubNames($pkg) {
  $out = @()
  foreach ($rel in @(& git ls-files $pkg 2>$null)) {
    if ($rel.EndsWith('_test.mbt')) { continue }
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    foreach ($m in [regex]::Matches($text, '(?m)^\s*pub\s+(?:async\s+)?fn\s+(?:[A-Za-z_][A-Za-z0-9_]*::)?([A-Za-z_][A-Za-z0-9_]*)\s*\(')) {
      $name = $m.Groups[1].Value
      if ($out -cnotcontains $name) { $out += $name }
    }
  }
  $out
}

# The name a package is called by in another package's source.
function Get-PkgAlias($caller, $callee) {
  $path = Join-Path $PWD (Join-Path $caller 'moon.pkg')
  if (-not (Test-Path $path)) { return '' }
  foreach ($line in [System.IO.File]::ReadAllLines($path, $enc)) {
    $m = [regex]::Match($line, '["][^"]*/' + [regex]::Escape($callee) + '["]([ \t]+@([A-Za-z_][A-Za-z0-9_]*))?')
    if ($m.Success) {
      if ($m.Groups[2].Success) { return $m.Groups[2].Value }
      return ($callee -split '/')[-1]
    }
  }
  ''
}

# The functions of one package that another package calls.
function Get-CalledNames($caller, $alias, $pub) {
  $out = @()
  foreach ($rel in @(& git ls-files $caller 2>$null)) {
    if ($rel.EndsWith('_test.mbt')) { continue }
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    $vars = @()
    foreach ($m in [regex]::Matches($text, 'let\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*@' + $alias + '\.')) {
      $vars += $m.Groups[1].Value
    }
    foreach ($m in [regex]::Matches($text, '@' + $alias + '\.([A-Za-z_][A-Za-z0-9_]*)')) {
      if ($pub -ccontains $m.Groups[1].Value) { $out += $m.Groups[1].Value }
    }
    foreach ($v in $vars) {
      foreach ($m in [regex]::Matches($text, '(?m)(?:^|[^A-Za-z0-9_])' + $v + '\.([A-Za-z_][A-Za-z0-9_]*)')) {
        if ($pub -ccontains $m.Groups[1].Value) { $out += $m.Groups[1].Value }
      }
    }
    foreach ($m in [regex]::Matches($text, '@' + $alias + '\.[A-Za-z_][A-Za-z0-9_]*\([^()]*\)\.([A-Za-z_][A-Za-z0-9_]*)')) {
      if ($pub -ccontains $m.Groups[1].Value) { $out += $m.Groups[1].Value }
    }
  }
  $out | Select-Object -Unique
}

# One coupling row, checked against the calls the tree makes.
function Test-CouplingClaim($doc, $line, $claim) {
  if (-not $claim.StartsWith('|')) { return }
  $cells = $claim.Split('|')
  if ($cells.Count -lt 3) { return }
  $first = $cells[1].Trim()
  $second = $cells[2].Trim()
  # the row has to name two packages
  $parts = @($first -split '\s+')
  if ($parts.Count -ne 3) { return }
  $caller = $parts[0]
  $callee = $parts[2]
  if ($script:couplingPkgs -cnotcontains $caller) { return }
  if ($script:couplingPkgs -cnotcontains $callee) { return }
  # the cell has to state a count of calls
  $m = [regex]::Match($second, '([A-Za-z]+)[ \t]+function[ \t]+calls?:')
  if (-not $m.Success) { return }
  $word = $m.Groups[1].Value
  $colon = $second.IndexOf(':')
  if ($colon -lt 0) { return }
  $list = $second.Substring($colon + 1)
  # the count, in words or in digits
  $count = ''
  $lower = $word.ToLower()
  if ($numberWords.ContainsKey($lower)) { $count = $numberWords[$lower] }
  if ($count -eq '' -and $word -match '^[0-9]+$') { $count = $word }
  if ($count -eq '') { return }
  # the symbols the row names
  $docSymbols = @()
  foreach ($sym in ($list -split ',')) {
    $sym = ($sym -replace '\(\)', '').Trim()
    $sym = $sym.TrimEnd('.')
    if ($sym -eq '') { continue }
    if ($docSymbols -cnotcontains $sym) { $docSymbols += $sym }
  }
  # the calls the tree makes
  $pub = @(Get-PubNames $callee)
  $alias = Get-PkgAlias $caller $callee
  if ($alias -eq '') { return }
  $treeCalls = @(Get-CalledNames $caller $alias $pub)
  # The calls are sorted, so the two twins print them in the same order.
  [Array]::Sort($treeCalls, [System.StringComparer]::Ordinal)
  # the symbols the row names, one by one
  foreach ($sym in $docSymbols) {
    $script:couplingChecked++
    if ($treeCalls -ccontains $sym) { continue }
    Write-Fail ("{0,-22} {1} line {2} names {3}, but {4} does not call it" -f 'coupling calls', $doc, $line, $sym, $caller)
    $script:couplingBad = $true
  }
  # the calls the tree makes that the row does not name
  foreach ($sym in $treeCalls) {
    if ($docSymbols -ccontains $sym) { continue }
    Write-Fail ("{0,-22} {1} line {2} does not name {3}, but {4} calls it" -f 'coupling calls', $doc, $line, $sym, $caller)
    $script:couplingBad = $true
  }
  # and the count the row states
  if ($treeCalls.Count -ne [int]$count) {
    Write-Fail ("{0,-22} {1} line {2} says {3} calls into {4}, but the tree has {5}" -f 'coupling calls', $doc, $line, $word, $callee, $treeCalls.Count)
    $script:couplingBad = $true
  }
}

$script:couplingPkgs = @(Get-CouplingPackages)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-CouplingClaim $doc $claim.line $claim.text
  }
}

if (-not $script:couplingBad) { Write-Ok 'coupling calls' ("{0} calls" -f $script:couplingChecked) }

# --- the cycles the graph does not have ---------------------------------------
#
# The dependency document says the package graph has no cycles: the packages
# depend strictly downward, so no package depends on one that depends on it.
# That is a claim about the tree, and the tree can be checked for it: the
# internal edges are known, and a cycle is an edge whose far end can reach
# its near end again.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:cycleBad = $false
$script:cycleChecked = 0
$script:treeCycles = @()

# The packages a package can reach.
function Get-Reachable($from, $edges) {
  $seen = @($from)
  $todo = @($from)
  $out = @()
  while ($todo.Count -gt 0) {
    $next = @()
    foreach ($node in $todo) {
      foreach ($edge in $edges) {
        $parts = $edge.Split(' ')
        if ($parts[0] -ne $node) { continue }
        $b = $parts[1]
        if ($seen -ccontains $b) { continue }
        $seen += $b
        $next += $b
        $out += $b
      }
    }
    $todo = $next
  }
  $out
}

# The cycles the tree's package graph has.
function Get-TreeCycles($edges) {
  $out = @()
  foreach ($edge in $edges) {
    $parts = $edge.Split(' ')
    $a = $parts[0]
    $b = $parts[1]
    $reach = @(Get-Reachable $b $edges)
    if ($reach -ccontains $a) { $out += ("{0} -> {1}" -f $a, $b) }
  }
  $out
}

# A claim that says the graph has no cycles.
$noCycleRe = 'no cycles'

# One claim, checked against the cycles the tree has.
function Test-CycleClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  if ($lower -notmatch $noCycleRe) { return }
  $script:cycleChecked++
  if ($script:treeCycles.Count -gt 0) {
    Write-Fail ("{0,-22} {1} line {2} says there are no cycles, but the tree has one: {3}" -f 'cycles', $doc, $line, ($script:treeCycles -join ' '))
    $script:cycleBad = $true
  }
}

$script:treeCycles = @(Get-TreeCycles (Get-TreeInternalEdges))

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-CycleClaim $doc $claim.line $claim.text
  }
}

if (-not $script:cycleBad) { Write-Ok 'cycles' ("{0} claims" -f $script:cycleChecked) }

# --- the gaps the evidence has to support -------------------------------------
#
# The deployment evidence has a table of gaps, and a gap is a claim that
# something is NOT there: no systemd unit, no exported metrics, no backup
# strategy. The evidence cell has to be true of the tree, or the gap is not
# a gap.
#
# Two shapes of evidence are read. A search that comes back empty ("`find`
# for *.service returns nothing") is true when the tree has no file that
# matches the pattern. A denial of a thing ("No cron, no WAL config") is
# true when the tree has no such thing: the imports, when the denial names
# imports, and the product's own source otherwise.
#
# The scope comes from the evidence, and the evidence gives it. The frontend
# has a variable called `stats`, so "no stats" would be a sentence about a
# library, not about that variable -- and the evidence cell that says it
# also says "imports", so the gate looks in the imports.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:absenceBad = $false
$script:absenceChecked = 0

# The tracked files that match a pattern.
function Get-FilesMatching($pattern) {
  $out = @()
  foreach ($rel in @(& git ls-files 2>$null)) {
    if ($rel -clike $pattern) { $out += $rel }
  }
  $out
}

# The import paths that carry a word.
function Get-ImportsWith($word) {
  $out = @()
  $whole = $word -match '^[A-Za-z_][A-Za-z0-9_]*$'
  foreach ($path in @(Get-TreeImports)) {
    if ($whole) {
      if ($path -match '(^|[^A-Za-z0-9_])' + [regex]::Escape($word) + '([^A-Za-z0-9_]|$)') { $out += $path }
    } else {
      if ($path.Contains($word)) { $out += $path }
    }
  }
  $out
}

# The files of the product's own source that carry a word. The tests are
# left out: a claim about what the server does is not a claim about what
# the tests say.
#
# A plain word is looked for as a whole word, so "wal" does not find
# "walked". A path is looked for as it is: "/metrics" is not a word.
function Get-SourceWith($word) {
  $out = @()
  $whole = $word -match '^[A-Za-z_][A-Za-z0-9_]*$'
  foreach ($rel in @(& git ls-files '*.mbt' 2>$null)) {
    if ($rel.EndsWith('_test.mbt')) { continue }
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    if ($whole) {
      if ($text -match '(?m)(^|[^A-Za-z0-9_])' + [regex]::Escape($word) + '([^A-Za-z0-9_]|$)') { $out += $rel }
    } else {
      if ($text.Contains($word)) { $out += $rel }
    }
  }
  $out
}

# One gap row, checked against the tree.
function Test-AbsenceClaim($doc, $line, $claim) {
  if (-not $claim.StartsWith('|')) { return }
  $cells = $claim.Split('|')
  if ($cells.Count -lt 3) { return }
  $gap = $cells[1].Trim()
  $evidence = $cells[2].Trim()
  # a gap is a row that says something is not there
  if (-not ($gap -cmatch '^(No|no) ')) { return }
  # a search that comes back empty
  $m = [regex]::Match($evidence, 'for\s+([^\s]+)\s+returns\s+nothing')
  if ($m.Success) {
    $script:absenceChecked++
    $hits = @(Get-FilesMatching $m.Groups[1].Value)
    if ($hits.Count -gt 0) {
      Write-Fail ("{0,-22} {1} line {2} says nothing matches {3}, but {4} does" -f 'absence evidence', $doc, $line, $m.Groups[1].Value, ($hits -join ' '))
      $script:absenceBad = $true
    }
    return
  }
  # a denial of a thing, one at a time. The word keeps its case: "WAL" is
  # the SQLite mode, and "wal" is a part of "walked".
  $lower = $evidence.ToLower()
  $orig = $evidence
  while ($lower -match 'no ') {
    $rest = $lower.Substring($lower.IndexOf('no ') + 3)
    $len = $lower.Length - $rest.Length
    $after = $orig.Substring($len)
    $word = $after.Split(' ')[0]
    $word = $word -replace '`', ''
    $word = ($word -split ',')[0]
    $word = ($word -split ';')[0]
    $word = ($word -split '\.')[0]
    $phrase = $after
    $restPhrase = $after.ToLower()
    $next = $restPhrase.IndexOf('no ')
    if ($next -ge 0) { $phrase = $after.Substring(0, $next) }
    if ($word -ne '') {
      $script:absenceChecked++
      $hits = @()
      if ($phrase -match 'import') { $hits = @(Get-ImportsWith $word) } else { $hits = @(Get-SourceWith $word) }
      if ($hits.Count -gt 0) {
        Write-Fail ("{0,-22} {1} line {2} says there is no {3}, but {4} has it" -f 'absence evidence', $doc, $line, $word, ($hits -join ' '))
        $script:absenceBad = $true
      }
    }
    $lower = $rest
    $orig = $after
  }
}

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-AbsenceClaim $doc $claim.line $claim.text
  }
}

if (-not $script:absenceBad) { Write-Ok 'absence evidence' ("{0} claims" -f $script:absenceChecked) }

# --- the edges the packages do not share ---------------------------------------
#
# The dependency document says the backend and the frontend share no direct
# dependency: they talk through the JSON contract at runtime, not through an
# import. That is a claim about the tree's edges, and the tree's edges are
# known.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:sharedBad = $false
$script:sharedChecked = 0
$script:sharedPkgs = @()

# A claim that names two packages and says they share no dependency.
$noSharedRe = '([a-z]+) and ([a-z]+) share no direct dependency'

# One claim, checked against the edges the tree has.
function Test-SharedClaim($doc, $line, $claim) {
  $lower = $claim.ToLower()
  $m = [regex]::Match($lower, $noSharedRe)
  if (-not $m.Success) { return }
  $first = $m.Groups[1].Value
  $second = $m.Groups[2].Value
  # both have to be packages of the tree
  if ($script:sharedPkgs -cnotcontains $first) { return }
  if ($script:sharedPkgs -cnotcontains $second) { return }
  $script:sharedChecked++
  # and the tree has to have no edge between them, either way
  $edge = ''
  foreach ($l in @(Get-TreeInternalEdges)) {
    $parts = $l.Split(' ')
    if (($parts[0] -ceq $first -and $parts[1] -ceq $second) -or ($parts[0] -ceq $second -and $parts[1] -ceq $first)) {
      $edge = $l
      break
    }
  }
  if ($edge -ne '') {
    Write-Fail ("{0,-22} {1} line {2} says {3} and {4} share no direct dependency, but the tree has the edge {5}" -f 'shared edge', $doc, $line, $first, $second, $edge)
    $script:sharedBad = $true
  }
}

$script:sharedPkgs = @(Get-CouplingPackages)

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-SharedClaim $doc $claim.line $claim.text
  }
}

if (-not $script:sharedBad) { Write-Ok 'shared edge' ("{0} claims" -f $script:sharedChecked) }

# --- the counts the summary repeats --------------------------------------------
#
# The summary repeats three numbers: the tests, the mutation anchors and the
# integration checks. The tests are checked already; the other two were not,
# so they could go stale in the summary while the README and the tree stayed
# right.
#
# The anchors are counted in the tree: every mutation has one `old =` line,
# so the anchors in the three suites are the mutations they anchor. The
# integration checks cannot be counted from the script -- some of its
# assertions sit in loops, and only a run knows how many it made -- so the
# number is read where the tree keeps it: the README's own table, which the
# integration suite checks on every run.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

# The anchors in one mutation suite. An anchor is one `old =` line.
function Get-AnchorCount($suite) {
  $count = 0
  foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $PWD $suite), $enc)) {
    if ($line -match '^[ \t]*old[ \t]*=') { $count++ }
  }
  $count
}

$allAnchors = (Get-AnchorCount 'tools/mutate-backend.ps1') + (Get-AnchorCount 'tools/mutate-frontend.ps1') + (Get-AnchorCount 'tools/mutate-loop.ps1')

# The integration checks the README states.
$readmeText = [System.IO.File]::ReadAllText((Join-Path $PWD 'README.md'), $enc)
$readmeIntegration = ''
$readmeMatch = [regex]::Match($readmeText, '\|\s*Integration checks\s*\|\s*([0-9]+)\s*\|')
if ($readmeMatch.Success) { $readmeIntegration = $readmeMatch.Groups[1].Value }

if ($readmeIntegration -eq '') {
  Write-Fail ("{0,-22} could not be read from the README" -f 'summary integration')
} else {
  Test-ClaimNumber 'summary anchors' '([0-9]+) mutation anchors' $allAnchors $summary
  Test-ClaimNumber 'summary integration' '([0-9]+) integration\s+checks' $readmeIntegration $summary
}

# --- the external column the table states -------------------------------------
#
# The dependency table has a column that says what each package leans on
# outside the project. It is a claim about the tree's manifests: the package
# imports exactly these, and nothing else.
#
# The document writes the paths the way a reader writes them -- "moonback"
# for "moonbitlang/moonback", "core (debug, env, json)" for the core
# packages -- so the comparison is made on the last segment of each path,
# which is the part both sides spell the same way.
#
# The test-only imports are left out: the column says what a package needs
# to run, and a test block is not what it needs to run.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:externalBad = $false
$script:externalChecked = 0

# The external imports of a package, the test block left out.
function Get-PkgExternal($pkg) {
  $out = @()
  $path = Join-Path $PWD (Join-Path $pkg 'moon.pkg')
  if (-not (Test-Path $path)) { return $out }
  $inside = $false
  $test = $false
  $block = ''
  foreach ($line in [System.IO.File]::ReadAllLines($path, $enc)) {
    if (-not $inside) {
      if ($line -match '^import \{') { $inside = $true; $block = ''; $test = $false }
      continue
    }
    if ($line -match '\}') {
      $inside = $false
      if ($line -match 'for "test"') { $test = $true }
      if (-not $test) {
        foreach ($m in [regex]::Matches($block, '"([^"]+)"')) {
          $p = $m.Groups[1].Value
          if ($p.StartsWith('riantr/MAKED')) { continue }
          $out += (($p -split '/')[-1])
        }
      }
      continue
    }
    $block = $block + ' ' + $line
  }
  $out
}

# The last segments a column names. A group -- "core (debug, env, json)" --
# is read as the paths it stands for.
function Get-ExternalNamed($cell) {
  $out = @()
  $items = @()
  $cur = ''
  $depth = 0
  foreach ($ch in $cell.ToCharArray()) {
    if ($ch -eq '(') { $depth++ } elseif ($ch -eq ')') { $depth-- }
    if ($ch -eq ',' -and $depth -eq 0) {
      $items += $cur
      $cur = ''
    } else {
      $cur += $ch
    }
  }
  $items += $cur
  foreach ($item in $items) {
    $item = $item.Trim()
    if ($item -eq '') { continue }
    if ($item -eq '(none)' -or $item -eq '(empty)') { continue }
    $m = [regex]::Match($item, '^([^\s]+)\s+\((.*)\)$')
    if ($m.Success) {
      foreach ($member in ($m.Groups[2].Value -split ',')) {
        $member = $member.Trim()
        if ($member -eq '') { continue }
        $out += (($member -split '/')[-1])
      }
    } else {
      $out += (($item -split '/')[-1])
    }
  }
  $out
}

# The rows of the internal dependencies table: the line, the package and the
# external cell.
function Get-DocExternalRows {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $depsMd), $enc)
  $inside = $false
  $n = 0
  foreach ($line in ($text -split "`r?`n")) {
    $n++
    if (-not $inside) {
      if ($line -match '^\|\s*Package\s*\|') { $inside = $true }
      continue
    }
    if (-not $line.StartsWith('|')) { break }
    $cells = $line -split '\|'
    if ($cells.Count -lt 4) { continue }
    $pkg = ($cells[1] -replace '`', '') -replace '\s', ''
    $ext = $cells[3].Trim()
    if ($pkg -match '^[-\t]+$') { continue }
    if ($pkg -eq '') { continue }
    if ($ext -eq '') { continue }
    $out += ,@($n, $pkg, $ext)
  }
  $out
}

# One row, checked against the package's own manifest.
function Test-ExternalColumn($doc, $line, $pkg, $cell) {
  $named = @(Get-ExternalNamed $cell | Select-Object -Unique)
  if ($pkg -like 'root*') { $pkg = '.' }
  $tree = @(Get-PkgExternal $pkg | Select-Object -Unique)
  [Array]::Sort($named, [System.StringComparer]::Ordinal)
  [Array]::Sort($tree, [System.StringComparer]::Ordinal)
  $script:externalChecked++
  foreach ($name in $named) {
    if ($tree -ccontains $name) { continue }
    Write-Fail ("{0,-22} {1} line {2} says {3} depends on {4}, but the tree does not" -f 'external column', $doc, $line, $pkg, $name)
    $script:externalBad = $true
  }
  foreach ($name in $tree) {
    if ($named -ccontains $name) { continue }
    Write-Fail ("{0,-22} {1} line {2} leaves {3} out of {4}, but the tree imports it" -f 'external column', $doc, $line, $name, $pkg)
    $script:externalBad = $true
  }
}

foreach ($row in @(Get-DocExternalRows)) {
  Test-ExternalColumn $depsMd $row[0] $row[1] $row[2]
}

if (-not $script:externalBad) { Write-Ok 'external column' ("{0} packages" -f $script:externalChecked) }

# --- the size a claim gives a file ---------------------------------------------
#
# The summary sizes the framework layer: the backend's `App` is ~150 lines.
# That is a number about the tree -- the file the type is defined in -- and
# the tree can be counted.
#
# A "~" is a tolerance, not an exact figure: the claim is about the size of
# the thing, not about a line. The gate accepts the stated number when the
# file is within a tenth of it, and says so plainly when it is not.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:sizeBad = $false
$script:sizeChecked = 0

# The files that define a type.
function Get-TypeFiles($name) {
  $out = @()
  foreach ($rel in @(& git ls-files '*.mbt' 2>$null)) {
    if ($rel.EndsWith('_test.mbt')) { continue }
    $file = Join-Path $PWD $rel
    if (-not (Test-Path $file)) { continue }
    $text = [System.IO.File]::ReadAllText($file, $enc)
    if ($text -match '(?m)^\s*pub struct ' + [regex]::Escape($name) + '([^A-Za-z0-9_]|$)') { $out += $rel }
  }
  $out
}

# One claim, checked against the file the type is defined in.
function Test-SizeClaim($doc, $line, $claim) {
  $m = [regex]::Match($claim, '`([A-Za-z_][A-Za-z0-9_]*)` is ~([0-9]+) lines')
  if (-not $m.Success) { return }
  $name = $m.Groups[1].Value
  $stated = [int]$m.Groups[2].Value
  $files = @(Get-TypeFiles $name)
  if ($files.Count -eq 0) {
    Write-Fail ("{0,-22} {1} line {2} sizes {3}, but the tree has no such type" -f 'file size', $doc, $line, $name)
    $script:sizeBad = $true
    return
  }
  if ($files.Count -gt 1) { return }
  $file = $files[0]
  $count = [System.IO.File]::ReadAllLines((Join-Path $PWD $file), $enc).Count
  $script:sizeChecked++
  $diff = [Math]::Abs($count - $stated)
  if ($diff -gt [int][Math]::Floor($stated / 10)) {
    Write-Fail ("{0,-22} {1} line {2} says {3} is ~{4} lines, but {5} has {6}" -f 'file size', $doc, $line, $name, $stated, $file, $count)
    $script:sizeBad = $true
  }
}

foreach ($doc in $archDocs) {
  # A document that describes the past is a record of the past. Its claims
  # are about the tree as it was, so they are not checked against the tree
  # as it is.
  if ($markedDocs -ccontains $doc) { continue }
  foreach ($claim in (Get-DocClaims $doc)) {
    Test-SizeClaim $doc $claim.line $claim.text
  }
}

if (-not $script:sizeBad) { Write-Ok 'file size' ("{0} claims" -f $script:sizeChecked) }

# --- the packages that use each dependency -----------------------------------
#
# The dependency table has a column that says who uses each dependency. It
# is a claim about the tree's manifests: the packages whose import block
# names the dependency, and no others.
#
# The comparison is on the MODULE, not on the path. A package that imports
# "moonbitlang/async/fs" imports the module "moonbitlang/async", and the
# table names modules. So the first two segments of an import path are what
# is compared.
#
# The test imports count: a package that imports a dependency for its tests
# still uses it.
#
# The cell is a set, not a list: the order the packages are written in says
# nothing, so the two are compared by membership.
#
# The bash twin says the same thing. The two are twins: they print the same
# lines and they go red together.

$script:usedByBad = $false
$script:usedByChecked = 0

# Every package the tree has, the root one included.
function Get-AllPackages {
  $out = @()
  foreach ($rel in @(& git ls-files 2>$null)) {
    if ($rel -notmatch '(^|/)moon\.pkg$') { continue }
    if ($rel -eq 'moon.pkg') { $out += 'root' } else { $out += ($rel -replace '/moon\.pkg$', '') }
  }
  $out
}

# The module roots a package imports, the test imports included.
function Get-PkgRoots($pkg) {
  $out = @()
  if ($pkg -eq 'root') { $path = Join-Path $PWD 'moon.pkg' }
  else { $path = Join-Path $PWD (Join-Path $pkg 'moon.pkg') }
  if (-not (Test-Path $path)) { return $out }
  $inside = $false
  $block = ''
  foreach ($line in [System.IO.File]::ReadAllLines($path, $enc)) {
    if (-not $inside) {
      if ($line.StartsWith('import {')) { $inside = $true; $block = '' }
      continue
    }
    if ($line -match '\}') {
      $inside = $false
      foreach ($m in [regex]::Matches($block, '"([^"]+)"')) {
        $p = $m.Groups[1].Value
        if ($p.StartsWith('riantr/MAKED')) { continue }
        if ($p -notmatch '/') { continue }
        $parts = $p -split '/'
        $out += ($parts[0] + '/' + $parts[1])
      }
      continue
    }
    $block = $block + ' ' + $line
  }
  $out
}

# The packages that import a dependency.
function Get-DepUsers($dep, $packages) {
  $out = @()
  foreach ($pkg in $packages) {
    foreach ($root in @(Get-PkgRoots $pkg)) {
      if ($root -cne $dep) { continue }
      if ($out -cnotcontains $pkg) { $out += $pkg }
    }
  }
  $out
}

# The packages a cell names.
function Get-UsedByNamed($cell) {
  $out = @()
  foreach ($item in ($cell -split ',')) {
    $item = $item.Trim()
    if ($item -eq '') { continue }
    $out += $item
  }
  $out
}

# The rows of the dependency table: the line, the dependency and the cell
# that says who uses it.
function Get-DocUsedByRows {
  $out = @()
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $evidence), $enc)
  $inside = $false
  $n = 0
  foreach ($line in ($text -split "`r?`n")) {
    $n++
    if (-not $inside) {
      if ($line -match '^\|\s*Dependency\s*\|\s*Version\s*\|\s*Used by\s*\|') { $inside = $true }
      continue
    }
    if (-not $line.StartsWith('|')) { break }
    $cells = $line -split '\|'
    if ($cells.Count -lt 5) { continue }
    $dep = ($cells[1] -replace '`', '') -replace '\s', ''
    $used = $cells[3].Trim()
    if ($dep -match '^[-\t]+$') { continue }
    if ($dep -eq '') { continue }
    if ($used -eq '') { continue }
    $out += ,@($n, $dep, $used)
  }
  $out
}

# One row, checked against the tree.
function Test-UsedBy($doc, $line, $dep, $cell) {
  $tree = @(Sort-Set @(Get-DepUsers $dep $script:allPkgs))
  $script:usedByChecked++
  if ($cell -ceq '(transitive)') {
    foreach ($name in $tree) {
      Write-Fail ("{0,-22} {1} line {2} says {3} is transitive, but the tree imports it in {4}" -f 'used by', $doc, $line, $dep, $name)
      $script:usedByBad = $true
    }
    return
  }
  $named = @(Sort-Set @(Get-UsedByNamed $cell))
  foreach ($name in $named) {
    if ($tree -ccontains $name) { continue }
    Write-Fail ("{0,-22} {1} line {2} says {3} is used by {4}, but the tree does not import it there" -f 'used by', $doc, $line, $dep, $name)
    $script:usedByBad = $true
  }
  foreach ($name in $tree) {
    if ($named -ccontains $name) { continue }
    Write-Fail ("{0,-22} {1} line {2} leaves {3} out of {4}, but the tree imports it there" -f 'used by', $doc, $line, $name, $dep)
    $script:usedByBad = $true
  }
}

$script:allPkgs = @(Get-AllPackages)
foreach ($row in @(Get-DocUsedByRows)) {
  Test-UsedBy $evidence $row[0] $row[1] $row[2]
}

if (-not $script:usedByBad) { Write-Ok 'used by' ("{0} rows" -f $script:usedByChecked) }

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
