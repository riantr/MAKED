///| Tests for the agent's view of the loop.
///
/// The agent reads the same machine the panel reads, and gets it in a
/// different shape: sentences where a sentence helps, ids where an id is
/// needed. Three things are worth pinning here.
///
/// The first is that **every slot is accounted for**. The options answer
/// splits the slots into the ones that can move and the ones that cannot,
/// and the two lists together are all of them. A slot that fell out of both
/// lists would be invisible -- the agent would never learn the slot exists
/// -- and a count alone would not catch it, because a slot listed twice and
/// another missing add up to the same number. So the names are compared as
/// well as the count.
///
/// The second is that **the lists of names are flat**. The backend's other
/// string lists are arrays of one-element arrays, because that is the shape
/// the browser's decoder expects. An agent reads JSON, not the browser, so
/// the agent's lists are flat arrays of strings. A change that nested them
/// would still be a JSON array of the right length, and only the shape
/// tells the two apart.
///
/// The third is that **a refusal says why**. A slot the model does not have
/// is refused by name. A target the table does not offer is refused with the
/// list of the ones it does offer, so a caller who asked for the wrong one
/// can see the right one instead of watching nothing happen.

///|
/// The slots the model has, as names.
fn slot_names() -> Array[String] {
  let names : Array[String] = []
  for (name, _, _) in @backend.all_slots_info() {
    names.push(name)
  }
  names
}

///|
/// The slot names in a list of option entries.
fn slots_in(entries : Array[Json]) -> Array[String] {
  let names : Array[String] = []
  for entry in entries {
    names.push(json_str(entry, "slot"))
  }
  names
}

///|
/// Whether a list of names holds one name.
fn holds_name(names : Array[String], name : String) -> Bool {
  for candidate in names {
    if candidate == name {
      return true
    }
  }
  false
}

///|
/// A field of a payload, or the test fails.
fn object_of(json : Json, key : String) -> Json raise {
  match field(json, key) {
    Some(value) => value
    None => fail("the payload has no field called " + key)
  }
}

///|
/// A number field of a payload, or -1 when it is not there.
fn int_of(json : Json, key : String) -> Int32 {
  match field(json, key) {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
}

///|
/// A boolean field of a payload, or false when it is not there.
fn bool_of(json : Json, key : String) -> Bool {
  match field(json, key) {
    Some(True) => true
    Some(False) => false
    _ => false
  }
}

///|
/// The outcome the model gives a slot at the position the loop stands at.
///
/// The model is asked, not the options read: the options are what MAKED
/// says, and the model is what it is based on. A test that compared the
/// options with themselves would pass whatever they said.
fn model_outcome_at(slot : String) -> String {
  let state = @backend.get_loop_state()
  let position = state.domain_state(state.current).position
  @backend.current_model().step(position, slot).kind()
}

///|
/// Drive the loop until the table leaves a slot open.
///
/// The machine has a handful of places where it declines to choose, and the
/// agent has to answer at one of them: a refusal that names the wrong
/// candidates is a refusal that sends the caller the wrong way. The machine
/// is fixed, so the walk is repeatable.
fn drive_to_an_open_slot(db : @backend.Database) -> String raise {
  let mut slot = ""
  let mut i = 0
  while i < 30 && slot == "" {
    for (name, _, _) in @backend.all_slots_info() {
      if @backend.open_candidate_names(name).length() > 0 {
        slot = name
        break
      }
    }
    if slot == "" {
      ignore(@backend.take_drive_step(db))
    }
    i += 1
  }
  if slot == "" {
    fail("the machine never left a slot open")
  }
  slot
}

///|
/// The options name every slot the model has, and name each one once.
test "the options account for every slot the model has" {
  ignore(@backend.reset_loop())
  let options = @backend.agent_options(3)
  let can = json_array(options, "can_move")
  let cannot = json_array(options, "cannot_move")
  let all = slot_names()
  assert_true(all.length() > 0)
  // The count first, and then the names: the count alone cannot tell a slot
  // listed twice from a slot that is missing.
  assert_eq(can.length() + cannot.length(), all.length())
  let named = slots_in(can)
  for name in slots_in(cannot) {
    named.push(name)
  }
  assert_eq(named.length(), all.length())
  for name in all {
    assert_true(holds_name(named, name))
  }
}

///|
/// The options say what the model says about each slot.
///
/// The options are MAKED's reading of the model, so a slot the model says
/// is blocked has to be in the list of the ones that cannot move, and a
/// slot the model says is open has to be in the other list -- with the
/// model's own outcome, not a tidied-up version of it.
test "the options say what the model says about each slot" {
  ignore(@backend.reset_loop())
  let options = @backend.agent_options(3)
  let can = json_array(options, "can_move")
  let cannot = json_array(options, "cannot_move")
  for (name, _, _) in @backend.all_slots_info() {
    let kind = model_outcome_at(name)
    if kind == "block" {
      assert_true(holds_name(slots_in(cannot), name))
      assert_true(!holds_name(slots_in(can), name))
    } else {
      assert_true(holds_name(slots_in(can), name))
      assert_true(!holds_name(slots_in(cannot), name))
      for entry in can {
        if json_str(entry, "slot") == name {
          assert_eq(json_str(entry, "outcome_kind"), kind)
        }
      }
    }
  }
}

///|
/// A slot that cannot move says why it cannot.
test "a slot that cannot move says why it cannot" {
  ignore(@backend.reset_loop())
  let options = @backend.agent_options(3)
  let cannot = json_array(options, "cannot_move")
  assert_true(cannot.length() > 0)
  for entry in cannot {
    let why = json_str(entry, "why")
    assert_true(why != "")
    // The reason names the slot, so a reader who was shown the slot can see
    // that the sentence is about that slot and not about another one.
    let designation = json_str(entry, "slot_name")
    assert_true(designation != "")
    assert_true(why.contains(designation))
  }
}

///|
/// The lists of names an agent reads are flat arrays of strings.
///
/// The backend's other string lists are arrays of one-element arrays, which
/// is the shape the browser's decoder expects. An agent reads JSON, so the
/// list is flat -- and a nested list is still an array of the right length,
/// so the shape has to be checked rather than the count.
test "the lists of names an agent reads are flat arrays of strings" {
  ignore(@backend.reset_loop())
  let options = @backend.agent_options(3)
  let can = json_array(options, "can_move")
  assert_true(can.length() > 0)
  for entry in can {
    match field(entry, "lands_at") {
      Some(Array(items)) => {
        assert_true(items.length() > 0)
        match items[0] {
          String(_) => ()
          _ => fail("the list of names is nested, and an agent cannot read it")
        }
      }
      _ => fail("a slot that can move does not say where it lands")
    }
  }
}

///|
/// The slots the table declined to choose are the open ones, and no others.
test "the slots the table declined to choose are the open ones and no others" {
  ignore(@backend.reset_loop())
  let options = @backend.agent_options(3)
  let can = json_array(options, "can_move")
  let declined = json_array(options, "the_table_declined_to_choose")
  let mut open = 0
  for entry in can {
    if json_str(entry, "outcome_kind") == "open" {
      open += 1
    }
  }
  assert_eq(declined.length(), open)
  for entry in declined {
    let slot = json_str(entry, "slot")
    // The declined slot is one of the slots that can move, and it is the
    // open one: the table offers it and declines to pick.
    let mut kind = ""
    let mut lands = 0
    for candidate in can {
      if json_str(candidate, "slot") == slot {
        kind = json_str(candidate, "outcome_kind")
        lands = json_array(candidate, "lands_at").length()
      }
    }
    assert_eq(kind, "open")
    // And the candidates it names are the ones that slot lands at.
    let candidates = json_array(entry, "the_candidates")
    assert_eq(candidates.length(), lands)
    assert_true(candidates.length() > 0)
  }
}

///|
/// The ids the agent is given are the model's own ids, read the model's way.
test "the position the agent is told about is labelled the way the model labels it" {
  ignore(@backend.reset_loop())
  let place = @backend.agent_where()
  let model = @backend.current_model()
  let position = json_str(place, "position")
  assert_true(position != "")
  assert_eq(json_str(place, "position_label"), model.position_label(position))
  let domain = json_str(place, "domain")
  assert_true(domain != "")
  assert_eq(
    json_str(place, "the_domain_in_words"),
    @backend.role_of(model, domain),
  )
}

///|
/// The status says where the loop stands, and says that nothing has happened yet.
async test "the status says where the loop stands before anything has happened" {
  let db = open_session_db("agent_status")
  let _ = fresh_session(db, "First exploration")
  let status = @backend.agent_status(db)
  let place = object_of(status, "where")
  assert_eq(json_str(place, "domain"), "M")
  assert_eq(json_str(place, "domain_name"), "Model")
  assert_true(json_str(place, "position") != "")
  assert_true(json_str(place, "position_label") != "")
  assert_true(json_str(place, "position_gloss") != "")
  assert_true(json_str(place, "the_group") != "")
  assert_true(json_str(place, "the_collective") != "")
  assert_eq(int_of(status, "steps_taken"), 0)
  assert_true(
    json_str(status, "the_last_move").contains("No step has been taken yet"),
  )
}

///|
/// A step taken through the agent's tool is recorded, and said to have happened.
async test "a step taken through the agent's tool is recorded and narrated" {
  let db = open_session_db("agent_step")
  let session = fresh_session(db, "First exploration")
  let before = @backend.agent_where()
  let before_label = json_str(before, "position_label")
  let _ = @backend.take_drive_step(db)
  // Recorded: the step is written down, so a person can look at it later.
  let steps = db.steps_of_session(session.id)
  assert_eq(steps.length(), 1)
  let step = steps[0]
  let result = @backend.agent_step_result(db)
  assert_eq(int_of(result, "steps_taken"), 1)
  let what = json_str(result, "what_happened")
  assert_true(what != "")
  // And narrated: the sentence names where the step came from and the slot
  // it went through, and both are the ones the history records -- so the
  // sentence and the ids beside it cannot disagree.
  assert_true(before_label != "")
  assert_true(what.contains(before_label))
  assert_true(step.slot_designation != "")
  assert_true(what.contains(step.slot_designation))
}

///|
/// A slot the model does not have is refused by name.
async test "a slot the model does not have is refused by name" {
  let db = open_session_db("agent_slot")
  let _ = fresh_session(db, "First exploration")
  match @backend.take_slot_step(db, "no-such-slot", "") {
    @backend.UnknownSlot(name) => assert_eq(name, "no-such-slot")
    @backend.Taken(_) => fail("a slot the model does not have was taken")
    @backend.UnknownTarget(_, _) =>
      fail("a slot the model does not have was read as a bad target")
  }
}

///|
/// A slot may be named by the id the machine uses or the label a reader saw.
async test "a slot may be named by the id the machine uses or the label a reader saw" {
  let db = open_session_db("agent_slot_name")
  let _ = fresh_session(db, "First exploration")
  match @backend.take_slot_step(db, "act", "") {
    @backend.Taken(_) => ()
    @backend.UnknownSlot(name) =>
      fail("the slot the machine calls act was refused: " + name)
    @backend.UnknownTarget(_, _) =>
      fail("a step with no target was read as a bad target")
  }
  // And the same slot under the name the panel shows.
  match @backend.take_slot_step(db, "Action", "") {
    @backend.Taken(_) => ()
    @backend.UnknownSlot(name) =>
      fail("the slot the panel calls Action was refused: " + name)
    @backend.UnknownTarget(_, _) =>
      fail("a step with no target was read as a bad target")
  }
}

///|
/// A target the table does not offer is refused with the ones it does offer.
async test "a target the table does not offer is refused with the ones it does" {
  let db = open_session_db("agent_target")
  let _ = fresh_session(db, "First exploration")
  let slot = drive_to_an_open_slot(db)
  let offered = @backend.open_candidate_names(slot)
  assert_true(offered.length() > 0)
  match @backend.take_slot_step(db, slot, "no-such-place") {
    @backend.UnknownTarget(asked, names) => {
      assert_eq(asked, "no-such-place")
      // The refusal names the candidates that were really on offer, so a
      // caller who asked for the wrong one can see the right one.
      assert_eq(names.length(), offered.length())
      for i in 0..<offered.length() {
        assert_eq(names[i], offered[i])
      }
    }
    @backend.Taken(_) => fail("a target the table does not offer was taken")
    @backend.UnknownSlot(name) =>
      fail("a slot the machine has was refused: " + name)
  }
  // And the target that IS on offer is taken.
  match @backend.take_slot_step(db, slot, offered[0]) {
    @backend.Taken(_) => ()
    @backend.UnknownTarget(asked, _) =>
      fail("a target the table offered was refused: " + asked)
    @backend.UnknownSlot(name) =>
      fail("a slot the machine has was refused: " + name)
  }
}

///|
/// The options name the slot the table declined to choose, and its candidates.
async test "the options name the slot the table declined to choose" {
  let db = open_session_db("agent_declined")
  let _ = fresh_session(db, "First exploration")
  let slot = drive_to_an_open_slot(db)
  let options = @backend.agent_options(3)
  let declined = json_array(options, "the_table_declined_to_choose")
  assert_true(declined.length() > 0)
  let mut found = false
  for entry in declined {
    if json_str(entry, "slot") == slot {
      found = true
      // And the candidates it names are the ones the slot really offers.
      let candidates = json_array(entry, "the_candidates")
      assert_eq(
        candidates.length(),
        @backend.open_candidate_names(slot).length(),
      )
    }
  }
  assert_true(found)
}

///|
/// The collective says where it stands, and what it can do from there.
test "the collective says where it stands and what it can do from there" {
  ignore(@backend.reset_loop())
  let society = @backend.agent_society()
  assert_true(json_str(society, "the_collective") != "")
  assert_true(json_str(society, "the_collective_position") != "")
  let moves = json_array(society, "what_it_can_do_from_here")
  assert_true(moves.length() > 0)
  for entry in moves {
    assert_true(json_str(entry, "trigger") != "")
    assert_true(json_str(entry, "the_move") != "")
    assert_true(json_str(entry, "lands_at") != "")
  }
}

///|
/// A move of the collective is taken, and said to have been taken.
test "a move of the collective is taken and said to have been taken" {
  ignore(@backend.reset_loop())
  let before = json_str(@backend.agent_society(), "the_collective_position")
  let result = @backend.agent_society_step("RaiseClaims")
  let what = json_str(result, "what_happened")
  assert_true(what != "")
  let after = json_str(@backend.agent_society(), "the_collective_position")
  // The move the collective took is the one it says it took: the position
  // moved, and the sentence says so.
  assert_true(after != before)
  assert_true(what.contains("moved from"))
}

///|
/// The explorations are listed, and the active one is marked.
async test "the explorations are listed and the active one is marked" {
  let db = open_session_db("agent_sessions")
  let session = fresh_session(db, "First exploration")
  let payload = @backend.agent_sessions(db)
  assert_eq(json_str(payload, "the_active_one"), session.id.to_string())
  let items = json_array(payload, "the_explorations")
  assert_eq(items.length(), 1)
  assert_eq(json_str(items[0], "name"), "First exploration")
  assert_eq(int_of(items[0], "steps"), 0)
  assert_true(bool_of(items[0], "is_the_active_one"))
}

///|
/// An exploration can be taken away as Markdown and as JSON.
async test "an exploration can be taken away as Markdown and as JSON" {
  let db = open_session_db("agent_export")
  let session = fresh_session(db, "First exploration")
  let _ = @backend.take_drive_step(db)
  let markdown = @backend.agent_export(db, session.id, "markdown")
  assert_eq(json_str(markdown, "format"), "markdown")
  let text = json_str(markdown, "the_exploration")
  assert_true(text.contains("First exploration"))
  let json = @backend.agent_export(db, session.id, "json")
  assert_eq(json_str(json, "format"), "json")
  // The machine form is an object, not a string: an agent that wants to
  // process it must not have to read prose.
  match field(json, "the_exploration") {
    Some(Object(_)) => ()
    _ => fail("the JSON export is not an object")
  }
  // And it is the same run the Markdown form describes.
  assert_true(json.stringify().contains("First exploration"))
}

///|
/// An exploration that does not exist is refused, not answered with nothing.
async test "an exploration that does not exist is refused" {
  let db = open_session_db("agent_export_missing")
  let _ = fresh_session(db, "First exploration")
  let payload = @backend.agent_export(db, 999999L, "markdown")
  assert_eq(json_str(payload, "error"), "there is no exploration with that id")
}

///|
/// The start-up refuses a file it could not read.
///
/// A server that starts with half a machine answers every request
/// confidently and wrongly, which is the worst thing a server can do. So
/// the start-up stops, and says why. Every file MAKED runs is checked this
/// way: the machine, the table that says what a document means, the words
/// for the collective, and the corpus the documents come from.
///
/// The refusal is tested in `bootstrap_test.mbt`, against the files the
/// plan names rather than against the environment: the environment is
/// process-wide, and the test driver runs these tests side by side.

///|
/// The version the agent's server reports is the version it is built from.
///
/// A server that says one version and is another is a server nobody can
/// file a bug against, and the registry is where the two numbers are
/// compared.
async test "the version the agent's server reports is the version in moon.mod" {
  let text = @fs.read_file("moon.mod").text() catch {
    err => fail("moon.mod could not be read: " + @debug.to_string(err))
  }
  let mut found = ""
  for line in text.split("\n") {
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix("version = \"") {
      let rest = trimmed[11:].to_owned()
      found = match rest.find("\"") {
        Some(end) => rest[0:end].to_owned()
        None => fail("the version line in moon.mod has no closing quote")
      }
    }
  }
  assert_true(found != "")
  assert_eq(@backend.MAKED_VERSION, found)
}
