// Workspace entries on the client: the records a user brings to MAKED, and the
// draft that becomes one.
//
// The backend is the only writer of these records, so the shapes here mirror
// `backend/entries.mbt`. The draft lives in the model rather than being read
// back out of the DOM, so the submit path has exactly one source of truth and
// cannot disagree with what the screen shows.
//
// Every decoder here is total: a missing or wrong-typed field yields the
// supplied fallback rather than raising, so one malformed record cannot take
// the workspace down.

///|
/// One record in the user's workspace, as the client sees it.
///
/// The id is the database rowid. The backend stores it as an `Int64`, and
/// MoonBit's own `ToJson` implementation encodes an `Int64` as a *string*
/// rather than as a number, so the id arrives as "2" and not as 2. Decoding it
/// as a number would quietly yield 0 for every record, which would make every
/// Delete button ask the server to remove record 0.
pub(all) struct Entry {
  id : Int32
  domain : String
  title : String
  body : String
  created_at : String
} derive(Eq)

///|
/// Read the record id, which arrives as a string because the backend holds it
/// as an `Int64`.
///
/// Both spellings are accepted. The string is what this API actually sends;
/// the number is what the rest of the JSON in this project uses, and a
/// mismatch here would be invisible -- every id would decode to 0.
fn get_id(json : Json, key : String) -> Int32 {
  match field(json, key) {
    Some(String(text)) => @string.parse_int(text) catch { _ => 0 }
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
fn entry_from_json(json : Json) -> Entry {
  {
    id: get_id(json, "id"),
    domain: get_string(json, "domain", ""),
    title: get_string(json, "title", ""),
    body: get_string(json, "body", ""),
    created_at: get_string(json, "created_at", ""),
  }
}

///|
/// Decode `{"entries": [...]}` into the list of records.
pub fn decode_entries(json : Json) -> Array[Entry] {
  match field(json, "entries") {
    Some(Array(items)) => items.map(fn(item) { entry_from_json(item) })
    _ => []
  }
}

///|
/// The entry the server just created, from `{"entry": {...}}`.
///
/// `None` means the server answered with something that is not an entry. That
/// is not a decode accident to shrug at: it is the shape a refusal takes, and
/// the caller turns it into a sentence rather than into a silent nothing.
pub fn decode_created_entry(json : Json) -> Entry? {
  match field(json, "entry") {
    Some(obj) => Some(entry_from_json(obj))
    _ => None
  }
}

///|
/// Why the server refused, from `{"error": ..., "reason": ...}`.
///
/// The HTTP status code never reaches the client -- rabbita's HTTP client
/// hands over the body whatever the status was -- so the body is the only
/// place a reason can come from. Reading it is what turns a refused save from
/// a silent no-op into a sentence the person can act on.
pub fn decode_error_reason(json : Json) -> String {
  let reason = get_string(json, "reason", "")
  if reason != "" {
    reason
  } else {
    get_string(json, "error", "")
  }
}

///|
/// The five ring letters, in the ring's order.
///
/// The backend sends the list with the entries so the client never has to keep
/// a second copy of the ring. The fallback is the same five letters, used only
/// when the field is missing or empty.
pub fn decode_entry_domains(json : Json) -> Array[String] {
  match field(json, "entry_domains") {
    Some(Array(items)) => {
      let letters : Array[String] = []
      for item in items {
        match item {
          String(letter) => letters.push(letter)
          _ => ()
        }
      }
      if letters.length() == 0 {
        default_entry_domains()
      } else {
        letters
      }
    }
    _ => default_entry_domains()
  }
}

///|
pub fn default_entry_domains() -> Array[String] {
  ["M", "D", "E", "A", "K"]
}

///|
/// The client-side half of the server's validation.
///
/// The same rules, applied before the request goes out, so that the common
/// mistakes produce a sentence straight away instead of a round trip that
/// comes back as a refusal. The server still validates -- this is a courtesy,
/// not a substitute, and the two are kept in step by the shared letter list.
///
/// `draft_title` is trimmed before the emptiness test because a title of
/// spaces is not a title, and the server trims it too.
pub fn draft_problem(
  domains : Array[String],
  draft_domain : String,
  draft_title : String,
  c : Chrome,
) -> String {
  if draft_domain == "" {
    c.workspace.no_domain
  } else if !domains.contains(draft_domain) {
    c.workspace.wrong_domain
  } else if draft_title.trim().to_owned().is_empty() {
    c.workspace.no_title
  } else {
    ""
  }
}
