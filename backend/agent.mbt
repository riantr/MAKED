///| The agent's view of the loop: what happened, and what it means.
///
/// A person reads the loop panel. An agent reads this. The difference is
/// what each of them needs first: a person wants the position and a button
/// to press, and an agent wants to know what the last move did in words it
/// can reason about, and what it may do next.
///
/// The raw loop status is not that. It is a map of ids -- "M", "Action",
/// "Undecided" -- and an agent that has to reconstruct the meaning from the
/// ids is an agent that guesses. So the sentences are written here, on the
/// server, where the model and the history both are, and the ids travel
/// beside the sentences for the agent that wants to be exact.
///
/// Nothing here is a second source of truth: every sentence is built from
/// the same model, the same transition table and the same recorded steps the
/// panel is built from.

///|
/// A list of strings, as a JSON array of strings.
///
/// The backend's other string lists are arrays of one-element arrays, which
/// is the shape the browser's decoder expects. An agent reads JSON, not the
/// browser, and an array of one-element arrays is a shape it has to know
/// about before it can read the list at all.
fn agent_strings(names : Array[String]) -> Json {
  let items : Array[Json] = []
  for name in names {
    items.push(Json::string(name))
  }
  Json::array(items)
}

///|
/// The steps on the active session's current path, oldest first.
///
/// The path is the run of steps that leads to where the loop stands now, as
/// opposed to the steps that were walked and then walked back from.
fn active_path(db : Database) -> Array[SessionStep] raise {
  let session = match db.session_by_id(active_session_id()) {
    Some(s) => s
    None => return []
  }
  chain_to_step(db.steps_of_session(session.id), session.head_step_id)
}

///|
/// The last step of the active path, if there is one.
fn last_step(path : Array[SessionStep]) -> SessionStep? {
  if path.length() == 0 {
    return None
  }
  Some(path[path.length() - 1])
}

///|
/// Where the loop stands: the domain, the position, the mode, the group and
/// the collective.
///
/// The ids travel beside the words, because an agent that wants to be exact
/// needs the model's own names and not only the ones the reader sees.
pub fn agent_where() -> Json {
  let state = get_loop_state()
  let model = state.model
  let domain = state.current
  let position = state.domain_state(domain).position
  let vocabulary = current_society_vocabulary()
  let society_id = society_position_id(state.society_state)
  {
    "domain": domain.letter(),
    "domain_name": domain.title(),
    "the_domain_in_words": role_of(model, domain.letter()),
    "position": position,
    "position_label": model.position_label(position),
    "position_gloss": model.position_gloss(position),
    "mode": state.mode.designation(),
    "the_group": state.group_state.en_designation(),
    "the_group_gloss": state.group_state.en_gloss(),
    "the_collective": society_position_label(vocabulary, society_id),
    "the_collective_position": society_id,
  }
}

///|
/// The state of the loop, as an agent should read it.
pub fn agent_status(db : Database) -> Json raise {
  let model = current_model()
  let path = active_path(db)
  let last_move = match last_step(path) {
    Some(step) => step_sentence(facts_of(model, step))
    None => "No step has been taken yet. The loop is standing where it starts."
  }
  {
    "where": agent_where(),
    "the_last_move": last_move,
    "the_run_so_far": summary_of(path),
    "steps_taken": path.length(),
    "the_measures": measure(path).to_json(),
    "note": "Call maked_options to see what the table offers from here, and maked_step to take one of them.",
  }
}

///|
/// What can be done from here, and what cannot.
///
/// The two lists are the same length as the model's slot vocabulary, and
/// together they are all of it. A slot that cannot move says why, because a
/// slot that is merely absent reads as a slot nobody has heard of.
pub fn agent_options(depth : Int32) -> Json {
  let state = get_loop_state()
  let model = state.model
  let position = state.domain_state(state.current).position
  let can_move : Array[Json] = []
  let cannot_move : Array[Json] = []
  let declined : Array[Json] = []
  for (name, designation, gloss) in all_slots_info() {
    let transition = model.step(position, name)
    let kind = transition.kind()
    if kind == "block" {
      cannot_move.push({
        "slot": name,
        "slot_name": designation,
        "what_the_slot_is": gloss,
        "why": "There is no \"" +
        designation +
        "\" out of " +
        model.position_label(position) +
        ".",
      })
    } else {
      let lands : Array[String] = []
      match transition {
        Moved(_, to) => lands.push(model.position_label(to))
        Held(_, to) => lands.push(model.position_label(to))
        Same(_, to) => lands.push(model.position_label(to))
        Open(candidates) =>
          for candidate in candidates {
            lands.push(model.position_label(candidate.to))
          }
        Block(_) => ()
      }
      can_move.push({
        "slot": name,
        "slot_name": designation,
        "what_the_slot_is": gloss,
        "outcome": model.outcome_label(kind),
        "outcome_kind": kind,
        "lands_at": agent_strings(lands),
      })
      if kind == "open" {
        declined.push({
          "slot": name,
          "slot_name": designation,
          "the_candidates": agent_strings(lands),
          "note": "The table offers several successors here and will not choose between them. Pass one of them to maked_step as the target.",
        })
      }
    }
  }
  let ahead : Array[Json] = []
  for (next, steps) in continuations(position, depth) {
    ahead.push({
      "position": next,
      "position_label": model.position_label(next),
      "steps_away": steps,
    })
  }
  {
    "can_move": can_move,
    "cannot_move": cannot_move,
    "the_table_declined_to_choose": declined,
    "the_machine_says_could_happen_next": ahead,
    "note": "The machine does not choose for you. Take one of the moves that can_move names, with maked_step.",
  }
}

///|
/// What a step did, in words.
///
/// The step itself is taken in `step.mbt`; this says what it came to.
pub fn agent_step_result(db : Database) -> Json raise {
  let model = current_model()
  let path = active_path(db)
  let what_happened = match last_step(path) {
    Some(step) => step_sentence(facts_of(model, step))
    None => "The step did not land anywhere the history can describe."
  }
  {
    "what_happened": what_happened,
    "where_now": agent_where(),
    "the_run_so_far": summary_of(path),
    "steps_taken": path.length(),
    "the_measures": measure(path).to_json(),
  }
}

///|
/// The machine itself, as data: the domains, the positions, the slots and
/// the rule for every pair of them.
pub fn agent_model() -> Json {
  current_model().to_json()
}

///|
/// The collective, as the agent sees it.
pub fn agent_society() -> Json {
  let vocabulary = current_society_vocabulary()
  let state = get_loop_state()
  let id = society_position_id(state.society_state)
  let moves : Array[Json] = []
  for edge in society_moves(state.society_state) {
    moves.push({
      "trigger": edge.trigger,
      "the_move": society_trigger_label(vocabulary, edge.trigger),
      "lands_at": society_position_label(vocabulary, edge.to),
    })
  }
  {
    "the_collective": society_position_label(vocabulary, id),
    "the_collective_position": id,
    "what_it_can_do_from_here": moves,
    "note": "The collective has no drive slots. It answers with the same four shapes the subject machine does: moved, held, open, block.",
  }
}

///|
/// Move the collective, and say what came of it.
///
/// The collective has no slots, so there is nothing for the machine to choose
/// for it: the caller names the move and the machine answers. A move that
/// does not exist is refused with the reason, in the same words the panel
/// uses.
pub fn agent_society_step(trigger : String) -> Json {
  let vocabulary = current_society_vocabulary()
  let before = get_loop_state()
  let from = society_position_id(before.society_state)
  let step = society_step(vocabulary, before.society_state, trigger)
  let what_happened = match step {
    Advanced(_, to) => {
      let landing = society_position_from_id(to)
      match landing {
        Some(state) => {
          set_loop_state(before.with_society_state(state))
          "The collective moved from " +
          society_position_label(vocabulary, from) +
          " to " +
          society_position_label(vocabulary, to) +
          "."
        }
        None =>
          "The collective did not move: the machine named a place that is not one of its positions."
      }
    }
    Kept(_, place) =>
      "The collective stayed where it was: " +
      society_position_label(vocabulary, place) +
      " is where that move leads."
    Undecided(_, places) => {
      let names : Array[String] = []
      for place in places {
        names.push(society_position_label(vocabulary, place))
      }
      "That move leaves the collective more than one place to be: " +
      names.join(", ") +
      "."
    }
    Refused(_, reason) => reason
  }
  { "what_happened": what_happened, "the_collective": agent_society() }
}

///|
/// The named explorations, and which one is in front of us.
pub fn agent_sessions(db : Database) -> Json raise {
  let active = active_session_id()
  let items : Array[Json] = []
  for session in db.all_sessions() {
    items.push({
      "id": session.id,
      "name": session.name,
      "steps": db.steps_of_session(session.id).length(),
      "is_the_active_one": session.id == active,
    })
  }
  {
    "the_active_one": active,
    "the_explorations": items,
    "note": "An exploration is a named run of steps. maked_export takes one away as Markdown or JSON.",
  }
}

///|
/// One exploration, as something to take away.
///
/// Markdown is the reading form and JSON is the machine form, and both are
/// the same run of steps. The Markdown opens with the run so far and carries
/// the measures, so an exploration is worth reading on its own.
pub fn agent_export(
  db : Database,
  session_id : Int64,
  format : String,
) -> Json raise {
  let session = match db.session_by_id(session_id) {
    Some(s) => s
    None =>
      return {
        "error": "there is no exploration with that id",
        "id": session_id,
      }
  }
  if format == "json" {
    { "format": "json", "the_exploration": export_json(db, session) }
  } else {
    {
      "format": "markdown",
      "the_exploration": Json::string(export_markdown(db, session)),
    }
  }
}
