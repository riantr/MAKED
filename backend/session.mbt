///| Sessions: named explorations, and the steps inside them.
///

///| Before this, the loop lived in one module-level array: one exploration, no

///| name, no history that outlived the process, and nothing to take away. A

///| user who spent twenty steps working out why their model would not move

///| had nowhere to put any of it, and restarting the server threw it away.

///| This module is the answer, and it is deliberately small: a session, a tree

///| of steps, and the two operations that make a history worth keeping -- go

///| back, and fork.
///

///| **A session's steps are a tree, not a list.** Each step records the step

///| it came from (`parent_step_id`) and the session records which step it is

///| standing on (`head_step_id`). Rewinding moves the head back; the steps

///| beyond it stay in the table and become the other branches. A list would

///| have had to delete them, and "let me try the other road from step 7" is

///| the whole reason to keep a history at all.
///

///| **Replay re-derives, it does not restore.** A step records the domain and

///| the slot, not a snapshot of the positions, so putting a session back

///| together means running those steps through the transition table again. The

///| positions that come out are the ones the table really produces, and a

///| record that disagreed with the table would be caught rather than trusted.
///

///| **Every step records why it was possible.** The "available" and "blocked"

///| slot lists are a snapshot taken at the moment of the step, not a lookup

///| performed now. A step that was refused because nothing could move from

///| there is only interesting if the record says so, and a reader three weeks

///| later should see what the table offered *then*.

///|
/// A named exploration.
///
/// `head_step_id` is the session's present: the step it is standing on. The
/// steps below it in the tree are the past, and the steps branching off it are
/// the roads not taken.
pub(all) struct Session {
  /// Assigned by SQLite on insert.
  id : Int64
  name : String
  /// The session this one was forked from, or 0 when it is not a fork.
  parent_id : Int64
  /// The step the fork happened at, inside the parent session.
  forked_step_id : Int64
  /// The step this session is standing on, or 0 for the root.
  head_step_id : Int64
  /// The domain the session started on.
  start_cursor : String
  /// "structured" or "free".
  mode : String
  created_at : String
  updated_at : String
} derive(Eq)

// The `implicit_impl_as_method` deprecation warning on that derive is accepted,
// exactly as it is on `Page`: declaring `extend Session with Eq::{not_equal,
// equal}` silences it but trades it for two `unused_value` warnings, since
// nothing calls the promoted forms.

///|
/// One recorded step inside a session.
pub(all) struct SessionStep {
  id : Int64
  session_id : Int64
  /// The step this one came from, or 0 for the first step of a path.
  parent_step_id : Int64
  /// The domain that was stepped: M, D, E, A or K.
  domain : String
  domain_title : String
  /// The slot's URL-safe name ("act"), as the step endpoint takes it.
  slot : String
  /// The slot's English designation ("Act"), as the button shows it.
  slot_designation : String
  /// The word the model calls the outcome: "Moved", "Held", "Converge",
  /// "Undecided" or "No-way" -- or whatever a model file says instead.
  outcome : String
  /// The outcome's kind: "moved", "held", "same", "open" or "block".
  ///
  /// The word is what a reader sees and the kind is what the machine matches
  /// on. Both are recorded, because a sentence built from the word would
  /// break the moment somebody renamed the model -- and renaming a model is
  /// exactly what a model file is for.
  outcome_kind : String
  /// The human-readable account of what the step did.
  detail : String
  /// The position the domain was on before the step.
  position_before : String
  /// The position the domain ended up on.
  position_after : String
  /// Which domain the cursor was pointing at after the step.
  cursor_after : String
  /// The group state after the step.
  group_state : String
  /// "structured" or "free".
  mode : String
  /// How the step was taken: "drive", "explicit" or "research".
  source : String
  /// The slot the table itself would have driven here, or "" when it had none.
  drive : String
  /// Whether the table offered several edges and declined to choose.
  undecided : Bool
  /// The slots that had an outgoing edge here, comma separated.
  available : String
  /// The slots that had none, comma separated.
  blocked : String
  created_at : String
} derive(Eq)

///|
/// The fields of a step that the caller supplies. `id` and `created_at` are
/// assigned by SQLite, so they are not part of the draft.
pub(all) struct StepDraft {
  session_id : Int64
  parent_step_id : Int64
  domain : String
  domain_title : String
  slot : String
  slot_designation : String
  outcome : String
  outcome_kind : String
  detail : String
  position_before : String
  position_after : String
  cursor_after : String
  group_state : String
  mode : String
  source : String
  drive : String
  undecided : Bool
  available : String
  blocked : String
} derive(Eq)

///|
/// The live session: the one the loop is currently advancing.
///
/// A one-element array rather than a `let mut`, because MoonBit has no
/// mutable module-level binding. The array element is mutable in place, which
/// is the same trick `loop.mbt` uses for the loop state itself.
let g_active_session : Array[Int64] = [0L]

///|
pub fn active_session_id() -> Int64 {
  g_active_session[0]
}

///|
pub fn set_active_session_id(id : Int64) -> Unit {
  g_active_session[0] = id
}

///|
/// A name longer than this is a paste accident, not a name.
pub const MAX_SESSION_NAME : Int32 = 120

///|
/// The outcome of checking a submitted session name.
pub(all) enum SessionName {
  Accepted(String)
  Rejected(String)
}

///|
/// Check a session name and normalise it.
///
/// Surrounding whitespace is stripped, because a name that renders with one
/// leading space looks like a layout bug rather than a typo, and an empty
/// name is refused rather than stored: a session called "" cannot be told
/// apart from a session that was never named, and the whole point of naming
/// one is to be able to find it again.
pub fn Session::validate_name(raw : String) -> SessionName {
  let name = raw.trim().to_owned()
  if name.is_empty() {
    Rejected("give the session a name")
  } else if name.length() > MAX_SESSION_NAME {
    Rejected(
      "name is " +
      name.length().to_string() +
      " characters; the limit is " +
      MAX_SESSION_NAME.to_string(),
    )
  } else {
    Accepted(name)
  }
}

///|
/// The two things that can go wrong when a session is addressed.
pub(all) enum SessionOutcome {
  /// Done, with the session that was addressed.
  Done(Session)
  /// No session has that id.
  MissingSession
  /// The step is not on the session's current path, so it cannot be the
  /// point to rewind to or fork from.
  MissingStep
  /// The request was refused, with a reason meant for the person who made it.
  Refused(String)
}

///|
fn mode_name(mode : LoopMode) -> String {
  match mode {
    Structured => "structured"
    Free => "free"
  }
}

///|
fn mode_from_name(name : String) -> LoopMode {
  match name {
    "free" => Free
    _ => Structured
  }
}

///|
/// Split a comma-separated slot list back into names.
///
/// The lists are stored as one column rather than as rows because they are a
/// snapshot of a set, never queried against: what the table offered at one
/// position is worth reading, not worth indexing.
fn split_slots(text : String) -> Array[String] {
  let out : Array[String] = []
  if text.is_empty() {
    return out
  }
  for part in text.split(",") {
    let name = part.to_owned()
    if name != "" {
      out.push(name)
    }
  }
  out
}

///|
/// Lift a list of strings into a `Json` array.
///
/// The same shape `loop.mbt` uses: an `Array[String]` does not coerce to
/// `Json`, and a one-element array literal per element is the form that does.
fn string_array_json(names : Array[String]) -> Json {
  let items : Array[Json] = []
  for name in names {
    items.push([name])
  }
  [..items]
}

///|
pub fn Session::to_json(self : Session) -> Json {
  {
    "id": self.id,
    "name": self.name,
    "parent_id": self.parent_id,
    "forked_step_id": self.forked_step_id,
    "head_step_id": self.head_step_id,
    "start_cursor": self.start_cursor,
    "mode": self.mode,
    "created_at": self.created_at,
    "updated_at": self.updated_at,
  }
}

///|
/// One step, as the API and the export report it.
///
/// `index` is the step's depth along its own path, 1-based. It is derived
/// rather than stored: two branches from the same step share a depth, and a
/// stored counter would have to be kept in step with the tree by hand.
///
/// The names a step carries are re-rendered in the reader's language rather
/// than shown as they were recorded. A step records the names the model was
/// written in, and a name is a word in one language; the ids it also records
/// are the thing the word was about, and those are what a re-rendering asks
/// the model about.
pub fn SessionStep::to_json(
  self : SessionStep,
  index : Int32,
  lang : Lang,
) -> Json {
  let model = current_model()
  {
    "id": self.id,
    "index": index,
    "domain": self.domain,
    "domain_title": domain_title_in(model, self.domain, self.domain_title, lang),
    "slot": self.slot,
    "slot_designation": slot_name_in(
      model,
      self.slot,
      self.slot_designation,
      lang,
    ),
    "outcome": model.outcome_label_in(self.outcome_kind, lang),
    "outcome_kind": self.outcome_kind,
    "detail": step_detail_in(model, self, lang),
    "position_before": position_name_in(model, self.position_before, lang),
    "position_after": position_name_in(model, self.position_after, lang),
    "cursor_after": self.cursor_after,
    "group_state": group_state_in(self.group_state, lang),
    "mode": self.mode,
    "source": self.source,
    "drive": self.drive,
    "undecided": self.undecided,
    // The reason, in one sentence, written here rather than in the client:
    // a second copy of that rule in the browser would be a second thing to
    // keep in step with this one.
    "why": why_line_in(self, lang),
    // What the step did, in a sentence: the position it left, the position
    // it reached, the slot it went through, and where the cursor went next.
    // The label and the detail above are the same fact in the machine's
    // vocabulary; this is the same fact in a reader's.
    "narration": step_sentence(facts_of(model, self), lang),
    "available": string_array_json(split_slots(self.available)),
    "blocked": string_array_json(split_slots(self.blocked)),
    "created_at": self.created_at,
  }
}

///|
/// The title of a domain, in the language asked for.
///
/// A domain the model does not have keeps the title it was recorded with,
/// because a stored title is better than no title at all.
fn domain_title_in(
  model : Model,
  letter : String,
  stored : String,
  lang : Lang,
) -> String {
  match model.domain_by_letter(letter) {
    Some(domain) => domain.title_in(lang)
    None => stored
  }
}

///|
/// The transition a recorded step took, rebuilt from the model.
///
/// A step records where it went, not which edge it went by, so the edge is
/// asked of the model. The one case where the model's own answer is not the
/// answer is the branch the table declined to choose: there the model offers
/// several candidates and the reader picked one, so the step records the
/// move the reader made rather than the refusal. The recorded kind says
/// which of the two it was.
fn transition_of(model : Model, step : SessionStep) -> Move {
  let from = model.position_id_by_label(step.position_before)
  let to = model.position_id_by_label(step.position_after)
  let transition = model.step(from, step.slot)
  match transition {
    Open(candidates) => {
      if step.outcome_kind == "open" {
        return transition
      }
      for candidate in candidates {
        if candidate.to == to && candidate.kind == step.outcome_kind {
          return match candidate.kind {
            "held" => Held(candidate.edge, candidate.to)
            "same" => Same([candidate.edge], candidate.to)
            _ => Moved(candidate.edge, candidate.to)
          }
        }
      }
      transition
    }
    _ => transition
  }
}

///|
/// The detail of a recorded step, in the language asked for.
///
/// English is the sentence the step already carries. Chinese is written
/// again from the move, because a move can be said in more than one way and
/// a sentence cannot be turned back into one.
///
/// The move is read from the model in force now, so a step recorded on a
/// different model reads through the model that is installed. The
/// structured fields beside it -- where the step went, which slot it used --
/// are read from what the step recorded, and they do not move.
fn step_detail_in(model : Model, step : SessionStep, lang : Lang) -> String {
  match lang {
    English => step.detail
    Chinese => {
      let from = model.position_id_by_label(step.position_before)
      outcome_detail_zh(
        model,
        transition_of(model, step),
        from,
        step.slot,
        lang,
      )
    }
  }
}

///|
/// The steps from the root down to `step_id`, oldest first.
///
/// The walk is a linear scan rather than an index because a session holds
/// tens of steps, not thousands, and the scan needs no hash support on the
/// key type. The guard stops a corrupted parent link from spinning forever:
/// a cycle would otherwise walk the same steps until the guard ran out.
fn chain_to_step(
  all : Array[SessionStep],
  step_id : Int64,
) -> Array[SessionStep] {
  let chain : Array[SessionStep] = []
  let mut cursor = step_id
  let mut budget = all.length() + 1
  while cursor != 0L && budget > 0 {
    budget -= 1
    let mut found : SessionStep? = None
    for step in all {
      if step.id == cursor {
        found = Some(step)
        break
      }
    }
    match found {
      Some(step) => {
        chain.push(step)
        cursor = step.parent_step_id
      }
      None => cursor = 0L
    }
  }
  reverse_steps(chain)
}

///|
fn reverse_steps(items : Array[SessionStep]) -> Array[SessionStep] {
  let out : Array[SessionStep] = []
  let mut i = items.length()
  while i > 0 {
    i -= 1
    out.push(items[i])
  }
  out
}

///|
/// The steps of a session that are not on its current path.
///
/// These are the roads that were walked and then walked back from. They stay
/// in the table on purpose: the point of a history is that the branch you
/// abandoned is still there to be read.
fn off_path_steps(
  all : Array[SessionStep],
  path : Array[SessionStep],
) -> Array[SessionStep] {
  let on_path : Array[Int64] = []
  for step in path {
    on_path.push(step.id)
  }
  let out : Array[SessionStep] = []
  for step in all {
    if !on_path.contains(step.id) {
      out.push(step)
    }
  }
  out
}

///|
/// How deep a step sits along its own path, 1-based.
///
/// For a step on the path this is its position in it. For one that is not, it
/// is the length of the chain that reaches it, which is the depth it had when
/// it was taken.
fn depth_of(all : Array[SessionStep], step : SessionStep) -> Int32 {
  chain_to_step(all, step.id).length()
}

///|
/// Rebuild the loop state at the end of a path of steps.
///
/// The state is rebuilt by running the recorded domains and slots through the
/// transition table, not by restoring a stored snapshot. That is what makes
/// the replay worth trusting: the positions that come out are the positions
/// the table really produces, so a record that had drifted from the table
/// shows up as a different result rather than as a quiet lie.
///
/// A step whose domain or slot cannot be parsed is skipped rather than
/// aborting the whole replay: one unreadable row should not cost the user the
/// rest of their history.
///
/// The model is named, not assumed. A replay is a re-derivation against a
/// machine, and the machine has to be the one the steps were taken on --
/// asking the installed model about a session that belongs to another one
/// would re-derive the wrong positions and report them as the right ones.
pub fn replay_steps(
  model : Model,
  steps : Array[SessionStep],
  start_cursor : String,
  mode : String,
) -> LoopState {
  let base = LoopState::new_for(model).with_mode(mode_from_name(mode))
  let mut state = match model.domain_by_letter(start_cursor) {
    Some(domain) => base.focus(domain)
    None => base
  }
  for step in steps {
    let domain = match model.domain_by_letter(step.domain) {
      Some(d) => d
      None => continue
    }
    let slot = match model.slot_from_name(step.slot) {
      Some(s) => s
      None => continue
    }
    state = state.step_domain_with(domain, slot, false)
    state = match model.domain_by_letter(step.cursor_after) {
      Some(d) => state.focus(d)
      None => state
    }
  }
  state
}

///|
/// Read an integer field out of a JSON object, or 0 when it is missing.
///
/// Both spellings are accepted. A step id arrives as a number from a client
/// that decoded it, and as a string from one that passed the raw value
/// through; the backend holds it as an `Int64`, and a mismatch here would be
/// invisible -- every id would read as 0 and every rewind would quietly land
/// on the root.
fn json_int(json : Json, key : String) -> Int32 {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(Number(n, ..)) => n.to_int()
        Some(String(text)) => @string.parse_int(text) catch { _ => 0 }
        _ => 0
      }
    _ => 0
  }
}

///|
/// Put a session back at its beginning.
///
/// The head goes to the root and the session records where it starts from
/// now. The steps that were taken are not deleted: they stay in the table as
/// the branches that were walked and then walked back from, which is the
/// only honest way to say "I started again" -- a reset that erased them
/// would be indistinguishable from never having taken them.
pub fn reset_session_start(db : Database, state : LoopState) -> Unit raise {
  let session_id = ensure_session(db)
  db.set_session_head(session_id, 0L)
  db.set_session_start(
    session_id,
    state.current.letter(),
    mode_name(state.mode),
  )
}

///|
/// The slots that had an outgoing edge at a position, as a stored list.
fn available_slots_text(model : Model, position : String) -> String {
  exitable_slots_of(model, position).join(",")
}

///|
/// The slots that had none at a position, as a stored list.
fn blocked_slots_text(model : Model, position : String) -> String {
  let names : Array[String] = []
  let usable = exitable_slots_of(model, position)
  for slot in model.slot_ids() {
    if !usable.contains(slot) {
      names.push(slot)
    }
  }
  names.join(",")
}

///|
/// The slot the model itself would have driven at a position, or "".
fn drive_slot_text(model : Model, position : String) -> String {
  match drive_slot_of(model, position) {
    Some(slot) => slot
    None => ""
  }
}

///|
/// Record the step that was just taken into the active session.
///
/// The step is derived from the two states rather than from the history
/// array: `before` says where the domain stood, `after` says where it landed
/// and where the cursor went, and the event carries the slot and the outcome.
/// Nothing is written that the caller had to remember to pass in, so a new
/// way of taking a step cannot forget to record itself.
///
/// The "why" is snapshotted here rather than looked up later: what the table
/// offered at that position is part of what happened, and it is worth keeping
/// even if the table is one day extended.
pub fn record_step(
  db : Database,
  before : LoopState,
  after : LoopState,
  source : String,
) -> Unit raise {
  let event = match after.history.last() {
    Some(e) => e
    None => return
  }
  let domain = event.domain
  let position_before = before.domain_state(domain).position
  let position_after = after.domain_state(domain).position
  // The model that produced the step, not the one that happens to be
  // installed. The record has to describe the machine the step was taken on:
  // a step taken on somebody else's model, with the installed model's words
  // written on it, is a record of a step nobody took.
  let model = before.model
  let session_id = ensure_session(db)
  let parent_step_id = match db.session_by_id(session_id) {
    Some(session) => session.head_step_id
    None => 0L
  }
  let draft : StepDraft = {
    session_id,
    parent_step_id,
    domain: domain.letter(),
    domain_title: domain.title(),
    slot: event.slot,
    slot_designation: model.slot_designation(event.slot),
    outcome: event.outcome_label,
    outcome_kind: event.outcome_kind,
    detail: event.outcome_detail,
    position_before: model.position_label(position_before),
    position_after: model.position_label(position_after),
    cursor_after: after.current.letter(),
    group_state: after.group_state.en_designation(),
    mode: mode_name(after.mode),
    source,
    drive: drive_slot_text(model, position_before),
    undecided: is_undecided_of(model, position_before),
    available: available_slots_text(model, position_before),
    blocked: blocked_slots_text(model, position_before),
  }
  let step = db.insert_step(draft)
  db.set_session_head(session_id, step.id)
}

///|
/// The session the loop is advancing, creating one if there is none.
///
/// A server that has just started has no active session, and a step taken
/// before one exists would otherwise have nowhere to go. Creating the session
/// here rather than at start-up means the very first step is recorded
/// instead of being silently dropped.
pub fn ensure_session(db : Database) -> Int64 raise {
  let active = active_session_id()
  if active != 0L {
    match db.session_by_id(active) {
      Some(_) => return active
      None => ()
    }
  }
  let sessions = db.all_sessions()
  if sessions.length() == 0 {
    let fresh = db.insert_session(
      "First exploration", 0L, 0L, "M", "structured",
    )
    set_active_session_id(fresh.id)
    fresh.id
  } else {
    let latest = sessions[0]
    set_active_session_id(latest.id)
    latest.id
  }
}

///|
/// Put a session back in front of the user.
///
/// The live loop state is rebuilt by replaying the session's path, and the
/// session becomes the active one. A session with no steps leaves the loop
/// where it started, which is the honest answer: nothing was recorded, so
/// there is nothing to restore.
pub fn activate_session(db : Database, id : Int64) -> SessionOutcome raise {
  let session = match db.session_by_id(id) {
    Some(s) => s
    None => return MissingSession
  }
  let all = db.steps_of_session(id)
  let path = chain_to_step(all, session.head_step_id)
  set_loop_state(
    replay_steps(current_model(), path, session.start_cursor, session.mode),
  )
  set_active_session_id(id)
  Done(session)
}

///|
/// Read a session back after changing it.
///
/// A `Session` value is a snapshot of one row, so a function that moves the
/// head and then returns the value it was handed would report the head the
/// session had *before* the move. The table is the truth, so the value has
/// to come from it: a branch that returned a session with an empty head
/// would tell the client its fork point was nowhere.
fn reload_session(db : Database, id : Int64) -> Session raise {
  match db.session_by_id(id) {
    Some(session) => session
    None => fail("the session vanished")
  }
}

///|
/// Move a session's head back to one of its steps.
///
/// The steps beyond it are not deleted: they stay in the table and become the
/// other branches, which is what makes "go back and try something else" a
/// thing the history can express rather than a thing it has to refuse.
///
/// The step has to be on the session's current path. A step that is off the
/// path is a branch that was already abandoned, and rewinding to it would
/// silently resurrect it.
pub fn rewind_session(
  db : Database,
  id : Int64,
  at_step_id : Int64,
) -> SessionOutcome raise {
  let session = match db.session_by_id(id) {
    Some(s) => s
    None => return MissingSession
  }
  let all = db.steps_of_session(id)
  let path = chain_to_step(all, session.head_step_id)
  if at_step_id != 0L && !contains_id(path, at_step_id) {
    return MissingStep
  }
  db.set_session_head(id, at_step_id)
  let shorter = chain_to_step(all, at_step_id)
  set_loop_state(
    replay_steps(current_model(), shorter, session.start_cursor, session.mode),
  )
  Done(reload_session(db, id))
}

///|
/// Fork a session at one of its steps.
///
/// The new session gets a copy of the path up to that step and stands on it,
/// so the fork is a real session with its own name and its own future. The
/// session it came from is left exactly as it was: a fork that moved the
/// parent would not be a fork.
///
/// The step has to be on the parent's current path, for the same reason a
/// rewind does.
pub fn branch_session(
  db : Database,
  source_id : Int64,
  at_step_id : Int64,
  name : String,
) -> SessionOutcome raise {
  let source = match db.session_by_id(source_id) {
    Some(s) => s
    None => return MissingSession
  }
  let all = db.steps_of_session(source_id)
  let path = chain_to_step(all, source.head_step_id)
  if at_step_id != 0L && !contains_id(path, at_step_id) {
    return MissingStep
  }
  let chain = chain_to_step(all, at_step_id)
  let branch = db.insert_session(
    name,
    source_id,
    at_step_id,
    source.start_cursor,
    source.mode,
  )
  // The chain is linear, so the parent of each copied step is the copy of the
  // one before it. The first step's parent is 0, which is the root.
  let mut parent = 0L
  for step in chain {
    let draft : StepDraft = {
      session_id: branch.id,
      parent_step_id: parent,
      domain: step.domain,
      domain_title: step.domain_title,
      slot: step.slot,
      slot_designation: step.slot_designation,
      outcome: step.outcome,
      outcome_kind: step.outcome_kind,
      detail: step.detail,
      position_before: step.position_before,
      position_after: step.position_after,
      cursor_after: step.cursor_after,
      group_state: step.group_state,
      mode: step.mode,
      source: step.source,
      drive: step.drive,
      undecided: step.undecided,
      available: step.available,
      blocked: step.blocked,
    }
    let copied = db.insert_step(draft)
    parent = copied.id
  }
  db.set_session_head(branch.id, parent)
  set_loop_state(
    replay_steps(current_model(), chain, branch.start_cursor, branch.mode),
  )
  set_active_session_id(branch.id)
  Done(reload_session(db, branch.id))
}

///|
/// Whether a step id is in a list of steps.
fn contains_id(steps : Array[SessionStep], id : Int64) -> Bool {
  for step in steps {
    if step.id == id {
      return true
    }
  }
  false
}

///|
/// The path of a session as JSON, 1-based, oldest first.
fn path_json(path : Array[SessionStep], lang : Lang) -> Json {
  let items = []
  let mut index = 0
  for step in path {
    index += 1
    items.push(step.to_json(index, lang))
  }
  [..items]
}

///|
/// The branches of a session that are not on its path, as JSON.
fn others_json(
  all : Array[SessionStep],
  others : Array[SessionStep],
  lang : Lang,
) -> Json {
  let items = []
  for step in others {
    items.push(step.to_json(depth_of(all, step), lang))
  }
  [..items]
}

///|
fn empty_json_array() -> Json {
  let empty : Array[Json] = []
  [..empty]
}

///|
/// The session state: the list of sessions, the active one, its path, and
/// the branches that are not on the path.
///
/// The live loop status is deliberately not in here. It has a request of its
/// own, and the start-up chain is the shape this client is known to survive:
/// one request out, one answer in, then the loop status. Folding the status
/// in as well would mean two copies of it, one of them a moment older than
/// the other.
pub fn session_state_json(db : Database, lang : Lang) -> Json raise {
  let sessions = sessions_array_json(db)
  let session_id = active_session_id()
  match db.session_by_id(session_id) {
    None =>
      {
        "sessions": sessions,
        "active_session_id": session_id,
        "session": Json::empty_object(),
        "path": empty_json_array(),
        "other_steps": empty_json_array(),
        "summary": "",
        "metrics": Json::empty_object(),
      }
    Some(session) => {
      let all = db.steps_of_session(session.id)
      let path = chain_to_step(all, session.head_step_id)
      let others = off_path_steps(all, path)
      {
        "sessions": sessions,
        "active_session_id": session_id,
        "session": session.to_json(),
        "path": path_json(path, lang),
        "other_steps": others_json(all, others, lang),
        // What the last few steps add up to. The timeline says what each step
        // did; this says what the run of them did, which is the question a
        // person has after the fifth click.
        "summary": summary_of(path, lang),
        // And whether the run is still finding ground, or going round in
        // circles. The summary says what happened; these say what it is
        // worth, which is the question after the twentieth click.
        "metrics": measure(path).to_json(),
      }
    }
  }
}

///|
/// What the last steps of a path add up to.
///
/// The last five, because five is enough to see a shape and few enough that
/// the sentence stays about something a reader can hold in their head. The
/// group state is the one the last step left behind, which is the one the
/// loop is in now.
pub fn summary_of(path : Array[SessionStep], lang : Lang) -> String {
  let start = if path.length() > 5 { path.length() - 5 } else { 0 }
  let recent : Array[SessionStep] = []
  let mut i = start
  while i < path.length() {
    recent.push(path[i])
    i += 1
  }
  let model = current_model()
  let facts : Array[StepFacts] = recent.map(fn(step) { facts_of(model, step) })
  let group = match recent.last() {
    Some(step) => step.group_state
    None => ""
  }
  phase_summary(model, facts, group, lang)
}

///|
/// The live loop status with the session state folded in.
///
/// The loop panel needs both halves: what the machine is doing now, and the
/// history the steps are being recorded into. They used to arrive on two
/// requests, and the second was only made at start-up -- so the panel showed
/// a step count that stopped moving after the first step, and a summary of a
/// run that was one step out of date. One payload keeps them in step.
pub fn loop_payload(db : Database, lang : Lang) -> Json raise {
  let status = get_loop_state().to_json(lang)
  match status {
    Object(fields) => {
      let merged = Map([], capacity=16)
      for (name, value) in fields {
        merged[name] = value
      }
      merged["session_state"] = session_state_json(db, lang)
      Json::object(merged)
    }
    _ => status
  }
}

///|
/// The session state plus the live loop status.
///
/// The status travels with it so that a client which has just replayed or
/// branched does not have to ask for it again -- and a client that asked for
/// it again could get a different answer, because the live state is whatever
/// the last request left it as.
pub fn session_payload(db : Database, lang : Lang) -> Json raise {
  let state = session_state_json(db, lang)
  match state {
    Object(fields) => {
      let merged = Map([], capacity=16)
      for (name, value) in fields {
        merged[name] = value
      }
      merged["loop"] = get_loop_state().to_json(lang)
      Json::object(merged)
    }
    _ => state
  }
}

///|
/// The session state, plus one named session of its own.
///
/// The state carries the *active* session under "session". A route that acts
/// on a session which is not the active one -- renaming, say -- would then
/// answer a question nobody asked: "here is the session you renamed" has to
/// be answerable, and "here is the session that happens to be active" does
/// not answer it when the two are not the same session. So the acted-on
/// session travels under its own key, next to the state it changed.
pub fn session_payload_with(
  db : Database,
  key : String,
  session : Session,
  lang : Lang,
) -> Json raise {
  let state = session_payload(db, lang)
  match state {
    Object(fields) => {
      let merged = Map([], capacity=16)
      for (name, value) in fields {
        merged[name] = value
      }
      merged[key] = session.to_json()
      Json::object(merged)
    }
    _ => state
  }
}

///|
/// The list of sessions, newest first.
///
/// The active flag is computed rather than stored: the live session is a
/// property of the running process, and a flag in the table would go stale
/// the moment the process ended.
pub fn sessions_array_json(db : Database) -> Json raise {
  let sessions = db.all_sessions()
  let items = []
  for session in sessions {
    let all = db.steps_of_session(session.id)
    let path = chain_to_step(all, session.head_step_id)
    let item : Json = {
      "id": session.id,
      "name": session.name,
      "parent_id": session.parent_id,
      "forked_step_id": session.forked_step_id,
      "head_step_id": session.head_step_id,
      "start_cursor": session.start_cursor,
      "mode": session.mode,
      "created_at": session.created_at,
      "updated_at": session.updated_at,
      "steps": path.length(),
      "total_steps": all.length(),
      "active": session.id == active_session_id(),
    }
    items.push(item)
  }
  [..items]
}

///|
/// The list of sessions, newest first, with the active one marked.
///
/// The active flag is computed rather than stored: the live session is a
/// property of the running process, and a flag in the table would go stale
/// the moment the process ended.
pub fn sessions_payload(db : Database) -> Json raise {
  {
    "sessions": sessions_array_json(db),
    "active_session_id": active_session_id(),
  }
}

///|
/// The designation of a slot, from the name it is stored under.
///
/// The slot list is stored under the URL-safe names ("occasion", "act"), so
/// that a step can be addressed by it. A reader knows the slots by their
/// designations ("Situation", "Action"), which are the words on the buttons.
fn slot_designation_of(english_name : String, lang : Lang) -> String {
  match slot_from_english(english_name) {
    Some(slot) => current_model().slot_designation_in(slot, lang)
    None => english_name
  }
}

///|
/// One sentence saying why the step was possible, or why it was not.
///
/// Built from the snapshot the step carries, so it describes the moment the
/// step was taken rather than the table as it stands now.
pub fn why_line(step : SessionStep) -> String {
  why_line_in(step, English)
}

///|
/// One sentence saying why the step was possible, in the language asked for.
///
/// Written in Chinese rather than translated: the English sentence is a list
/// of clauses joined by semicolons, and Chinese joins a list of clauses with
/// a comma and a full stop rather than with a semicolon.
fn why_line_in(step : SessionStep, lang : Lang) -> String {
  let available = split_slots(step.available)
  let blocked = split_slots(step.blocked)
  let parts : Array[String] = []
  match lang {
    English => {
      parts.push(
        available.length().to_string() +
        " of the 8 slots had an outgoing edge here",
      )
      if step.undecided {
        parts.push("the table offered several and declined to choose")
      }
      if step.drive != "" {
        // The drive slot is stored under its URL-safe name ("occasion"), which is
        // the code's name for it. The reader knows it as "Situation", and a line
        // that said "occasion" would be a line about the implementation.
        parts.push(
          "its own drive slot was " + slot_designation_of(step.drive, lang),
        )
      } else {
        parts.push("it had no drive slot at all")
      }
      if blocked.length() > 0 {
        parts.push(blocked.length().to_string() + " slots had no edge here")
      }
      parts.join("; ")
    }
    Chinese => {
      parts.push(
        "八个槽中有" +
        available.length().to_string() +
        "个在此处有出边",
      )
      if step.undecided {
        parts.push("表格给出了几条路却不肯选择")
      }
      if step.drive != "" {
        parts.push(
          "它自己的驱动槽是" + slot_designation_of(step.drive, lang),
        )
      } else {
        parts.push("它根本没有驱动槽")
      }
      if blocked.length() > 0 {
        parts.push(blocked.length().to_string() + "个槽在此处没有边")
      }
      parts.join("，") + "。"
    }
  }
}

///|
/// The session as a Markdown document.
///
/// Written for a person reading it later: the timeline in order, one heading
/// per step, and the reason under each one. The branch points are named, so
/// a reader can see where the exploration forked rather than being shown a
/// single path and left to guess that others existed.
pub fn export_markdown(db : Database, session : Session) -> String raise {
  let all = db.steps_of_session(session.id)
  let path = chain_to_step(all, session.head_step_id)
  let others = off_path_steps(all, path)
  let mut out = "# MAKED session: " + session.name + "\n\n"
  out = out + "- **Session id:** " + session.id.to_string() + "\n"
  out = out + "- **Created:** " + session.created_at + "\n"
  out = out + "- **Last updated:** " + session.updated_at + "\n"
  out = out + "- **Mode:** " + session.mode + "\n"
  out = out + "- **Started on:** " + session.start_cursor + "\n"
  out = out + "- **Steps on this path:** " + path.length().to_string() + "\n"
  out = out +
    "- **Other steps recorded in this session:** " +
    others.length().to_string() +
    "\n"
  if session.parent_id != 0L {
    out = out +
      "- **Forked from session:** " +
      session.parent_id.to_string() +
      " at step " +
      session.forked_step_id.to_string() +
      "\n"
  }
  // What the last few steps add up to. A document that opens with a
  // timeline and no account of it is a list; this is the account.
  let summary = summary_of(path, English)
  if summary != "" {
    out = out + "\n## The run so far\n\n" + summary + "\n"
  }
  // And whether the run is worth continuing: the measures, and the
  // comparison of its beginning with its end. A document that lists the
  // steps without saying whether the run was getting anywhere is the
  // timeline again, and the timeline is the part nobody wants.
  let metrics = measure(path)
  if metrics.metrics.length() > 0 {
    out = out + "\n## How the run is doing\n\n"
    for metric in metrics.metrics {
      out = out +
        "- **" +
        metric.label +
        ":** " +
        metric.value.to_string() +
        (if metric.of > 0 { " of " + metric.of.to_string() } else { "" }) +
        " — " +
        metric.sentence +
        "\n"
    }
    if metrics.comparison != "" {
      out = out + "\n" + metrics.comparison + "\n"
    }
  }
  out = out + "\n## Timeline\n"
  let mut index = 0
  for step in path {
    index += 1
    out = out +
      "\n### " +
      index.to_string() +
      ". " +
      step.domain +
      " · " +
      step.slot_designation +
      " · " +
      step.outcome +
      "\n\n"
    // The sentence first, for the same reason the timeline on screen leads
    // with it: a document that a person reads later should say what
    // happened, not only list the labels.
    out = out + step_sentence(facts_of(current_model(), step), English) + "\n\n"
    out = out +
      "- **Position:** " +
      step.position_before +
      " → " +
      step.position_after +
      "\n"
    out = out + "- **Detail:** " + step.detail + "\n"
    out = out + "- **Why:** " + why_line_in(step, English) + "\n"
    out = out +
      "- **Cursor after:** " +
      step.cursor_after +
      " · **group:** " +
      step.group_state +
      " · **taken by:** " +
      step.source +
      "\n"
  }
  if others.length() > 0 {
    out = out + "\n## Other roads taken\n"
    out = out +
      "\nThese steps are recorded in the session but are not on its current " +
      "path: they are the branches that were walked and then walked back " +
      "from.\n"
    for step in others {
      out = out +
        "\n- **Step " +
        depth_of(all, step).to_string() +
        "** · " +
        step.domain +
        " · " +
        step.slot_designation +
        " · " +
        step.outcome +
        " — " +
        step.detail +
        "\n"
    }
  }
  out
}

///|
/// The session as a machine-readable document.
///
/// The same content as the Markdown export, in a shape another program can
/// read: the session, the path, and the branches that are not on it. The
/// `format` field is the version of this shape, so a consumer can tell what
/// it is holding.
pub fn export_json(db : Database, session : Session) -> Json raise {
  let all = db.steps_of_session(session.id)
  let path = chain_to_step(all, session.head_step_id)
  let others = off_path_steps(all, path)
  let path_json = []
  let mut index = 0
  for step in path {
    index += 1
    path_json.push(step.to_json(index, English))
  }
  let others_json = []
  for step in others {
    others_json.push(step.to_json(depth_of(all, step), English))
  }
  // The account of the run, kept in a name of its own so that the document
  // and the live state say the same thing by the same route.
  let run_summary = summary_of(path, English)
  let run_metrics = measure(path)
  {
    "format": "maked.session.v1",
    "session": session.to_json(),
    // The summary of the run, so that a consumer does not have to work it
    // out from the path itself.
    "summary": run_summary,
    // And the measures: whether the run is still finding ground, how far it
    // has ranged, and whether it is doing better than it was at the start.
    "metrics": run_metrics.to_json(),
    "path": [..path_json],
    "other_steps": [..others_json],
  }
}
