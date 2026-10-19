///| Session tests: persistence, replay, branching and export.
///

///| The property that matters most here is the one a user would notice

///| first: **the work survives a restart**. A loop that forgets is a demo,

///| not a tool, and every other property in this file is downstream of that

///| one.
///

///| The second is that **replay re-derives rather than restores**: putting a

///| session back together runs its steps through the transition table again,

///| so the state that comes back is one the table really produces. A test

///| that only checked "the numbers came back" would pass even if the replay

///| were reading a stale snapshot -- so the comparison here is against the

///| state captured at the time, not against a stored copy.
///

///| The third is that **nothing is destroyed on the way**. A rewind leaves

///| the steps it walked back from in the table, and a branch leaves the

///| session it came from untouched. A history that deletes what it no longer

///| shows is not a history.

///|
fn session_db_path(name : String) -> String {
  "test_session_" + name + ".db"
}

///|
async fn open_session_db(name : String) -> @backend.Database {
  let path = session_db_path(name)
  drop_db(path)
  @backend.Database::open(path)
}

///|
/// How many slot names a stored list holds. An empty list holds none, and
/// `split` on an empty string yields one empty piece, which is why this does
/// not simply count the pieces.
fn count_slots(text : String) -> Int32 {
  if text.is_empty() {
    return 0
  }
  let mut n = 0
  for part in text.split(",") {
    if part.to_owned() != "" {
      n += 1
    }
  }
  n
}

///|
/// Whether a stored list of slot names contains one name.
fn list_has(text : String, name : String) -> Bool {
  if text.is_empty() {
    return false
  }
  for part in text.split(",") {
    if part.to_owned() == name {
      return true
    }
  }
  false
}

///|
/// A fresh session, activated, with the loop reset to the beginning.
///
/// The loop's state is global, so every test that steps the loop has to say
/// where it starts. A test that inherited the previous test's position would
/// be testing whatever that position happened to be.
fn fresh_session(
  db : @backend.Database,
  name : String,
) -> @backend.Session raise {
  ignore(@backend.reset_loop())
  let session = db.insert_session(name, 0L, 0L, "M", "structured")
  @backend.set_active_session_id(session.id)
  session
}

///|
/// Take `n` steps and record each one, the way the API does.
fn take_steps(db : @backend.Database, n : Int32) -> @backend.LoopState raise {
  let mut state = @backend.get_loop_state()
  let mut i = 0
  while i < n {
    let before = state
    state = @backend.step_loop()
    @backend.record_step(db, before, state, "drive")
    i += 1
  }
  state
}

///|
/// One field of a JSON object, or None when it is not there.
fn json_field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
/// The id of a session, in either spelling.
///
/// The backend holds an id as an `Int64`, and MoonBit's own `ToJson` encodes
/// an `Int64` as a *string* -- so that is how the id travels. The client
/// accepts both spellings, and so does this helper: what is being checked
/// here is which session the payload is about, not how its id is written
/// down.
fn payload_id(json : Json) -> Int64 {
  match json_field(json, "id") {
    Some(Json::String(text)) => @string.parse_int64(text) catch { _ => 0L }
    Some(Json::Number(n, ..)) => n.to_int64()
    _ => 0L
  }
}

///|
/// The session as it stands in the table, not as it was when it was created.
///
/// A `Session` value is a snapshot: the one `insert_session` hands back has
/// an empty head, because no step had been taken yet. Reading it back is how
/// a caller finds out where the session has got to.
fn reload(db : @backend.Database, id : Int64) -> @backend.Session raise {
  match db.session_by_id(id) {
    Some(session) => session
    None => fail("no such session")
  }
}

///|
/// The session that is active, read back from the table.
fn active_from(db : @backend.Database) -> @backend.Session raise {
  match db.session_by_id(@backend.active_session_id()) {
    Some(session) => session
    None => fail("no active session")
  }
}

///|
async test "a step is recorded with the slot, the positions and the why" {
  let db = open_session_db("record")
  let session = fresh_session(db, "First pass")
  let before = @backend.get_loop_state()
  let after = @backend.step_loop()
  @backend.record_step(db, before, after, "drive")
  let steps = db.steps_of_session(session.id)
  assert_eq(steps.length(), 1)
  let step = steps[0]
  assert_eq(step.domain, "M")
  assert_eq(step.source, "drive")
  assert_eq(
    step.outcome,
    after.history[after.history.length() - 1].outcome_label,
  )
  // The position the step started from, not the one it landed on. This is
  // the whole reason the per-domain map is copied on every step: read from
  // the shared map, "before" and "after" are the same value.
  //
  // The first step of a session starts at the domain's anchor, so the
  // position it started from is the anchor and nothing else. Comparing the
  // record against that -- rather than against the same expression read
  // from the same map -- is what makes the check able to fail: a comparison
  // of two things derived the same way passes however wrong both are.
  assert_eq(
    step.position_before,
    @backend.current_model().position_label(
      @backend.domain_from_id("model").unwrap().position(),
    ),
  )
  assert_eq(
    step.position_after,
    @backend.current_model().position_label(
      after.domain_state(@backend.domain_from_id("model").unwrap()).position,
    ),
  )
  assert_true(step.detail != "")
  assert_true(step.created_at.contains("T"))
  db.close()
  drop_db(session_db_path("record"))
}

///|
async test "the why accounts for all eight slots" {
  let db = open_session_db("why")
  let session = fresh_session(db, "Why")
  let before = @backend.get_loop_state()
  let after = @backend.step_loop()
  @backend.record_step(db, before, after, "drive")
  let step = db.steps_of_session(session.id)[0]
  // Available plus blocked is the whole vocabulary: a slot that is in
  // neither was never asked about.
  assert_eq(count_slots(step.available) + count_slots(step.blocked), 8)
  // The slot that was used is in the list that matches what happened: a
  // refused step used a slot with no edge, and any other step used one with
  // an edge.
  if step.outcome == "No-way" {
    assert_true(list_has(step.blocked, step.slot))
  } else {
    assert_true(list_has(step.available, step.slot))
  }
  db.close()
  drop_db(session_db_path("why"))
}

///|
async test "the session survives a restart" {
  let db = open_session_db("restart")
  let session = fresh_session(db, "Work in progress")
  ignore(take_steps(db, 3))
  let recorded = db.steps_of_session(session.id)
  assert_eq(recorded.length(), 3)
  let before_positions = []
  for domain in @backend.ring_domains_loop() {
    before_positions.push(
      @backend.current_model().position_label(
        @backend.get_loop_state().domain_state(domain).position,
      ),
    )
  }
  db.close()
  // A new process, a new connection: the same file.
  let reopened = @backend.Database::open(session_db_path("restart"))
  @backend.restore_session(reopened)
  assert_eq(@backend.active_session_id(), session.id)
  assert_eq(reopened.steps_of_session(session.id).length(), 3)
  // The loop came back with the same history and the same positions, which
  // is what "not amnesia" has to mean if the history is to be usable.
  assert_eq(@backend.get_loop_state().history.length(), 3)
  let after_positions = []
  for domain in @backend.ring_domains_loop() {
    after_positions.push(
      @backend.current_model().position_label(
        @backend.get_loop_state().domain_state(domain).position,
      ),
    )
  }
  assert_eq(after_positions, before_positions)
  reopened.close()
  drop_db(session_db_path("restart"))
}

///|
async test "replay puts the loop back where the step left it" {
  let db = open_session_db("replay")
  let session = fresh_session(db, "Replay")
  ignore(take_steps(db, 1))
  // Captured after the first step, before the second: this is the state the
  // replay has to reproduce.
  let after_first = @backend.get_loop_state()
  ignore(take_steps(db, 2))
  let steps = db.steps_of_session(session.id)
  assert_eq(steps.length(), 3)
  match @backend.rewind_session(db, session.id, steps[0].id) {
    @backend.Done(_) => ()
    _ => fail("rewind should have succeeded")
  }
  // Re-derived, not restored: the positions come out of the transition
  // table again, and they match what the table produced the first time.
  assert_eq(@backend.get_loop_state().history.length(), 1)
  for domain in @backend.ring_domains_loop() {
    assert_eq(
      @backend.get_loop_state().domain_state(domain).position,
      after_first.domain_state(domain).position,
    )
  }
  db.close()
  drop_db(session_db_path("replay"))
}

///|
async test "a rewind keeps the steps it walked back from" {
  let db = open_session_db("rewind")
  let session = fresh_session(db, "Rewind")
  ignore(take_steps(db, 3))
  let steps = db.steps_of_session(session.id)
  match @backend.rewind_session(db, session.id, steps[0].id) {
    @backend.Done(rewound) =>
      // The returned session reports the head it moved to, not the one it
      // had before the move.
      assert_eq(rewound.head_step_id, steps[0].id)
    _ => fail("rewind should have succeeded")
  }
  // Nothing is deleted. The steps beyond the head are the branches that
  // were walked and then walked back from, and they stay readable.
  assert_eq(db.steps_of_session(session.id).length(), 3)
  let head = active_from(db)
  assert_eq(head.head_step_id, steps[0].id)
  db.close()
  drop_db(session_db_path("rewind"))
}

///|
async test "a rewind to a step that is not on the path is refused" {
  let db = open_session_db("refuse")
  let session = fresh_session(db, "Refuse")
  ignore(take_steps(db, 3))
  let steps = db.steps_of_session(session.id)
  // Walk the session back to its first step. The steps beyond it are no
  // longer on the path, so they are not places the session can be sent.
  match @backend.rewind_session(db, session.id, steps[0].id) {
    @backend.Done(_) => ()
    _ => fail("rewind should have succeeded")
  }
  match @backend.rewind_session(db, session.id, steps[2].id) {
    @backend.MissingStep => ()
    _ => fail("a step off the path must not be a rewind target")
  }
  db.close()
  drop_db(session_db_path("refuse"))
}

///|
async test "a branch is its own session and leaves the original alone" {
  let db = open_session_db("branch")
  let session = fresh_session(db, "Original")
  ignore(take_steps(db, 3))
  let steps = db.steps_of_session(session.id)
  match @backend.branch_session(db, session.id, steps[1].id, "Other road") {
    @backend.Done(branch) => {
      assert_eq(branch.parent_id, session.id)
      assert_eq(branch.forked_step_id, steps[1].id)
      // The branch carries the path up to the fork point...
      assert_eq(db.steps_of_session(branch.id).length(), 2)
      // ...and the copied steps are chained to each other, so the branch's
      // second step really does follow its first. A copy that forgot to
      // carry the parent link would give the branch a path of one step and
      // a second step floating beside it.
      let branch_steps = db.steps_of_session(branch.id)
      assert_eq(branch_steps[1].parent_step_id, branch_steps[0].id)
      // ...and the session it came from is exactly as it was.
      assert_eq(db.steps_of_session(session.id).length(), 3)
      // The branch is the one in front of the user now.
      assert_eq(@backend.active_session_id(), branch.id)
      // And it reports the head it actually has. A session value is a
      // snapshot of a row, so a branch that returned the value it was
      // handed would report an empty head and claim its fork point was
      // nowhere.
      assert_eq(branch.head_step_id, branch_steps[1].id)
    }
    _ => fail("branch should have succeeded")
  }
  // A step taken in the branch belongs to the branch.
  ignore(take_steps(db, 1))
  assert_eq(db.steps_of_session(session.id).length(), 3)
  let active = active_from(db)
  assert_eq(db.steps_of_session(active.id).length(), 3)
  db.close()
  drop_db(session_db_path("branch"))
}

///|
/// The payload names the session it acted on.
///
/// The state under "session" is the *active* session. A route that acts on
/// some other session has to name its subject as well, or the answer is
/// about a session the caller did not ask about -- and a caller that renamed
/// a background session would be told about the foreground one and conclude
/// that the rename had gone somewhere else.
async test "a payload names the session it acted on, not only the active one" {
  let db = open_session_db("payload")
  let active = fresh_session(db, "The live one")
  // A zero id would make every id comparison below vacuously true, so the
  // ids are checked for being real first.
  assert_true(active.id != 0L)
  // A second session, so that "the active one" and "the renamed one" are
  // two different sessions and the difference can be seen at all.
  let background = db.insert_session(
    "The background one", 0L, 0L, "M", "structured",
  )
  assert_true(db.rename_session(background.id, "Renamed"))
  let renamed = reload(db, background.id)
  let payload = @backend.session_payload_with(db, "renamed", renamed)
  // The renamed session is there, under its own key, with its new name.
  match json_field(payload, "renamed") {
    Some(Json::Object(fields)) =>
      match fields.get("name") {
        Some(Json::String(name)) => assert_eq(name, "Renamed")
        _ => fail("the renamed session should carry its name")
      }
    _ => fail("the payload should carry the renamed session")
  }
  // It is the session that was renamed, not some other one.
  match json_field(payload, "renamed") {
    Some(renamed) => assert_eq(payload_id(renamed), background.id)
    None => fail("the payload should carry the renamed session")
  }
  // The active session is still reported under "session": the two keys are
  // there for two different questions, and neither replaces the other.
  match json_field(payload, "session") {
    Some(live) => assert_eq(payload_id(live), active.id)
    None => fail("the payload should carry the active session")
  }
  // And the live status still travels with it, so a client that renamed a
  // session does not have to ask for the status again.
  assert_true(json_field(payload, "loop") is Some(_))
  db.close()
  drop_db(session_db_path("payload"))
}

///|
async test "the markdown export names the session and every step" {
  let db = open_session_db("markdown")
  let session = fresh_session(db, "Export me")
  ignore(take_steps(db, 2))
  let markdown = @backend.export_markdown(db, reload(db, session.id))
  assert_true(markdown.contains("# MAKED session: Export me"))
  assert_true(markdown.contains("## Timeline"))
  assert_true(markdown.contains("**Why:**"))
  assert_true(markdown.contains("**Position:**"))
  // One heading per step.
  let mut headings = 0
  for line in markdown.split("\n") {
    if line.to_owned().has_prefix("### ") {
      headings += 1
    }
  }
  assert_eq(headings, 2)
  db.close()
  drop_db(session_db_path("markdown"))
}

///|
async test "the json export carries the format, the path and the branches" {
  let db = open_session_db("json")
  let session = fresh_session(db, "Export me")
  ignore(take_steps(db, 3))
  let steps = db.steps_of_session(session.id)
  // Fork off the first step so there is a branch to report.
  match @backend.branch_session(db, session.id, steps[0].id, "Side road") {
    @backend.Done(_) => ()
    _ => fail("branch should have succeeded")
  }
  let exported = @backend.export_json(db, reload(db, session.id))
  match json_field(exported, "format") {
    Some(String(text)) => assert_eq(text, "maked.session.v1")
    _ => fail("the export must say what format it is")
  }
  match json_field(exported, "path") {
    Some(Array(items)) => assert_eq(items.length(), 3)
    _ => fail("the export must carry the path")
  }
  match json_field(exported, "other_steps") {
    Some(Array(items)) => assert_eq(items.length(), 0)
    _ => fail("the export must carry the branches")
  }
  db.close()
  drop_db(session_db_path("json"))
}

///|
async test "a session name is required, and is trimmed" {
  match @backend.Session::validate_name("  ") {
    @backend.Rejected(reason) => assert_true(reason.contains("name"))
    @backend.Accepted(_) => fail("an empty name must be refused")
  }
  match @backend.Session::validate_name("  Working set  ") {
    @backend.Accepted(name) => assert_eq(name, "Working set")
    @backend.Rejected(_) => fail("a name with padding is a name")
  }
  let long = "x".repeat(200)
  match @backend.Session::validate_name(long) {
    @backend.Rejected(reason) => assert_true(reason.contains("limit"))
    @backend.Accepted(_) => fail("an absurd name must be refused")
  }
}

///|
async test "deleting a session takes its steps with it" {
  let db = open_session_db("delete")
  let session = fresh_session(db, "Temporary")
  ignore(take_steps(db, 2))
  assert_eq(db.steps_of_session(session.id).length(), 2)
  assert_true(db.delete_session(session.id))
  assert_eq(db.steps_of_session(session.id).length(), 0)
  assert_true(db.session_by_id(session.id) is None)
  db.close()
  drop_db(session_db_path("delete"))
}

///|
async test "a step that could not move is recorded as one" {
  let db = open_session_db("blocked")
  let session = fresh_session(db, "Blocked")
  // Find a slot the model has no edge for at this position. 228 of the 272
  // position-slot combinations are Block, so there is always one to be had.
  let position = @backend.get_loop_state().domain_state(
      @backend.domain_from_id("model").unwrap(),
    ).position
  let open = @backend.exitable_slots(position)
  let mut blocked_slot = None
  for slot in @backend.current_model().slot_ids() {
    if !open.contains(slot) {
      blocked_slot = Some(slot)
      break
    }
  }
  match blocked_slot {
    None => fail("every position should leave some slot without an edge")
    Some(slot) => {
      let before = @backend.get_loop_state()
      let after = @backend.step_loop_with_slot(slot)
      @backend.record_step(db, before, after, "explicit")
      let step = db.steps_of_session(session.id)[0]
      assert_eq(step.outcome, "No-way")
      assert_eq(step.source, "explicit")
      // The cursor did not move, and the record says where it stayed.
      assert_eq(step.cursor_after, step.domain)
      // And the slot that was refused is on the list of slots with no edge.
      assert_true(list_has(step.blocked, step.slot))
    }
  }
  db.close()
  drop_db(session_db_path("blocked"))
}
