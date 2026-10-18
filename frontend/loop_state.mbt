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
/// One drive slot, as the backend describes it in `GET /api/loop/slots`.
///
/// `name` is the URL slug the step endpoint takes; `designation` is what the
/// button shows. Keeping both here is what lets the frontend stop hard-coding
/// its own copy of the eight-slot vocabulary.
pub(all) struct Slot {
  name : String
  designation : String
  gloss : String
} derive(Eq)

///|
/// A slot that really has an outgoing edge at the current position.
///
/// This is the backend's own answer to "can this move, and where to", taken
/// from the transition table rather than inferred from a naming convention.
pub(all) struct OpenSlot {
  name : String
  designation : String
  outcome : String
  targets : Array[String]
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
  drive_slot_name : String
  /// True when the drive slot has no outgoing edge at all here.
  blocked : Bool
  /// True when the table offers several edges and declines to choose one.
  undecided : Bool
  open_slots : Array[OpenSlot]
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
/// `open_slots[].targets` is a list of `[from, to]` pairs in the backend's
/// shape, but only the destinations are meaningful to a reader, so this keeps
/// the `to` of each pair.
fn target_labels(json : Json) -> Array[String] {
  let out : Array[String] = []
  for item in get_array(json, "targets") {
    match item {
      Array(pair) =>
        for entry in pair {
          match entry {
            String(s) => out.push(s)
            _ => ()
          }
        }
      _ => ()
    }
  }
  out
}

///|
fn open_slot(json : Json) -> OpenSlot {
  {
    name: get_string(json, "name", ""),
    designation: get_string(json, "designation", ""),
    outcome: get_string(json, "outcome", ""),
    targets: target_labels(json),
  }
}

///|
/// The real reason a step may appear to do nothing.
///
/// Before this was decoded, the backend computed `blocked` / `undecided` /
/// `open_slots` and the frontend discarded all three, so 228 of the 272
/// position-slot combinations silently did nothing and the page looked healthy.
pub fn decode_loop_status(json : Json) -> LoopStatus {
  {
    current_domain: get_string(json, "current_domain", ""),
    current_title: get_string(json, "current_title", ""),
    current_position: get_string(json, "current_position", ""),
    current_position_label: get_string(json, "current_position_label", ""),
    current_gloss: get_string(json, "current_gloss", ""),
    next_domain: get_string(json, "next_domain", ""),
    drive_slot: get_string(json, "drive_slot", ""),
    drive_slot_name: get_string(json, "drive_slot_name", ""),
    blocked: get_bool(json, "blocked", false),
    undecided: get_bool(json, "undecided", false),
    open_slots: get_array(json, "open_slots").map(fn(item) { open_slot(item) }),
    history_length: get_int(json, "history_length", 0),
    history: get_array(json, "history").map(fn(item) { loop_event(item) }),
  }
}

///|
/// The eight drive slots, in the backend's order.
pub fn decode_slots(json : Json) -> Array[Slot] {
  get_array(json, "slots").map(fn(item) {
    {
      name: get_string(item, "name", ""),
      designation: get_string(item, "designation", ""),
      gloss: get_string(item, "gloss", ""),
    }
  })
}

///|
/// Look up one slot's live edge at this position, if it has one.
pub fn find_open_slot(status : LoopStatus, name : String) -> OpenSlot? {
  for slot in status.open_slots {
    if slot.name == name {
      return Some(slot)
    }
  }
  None
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
