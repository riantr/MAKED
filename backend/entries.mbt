///| Workspace entries: the things a user brings to MAKED.
///
/// Every other piece of content in this project is seed data the maintainer
/// wrote. This is the first content the *user* writes, so it lives in its own
/// table and its own type rather than being bolted onto `Page`: a page is
/// navigation and site chrome, an entry is a record in someone's working set.
/// Sharing a table would let a user record silently appear in the site nav.
///
/// An entry names one of the five domains -- M, D, E, A, K -- because "put my
/// thing in" means putting it somewhere in the ring. The letter is stored
/// exactly as the ring spells it, and validation rejects anything else rather
/// than storing a value no later reader can interpret.

///|
/// One record in the user's workspace.
pub(all) struct Entry {
  /// Assigned by SQLite on insert. Monotonic, so ordering by it is ordering by
  /// creation without needing a clock the application can trust.
  id : Int64
  /// One of M, D, E, A, K.
  domain : String
  title : String
  body : String
  /// UTC ISO-8601, produced by SQLite's own `strftime` rather than by the
  /// application clock.
  created_at : String
} derive(Eq)

///|
/// The five domain letters, in the clockwise ring order the logo draws.
pub fn entry_domains() -> Array[String] {
  ["M", "D", "E", "A", "K"]
}

///|
/// A title longer than this is a paste accident, not a title. Rejecting it at
/// the boundary keeps a runaway client from filling the database in one request.
pub const MAX_ENTRY_TITLE : Int32 = 200

///|
/// The same guard for the body, generously: long notes are legitimate, and the
/// limit here is a backstop rather than a product decision.
pub const MAX_ENTRY_BODY : Int32 = 20000

///|
/// The outcome of checking a submitted entry: either cleaned fields ready to
/// store, or the reason it will not be stored.
///
/// `Invalid` carries a message meant to be shown to the person who typed it, so
/// it names the field and the limit rather than saying "bad request".
pub(all) enum EntryDraft {
  Accepted(String, String, String)
  Rejected(String)
}

///|
/// Check a submitted entry and normalise it.
///
/// Two normalisations happen here, and both matter downstream: surrounding
/// whitespace is stripped, because a title that renders with one leading space
/// looks like a layout bug rather than a typo; and the domain letter is
/// matched case-insensitively, because `m` and `M` meaning the same thing and
/// being stored differently would split one domain's records in two.
pub fn Entry::validate(
  domain : String,
  title : String,
  body : String,
) -> EntryDraft {
  let domain = normalise_domain(domain)
  let title = title.trim().to_owned()
  let body = body.trim().to_owned()
  if !entry_domains().contains(domain) {
    return Rejected(
      "domain must be one of " +
      join_letters(entry_domains()) +
      "; got \"" +
      domain +
      "\"",
    )
  }
  if title.is_empty() {
    return Rejected("title must not be empty")
  }
  if title.length() > MAX_ENTRY_TITLE {
    return Rejected(
      "title is " +
      title.length().to_string() +
      " characters; the limit is " +
      MAX_ENTRY_TITLE.to_string(),
    )
  }
  if body.length() > MAX_ENTRY_BODY {
    return Rejected(
      "body is " +
      body.length().to_string() +
      " characters; the limit is " +
      MAX_ENTRY_BODY.to_string(),
    )
  }
  Accepted(domain, title, body)
}

///|
/// Map whatever the user typed to a ring letter, or hand back what they typed
/// if it is not one.
///
/// Written as an explicit match rather than with a case-folding helper so the
/// accepted set is literally the same five letters `entry_domains` returns.
/// `tools/mutate-backend.ps1` does not cover this file, so the consistency is
/// pinned by a test instead: `entry_domains` and this function must accept
/// exactly the same set.
fn normalise_domain(raw : String) -> String {
  match raw.trim().to_owned() {
    "M" | "m" => "M"
    "D" | "d" => "D"
    "E" | "e" => "E"
    "A" | "a" => "A"
    "K" | "k" => "K"
    other => other
  }
}

///|
/// Join letters for a message. `Array::join` does not apply to `Array[String]`
/// in this version of the standard library, and the message is derived from the
/// array rather than typed out separately so the two cannot disagree.
fn join_letters(letters : Array[String]) -> String {
  let mut out = ""
  for letter in letters {
    if out != "" {
      out = out + ", "
    }
    out = out + letter
  }
  out
}

///|
/// Read a submitted entry out of a JSON request body.
///
/// Missing and wrongly-typed fields both decode to the empty string, which
/// `validate` then rejects with a message about that field. That is deliberate:
/// a missing key and an empty value are the same mistake to the person who made
/// it, and distinguishing them would only produce two messages for one problem.
pub fn Entry::from_json(json : Json) -> EntryDraft {
  Entry::validate(
    json_string(json, "domain"),
    json_string(json, "title"),
    json_string(json, "body"),
  )
}

///|
/// Pull a string field out of a JSON object, or the empty string if it is
/// missing or is not a string.
fn json_string(json : Json, key : String) -> String {
  match json {
    Object(fields) =>
      match fields.get(key) {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
pub fn Entry::to_json(self : Entry) -> Json {
  {
    "id": self.id,
    "domain": self.domain,
    "title": self.title,
    "body": self.body,
    "created_at": self.created_at,
  }
}

///|
/// What `POST /api/entries` answers with on success.
pub fn Entry::created_json(self : Entry) -> Json {
  { "entry": self.to_json() }
}
