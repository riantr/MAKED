// Typed accessors for the loop status JSON from the backend.
//
// The shape mirrors `backend/loop.mbt` `LoopState::to_json`. The frontend does
// not need the full pyroduct vocabulary -- just the labels and strings the
// backend has already resolved, so the decoding is flat.

///|
pub(all) struct LoopEvent {
  domain : String
  slot : String
  outcome : String
  detail : String
  position : String
  position_label : String
} derive(Eq)

///|
pub(all) struct LoopStatus {
  current_domain : String
  current_title : String
  current_position : String
  current_position_label : String
  current_gloss : String
  next_domain : String
  drive_slot : String
  history_length : Int32
  history : Array[LoopEvent]
} derive(Eq)

///|
fn get_array(json : Json, key : String) -> Array[Json] {
  match field(json, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn loop_event(json : Json) -> LoopEvent {
  {
    domain: get_string(json, "domain", ""),
    slot: get_string(json, "slot", ""),
    outcome: get_string(json, "outcome", ""),
    detail: get_string(json, "detail", ""),
    position: get_string(json, "position", ""),
    position_label: get_string(json, "position_label", ""),
  }
}

///|
pub fn decode_loop_status(json : Json) -> LoopStatus {
  {
    current_domain: get_string(json, "current_domain", ""),
    current_title: get_string(json, "current_title", ""),
    current_position: get_string(json, "current_position", ""),
    current_position_label: get_string(json, "current_position_label", ""),
    current_gloss: get_string(json, "current_gloss", ""),
    next_domain: get_string(json, "next_domain", ""),
    drive_slot: get_string(json, "drive_slot", ""),
    history_length: get_int(json, "history_length", 0),
    history: get_array(json, "history").map(fn(item) { loop_event(item) }),
  }
}
