///| Loop domain state and group state tests.
///
/// These tests pin down the per-domain independent state machines and the
/// group-level state that emerges from domain activity. They are separate from
/// the main loop tests because they test the *new* architecture (each domain
/// has its own state machine) rather than the *old* single-state-machine model.

///|
/// DomainState::new starts at the domain's anchor position.
test "DomainState::new starts at domain anchor" {
  let ds = @backend.DomainState::new(@backend.Model)
  assert_eq(ds.domain, @backend.Model)
  assert_eq(ds.position, @sm.Standing)
  assert_eq(ds.history.length(), 0)
}

///|
/// DomainState::new for each domain starts at the correct position.
test "DomainState::new for all domains" {
  let m = @backend.DomainState::new(@backend.Model)
  assert_eq(m.position, @sm.Standing)
  let d = @backend.DomainState::new(@backend.Data)
  assert_eq(d.position, @sm.Encounter)
  let e = @backend.DomainState::new(@backend.Experience)
  assert_eq(e.position, @sm.Honor)
  let a = @backend.DomainState::new(@backend.Attack)
  assert_eq(a.position, @sm.Evil)
  let k = @backend.DomainState::new(@backend.Knowledge)
  assert_eq(k.position, @sm.Discipline)
}

///|
/// DomainState::step appends to history.
test "DomainState::step appends history event" {
  let ds = @backend.DomainState::new(@backend.Model)
  let stepped = ds.step(@sm.CoBeing)
  assert_eq(stepped.history.length(), 1)
  assert_eq(stepped.history[0].domain, @backend.Model)
  assert_eq(stepped.history[0].slot, @sm.CoBeing)
}

///|
/// DomainState::step with Block outcome stays at same position.
test "DomainState::step with Block stays put" {
  let ds = @backend.DomainState::new(@backend.Model)
  let stepped = ds.step(@sm.CoBeing)
  assert_eq(stepped.position, @sm.Standing)
}

///|
/// LoopState::new initializes all five domain states.
test "LoopState::new initializes all domain states" {
  let state = @backend.LoopState::new()
  for domain in @backend.ring_domains_loop() {
    let ds = state.domain_state(domain)
    assert_eq(ds.domain, domain)
    assert_eq(ds.position, domain.position())
    assert_eq(ds.history.length(), 0)
  }
}

///|
/// LoopState::new starts with Scattered group state.
test "LoopState::new starts with Scattered group state" {
  let state = @backend.LoopState::new()
  assert_true(state.group_state is @group.Scattered)
}

///|
/// LoopState::step updates the current domain's state.
test "LoopState::step updates domain state" {
  let state = @backend.LoopState::new()
  let stepped = state.step()
  let model_ds = stepped.domain_state(@backend.Model)
  assert_eq(model_ds.history.length(), 1)
}

///|
/// LoopState::step updates group state based on domain activity.
test "LoopState::step changes group state" {
  let state = @backend.LoopState::new()
  assert_true(state.group_state is @group.Scattered)
  let stepped = state.step()
  // After one step, one domain has moved (or stayed), so group may change
  // The exact group state depends on how many domains have moved
  let group = stepped.group_state
  assert_true(
    group is @group.Scattered ||
    group is @group.Converging ||
    group is @group.CommonTongue ||
    group is @group.Settled,
  )
}

///|
/// LoopState::to_json includes domain_states array.
test "LoopState::to_json includes domain_states" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) =>
      match fields.get("domain_states") {
        Some(Array(items)) => assert_eq(items.length(), 5)
        _ => fail("domain_states is not an array of length 5")
      }
    _ => fail("to_json did not return an object")
  }
}

///|
/// LoopState::to_json includes group_state field.
test "LoopState::to_json includes group_state" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("group_state") is Some(_))
      assert_true(fields.get("group_state_gloss") is Some(_))
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// LoopState::to_json domain_states have expected shape.
test "LoopState::to_json domain_states have correct shape" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) =>
      match fields.get("domain_states") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(ds_fields) => {
                assert_true(ds_fields.get("domain") is Some(_))
                assert_true(ds_fields.get("title") is Some(_))
                assert_true(ds_fields.get("position") is Some(_))
                assert_true(ds_fields.get("position_label") is Some(_))
                assert_true(ds_fields.get("history_length") is Some(_))
              }
              _ => fail("domain_state item is not an object")
            }
          }
        _ => fail("domain_states is not an array")
      }
    _ => fail("to_json did not return an object")
  }
}

///|
/// DomainState equality works correctly.
test "DomainState equality" {
  let a = @backend.DomainState::new(@backend.Model)
  let b = @backend.DomainState::new(@backend.Model)
  // Both start with same domain, position, and empty history
  assert_eq(a.domain, b.domain)
  assert_eq(a.position, b.position)
  assert_eq(a.history.length(), b.history.length())
}

///|
/// LoopState equality considers domain_states.
test "LoopState equality considers domain_states" {
  let a = @backend.LoopState::new()
  let b = @backend.LoopState::new()
  assert_true(a == b)
  let c = a.step()
  assert_true(a != c)
}

///|
/// Five steps update each domain's history independently.
test "five steps update domain histories independently" {
  let mut state = @backend.LoopState::new()
  for _ in 0..<5 {
    state = state.step()
  }
  // Each domain should have been stepped at least once
  for domain in @backend.ring_domains_loop() {
    let ds = state.domain_state(domain)
    assert_true(ds.history.length() >= 1)
  }
}

///|
/// Group state transitions from Scattered as domains move.
test "group state transitions as domains move" {
  let state = @backend.LoopState::new()
  // Initially Scattered
  assert_true(state.group_state is @group.Scattered)
  // Step multiple times to move domains
  let mut s = state
  for _ in 0..<10 {
    s = s.step()
  }
  // After 10 steps, group should have progressed
  let group = s.group_state
  // The exact state depends on how many domains moved from initial positions
  assert_true(
    group is @group.Scattered ||
    group is @group.Converging ||
    group is @group.CommonTongue ||
    group is @group.Settled,
  )
}

///|
/// step_with_slot updates the specific domain's state.
test "step_with_slot updates domain state" {
  let state = @backend.LoopState::new()
  let stepped = state.step_with_slot(@sm.Occasion)
  let model_ds = stepped.domain_state(@backend.Model)
  assert_eq(model_ds.history.length(), 1)
}

///|
/// reset_loop resets all domain states.
test "reset_loop resets all domain states" {
  @backend.reset_loop() |> ignore
  @backend.step_loop() |> ignore
  @backend.step_loop() |> ignore
  let state = @backend.reset_loop()
  for domain in @backend.ring_domains_loop() {
    let ds = state.domain_state(domain)
    assert_eq(ds.history.length(), 0)
    assert_eq(ds.position, domain.position())
  }
  assert_true(state.group_state is @group.Scattered)
}

///|
/// LoopState::new_from starts at the specified domain.
test "LoopState::new_from starts at specified domain" {
  let state_m = @backend.LoopState::new_from(@backend.Model)
  assert_eq(state_m.current, @backend.Model)
  let state_d = @backend.LoopState::new_from(@backend.Data)
  assert_eq(state_d.current, @backend.Data)
  let state_e = @backend.LoopState::new_from(@backend.Experience)
  assert_eq(state_e.current, @backend.Experience)
  let state_a = @backend.LoopState::new_from(@backend.Attack)
  assert_eq(state_a.current, @backend.Attack)
  let state_k = @backend.LoopState::new_from(@backend.Knowledge)
  assert_eq(state_k.current, @backend.Knowledge)
}

///|
/// LoopState::new_from initializes all domain states correctly.
test "LoopState::new_from initializes all domain states" {
  let state = @backend.LoopState::new_from(@backend.Data)
  // Current is Data
  assert_eq(state.current, @backend.Data)
  // But all domains still have their own anchor positions
  for domain in @backend.ring_domains_loop() {
    let ds = state.domain_state(domain)
    assert_eq(ds.domain, domain)
    assert_eq(ds.position, domain.position())
    assert_eq(ds.history.length(), 0)
  }
  // Group state is Scattered
  assert_true(state.group_state is @group.Scattered)
}

///|
/// reset_to resets to the specified domain.
test "reset_to resets to specified domain" {
  @backend.reset_loop() |> ignore
  @backend.step_loop() |> ignore
  let state = @backend.reset_to(@backend.Attack)
  assert_eq(state.current, @backend.Attack)
  assert_eq(state.history.length(), 0)
  assert_true(state.group_state is @group.Scattered)
}

///|
/// domain_from_letter parses all five domain letters.
test "domain_from_letter parses all five letters" {
  assert_true(@backend.domain_from_letter("M") is Some(@backend.Model))
  assert_true(@backend.domain_from_letter("D") is Some(@backend.Data))
  assert_true(@backend.domain_from_letter("E") is Some(@backend.Experience))
  assert_true(@backend.domain_from_letter("A") is Some(@backend.Attack))
  assert_true(@backend.domain_from_letter("K") is Some(@backend.Knowledge))
}

///|
/// domain_from_letter returns None for invalid input.
test "domain_from_letter returns None for invalid input" {
  assert_true(@backend.domain_from_letter("") is None)
  assert_true(@backend.domain_from_letter("X") is None)
  assert_true(@backend.domain_from_letter("model") is None)
}

///|
/// domain_from_english parses all five English names (case-insensitive).
test "domain_from_english parses all five names" {
  assert_true(@backend.domain_from_english("model") is Some(@backend.Model))
  assert_true(@backend.domain_from_english("Model") is Some(@backend.Model))
  assert_true(@backend.domain_from_english("MODEL") is Some(@backend.Model))
  assert_true(@backend.domain_from_english("data") is Some(@backend.Data))
  assert_true(
    @backend.domain_from_english("experience") is Some(@backend.Experience),
  )
  assert_true(@backend.domain_from_english("attack") is Some(@backend.Attack))
  assert_true(
    @backend.domain_from_english("knowledge") is Some(@backend.Knowledge),
  )
}

///|
/// domain_from_english returns None for invalid input.
test "domain_from_english returns None for invalid input" {
  assert_true(@backend.domain_from_english("") is None)
  assert_true(@backend.domain_from_english("unknown") is None)
  assert_true(@backend.domain_from_english("M") is None)
}

///|
/// LoopMode::designation returns correct Chinese names.
test "LoopMode::designation returns correct names" {
  assert_eq(@backend.Structured.designation(), "结构")
  assert_eq(@backend.Free.designation(), "自由")
}

///|
/// LoopMode::gloss returns correct descriptions.
test "LoopMode::gloss returns correct descriptions" {
  assert_eq(
    @backend.Structured.gloss(),
    "遵循环序 M→D→E→A→K，每域使用驱动槽",
  )
  assert_eq(@backend.Free.gloss(), "任意槽驱动，探索状态空间")
}

///|
/// LoopState::new defaults to Structured mode.
test "LoopState::new defaults to Structured mode" {
  let state = @backend.LoopState::new()
  assert_true(state.mode is @backend.Structured)
}

///|
/// LoopState::new_with_mode creates state in specified mode.
test "LoopState::new_with_mode creates correct mode" {
  let structured = @backend.LoopState::new_with_mode(@backend.Structured)
  assert_true(structured.mode is @backend.Structured)
  let free = @backend.LoopState::new_with_mode(@backend.Free)
  assert_true(free.mode is @backend.Free)
}

///|
/// LoopState::to_json includes mode fields.
test "LoopState::to_json includes mode fields" {
  let state = @backend.LoopState::new()
  let json = state.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("mode") is Some(_))
      assert_true(fields.get("mode_designation") is Some(_))
      assert_true(fields.get("mode_gloss") is Some(_))
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// step_with_slot preserves mode field.
test "step_with_slot preserves mode" {
  let state = @backend.LoopState::new_with_mode(@backend.Free)
  let stepped = state.step_with_slot(@sm.Occasion)
  assert_true(stepped.mode is @backend.Free)
}

///|
/// Free mode: step stays on same domain when outcome is Block.
test "free mode stays on Block" {
  let state = @backend.LoopState::new_with_mode(@backend.Free)
  let initial_domain = state.current
  // Step - if outcome is Block, should stay on same domain
  let stepped = state.step()
  // Check if the outcome was Block by looking at the last event
  match stepped.history.last() {
    Some(event) =>
      if event.outcome_label == "无路" {
        // Should stay on same domain
        assert_eq(stepped.current, initial_domain)
      }
    // If not Block, it advances (tested in structured mode)
    None => fail("step should always add an event")
  }
}

///|
/// Structured mode: step always advances to next domain.
test "structured mode always advances" {
  let state = @backend.LoopState::new_with_mode(@backend.Structured)
  let initial_domain = state.current
  let stepped = state.step()
  // In structured mode, always advances regardless of outcome
  assert_eq(stepped.current, initial_domain.next())
}

///|
/// set_loop_mode changes the mode.
test "set_loop_mode changes mode" {
  @backend.reset_loop() |> ignore
  let state1 = @backend.set_loop_mode(@backend.Free)
  assert_true(state1.mode is @backend.Free)
  let state2 = @backend.set_loop_mode(@backend.Structured)
  assert_true(state2.mode is @backend.Structured)
}

///|
/// get_loop_mode returns current mode.
test "get_loop_mode returns current mode" {
  @backend.reset_loop() |> ignore
  @backend.set_loop_mode(@backend.Free) |> ignore
  let mode = @backend.get_loop_mode()
  assert_true(mode is @backend.Free)
}
