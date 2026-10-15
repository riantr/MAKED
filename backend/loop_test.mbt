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
/// All five domain-anchor positions return Block("无路") for their default
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
/// Each domain maps to the expected drive slot.
test "slot_to_next maps each domain to its drive slot" {
  assert_eq(@backend.Model.slot_to_next(), @sm.CoBeing)
  assert_eq(@backend.Data.slot_to_next(), @sm.Feedback)
  assert_eq(@backend.Experience.slot_to_next(), @sm.Unveil)
  assert_eq(@backend.Attack.slot_to_next(), @sm.Hold)
  assert_eq(@backend.Knowledge.slot_to_next(), @sm.Orientation)
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
/// step() advances the domain and appends one history event.
test "step() advances domain and appends history" {
  let state = @backend.LoopState::new()
  let stepped = state.step()
  assert_eq(stepped.current, @backend.Data)
  assert_eq(stepped.history.length(), 1)
  let event = stepped.history[0]
  assert_eq(event.domain, @backend.Model)
  assert_eq(event.slot, @sm.CoBeing)
  assert_eq(event.outcome_label, "无路")
  assert_eq(event.position_designation, "立位")
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
  assert_eq(stepped.history[0].outcome_label, "无路")
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
/// Each step's outcome_detail for Block contains the position designation.
test "Block outcome_detail mentions the position" {
  let state = @backend.LoopState::new()
  let stepped = state.step()
  let detail = stepped.history[0].outcome_detail
  assert_true(detail.contains("立位"))
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
  assert_true(@backend.slot_from_designation("处境") is Some(@sm.Occasion))
  assert_true(@backend.slot_from_designation("取向") is Some(@sm.Orientation))
  assert_true(@backend.slot_from_designation("先行") is Some(@sm.Antecedent))
  assert_true(@backend.slot_from_designation("行动") is Some(@sm.Act))
  assert_true(@backend.slot_from_designation("反馈") is Some(@sm.Feedback))
  assert_true(@backend.slot_from_designation("持存") is Some(@sm.Hold))
  assert_true(@backend.slot_from_designation("共在") is Some(@sm.CoBeing))
  assert_true(@backend.slot_from_designation("揭蔽") is Some(@sm.Unveil))
}

///|
/// slot_from_designation returns None for unknown strings.
test "slot_from_designation returns None for unknown input" {
  assert_true(@backend.slot_from_designation("") is None)
  assert_true(@backend.slot_from_designation("未知") is None)
  assert_true(@backend.slot_from_designation("CoBeing") is None)
}

///|
/// slot_from_designation round-trips with Slot::designation for all slots.
test "slot_from_designation round-trips with designation" {
  for slot in @sm.all_slots() {
    let designation = slot.designation()
    match @backend.slot_from_designation(designation) {
      Some(parsed) => assert_eq(parsed, slot)
      None => fail("slot_from_designation returned None for \{designation}")
    }
  }
}

///|
/// all_slots_info returns eight entries with non-empty fields.
test "all_slots_info returns eight entries" {
  let info = @backend.all_slots_info()
  assert_eq(info.length(), 8)
  for (english, designation, gloss, source) in info {
    assert_true(english != "")
    assert_true(designation != "")
    assert_true(gloss != "")
    assert_true(source != "")
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
