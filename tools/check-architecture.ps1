# Check the architecture documents against the tree.
#
#   .\tools\check-architecture.ps1
#
# The PowerShell twin of tools/check-architecture.sh. It exists for the same
# reason the other twins exist: the CI runner is ubuntu and carries bash, so
# a gate written only in PowerShell is a gate that does not run where the
# build runs.
#
# The two are kept in step deliberately. Both implement one invariant:
#
#   **the number the document states IS the number the tree has**
#
# The README has a gate for its numbers (tools/check-readme.ps1). The
# architecture documents make the same kind of claim -- a count, a shape, a
# file and line to look at -- and they rotted the same way: four API
# endpoints when there are thirty-seven, eight columns when there are
# twelve, "no Dockerfile" when there is one, and a hundred file:line
# references pointing at lines that had long since moved.
#
# Two kinds of claim are checked, and they are checked differently.
#
# The COUNTS are derived from the tree and compared with what the documents
# say.
#
# The REFERENCES are checked for existence and for range. A reference to a
# file that is not there is a broken pointer. A reference to a line past the
# end of the file is a broken pointer too. A reference to a line that is
# still IN RANGE but no longer says what the claim says it says is the
# dangerous one -- it looks verified -- and no script can catch that; it is
# why the documents carry the claim in words next to the pointer.
#
# It reads only. It never writes to the source tree.
#
# Exit codes:
#   0  every claim in the documents matches the tree
#   1  a claim in the documents does not match the tree

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

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

# --- how the tree is counted ------------------------------------------------

# A route is one registration: app.get(...), app.post(...), and the rest.
# The count is the number of registrations, not the number of distinct
# paths, because a path registered for two verbs is two registrations and
# the handler behind them is two handlers.
function Count-Routes {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD 'backend/api.mbt'), $enc)
  ([regex]::Matches($text, 'app\.(get|post|put|delete|patch)\(')).Count
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
# is then the only run of digits in that fragment. Two things follow from
# that, and both are why it is written this way.
#
# The fragment is matched whole rather than through a capture group. A
# greedy leading `.*` eats INTO the number: "37 API routes" leaves "7" for
# the capture group, because the engine tries the longest `.*` first and "7"
# is the longest prefix that still leaves a digit before " API routes". A
# gate that reads 7 where the document says 37 is a gate that cannot be
# trusted.
#
# The context around the number carries no digits of its own. That is what
# makes "the only run of digits in the fragment" the right answer, and it is
# why a pattern like "mutate-backend.ps1 # 143 mutations" is not safe here:
# the "1" of "ps1" would be a digit run of its own.
function Get-DocNumber($pattern, $file) {
  $text = [System.IO.File]::ReadAllText((Join-Path $PWD $file), $enc)
  $m = [regex]::Match($text, $pattern)
  if (-not $m.Success) { return '' }
  $digits = [regex]::Match($m.Value, '[0-9]+')
  if (-not $digits.Success) { return '' }
  $digits.Value
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
  $bad = $false
  foreach ($ref in $refs) {
    $file = $ref.Groups[1].Value
    $last = if ($ref.Groups[3].Success) { [int]$ref.Groups[3].Value } else { [int]$ref.Groups[2].Value }
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
    Write-Ok "references $(Split-Path -Leaf $doc)" $seen.Count
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

Write-Output ""
if ($failures -gt 0) {
  Write-Output ("{0} claim(s) in the architecture documents do not match the tree." -f $failures)
  Write-Output "*** FAIL ***"
  Write-Output ""
  Write-Output "The documents state a claim and the tree has another. Fix the documents,"
  Write-Output "or fix the tree -- but make the two agree before saying anything about"
  Write-Output "either of them."
  exit 1
}
Write-Output "Every claim in the architecture documents matches the tree."
exit 0
