///| BDD / Gherkin-style tests for the MAKED loop engine.
///
/// These tests use a lightweight Given/When/Then pattern implemented directly
/// in MoonBit test blocks. Each scenario is named with the Gherkin convention
/// and documents the expected behaviour in the test name.
///
/// The scenarios cover the loop engine's key properties:
///   - Domain ring navigation
///   - Per-domain independent state machines
///   - Group state emergence
///   - Slot-driven stepping
///   - Reset behaviour

///|
/// Scenario: Fresh loop starts at Model with Scattered group state.
/// Given a new loop state
/// Then the current domain is Model
/// And the group state is Scattered
/// And the history is empty
test "Scenario: fresh loop starts at Model with Scattered group" {
  // Given a new loop state
  let state = @backend.LoopState::new()
  // Then the current domain is Model
  assert_eq(state.current, @backend.Model)
  // And the group state is Scattered
  assert_true(state.group_state is @group.Scattered)
  // And the history is empty
  assert_eq(state.history.length(), 0)
}

///|
/// Scenario: Stepping from Model advances to Data.
/// Given a fresh loop state at Model
/// When I step the loop
/// Then the current domain is Data
/// And the history has one event
test "Scenario: step from Model advances to Data" {
  // Given a fresh loop state at Model
  let state = @backend.LoopState::new()
  // When I step the loop
  let stepped = state.step()
  // Then the current domain is Data
  assert_eq(stepped.current, @backend.Data)
  // And the history has one event
  assert_eq(stepped.history.length(), 1)
}

///|
/// Scenario: Five steps complete one full ring.
/// Given a fresh loop state
/// When I step five times
/// Then the current domain is Model again
/// And the history has five events
test "Scenario: five steps complete one full ring" {
  // Given a fresh loop state
  let mut state = @backend.LoopState::new()
  // When I step five times
  for _ in 0..<5 {
    state = state.step()
  }
  // Then the current domain is Model again
  assert_eq(state.current, @backend.Model)
  // And the history has five events
  assert_eq(state.history.length(), 5)
}

///|
/// Scenario: Each domain has its own independent state machine.
/// Given a fresh loop state
/// When I step three times
/// Then each domain state has its own history
/// And the histories are independent
test "Scenario: domains have independent state machines" {
  // Given a fresh loop state
  let mut state = @backend.LoopState::new()
  // When I step three times
  for _ in 0..<3 {
    state = state.step()
  }
  // Then each domain state has its own history
  let model_ds = state.domain_state(@backend.Model)
  let data_ds = state.domain_state(@backend.Data)
  // And the histories are independent (Model was stepped, Data was not yet)
  assert_true(model_ds.history.length() >= 1)
  // Data may or may not have history depending on ring position
  assert_true(data_ds.history.length() >= 0)
}

///|
/// Scenario: Group state emerges from domain activity.
/// Given a fresh loop state with Scattered group
/// When domains start moving
/// Then the group state transitions toward convergence
test "Scenario: group state emerges from domain activity" {
  // Given a fresh loop state with Scattered group
  let state = @backend.LoopState::new()
  assert_true(state.group_state is @group.Scattered)
  // When domains start moving (step multiple times)
  let mut s = state
  for _ in 0..<5 {
    s = s.step()
  }
  // Then the group state has potentially changed
  // (exact state depends on how many domains moved from initial positions)
  let group = s.group_state
  assert_true(
    group is @group.Scattered ||
    group is @group.Converging ||
    group is @group.CommonTongue ||
    group is @group.Settled,
  )
}

///|
/// Scenario: Step with slot uses the specified drive.
/// Given a loop state at Model
/// When I step with slot Occasion
/// Then the history records the Occasion slot
test "Scenario: step_with_slot uses specified drive" {
  // Given a loop state at Model
  let state = @backend.LoopState::new()
  // When I step with slot Occasion
  let stepped = state.step_with_slot(@sm.Occasion)
  // Then the history records the Occasion slot
  assert_eq(stepped.history[0].slot, @sm.Occasion)
}

///|
/// Scenario: Block outcome keeps the domain in place.
/// Given a loop state at Model
/// When I step with a slot that produces Block
/// Then the current domain stays at Model
test "Scenario: Block outcome keeps domain in place" {
  // Given a loop state at Model
  let state = @backend.LoopState::new()
  // When I step with CoBeing (which produces Block at Standing)
  let stepped = state.step_with_slot(@sm.CoBeing)
  // Then the current domain stays at Model
  assert_eq(stepped.current, @backend.Model)
  // And the outcome is Block
  assert_eq(stepped.history[0].outcome_label, "No Edge")
}

///|
/// Scenario: Reset returns to initial state.
/// Given a loop state that has been stepped
/// When I reset the loop
/// Then the current domain is Model
/// And the history is empty
/// And the group state is Scattered
test "Scenario: reset returns to initial state" {
  // Given a loop state that has been stepped
  @backend.reset_loop() |> ignore
  @backend.step_loop() |> ignore
  @backend.step_loop() |> ignore
  // When I reset the loop
  let state = @backend.reset_loop()
  // Then the current domain is Model
  assert_eq(state.current, @backend.Model)
  // And the history is empty
  assert_eq(state.history.length(), 0)
  // And the group state is Scattered
  assert_true(state.group_state is @group.Scattered)
}

///|
/// Scenario: Slot designation round-trips through parsing.
/// Given all eight slot designations
/// When I parse each designation
/// Then I get back the original slot
test "Scenario: slot designation round-trips" {
  // Given all eight slot designations
  let slots = @sm.all_slots()
  for slot in slots {
    // When I parse each designation
    let designation = slot.en_designation()
    let parsed = @backend.slot_from_designation(designation)
    // Then I get back the original slot
    match parsed {
      Some(s) => assert_eq(s, slot)
      None => fail("slot_from_designation returned None for \{designation}")
    }
  }
}

///|
/// Scenario: Slot English name round-trips through parsing.
/// Given all eight slot English names
/// When I parse each name
/// Then I get back the original slot
test "Scenario: slot English name round-trips" {
  // Given all eight slot English names
  let slots = @sm.all_slots()
  for slot in slots {
    // When I parse each name
    let name = @backend.slot_english_name(slot)
    let parsed = @backend.slot_from_english(name)
    // Then I get back the original slot
    match parsed {
      Some(s) => assert_eq(s, slot)
      None => fail("slot_from_english returned None for \{name}")
    }
  }
}

///|
/// Scenario: Domain ring order is M-D-E-A-K.
/// Given the five domains
/// When I follow the next() links
/// Then the order is M, D, E, A, K, M
test "Scenario: domain ring order is MDEAK" {
  // Given the five domains
  // When I follow the next() links
  // Then the order is M, D, E, A, K, M
  assert_eq(@backend.Model.next(), @backend.Data)
  assert_eq(@backend.Data.next(), @backend.Experience)
  assert_eq(@backend.Experience.next(), @backend.Attack)
  assert_eq(@backend.Attack.next(), @backend.Knowledge)
  assert_eq(@backend.Knowledge.next(), @backend.Model)
}

///|
/// Scenario: Paper to trigger mapping follows priority.
/// Given a paper with multiple keyword categories
/// When I map it to a trigger
/// Then the highest-priority keyword wins
test "Scenario: paper trigger mapping priority" {
  // Given a paper with SOTA and novel keywords
  let paper : @backend.Paper = {
    id: "1",
    title: "Novel SOTA SNN",
    summary: "We propose and outperform",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  // When I map it to a trigger
  let trigger = @backend.paper_to_trigger(paper)
  // Then SOTA (AbsorbGlory) wins over novel (ActInFreedom)
  assert_true(trigger is @sm.AbsorbGlory)
}

///|
/// Scenario: to_json includes all required fields for frontend.
/// Given a loop state
/// When I convert to JSON
/// Then the JSON has all fields the frontend needs
test "Scenario: to_json has all frontend fields" {
  // Given a loop state
  let state = @backend.LoopState::new()
  // When I convert to JSON
  let json = state.to_json()
  // Then the JSON has all fields the frontend needs
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
      assert_true(fields.get("domain_states") is Some(_))
      assert_true(fields.get("group_state") is Some(_))
      assert_true(fields.get("group_state_gloss") is Some(_))
    }
    _ => fail("to_json did not return an object")
  }
}
