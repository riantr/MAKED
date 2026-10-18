///| Loop engine tests.
///
/// The loop is the newest and most complex backend module. These tests pin
/// down the properties that would silently break if the pyroduct mapping, the
/// ring order, or the state mutation were wrong:
///
///   - Domain ↔ position round-trips
///   - Ring order is M→D→E→A→K→M (not alphabetical)
///   - step() always advances and appends history
///   - step_with_slot() stays put when outcome has no landing
///   - Module-level state mutates correctly (step, reset)
///   - to_json shape matches what the frontend decodes
///
/// All five domain-anchor positions return Block("No Edge") for their default
/// drive slots in the current pyroduct migration table. The tests assert on
/// this actual outcome rather than an idealised one -- a test that passes
/// either way is not evidence.

///|
/// Domain letters in ring order.
test "ring order is M D E A K, not alphabetical" {
  let domains = @backend.ring_domains_loop()
  assert_eq(domains.map(fn(d) { d.letter() }), ["M", "D", "E", "A", "K"])
}

///|
/// Domain → position → Domain round-trips for all five anchors.
test "position and position_to_domain are inverses for domain anchors" {
  for d in @backend.ring_domains_loop() {
    let pos = d.position()
    let roundtrip = @backend.position_to_domain(pos)
    match roundtrip {
      Some(r) => assert_eq(r, d)
      None => fail("position_to_domain returned None for a domain anchor")
    }
  }
}

///|
/// position_to_domain returns None for non-anchor positions.
test "position_to_domain returns None for non-anchor positions" {
  // NoPast is position 0, which is not a domain anchor.
  assert_true(@backend.position_to_domain(@sm.NoPast) is None)
}

///|
/// Each domain's next() follows the ring.
test "next() follows M→D→E→A→K→M" {
  assert_eq(@backend.Model.next(), @backend.Data)
  assert_eq(@backend.Data.next(), @backend.Experience)
  assert_eq(@backend.Experience.next(), @backend.Attack)
  assert_eq(@backend.Attack.next(), @backend.Knowledge)
  assert_eq(@backend.Knowledge.next(), @backend.Model)
}

///|
/// Every MAKED anchor has a slot the table can actually move it with.
///
/// This replaces a test that asserted the old hard-coded mapping slot by slot.
/// Those five slots were all Block in the migration table, so the loop stepped
/// forever without any domain ever leaving its starting position. Asserting the
/// mapping could not have caught that -- the mapping was the bug. What matters
/// is the property the mapping was supposed to serve: from every anchor, the
/// table offers at least one slot that produces something other than No Edge.
test "every anchor is movable by the table" {
  for d in @backend.ring_domains_loop() {
    let pos = d.position()
    assert_true(
      @backend.exitable_slots(pos).length() > 0,
      msg="\{d.letter()} at \{pos.en_label()} has no exitable slot",
    )
    let drive = @backend.drive_slot(pos)
    assert_true(drive is Some(_))
    match drive {
      Some(slot) => assert_true(@sm.step(pos, slot).en_label() != "No Edge")
      None => ()
    }
  }
}

///|
/// The derived drive slot is one the table genuinely has an edge for.
test "drive_slot is always exitable and prefers a real move" {
  for pos in @sm.all_states() {
    match @backend.drive_slot(pos) {
      None => ()
      Some(slot) => {
        assert_true(
          @sm.exitable(pos, slot),
          msg="\{pos.en_label()} chose a slot it has no edge for",
        )
        // If a Moved edge exists anywhere, the derived slot must be one.
        let any_moved = {
          let mut found = false
          for s in @backend.exitable_slots(pos) {
            if @sm.step(pos, s).en_label() == "Moved" {
              found = true
            }
          }
          found
        }
        if any_moved {
          assert_eq(@sm.step(pos, slot).en_label(), "Moved")
        }
      }
    }
  }
}

///|
/// A position with no outgoing edge reports blocked rather than a slot.
test "a position with no out-edge yields no drive slot" {
  for pos in @sm.all_states() {
    if @backend.exitable_slots(pos).length() == 0 {
      assert_true(@backend.drive_slot(pos) is None)
    }
  }
}

///|
/// `drive_slot` must never invent a slot for a position the table cannot move.
///
/// The variant that returns some slot anyway survives every other test in this
/// file, because all five MAKED anchors are movable: the fall-through is only
/// reached at a position with no outgoing edge at all.
///
/// Measured over all 34 positions: **there are none.** Every position has at
/// least one exitable slot; what varies is whether the outcome is Moved (a
/// move) or Undecided (the table declines to choose). So the `None` branch is
/// currently unreachable from any real position -- it is there so that a
/// future table with a genuine gap reports one instead of inventing a drive.
///
/// The test therefore asserts the *invariant* rather than reaching the branch:
/// whatever `drive_slot` returns must be a slot the table has an edge for.
test "drive_slot only ever names a slot the table has an edge for" {
  let mut movable = 0
  for pos in @sm.all_states() {
    match @backend.drive_slot(pos) {
      None => ()
      Some(slot) => {
        movable += 1
        assert_true(
          @sm.exitable(pos, slot),
          msg="\{pos.en_label()} chose a slot it has no edge for",
        )
      }
    }
  }
  // All 34 positions are movable, which is why no test reaches the None branch.
  assert_eq(movable, 34)
}

///|
/// The cursor must not advance when the step was blocked.
test "a blocked step leaves the cursor where it was" {
  let state = @backend.LoopState::new()
  // Standing x Co-being is a real gap in the table.
  let blocked = state.step_with_slot(@sm.CoBeing)
  assert_eq(blocked.current, @backend.Model)
  assert_eq(blocked.history[0].outcome_label, "No Edge")
}

///|
/// A blocked step must not move the *cursor* -- and neither must an undecided
/// one, since Undecided means the table declined to pick a successor.
///
/// The undecided half is the case that does not go through `blocked` at all:
/// `drive_slot` returns a real slot, `step` returns Undecided, and the only
/// thing standing between that and a fake advance is the outcome check in
/// `step_domain_with`. Asserting only the explicit-slot case would leave that
/// path uncovered.
test "neither a blocked nor an undecided step advances the cursor" {
  let mut state = @backend.LoopState::new()
  // Model Standing -> Freedom by Action; the cursor moves to Data.
  state = state.step()
  assert_eq(state.current, @backend.Data)
  assert_eq(state.domain_state(@backend.Model).position, @sm.Freedom)
  // Come back to Model. From Freedom the only exitable slot is Occasion, which
  // is Undecided.
  let back = state.focus(@backend.Model)
  assert_eq(back.current, @backend.Model)
  let stepped = back.step()
  assert_eq(
    stepped.history[stepped.history.length() - 1].outcome_label,
    "Undecided",
  )
  // Nothing moved, so the cursor must not have moved either.
  assert_eq(stepped.current, @backend.Model)
  assert_eq(stepped.domain_state(@backend.Model).position, @sm.Freedom)
}

///|
/// Read a string field out of a `Json` object, or "" when it is absent or is
/// not a string. Total on purpose: the assertions below are about one field,
/// and a wrong shape should fail the assertion rather than raise.
fn json_str(json : Json, key : String) -> String {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(String(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
/// Read an array field, or an empty array.
fn json_array(json : Json, key : String) -> Array[Json] {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(Array(items)) => items
        _ => []
      }
    _ => []
  }
}

///|
/// The status reports the position the subject is actually at.
///
/// `current_position` used to come from `Domain::position`, the static anchor,
/// so a domain that had genuinely moved still reported where it started -- the
/// status contradicting the history in the same response.
test "status reports the real position, not the anchor, after a move" {
  let state = @backend.LoopState::new()
  let stepped = state.step()
  let ds = stepped.domain_state(@backend.Model)
  assert_true(ds.position != @backend.Model.position())
  let json = stepped.to_json()
  // Model moved to Freedom; the per-domain view must say so.
  let mut saw_freedom = false
  for item in json_array(json, "domain_states") {
    let is_model = json_str(item, "domain") == "M"
    if is_model && json_str(item, "position") == "Freedom" {
      saw_freedom = true
    }
    // `at_anchor` is the explicit statement of the same fact.
    if json_str(item, "domain") == "M" {
      assert_eq(
        match item {
          Object(f) =>
            match f.get("at_anchor") {
              Some(False) => false
              Some(True) => true
              _ => true
            }
          _ => true
        },
        false,
      )
    }
  }
  assert_true(saw_freedom)
  // The cursor's own reported position must equal its DomainState, not the
  // anchor the cursor's letter happens to map to.
  assert_eq(
    json_str(json, "current_position"),
    stepped.domain_state(stepped.current).position.en_label(),
  )
}

///|
/// `drive_slot` in the status is the table's answer, not a hard-coded one.
test "status drive_slot comes from the table" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  // Standing only leaves via Action -- the old mapping said Co-being.
  assert_eq(json_str(json, "drive_slot"), "Action")
  assert_eq(json_str(json, "drive_slot_name"), "act")
  assert_eq(
    match json {
      Object(f) =>
        match f.get("blocked") {
          Some(False) => false
          _ => true
        }
      _ => true
    },
    false,
  )
}

///|
/// `open_slots` is what the table offers here -- not all eight slots.
test "status open_slots lists only slots the table has edges for" {
  let state = @backend.LoopState::new()
  let open = json_array(state.to_json(), "open_slots")
  // Standing has exactly one exitable slot out of eight.
  assert_eq(open.length(), 1)
  assert_eq(json_str(open[0], "name"), "act")
  assert_eq(json_str(open[0], "outcome"), "Moved")
  // And every listed slot must be genuinely exitable, cross-checked against
  // pyroduct rather than against the function that produced the list.
  let pos = @sm.Standing
  for item in open {
    let slot = match @backend.slot_from_english(json_str(item, "name")) {
      Some(s) => s
      None =>
        fail("open_slots named an unknown slot: \{json_str(item, "name")}")
    }
    assert_true(@sm.exitable(pos, slot))
  }
}

///|
/// `undecided` is reported when the table declines to choose.
test "status reports undecided at an Undecided branch" {
  let mut state = @backend.LoopState::new()
  state = state.step() // Model Standing -> Freedom, cursor moves to D
  // Freedom is where Occasion is Undecided. Drive Model back to the cursor and
  // step it.
  let back = state.focus(@backend.Model)
  let json = back.to_json()
  // From Freedom the only exitable slot is Occasion, which is Undecided. The
  // status must say Undecided rather than present the branch as an ordinary
  // drive.
  assert_eq(json_str(json, "current_position"), "Freedom")
  assert_eq(json_str(json, "drive_slot"), "Occasion")
  let open = json_array(json, "open_slots")
  assert_eq(open.length(), 1)
  assert_eq(json_str(open[0], "outcome"), "Undecided")
  assert_eq(
    match json {
      Object(f) =>
        match f.get("undecided") {
          Some(True) => true
          _ => false
        }
      _ => false
    },
    true,
  )
}

///|
/// Stepping a domain that already moved keeps driving from where it is.
test "a moved domain is driven from its new position, not its anchor" {
  let mut state = @backend.LoopState::new()
  state = state.step() // Model Standing -> Freedom
  let moved = state.domain_state(@backend.Model)
  assert_eq(moved.position, @sm.Freedom)
  // Come back to Model and step again: the slot must be derived from Freedom,
  // where Occasion is the only exitable slot.
  let mut back = state
  back = {
    current: @backend.Model,
    domain_states: back.domain_states,
    group_state: back.group_state,
    history: back.history,
    mode: back.mode,
  }
  let stepped = back.step()
  let event = stepped.history[stepped.history.length() - 1]
  assert_eq(event.position_designation, "Freedom")
  assert_eq(event.slot, @sm.Occasion)
}

///|
/// `is_undecided` reports a genuine Undecided branch, and only a real one.

///|
/// Converge is a move, not a failure.
///
/// Encounter x Holding and Discipline x Action both land the subject back on
/// its own position while still consuming the trigger. Classifying Converge as
/// "did not move" would park the cursor on those domains forever, even though
/// the table settled the question. Walk every position and assert the
/// classification of Converge.
test "a Same outcome counts as a move" {
  let mut found_same = 0
  for pos in @sm.all_states() {
    for slot in @backend.exitable_slots(pos) {
      match @sm.step(pos, slot) {
        @sm.Same(_, _, _) => {
          found_same += 1
          assert_true(
            @backend.StepEffect::of(@sm.step(pos, slot)).moved(),
            msg="\{pos.en_label()} x \{slot.en_designation()} is Same but was not counted as a move",
          )
        }
        _ => ()
      }
    }
  }
  // Discipline x Action is one of them, so this is not vacuous.
  assert_true(found_same > 0)
}

///|
/// `is_undecided` is true only where the table declines to choose.
test "is_undecided is true only where the table declines to choose" {
  // Freedom x Occasion is Undecided: two successors, machine does not pick.
  assert_true(@backend.is_undecided(@sm.Freedom))
  // Standing x Action is a single Moved.
  assert_true(!@backend.is_undecided(@sm.Standing))
  // A dead position is blocked, not undecided.
  for pos in @sm.all_states() {
    if @backend.exitable_slots(pos).length() == 0 {
      assert_true(!@backend.is_undecided(pos))
    }
  }
}

///|
/// `continuations` returns real successors reachable from the current position.
test "continuations are reachable successors with a step count" {
  let out = @backend.continuations(@sm.Standing, 3)
  assert_true(out.length() > 0)
  // Every entry must name a position with at least one edge from Standing.
  let reach = @sm.reachable(@sm.Standing, @sm.Freedom)
  assert_true(reach)
  let mut saw_freedom = false
  for pair in out {
    assert_true(pair.1 >= 1)
    assert_true(pair.1 <= 3)
    if pair.0 == @sm.Freedom {
      saw_freedom = true
    }
  }
  // Action moves Standing -> Freedom in one step, so it must be there.
  assert_true(saw_freedom)
}

///|
/// `continuations` dedups: the same position may be reached by several slots.

///|
/// A position reachable by two routes is listed once, at its shortest.
///
/// Opening is reachable from Encounter in one step via Co-being and in two via
/// Holding. Listing it twice reads as two distinct futures when it is one
/// position reached two ways -- and the walk would no longer be a "what could
/// happen next" answer.
test "a position reachable twice is listed once at the shortest distance" {
  for pos in @sm.all_states() {
    let out = @backend.continuations(pos, 3)
    for i in 0..<out.length() {
      for j in (i + 1)..<out.length() {
        assert_true(
          out[i].0 != out[j].0,
          msg="\{pos.en_label()}: \{out[i].0.en_label()} listed twice",
        )
      }
    }
  }
  // Spot-check the case this exists for: from Encounter, Opening is one step
  // via Co-being.
  let from_encounter = @backend.continuations(@sm.Encounter, 3)
  let mut found = -1
  for pair in from_encounter {
    if pair.0 == @sm.Opening {
      found = pair.1
    }
  }
  assert_eq(found, 1)
}

///|
test "continuations lists each position once" {
  let out = @backend.continuations(@sm.Standing, 3)
  for i in 0..<out.length() {
    for j in (i + 1)..<out.length() {
      assert_true(
        out[i].0 != out[j].0 || out[i].1 != out[j].1,
        msg="continuations repeats \{out[i].0.en_label()}",
      )
    }
  }
}

///|
/// Domain properties are consistent.
test "letter, title, role are non-empty for every domain" {
  for d in @backend.ring_domains_loop() {
    assert_true(d.letter() != "")
    assert_true(d.title() != "")
    assert_true(d.role() != "")
  }
}

///|
/// LoopState::new starts at Model with empty history.
test "LoopState::new starts at Model with empty history" {
  let state = @backend.LoopState::new()
  assert_eq(state.current, @backend.Model)
  assert_eq(state.history.length(), 0)
}

///|
/// step() records a real transition and advances the cursor.
///
/// Model starts at Standing, which `only_act_exits` lists among the four
/// positions that only Action leaves. So the step must drive Act, land on
/// Freedom, and record Moved. This is the test the old loop could not have
/// passed: with CoBeing it recorded No Edge, left Standing untouched, and still
/// advanced to Data.
test "step() moves Model off its anchor on the first step" {
  let state = @backend.LoopState::new()
  let stepped = state.step()
  assert_eq(stepped.history.length(), 1)
  let event = stepped.history[0]
  assert_eq(event.domain, @backend.Model)
  assert_eq(event.slot, @sm.Act)
  assert_eq(event.outcome_label, "Moved")
  assert_eq(event.position_designation, "Standing")
  // The cursor moved on, and Model itself actually went somewhere.
  assert_eq(stepped.current, @backend.Data)
  assert_eq(stepped.domain_state(@backend.Model).position, @sm.Freedom)
}

///|
/// Five steps complete one full ring and return to Model.
test "five steps complete one full ring" {
  let mut state = @backend.LoopState::new()
  for _ in 0..<5 {
    state = state.step()
  }
  assert_eq(state.current, @backend.Model)
  assert_eq(state.history.length(), 5)
}

///|
/// History records the domain that was left, not the one arrived at.
test "history records the departing domain" {
  let state = @backend.LoopState::new()
  let stepped = state.step()
  // We started at Model and stepped to Data; the history records Model.
  assert_eq(stepped.history[0].domain, @backend.Model)
  assert_eq(stepped.current, @backend.Data)
}

///|
/// step_with_slot() stays put when outcome has no landing (Block).
test "step_with_slot stays put on Block outcome" {
  let state = @backend.LoopState::new()
  // Model/Standing with CoBeing returns Block, which has no landing.
  let stepped = state.step_with_slot(@sm.CoBeing)
  assert_eq(stepped.current, @backend.Model)
  assert_eq(stepped.history.length(), 1)
  assert_eq(stepped.history[0].outcome_label, "No Edge")
}

///|
/// Module-level step_loop() mutates global state.
test "step_loop advances the global state" {
  @backend.reset_loop() |> ignore
  let s1 = @backend.step_loop()
  assert_eq(s1.current, @backend.Data)
  let s2 = @backend.get_loop_state()
  assert_eq(s2.current, @backend.Data)
  assert_eq(s2.history.length(), 1)
  @backend.reset_loop() |> ignore
}

///|
/// reset_loop() returns to Model with empty history.
test "reset_loop returns to initial state" {
  @backend.reset_loop() |> ignore
  @backend.step_loop() |> ignore
  @backend.step_loop() |> ignore
  let state = @backend.reset_loop()
  assert_eq(state.current, @backend.Model)
  assert_eq(state.history.length(), 0)
  assert_eq(@backend.get_loop_state().current, @backend.Model)
}

///|
/// to_json has the shape the frontend decodes.
test "to_json contains all required fields" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("current_domain") is Some(_))
      assert_true(fields.get("current_title") is Some(_))
      assert_true(fields.get("current_position") is Some(_))
      assert_true(fields.get("current_position_label") is Some(_))
      assert_true(fields.get("current_gloss") is Some(_))
      assert_true(fields.get("next_domain") is Some(_))
      assert_true(fields.get("drive_slot") is Some(_))
      assert_true(fields.get("history_length") is Some(_))
      assert_true(fields.get("history") is Some(_))
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// to_json current_domain matches the domain letter.
test "to_json current_domain is the letter, not the title" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) =>
      match fields.get("current_domain") {
        Some(String(s)) => assert_eq(s, "M")
        _ => fail("current_domain is not a string")
      }
    _ => fail("to_json did not return an object")
  }
}

///|
/// to_json history is an empty array for a fresh state.
test "to_json history is empty for fresh state" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) => {
      match fields.get("history") {
        Some(Array(items)) => assert_eq(items.length(), 0)
        _ => fail("history is not an array")
      }
      match fields.get("history_length") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
        _ => fail("history_length is not a number")
      }
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// to_json history_length matches the actual history array length.
test "to_json history_length matches history array length after steps" {
  let mut state = @backend.LoopState::new()
  for _ in 0..<3 {
    state = state.step()
  }
  let json = state.to_json()
  match json {
    Object(fields) => {
      let length = match fields.get("history_length") {
        Some(Number(n, ..)) => n.to_int()
        _ => -1
      }
      let array_len = match fields.get("history") {
        Some(Array(items)) => items.length()
        _ => -1
      }
      assert_eq(length, array_len)
      assert_eq(length, 3)
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// A Block records which position had no edge, and leaves the cursor alone.
///
/// Uses an explicit non-exitable slot rather than the default drive, because
/// Standing now has a working drive and no longer produces a Block on its own.
test "Block outcome_detail mentions the position" {
  let state = @backend.LoopState::new()
  // Standing has no Co-being edge; asking for it must report the gap, not move.
  let stepped = state.step_with_slot(@sm.CoBeing)
  let event = stepped.history[0]
  assert_eq(event.outcome_label, "No Edge")
  assert_true(event.outcome_detail.contains("Standing"))
  // Nothing moved, so the cursor stays on the domain that could not move.
  assert_eq(stepped.current, @backend.Model)
  assert_eq(stepped.domain_state(@backend.Model).position, @sm.Standing)
}

///|
/// Eq on Domain works correctly.
test "Domain equality" {
  assert_eq(@backend.Model, @backend.Model)
  assert_true(@backend.Model != @backend.Data)
}

///|
/// Eq on LoopState works correctly.
test "LoopState equality" {
  let a = @backend.LoopState::new()
  let b = @backend.LoopState::new()
  assert_true(a == b)
  let c = a.step()
  assert_true(a != c)
}

///|
/// slot_from_designation parses all eight slot designations correctly.
test "slot_from_designation parses all eight slots" {
  assert_true(@backend.slot_from_designation("Occasion") is Some(@sm.Occasion))
  assert_true(
    @backend.slot_from_designation("Orientation") is Some(@sm.Orientation),
  )
  assert_true(
    @backend.slot_from_designation("Anticipation") is Some(@sm.Antecedent),
  )
  assert_true(@backend.slot_from_designation("Action") is Some(@sm.Act))
  assert_true(@backend.slot_from_designation("Feedback") is Some(@sm.Feedback))
  assert_true(@backend.slot_from_designation("Holding") is Some(@sm.Hold))
  assert_true(@backend.slot_from_designation("Co-being") is Some(@sm.CoBeing))
  assert_true(@backend.slot_from_designation("Unveiling") is Some(@sm.Unveil))
}

///|
/// slot_from_designation returns None for unknown strings.
test "slot_from_designation returns None for unknown input" {
  assert_true(@backend.slot_from_designation("") is None)
  assert_true(@backend.slot_from_designation("unknown") is None)
  assert_true(@backend.slot_from_designation("CoBeing") is None)
}

///|
/// slot_from_designation round-trips with Slot::en_designation for all slots.
test "slot_from_designation round-trips with designation" {
  for slot in @sm.all_slots() {
    let designation = slot.en_designation()
    match @backend.slot_from_designation(designation) {
      Some(parsed) => assert_eq(parsed, slot)
      None => fail("slot_from_designation returned None for \{designation}")
    }
  }
}

///|
/// all_slots_info returns eight entries with non-empty fields.
///
/// The entry is (english_name, designation, gloss). There is no `source` field:
/// pyroduct's source quote is Chinese source-layer text with no English form,
/// and inventing one would break the traceability it exists for.
test "all_slots_info returns eight entries" {
  let info = @backend.all_slots_info()
  assert_eq(info.length(), 8)
  for (english, designation, gloss) in info {
    assert_true(english != "")
    assert_true(designation != "")
    assert_true(gloss != "")
  }
}

///|
/// slot_from_english parses all eight English names.
test "slot_from_english parses all eight names" {
  assert_true(@backend.slot_from_english("occasion") is Some(@sm.Occasion))
  assert_true(
    @backend.slot_from_english("orientation") is Some(@sm.Orientation),
  )
  assert_true(@backend.slot_from_english("antecedent") is Some(@sm.Antecedent))
  assert_true(@backend.slot_from_english("act") is Some(@sm.Act))
  assert_true(@backend.slot_from_english("feedback") is Some(@sm.Feedback))
  assert_true(@backend.slot_from_english("hold") is Some(@sm.Hold))
  assert_true(@backend.slot_from_english("cobeing") is Some(@sm.CoBeing))
  assert_true(@backend.slot_from_english("unveil") is Some(@sm.Unveil))
}

///|
/// slot_from_english returns None for unknown names.
test "slot_from_english returns None for unknown" {
  assert_true(@backend.slot_from_english("") is None)
  assert_true(@backend.slot_from_english("unknown") is None)
}

///|
/// Slot::english_name round-trips with slot_from_english.
test "english_name round-trips with slot_from_english" {
  for slot in @sm.all_slots() {
    let name = @backend.slot_english_name(slot)
    match @backend.slot_from_english(name) {
      Some(parsed) => assert_eq(parsed, slot)
      None => fail("slot_from_english returned None for \{name}")
    }
  }
}
