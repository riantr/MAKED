# Mutation check for the backend tests.
#
# Green tests are not evidence. Each entry deliberately breaks one behaviour
# and asserts the suite goes red. A mutation that survives means the test it
# targeted does not actually reach the code.
#
#   .\tools\mutate-backend.ps1
#
# Run from anywhere; the repo root is derived from this script's own path.
#
# Files are patched and restored byte-exactly (UTF-8, no BOM, LF preserved) so
# the repo is unchanged whichever way this script exits.
#
# Three traps this script already hit, all of which look like a weak test and
# are not:
#
#   - An anchor that does not occur in the file. `String::Replace` then does
#     nothing, the suite stays green, and the mutation is reported as
#     SURVIVED. Anchors are therefore checked and a miss is an ERROR.
#   - A single-quoted PowerShell string containing `` `" ``. The backtick is
#     literal there, so the anchor silently never matches. Quote anchors that
#     contain `"` with double quotes instead.
#   - Expectation derived from the implementation is the failure this caught:
#     the ring test compared each node's distance against RING_R, so shrinking
#     the radius to 64 moved the nodes and the expectation together and the
#     suite stayed green. The geometry is now pinned to literal coordinates.

# A mutation marked `equivalent = $true` is *expected* to survive. That means
# the change is unobservable, not that the suite is too weak -- the usual cause
# is a statement that is prepared fresh on every call, for which a reset before
# the first bind is a no-op. Hardening such a test would only assert something
# that cannot fail. Keep these listed anyway: if the surrounding code ever
# starts reusing one prepared statement, the entry flips to KILLED and that is
# the signal you want.

Set-Location (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

# `moon` writes diagnostics to stderr; under 'Stop' PowerShell turns every one
# of them into a terminating error before the exit code is ever read.
$ErrorActionPreference = 'Continue'
$enc = New-Object System.Text.UTF8Encoding($false)

# --- mutations ------------------------------------------------------------
# name; file; old text; new text
$mutations = @(
  # The two SQLite behaviours the storage layer is shaped around.
  @{
    name = 'exec never steps the statement'
    file = 'backend/database.mbt'
    old  = '    ignore(stmt.step())
    None'
    new  = '    None'
  },
  @{
    name = 'seed forgets to reset the statement'
    file = 'backend/database.mbt'
    old  = '    stmt.reset(clear_bindings=true)
    stmt.bind(index=1, page.slug)'
    new  = '    stmt.bind(index=1, page.slug)'
  },
  @{
    name = 'page_by_slug forgets to reset before binding'
    file = 'backend/database.mbt'
    old  = '  stmt.reset(clear_bindings=true)
  stmt.bind(index=1, slug)'
    new  = '  stmt.bind(index=1, slug)'
    # Expected to survive: this function prepares a *fresh* statement on every
    # call, so it has no previous bindings and has never stepped. The reset is
    # unobservable here. It stays listed because the moment this function starts
    # reusing one prepared statement, the same mutation becomes a real bug and
    # this entry flips to KILLED.
    equivalent = $true
  },
  # Read-side guards.
  @{
    name = 'page_by_slug ignores the slug it was given'
    file = 'backend/database.mbt'
    old  = ' FROM pages WHERE slug = ?"'
    new  = ' FROM pages WHERE 1 = 1"'
  },
  @{
    name = 'all_pages drops the sort order'
    file = 'backend/database.mbt'
    old  = ' FROM pages ORDER BY sort ASC, slug ASC'
    new  = ' FROM pages'
  },
  @{
    name = 'all_pages reads the nav flag as always false'
    file = 'backend/database.mbt'
    old  = '    in_navigation: (stmt.column(index=6) : Int64) != 0L,'
    new  = '    in_navigation: false,'
  },
  @{
    name = 'read_page shifts every column by one'
    file = 'backend/database.mbt'
    old  = '    title: stmt.column(index=1),'
    new  = '    title: stmt.column(index=2),'
  },
  # Seed behaviour the tests claim to pin.
  @{
    name = 'seed stops after the first page'
    file = 'backend/database.mbt'
    old  = '  for page in pages {'
    new  = '  for page in pages[0:1] {'
  },
  @{
    name = 'seed never binds the sort key'
    file = 'backend/database.mbt'
    old  = '    stmt.bind(index=8, page.sort.to_int64())'
    new  = '    stmt.bind(index=8, 0L)'
  },
  @{
    name = 'seed never binds the nav flag'
    file = 'backend/database.mbt'
    old  = '    stmt.bind(index=7, if page.in_navigation { 1L } else { 0L })'
    new  = '    stmt.bind(index=7, 1L)'
  },
  # The order the whole project treats as load-bearing. This is the mutation
  # that looks the most harmless and is caught by exactly one test.
  @{
    name = 'ring order tidied into spelling order'
    file = 'backend/pages.mbt'
    old  = "    (`"model`", `"Model`", `"M`", `"the model formulator`"),
    (`"data`", `"Data`", `"D`", `"the data turbine`"),
    (`"experience`", `"Experience`", `"E`", `"the experience absorber`"),
    (`"attack`", `"Attack`", `"A`", `"the attack generator`"),
    (`"knowledge`", `"Knowledge`", `"K`", `"the knowledge distiller`"),"
    new  = "    (`"model`", `"Model`", `"M`", `"the model formulator`"),
    (`"attack`", `"Attack`", `"A`", `"the attack generator`"),
    (`"knowledge`", `"Knowledge`", `"K`", `"the knowledge distiller`"),
    (`"experience`", `"Experience`", `"E`", `"the experience absorber`"),
    (`"data`", `"Data`", `"D`", `"the data turbine`"),"
  },
  # A session's steps are a tree, and the tree is the parent link. A copy
  # that forgot to carry it would give the branch a path of one step and the
  # rest floating beside it, and the branch would be a session whose history
  # is a pile rather than a walk.
  @{
    name = 'a forked step is not chained to the step before it'
    file = 'backend/session.mbt'
    old  = '      parent_step_id: parent,'
    new  = '      parent_step_id: 0L,'
  },
  # A session's head is where it is standing. Forgetting to move it would
  # leave the session pointing at a step the user has already walked past,
  # and the timeline would show the wrong path.
  @{
    name = 'the session head is never moved'
    file = 'backend/session.mbt'
    old  = '  db.set_session_head(session_id, step.id)'
    new  = '  let _ = step'
  },
  # The reason a step was possible is snapshotted when the step is taken.
  # Dropping the blocked slots would leave a reader with "it moved" and no
  # way of knowing that six of the other seven slots could not have.
  @{
    name = 'the blocked slots are not recorded'
    file = 'backend/session.mbt'
    old  = '    blocked: blocked_slots_text(position_before),'
    new  = '    blocked: "",'
  },
  # A route that acts on one session names that session in its answer. The
  # state under "session" is the *active* one, so a payload that dropped the
  # named session would answer "here is the session you renamed" with the
  # session that happened to be live -- which is the wrong session whenever
  # the two are not the same one.
  @{
    name = 'the payload does not name the session it acted on'
    file = 'backend/session.mbt'
    old  = '      merged[key] = session.to_json()'
    new  = '      merged[key] = Json::empty_object()'
  },
  # A step that was chosen by hand and a step the table drove are different
  # claims. A sentence that says the table chose it, when the reader chose
  # it, is the machine taking credit for a decision it did not make.
  @{
    name = 'a hand-chosen slot is reported as a table-driven one'
    file = 'backend/narration.mbt'
    old  = '    "explicit" => facts.slot + " was the slot you chose"'
    new  = '    "explicit" => facts.slot + " was the slot the table drives with here"'
  },
  # The summary is a summary of the last few steps. Summarising the whole
  # history instead would answer a different question, and one nobody asked.
  @{
    name = 'the summary covers every step instead of the last five'
    file = 'backend/session.mbt'
    old  = '  let start = if path.length() > 5 { path.length() - 5 } else { 0 }'
    new  = '  let start = 0'
  }
)

# --- run ------------------------------------------------------------------
$survivors = @()
$equivalent = @()
foreach ($m in $mutations) {
  $full = Join-Path $PWD $m.file
  $original = [System.IO.File]::ReadAllText($full)
  try {
    # A silent no-op Replace reports a mutation that never happened as a
    # surviving test, which reads as a test weakness and is not one. Make an
    # unmatched anchor an error instead.
    if (-not $original.Contains($m.old)) {
      throw "anchor not present in $($m.file) -- mutation never applied"
    }
    [System.IO.File]::WriteAllText($full, $original.Replace($m.old, $m.new), $enc)
    $out = & moon test --target native backend 2>&1 | Out-String
    $killed = ($LASTEXITCODE -ne 0) -or ($out -match 'failed: [1-9]')
    if ($killed) {
      Write-Output ("KILLED   {0}" -f $m.name)
    } elseif ($m.equivalent) {
      Write-Output ("EQUIV    {0}" -f $m.name)
      $equivalent += $m.name
    } else {
      Write-Output ("SURVIVED {0}" -f $m.name)
      $survivors += $m.name
    }
  } catch {
    Write-Output ("ERROR    {0} :: {1}" -f $m.name, $_.Exception.Message)
    $survivors += $m.name
  } finally {
    [System.IO.File]::WriteAllText($full, $original, $enc)
  }
}

Write-Output ""
Write-Output ("survivors: {0}   (expected-equivalent: {1})" -f $survivors.Count, $equivalent.Count)