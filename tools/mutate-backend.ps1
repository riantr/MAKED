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
  },
  # The document the user takes away is not a list of labels. If the export
  # dropped the sentence that says what each step did, the export would be
  # exactly the unreadable thing the sentences were added to stop.
  @{
    name = 'the exported document drops the sentence for each step'
    file = 'backend/session.mbt'
    old  = '    out = out + step_sentence(facts_of(step)) + "\n\n"'
    new  = '    out = out + "\n\n"'
  },
  # The json export carries the summary so that a consumer does not have to
  # work it out from the path. An empty string answers nothing.
  @{
    name = 'the json export carries an empty summary'
    file = 'backend/session.mbt'
    old  = '    "summary": run_summary,'
    new  = '    "summary": "",'
  },
  # The comparison is the whole point of the measures: it is what says
  # whether a longer run is a better one. Counting the first window twice
  # makes every run look like it was finding less, which is a claim the
  # reader would act on.
  @{
    name = 'the comparison measures the first window twice'
    file = 'backend/metrics.mbt'
    old  = '  let last = count_fresh(fresh, n - window, n)'
    new  = '  let last = count_fresh(fresh, 0, window)'
  },
  # New ground is new ground: a step that reached a position the run had
  # already been on added nothing to the map. Counting every step as new
  # would make a run that is going round in circles look like an explorer.
  @{
    name = 'every step counts as new ground'
    file = 'backend/metrics.mbt'
    old  = '    let fresh = !contains_string(occupied, step.position_after)'
    new  = '    let fresh = true'
  },
  # The measures are taken over the window, so that two runs can be
  # compared. Counting the whole run instead would report the same number
  # for a run that was still finding ground and one that had stopped.
  @{
    name = 'the new ground measure covers the whole run instead of the window'
    file = 'backend/metrics.mbt'
    old  = '  let count = count_fresh(fresh, start, fresh.length())'
    new  = '  let count = count_fresh(fresh, 0, fresh.length())'
  },
  # The measures travel with the export, so a reader of the document can
  # see whether the run was getting anywhere.
  @{
    name = 'the export drops the measures'
    file = 'backend/session.mbt'
    old  = '    "metrics": run_metrics.to_json(),'
    new  = '    "metrics": Json::empty_object(),'
  },
  # A run that did not move at all is stuck; a run that moved into a position
  # it already knew is settling. Calling a stuck run "settling" tells a
  # reader to wait for a convergence that is never coming.
  @{
    name = 'a stuck run is reported as settling'
    file = 'backend/metrics.mbt'
    old  = '    if !moved_outcome(recent[i - start].outcome) {'
    new  = '    if false {'
  },
  # The sentences are read by people. A phrase that begins in the middle of
  # the alphabet reads as a typo, and a reader who sees one stops trusting
  # the rest.
  @{
    name = 'a sentence starts in the middle of the alphabet'
    file = 'backend/metrics.mbt'
    old  = '    "The last step"'
    new  = '    "the last step"'
  },
  # The way out of a position the table declined to decide. If the reader's
  # choice is ignored, the run is stuck again -- with a button on the screen
  # that says it can be unstuck.
  @{
    name = "the reader's choice of successor is ignored"
    file = 'backend/loop.mbt'
    old  = '    Some(candidate) => self.step_domain_with_candidate(domain, slot, candidate)'
    new  = '    Some(candidate) => self'
  },
  # The candidate is found by the name the panel showed. A lookup that never
  # matches is a way out that is not there.
  @{
    name = 'a candidate is never found by its name'
    file = 'backend/loop.mbt'
    old  = '    if candidate.to.to_lower() == needle ||
      current_model().position_label(candidate.to).to_lower() == needle {'
    new  = '    if false {'
  },
  # The model is the machine written down. A translation that sends the
  # subject somewhere else is a model that says something the table does
  # not, and the comparison over all 272 combinations is what catches it.
  @{
    name = 'the model writes down the wrong destination'
    file = 'backend/model.mbt'
    old  = '    @sm.Moved(tr, to) => Moved(tr.en_label(), position_id_of(to))'
    new  = '    @sm.Moved(tr, to) => Moved(tr.en_label(), position_id_of(state))'
  },
  # A pair with no way out is not a way out. A model that counts it as one
  # would offer a reader a drive slot that goes nowhere.
  @{
    name = 'a blocked pair is counted as a way out'
    file = 'backend/model.mbt'
    old  = '          Block(_) => ()
          _ => usable.push(slot.id)'
    new  = '          Block(_) => usable.push(slot.id)
          _ => usable.push(slot.id)'
  },
  # A model file that names a position it does not define is a rule about
  # nowhere. Reading it would mean inventing a position to hold it.
  @{
    name = 'a model that names what it does not define is accepted'
    file = 'backend/model.mbt'
    old  = '  if model.first_broken_rule() is Some(_) {'
    new  = '  if model.first_broken_rule() is None {'
  },
  # The format is how a model says which version wrote it. Without it, a file
  # from a later version would be read as if it were this one.
  @{
    name = 'the model does not say which format it is'
    file = 'backend/model.mbt'
    old  = '    "format": MODEL_FORMAT,'
    new  = '    "format": "maked.model.v0",'
  },
  # A candidate is found by its id as well as by its label. The two are not the
  # same string, so accepting one and not the other refuses a client that read
  # the id out of /api/model and posted it back.
  @{
    name = 'a candidate can only be named by its label'
    file = 'backend/loop.mbt'
    old  = '    if candidate.to.to_lower() == needle ||
      current_model().position_label(candidate.to).to_lower() == needle {'
    new  = '    if current_model().position_label(candidate.to).to_lower() == needle {'
  },
  # The outcome's word is the model's, and the model may rename it. A loop
  # that had its own copy of the word would keep saying the old one after the
  # model was renamed.
  @{
    name = 'the model renames the Undecided outcome'
    file = 'backend/model.mbt'
    old  = '    Open(_) => "Undecided"'
    new  = '    Open(_) => "Pending"'
  },
  # The loop offers the edges the model has, not every slot in the vocabulary.
  @{
    name = 'the loop offers every slot, not the model''s edges'
    file = 'backend/loop.mbt'
    old  = 'pub fn exitable_slots(position : String) -> Array[String] {
  current_model().exitable_slots(position)
}'
    new  = 'pub fn exitable_slots(position : String) -> Array[String] {
  let out = []
  for slot in current_model().slot_ids() {
    out.push(slot)
  }
  out
}'
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