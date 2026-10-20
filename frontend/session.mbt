// Sessions on the client: the named explorations, and the steps inside one.
//
// The backend owns the shape of a session and the sentence that explains a
// step, so this file decodes rather than interprets. Nothing here decides
// what a step means: the "why" line arrives ready to be shown, because a
// second copy of that rule in the browser would be a second thing to keep in
// step with the first.
//
// Two details of the wire shape are worth naming:
//
//   - A session id arrives as a *string*, because the backend holds it as an
//     `Int64` and MoonBit's own `ToJson` encodes an `Int64` as a string. The
//     `get_id` helper accepts both spellings, so a client that decodes the
//     id as a number and one that passes the raw value through agree.
//   - The slot lists arrive as arrays of one-element arrays. That is the
//     shape MoonBit's `Json` builder accepts for a list of strings, and the
//     same shape the loop panel's `targets` already use.

///|
/// One named exploration, as the list of them reports it.
pub(all) struct Session {
  id : Int32
  name : String
  /// The steps on the session's current path.
  steps : Int32
  /// Every step recorded in the session, branches included.
  total_steps : Int32
  /// Whether this is the session in front of the user.
  active : Bool
  /// The session this one was forked from, or 0.
  parent_id : Int32
  created_at : String
  updated_at : String
} derive(Eq)

///|
/// One recorded step.
pub(all) struct SessionStep {
  id : Int32
  /// How deep the step sits along its path, 1-based.
  index : Int32
  /// The domain that was stepped: M, D, E, A or K.
  domain : String
  domain_title : String
  /// The slot's URL-safe name.
  slot : String
  /// The slot's English designation, as the button shows it.
  slot_designation : String
  /// Moved, Held, Same, Undecided or No-way.
  outcome : String
  /// The human-readable account of what the step did.
  detail : String
  position_before : String
  position_after : String
  /// Which domain the cursor was pointing at after the step.
  cursor_after : String
  group_state : String
  /// How the step was taken: "drive", "explicit" or "research".
  source : String
  /// Why the step was possible, in one sentence, written by the backend.
  why : String
  /// What the step did, in a sentence, written by the backend: the position
  /// it left, the position it reached, the slot it went through, and where
  /// the cursor went next.
  narration : String
  /// The slots that had an outgoing edge there.
  available : Array[String]
  /// The slots that had none.
  blocked : Array[String]
} derive(Eq)

///|
/// One measured number, and the reading that goes with it.
///
/// The number and the sentence arrive together from the server. The client
/// shows both and derives neither: a client that worked out its own idea of
/// "new ground" would be measuring a slightly different thing from the one
/// the server is reporting, and the two would disagree on the screen.
pub(all) struct Metric {
  /// The name it is filed under: "new_ground".
  key : String
  /// The name a reader sees: "New ground".
  label : String
  /// The number itself.
  value : Int32
  /// What the number is out of, or 0 when the measure has no denominator.
  of : Int32
  /// The reading, in one sentence.
  sentence : String
} derive(Eq)

///|
/// The report: the measures, and the comparison of the run's beginning with
/// its end.
pub(all) struct MetricReport {
  /// The window the measures are taken over.
  window : Int32
  /// How many steps the window actually holds.
  window_steps : Int32
  /// The measures themselves.
  metrics : Array[Metric]
  /// The comparison between the first window and the last one.
  comparison : String
} derive(Eq)

///|
/// The report as it stands when there is nothing to report: no measures, and
/// no comparison.
pub fn empty_metric_report() -> MetricReport {
  { window: 0, window_steps: 0, metrics: [], comparison: "", }
}

///|
/// The whole session state: the list, the active one, its path, and the
/// branches that are not on the path.
pub(all) struct SessionState {
  sessions : Array[Session]
  active_session_id : Int32
  session : Session
  path : Array[SessionStep]
  other_steps : Array[SessionStep]
  /// What the last few steps add up to, in one sentence.
  ///
  /// Written by the backend, like the "why" line: the sentence needs the
  /// transition table and the recorded steps to say anything true, and a
  /// browser that had its own copy of that rule would be a second thing to
  /// keep in step with the first.
  summary : String
  /// What the run is worth: whether it is still finding ground, how far it
  /// has ranged, and whether it is doing better than it was at the start.
  ///
  /// Also written by the backend. The measures need the whole path and the
  /// size of the state space to say anything true, and a client that had its
  /// own copy would be measuring something else.
  metrics : MetricReport
  /// The live loop status, when the response carried one.
  ///
  /// A session action changes the live state -- a rewind puts it back, a fork
  /// moves it -- so the response carries the status as it now is. Without
  /// it, the loop panel would show where the loop was before the action and
  /// the timeline would show where it is now, and the two would disagree.
  loop_status : LoopStatus?
} derive(Eq)

///|
/// A list of strings, unwrapped from the one-element arrays the backend
/// sends.
fn string_list(json : Json, key : String) -> Array[String] {
  let out : Array[String] = []
  match field(json, key) {
    Some(Array(items)) =>
      for item in items {
        match item {
          Array(parts) =>
            for part in parts {
              match part {
                String(text) => out.push(text)
                _ => ()
              }
            }
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
fn session_from_json(json : Json) -> Session {
  {
    id: get_id(json, "id"),
    name: get_string(json, "name", ""),
    steps: get_int(json, "steps", 0),
    total_steps: get_int(json, "total_steps", 0),
    active: get_bool(json, "active", false),
    parent_id: get_id(json, "parent_id"),
    created_at: get_string(json, "created_at", ""),
    updated_at: get_string(json, "updated_at", ""),
  }
}

///|
fn session_step_from_json(json : Json) -> SessionStep {
  {
    id: get_id(json, "id"),
    index: get_int(json, "index", 0),
    domain: get_string(json, "domain", ""),
    domain_title: get_string(json, "domain_title", ""),
    slot: get_string(json, "slot", ""),
    slot_designation: get_string(json, "slot_designation", ""),
    outcome: get_string(json, "outcome", ""),
    detail: get_string(json, "detail", ""),
    position_before: get_string(json, "position_before", ""),
    position_after: get_string(json, "position_after", ""),
    cursor_after: get_string(json, "cursor_after", ""),
    group_state: get_string(json, "group_state", ""),
    source: get_string(json, "source", ""),
    why: get_string(json, "why", ""),
    narration: get_string(json, "narration", ""),
    available: string_list(json, "available"),
    blocked: string_list(json, "blocked"),
  }
}

///|
/// One measure, as the server reports it.
fn metric_from_json(json : Json) -> Metric {
  {
    key: get_string(json, "key", ""),
    label: get_string(json, "label", ""),
    value: get_int(json, "value", 0),
    of: get_int(json, "of", 0),
    sentence: get_string(json, "sentence", ""),
  }
}

///|
/// The report, as the server reports it.
///
/// A response without a report decodes to an empty one rather than failing:
/// the measures are an addition to the session state, and an addition that
/// is missing must not be able to break the state that was there.
pub fn decode_metric_report(json : Json) -> MetricReport {
  match field(json, "metrics") {
    Some(obj) =>
      match field(obj, "metrics") {
        Some(Array(items)) =>
          {
            window: get_int(obj, "window", 0),
            window_steps: get_int(obj, "window_steps", 0),
            metrics: items.map(fn(item) { metric_from_json(item) }),
            comparison: get_string(obj, "comparison", ""),
          }
        _ => empty_metric_report()
      }
    None => empty_metric_report()
  }
}

///|
/// Decode the session state.
///
/// The same shape is used for the bootstrap and for every session action, so
/// one decoder covers all of them and the client cannot end up reading the
/// list from one response and the path from another.
pub fn decode_session_state(json : Json) -> SessionState {
  {
    sessions: decode_sessions(json),
    active_session_id: get_id(json, "active_session_id"),
    session: match field(json, "session") {
      Some(obj) => session_from_json(obj)
      None => empty_session()
    },
    path: decode_steps(json, "path"),
    other_steps: decode_steps(json, "other_steps"),
    summary: get_string(json, "summary", ""),
    metrics: decode_metric_report(json),
    loop_status: match field(json, "loop") {
      Some(obj) => Some(decode_loop_status(obj))
      None => None
    },
  }
}

///|
/// The session state carried by the bootstrap.
///
/// The bootstrap nests it under `session_state`, so the decoder is pointed at
/// that rather than at the whole payload: the payload also carries the pages
/// and the workspace entries, and none of those are sessions. Decoding the
/// wrong level does not fail -- it yields an empty list, and the page shows
/// "No sessions yet" while the server has one.
pub fn decode_bootstrap_session_state(json : Json) -> SessionState {
  match field(json, "session_state") {
    Some(obj) => decode_session_state(obj)
    None => empty_session_state()
  }
}

///|
/// The session state a response carried, if it carried one.
///
/// A step response is the loop status with the session state folded in
/// under `session_state`, the same key the bootstrap uses. A response
/// without one leaves the model alone: a missing field must not be able to
/// erase the session list.
pub fn session_state_of(json : Json) -> SessionState? {
  match field(json, "session_state") {
    Some(obj) => Some(decode_session_state(obj))
    None => None
  }
}

///|
/// The list of sessions, newest first.
pub fn decode_sessions(json : Json) -> Array[Session] {
  match field(json, "sessions") {
    Some(Array(items)) => items.map(fn(item) { session_from_json(item) })
    _ => []
  }
}

///|
/// A list of steps, under the given key.
pub fn decode_steps(json : Json, key : String) -> Array[SessionStep] {
  match field(json, key) {
    Some(Array(items)) => items.map(fn(item) { session_step_from_json(item) })
    _ => []
  }
}

///|
/// The session state as it is before anything has happened: no sessions, and
/// no active one.
pub fn empty_session_state() -> SessionState {
  {
    sessions: [],
    active_session_id: 0,
    session: empty_session(),
    path: [],
    other_steps: [],
    summary: "",
    metrics: empty_metric_report(),
    loop_status: None,
  }
}

///|
/// A session with nothing in it: no id, no name, no steps.
///
/// The value the model starts with, and what a response without a session
/// decodes to. It is public because a test that builds a model by hand needs
/// the same starting point the model itself starts from.
pub fn empty_session() -> Session {
  {
    id: 0,
    name: "",
    steps: 0,
    total_steps: 0,
    active: false,
    parent_id: 0,
    created_at: "",
    updated_at: "",
  }
}

///|
/// The name a fork gets when the user did not choose one.
///
/// The fork has to be findable, and "branch" on its own would not be. The
/// parent's name is carried over, so the two are recognisably the same
/// exploration -- and the user can rename it afterwards, which is why this
/// is a default rather than the only option.
pub fn branch_name(parent : String, c : Chrome) -> String {
  let trimmed = parent.trim().to_owned()
  if trimmed == "" {
    c.sessions.branch
  } else {
    trimmed + c.sessions.branch_suffix
  }
}

///|
/// Whether the server refused the request.
///
/// The HTTP status never reaches the client -- rabbita's HTTP client hands
/// over the body whatever the status was -- so the body is the only place a
/// refusal can be seen. A refusal carries an `error`; a success does not.
pub fn session_refused(json : Json) -> Bool {
  get_string(json, "error", "") != ""
}

///|
/// Why the server refused, from `{"error": ..., "reason": ...}`.
pub fn session_refusal_reason(json : Json) -> String {
  let reason = get_string(json, "reason", "")
  if reason != "" {
    reason
  } else {
    get_string(json, "error", "")
  }
}
