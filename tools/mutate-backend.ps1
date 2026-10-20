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
#
# `-Only <text>` runs the mutations whose name or whose file contains the
# given text. It exists because a survivor is only useful if it can be
# re-checked in a minute rather than in half an hour: the whole suite is the
# honest answer, and a filter is the cheap way to ask "is this one still
# uncaught?" while the fix is being written.
param(
  [string]$Only = ""
)

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
    old  = '    blocked: blocked_slots_text(model, position_before),'
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
  # A model file may be written in YAML as well as JSON. The extension says
  # which, because the two syntaxes overlap -- JSON is a subset of YAML --
  # and a file read as the wrong syntax is a file that half-reads. The rule
  # itself lives in datafile.mbt now, because the research file follows it
  # too and two rules written down twice are two rules that will one day
  # disagree.
  @{
    name = 'a YAML model file is read as JSON'
    file = 'backend/datafile.mbt'
    old  = '  lower.has_suffix(".yaml") || lower.has_suffix(".yml")'
    new  = '  lower.has_suffix(".yaml") && lower.has_suffix(".yml")'
  },
  # A model file is one machine. A file with two documents in it is a file
  # whose author was not sure which one they meant, and guessing for them
  # would be running a machine nobody chose.
  @{
    name = 'a model file with two machines in it is read anyway'
    file = 'backend/datafile.mbt'
    old  = '    if documents.length() > 1 {'
    new  = '    if false {'
  },
  # The mapping table is data, and a table that never fires is a table that
  # says nothing: every document would fall through to the fallback and the
  # reader would be told the wrong thing about every paper they brought.
  @{
    name = 'the mapping table never fires'
    file = 'backend/research_config.mbt'
    old  = '      if lower.contains(word) {'
    new  = '      if false {'
  },
  # A table is written back in the syntax its name asks for. A YAML file
  # written as JSON is a file that is read as YAML and half-reads, and the
  # reader's edit is lost in the failure.
  @{
    name = 'a YAML table is written back as JSON'
    file = 'backend/datafile.mbt'
    old  = '  if is_yaml_path(path) {
    @yaml.Yaml::dump(json_to_yaml(json))'
    new  = '  if false {
    @yaml.Yaml::dump(json_to_yaml(json))'
  },
  # A table that names a slot the model does not have is a rule about
  # nowhere. Accepting it would mean driving a document through a slot that
  # is not there -- a step that goes nowhere while looking like a step.
  @{
    name = 'a table that names a slot the model does not have is accepted'
    file = 'backend/research_config.mbt'
    old  = '    if model.slot_from_name(rule.slot) is None {
      return Some(rule.slot)
    }'
    new  = '    if false {
      return Some(rule.slot)
    }'
  },
  # The table that runs is the table that was installed. A server that read
  # a file and then ran the built-in table anyway would answer every
  # request confidently and about the wrong table.
  @{
    name = 'the table that was read is never installed'
    file = 'backend/research_config.mbt'
    old  = '  g_research[0] = config'
    new  = '  g_research[0] = current_research()'
  },
  # The corpus is a file, and a corpus file that says something MAKED does
  # not understand is a corpus that reads the wrong documents. Accepting a
  # file from a later version is how a reader's corpus stops being theirs.
  @{
    name = 'a corpus file with the wrong format is accepted'
    file = 'backend/corpus.mbt'
    old  = '  if format != CORPUS_FORMAT {'
    new  = '  if false {'
  },
  # A corpus that names a source it cannot read reads nothing, and says
  # nothing while it does. An arxiv source with no query has nothing to ask
  # arxiv, and the panel would show an empty list as if the answer were
  # "there is nothing new".
  @{
    name = 'an arxiv source with no query is accepted'
    file = 'backend/corpus.mbt'
    old  = '    Arxiv => if query == "" { return Rejected("an arxiv source needs a query") }'
    new  = '    Arxiv => if false { return Rejected("an arxiv source needs a query") }'
  },
  # The corpus that runs is the corpus that was read. A server that read a
  # file and then read arxiv anyway would answer every request confidently
  # and about the wrong documents -- and the reader would never know.
  @{
    name = 'the corpus that was read is never installed'
    file = 'backend/corpus.mbt'
    old  = '  g_corpus[0] = config'
    new  = '  g_corpus[0] = current_corpus()'
  },
  # A local corpus is a folder of documents. Reading a folder as if it were
  # empty leaves the reader with a panel that says nothing about the notes
  # they put in it.
  @{
    name = 'a local corpus reads no documents'
    file = 'backend/corpus_sources.mbt'
    old  = '    if !is_readable_extension(file) {
      continue
    }'
    new  = '    if true {
      continue
    }'
  },
  # A folder is read in path order, so that the same folder drives the same
  # steps every time. A corpus read in whatever order the filesystem hands
  # back is a corpus that replays differently every run.
  @{
    name = 'a local folder is read in whatever order it comes in'
    file = 'backend/corpus_sources.mbt'
    old  = '  sorted_paths(found)'
    new  = '  found'
  },
  # The sort itself. The call above is where the order is decided, and this
  # is what decides it; a folder read in path order depends on both.
  @{
    name = 'the paths are not sorted at all'
    file = 'backend/corpus_sources.mbt'
    old  = '  let sorted = paths.copy()
  sorted.sort_by(fn(a, b) { compare_paths(a, b) })
  sorted'
    new  = '  let sorted = paths.copy()
  sorted'
  },
  # MoonBit's own string order is by length first and only then by content,
  # so a sort that uses it puts "notes/b.txt" before "notes/a/first.txt".
  # A folder read in that order looks sorted and is not: the reader cannot
  # predict it, and the same folder drives the loop differently every run.
  @{
    name = 'the paths are sorted by length, not by name'
    file = 'backend/corpus_sources.mbt'
    old  = '  sorted.sort_by(fn(a, b) { compare_paths(a, b) })'
    new  = '  sorted.sort_by(fn(a, b) { a.compare(b) })'
  },
  # A Zotero export says when its item was written. Dropping the date
  # leaves the reader with a document that has no history, which is a
  # document the timeline cannot place.
  @{
    name = "a zotero item's date is dropped"
    file = 'backend/corpus_sources.mbt'
    old  = '    Number(value, ..) => value.to_int().to_string()'
    new  = '    Number(value, ..) => ""'
  },
  # An Atom feed is read as an Atom feed. Preferring the RSS reading of a
  # feed that has both would read an arxiv feed as nothing at all, because
  # an arxiv entry is not an RSS item.
  @{
    name = 'an atom feed is read as an rss feed'
    file = 'backend/corpus_sources.mbt'
    old  = '  if documents.length() > 0 {
    return documents
  }'
    new  = '  if false {
    return documents
  }'
  },
  # A markdown file is titled by its heading. A file titled by its first
  # line instead is a file called "We fail at scale" rather than "What we
  # learned", and the reader cannot tell one document from another.
  @{
    name = 'a markdown file is titled by its first line, not its heading'
    file = 'backend/corpus_sources.mbt'
    old  = '  if heading != "" {
    return clip(heading, 120)
  }'
    new  = '  if false {
    return clip(heading, 120)
  }'
  },
  # A PDF read as markdown is a list of pages, and the converter marks each
  # one. A document called "Page 1" is a document called nothing at all.
  @{
    name = 'a page marker is taken for the title'
    file = 'backend/corpus_sources.mbt'
    old  = '  if !trimmed.has_prefix("Page ") && !trimmed.has_prefix("page ") {'
    new  = '  if true {'
  },
  # A PDF that cannot be read is refused. Reading it as an empty document
  # is a document that says nothing, and the table would answer "nothing"
  # for it as if the reader had read it.
  @{
    name = 'a pdf that cannot be read is read as an empty document'
    file = 'backend/corpus_sources.mbt'
    old  = '      return None
    }
  }
  Some(document_from_text(path, text))'
    new  = '      return Some(document_from_text(path, ""))
    }
  }
  Some(document_from_text(path, text))'
  },
  # The role of a domain is the model's word for it. MAKED used to carry its
  # own five roles and look them up by letter, so a model file's domains had
  # no voice in the sentence about them: a domain called "I" got a sentence
  # about the letter I.
  @{
    name = 'the role is looked up in the installed model, not the one asked'
    file = 'backend/narration.mbt'
    old  = '  match model.domain_by_letter(letter) {'
    new  = '  match current_model().domain_by_letter(letter) {'
  },
  # The ring is the model's, so the order the summary lists the domains in is
  # the model's too. A summary that walked MAKED's own five would count
  # nothing for a model file's domains -- and would list no domains at all.
  @{
    name = 'the summary walks the installed model''s ring, not the one asked'
    file = 'backend/narration.mbt'
    old  = '  for domain in model.domains {
    let mut count = 0
    for step in steps {
      if step.letter == domain.letter {'
    new  = '  for domain in current_model().domains {
    let mut count = 0
    for step in steps {
      if step.letter == domain.letter {'
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
    old  = '    out = out + step_sentence(facts_of(current_model(), step)) + "\n\n"'
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
    old  = '    if !moved_outcome(recent[i - start].outcome_kind) {'
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
      model.position_label(candidate.to).to_lower() == needle {'
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
      model.position_label(candidate.to).to_lower() == needle {'
    new  = '    if model.position_label(candidate.to).to_lower() == needle {'
  },
  # The outcome's word is the model's, and the model may rename it. A loop
  # that had its own copy of the word would keep saying the old one after the
  # model was renamed.
  @{
    name = 'the model renames the Undecided outcome'
    file = 'backend/model.mbt'
    # The word for an outcome is no longer written down in a table of five --
    # it is collected from the transition table as the table is walked. So
    # the mutation moves where the word comes from: the "open" kind is given
    # a name of its own, and the model's own vocabulary stops being the
    # table's.
    old  = @'
      if !known {
        words.push({ kind, label: outcome.en_label(), })
      }
'@
    new  = @'
      if !known {
        let label = if kind == "open" { "Pending" } else { outcome.en_label() }
        words.push({ kind, label, })
      }
'@
  },
  # The loop offers the edges the model has, not every slot in the vocabulary.
  @{
    name = 'the loop offers every slot, not the model''s edges'
    file = 'backend/loop.mbt'
    old  = 'pub fn exitable_slots(position : String) -> Array[String] {
  exitable_slots_of(current_model(), position)
}'
    new  = 'pub fn exitable_slots(position : String) -> Array[String] {
  let out = []
  for slot in current_model().slot_ids() {
    out.push(slot)
  }
  out
}'
  },
  # The ring is the model's, and as long as the model says. A ring that
  # skipped a domain would put two of the model's lenses next to each other
  # and leave one of them unvisited, and the reader would never be shown it.
  @{
    name = 'the ring skips a domain'
    file = 'backend/model.mbt'
    old  = '      if i + 1 < self.domains.length() {
        return self.domains[i + 1]
      }'
    new  = '      if i + 1 < self.domains.length() {
        return self.domains[0]
      }'
  },
  # A domain starts at its anchor, and the anchor is the model's. Ignoring it
  # would leave every domain standing nowhere.
  @{
    name = 'a domain''s anchor is ignored'
    file = 'backend/loop.mbt'
    old  = 'pub fn Domain::position(self : Domain) -> String {
  self.anchor
}'
    new  = 'pub fn Domain::position(self : Domain) -> String {
  ""
}'
  },
  # A domain that anchors nowhere is a domain that starts nowhere, and the
  # file is refused rather than half-read.
  @{
    name = 'a domain that anchors nowhere is accepted'
    file = 'backend/model.mbt'
    old  = '  for domain in self.domains {
    if self.position(domain.anchor) is None {
      return Some(domain.anchor)
    }
  }'
    new  = '  for domain in self.domains {
    if false {
      return Some(domain.anchor)
    }
  }'
  },
  # A model that writes no continuations down has them worked out from its
  # rules. Without the working-out, the "what could happen next" panel of a
  # hand-written model is empty.
  @{
    name = 'the continuations are never worked out'
    file = 'backend/model.mbt'
    old  = '  if self.continuations.length() == 0 {
    return self.derived_continuations(from, depth, None)
  }'
    new  = '  if self.continuations.length() == 0 {
    return []
  }'
  },
  # The format is how a model says which version wrote it. A file from a
  # later version is refused, not read as if it were this one.
  @{
    name = 'a model in another format is read anyway'
    file = 'backend/model.mbt'
    old  = '  if format != MODEL_FORMAT {
    return None
  }'
    new  = '  if false {
    return None
  }'
  },
  # The model that was read is the model that runs. A server that read a
  # file and then ran the built-in machine anyway would answer every
  # request confidently and about the wrong loop.
  @{
    name = 'the model is read but never installed'
    file = 'backend/model.mbt'
    old  = '  g_model[0] = model
  ignore(reset_loop())'
    new  = '  g_model[0] = current_model()
  ignore(reset_loop())'
  }
)

# --- run ------------------------------------------------------------------
$survivors = @()
$equivalent = @()
foreach ($m in $mutations) {
  if ($Only -ne "" -and
    -not $m.name.Contains($Only) -and
    -not $m.file.Contains($Only)) {
    continue
  }
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