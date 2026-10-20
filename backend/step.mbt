///| Taking a step, once, for everybody.
///
/// The web panel and the agent's tools both move the loop, and they have to
/// move it the same way: the same slot is parsed the same way, the same
/// target is accepted the same way, and the same step is recorded the same
/// way. Two copies of "what a step does" is two things to keep in step with
/// each other, and the one that drifts is the one nobody is looking at.
///
/// So the step lives here, and the API route and the agent's tools are both
/// callers of it. A refusal is a refusal in both: the same reason, and the
/// same list of the targets that were really on offer.

///|
/// The answer to a request to move the loop.
pub(all) enum StepAnswer {
  /// The step was taken. The payload is the loop status with the session
  /// state folded in -- the same body the API route answers with.
  Taken(Json)
  /// The slot is not one the model has.
  UnknownSlot(String)
  /// The target is not one the table offers from here. The names are the
  /// ones it does offer, so a caller who asked for the wrong one can see
  /// the right one instead of watching nothing happen.
  UnknownTarget(String, Array[String])
}

///|
/// Take a step with the slot the table drives with here.
///
/// The table's own choice, which is the one a reader gets by pressing
/// "Step". The step is recorded as a table-driven one, so the history says
/// the table chose it rather than the reader.
///
/// The answer is the payload and not a `StepAnswer`, because there is
/// nothing here to get wrong: the table has an opinion about this position
/// and this is it. A step the caller names a slot for can be refused; this
/// one cannot.
pub fn take_drive_step(db : Database, lang : Lang) -> Json raise {
  let before = get_loop_state()
  let after = step_loop()
  record_step(db, before, after, "drive")
  loop_payload(db, lang)
}

///|
/// Take a step with the slot the caller named.
///
/// The slot may be the model's own id ("act") or the designation a reader
/// saw ("Action"), case-insensitively: the caller may hold either, and a
/// caller that holds the wrong one is refused by name rather than left
/// wondering.
///
/// A target means the caller chose one of the successors the table offered
/// and declined to pick. An empty target means they did not, and the step
/// goes with the slot alone.
pub fn take_slot_step(
  db : Database,
  slot_name : String,
  target : String,
  lang : Lang,
) -> StepAnswer raise {
  let parsed = match slot_from_english(slot_name) {
    Some(s) => Some(s)
    None => slot_from_designation(slot_name)
  }
  match parsed {
    None => UnknownSlot(slot_name)
    Some(slot) => {
      let before = get_loop_state()
      if target == "" {
        let after = step_loop_with_slot(slot)
        record_step(db, before, after, "explicit")
        Taken(loop_payload(db, lang))
      } else {
        let position = before.domain_state(before.current).position
        let candidates = open_candidates_of(before.model, position, slot)
        match candidate_named_of(before.model, candidates, target) {
          Some(_) => {
            let after = step_loop_with_target(slot, target)
            record_step(db, before, after, "explicit")
            Taken(loop_payload(db, lang))
          }
          None =>
            UnknownTarget(target, candidate_names_of(before.model, candidates))
        }
      }
    }
  }
}

///|
/// The names of the successors the table offers from here and declined to
/// choose between.
///
/// This is the way out of a position the machine cannot decide for itself,
/// so it is asked for by name rather than guessed at. Empty when the table
/// has an opinion, and empty when the slot has no road out at all -- the
/// two are told apart by whether the slot appears in the options at all.
pub fn open_candidate_names(slot : String) -> Array[String] {
  let state = get_loop_state()
  let position = state.domain_state(state.current).position
  candidate_names_of(
    state.model,
    open_candidates_of(state.model, position, slot),
  )
}
