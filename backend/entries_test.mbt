///| Workspace-entry tests: validation, JSON decoding, and storage.
///
/// The interesting properties here are the *rejections*. A workspace that
/// accepts anything silently is the failure mode this feature exists to avoid,
/// so most of these tests are about what must NOT be stored.

///|
async fn open_entries_db(name : String) -> @backend.Database {
  let path = "test_entries_" + name + ".db"
  drop_db(path)
  @backend.Database::open(path)
}

///|
/// The reason an entry was refused, or the empty string if it was accepted.
///
/// Test bodies read better when they can say `assert_eq(reason_of(draft), "")`
/// than when every call site matches on the enum.
fn reason_of(draft : @backend.EntryDraft) -> String {
  match draft {
    Accepted(_, _, _) => ""
    Rejected(reason) => reason
  }
}

///|
fn fields_of(draft : @backend.EntryDraft) -> (String, String, String) {
  match draft {
    Accepted(domain, title, body) => (domain, title, body)
    Rejected(_) => ("", "", "")
  }
}

///|
/// The ring, as the validator sees it. This is the consistency gate between
/// `entry_domains` (what the API advertises and the client renders) and
/// `normalise_domain` (what the API accepts). They are two separate lists and
/// nothing at the type level keeps them equal, so this test is what makes it
/// safe to have written them twice.
test "every advertised domain letter is also an accepted one" {
  for letter in @backend.entry_domains() {
    assert_eq(reason_of(@backend.Entry::validate(letter, "a title", "")), "")
  }
  assert_eq(@backend.entry_domains().length(), 5)
}

///|
/// And nothing else is accepted -- otherwise a caller could store a domain that
/// the listing endpoint will never show a heading for.
test "a domain outside the ring is refused" {
  let reason = reason_of(@backend.Entry::validate("Z", "a title", ""))
  assert_true(reason.contains("domain must be one of"))
  // The message has to name the valid set, or the user is left guessing.
  assert_true(reason.contains("M, D, E, A, K"))
}

///|
/// `m` and `M` are the same domain. Storing them differently would split one
/// domain's records in two, so the letter is normalised on the way in.
test "a lowercase domain letter is accepted and stored uppercase" {
  let (domain, _, _) = fields_of(@backend.Entry::validate(" m ", "t", ""))
  assert_eq(domain, "M")
}

///|
test "surrounding whitespace is stripped from the title" {
  let (_, title, _) = fields_of(@backend.Entry::validate("D", "  spaced  ", ""))
  assert_eq(title, "spaced")
}

///|
test "a title that is only whitespace is refused, not stored blank" {
  let reason = reason_of(@backend.Entry::validate("D", "   ", "body"))
  assert_eq(reason, "title must not be empty")
}

///|
/// An empty body is legitimate: a record can be a title and nothing else yet.
test "an empty body is allowed" {
  let (_, title, body) = fields_of(@backend.Entry::validate("D", "t", "   "))
  assert_eq(title, "t")
  assert_eq(body, "")
}

///|
test "an over-long title is refused and the message states the limit" {
  let long = "x".repeat(@backend.MAX_ENTRY_TITLE + 1)
  let reason = reason_of(@backend.Entry::validate("D", long, ""))
  assert_true(reason.contains("the limit is"))
  assert_true(reason.contains(@backend.MAX_ENTRY_TITLE.to_string()))
}

///|
test "a title exactly at the limit is accepted" {
  let exact = "x".repeat(@backend.MAX_ENTRY_TITLE)
  assert_eq(reason_of(@backend.Entry::validate("D", exact, "")), "")
}

///|
test "an over-long body is refused" {
  let long = "x".repeat(@backend.MAX_ENTRY_BODY + 1)
  assert_true(
    reason_of(@backend.Entry::validate("D", "t", long)).contains("the limit is"),
  )
}

///|
/// A missing key and an empty value are the same mistake to the person who made
/// it, so both produce the same complaint rather than two different errors.
test "a payload with no title is refused the same way as an empty one" {
  let json : Json = { "domain": "M", "body": "something" }
  assert_eq(
    reason_of(@backend.Entry::from_json(json)),
    "title must not be empty",
  )
}

///|
test "a payload whose title is the wrong type is refused" {
  let json : Json = { "domain": "M", "title": 42, "body": "" }
  assert_eq(
    reason_of(@backend.Entry::from_json(json)),
    "title must not be empty",
  )
}

///|
test "a payload with no domain names the valid set" {
  let json : Json = { "title": "something" }
  assert_true(
    reason_of(@backend.Entry::from_json(json)).contains("domain must be one of"),
  )
}

///|
test "a well-formed payload is accepted with its fields intact" {
  let json : Json = { "domain": "k", "title": "the failure", "body": "notes" }
  let (domain, title, body) = fields_of(@backend.Entry::from_json(json))
  assert_eq(domain, "K")
  assert_eq(title, "the failure")
  assert_eq(body, "notes")
}

///|
/// The whole point of the feature: what a user writes comes back out of the
/// database intact, with an id it did not have on the way in.
async test "an inserted entry round-trips with an id and a timestamp" {
  let db = open_entries_db("roundtrip")
  let entry = db.insert_entry("M", "my model", "what I believe")
  assert_true(entry.id > 0L)
  let stored = db.all_entries()
  assert_eq(stored.length(), 1)
  assert_eq(stored[0].id, entry.id)
  assert_eq(stored[0].domain, "M")
  assert_eq(stored[0].title, "my model")
  assert_eq(stored[0].body, "what I believe")
  // Stamped by SQLite's own strftime, so it is a UTC ISO-8601 instant.
  assert_true(stored[0].created_at.length() >= 19)
  assert_true(stored[0].created_at.contains("T"))
  db.close()
  drop_db("test_entries_roundtrip.db")
}

///|
/// Ordering is by rowid, not by the timestamp column, so a clock that jumps
/// backwards between two inserts cannot reorder someone's workspace.
async test "entries come back in creation order" {
  let db = open_entries_db("order")
  ignore(db.insert_entry("M", "first", ""))
  ignore(db.insert_entry("D", "second", ""))
  ignore(db.insert_entry("A", "third", ""))
  let stored = db.all_entries()
  assert_eq(stored.length(), 3)
  assert_eq(stored[0].title, "first")
  assert_eq(stored[1].title, "second")
  assert_eq(stored[2].title, "third")
  db.close()
  drop_db("test_entries_order.db")
}

///|
/// The second read must not be served from a cached first read. `prepare`
/// re-runs, but a forgotten `reset` would re-execute the *previous* statement
/// with new bindings -- so this asserts the delete is actually visible.
async test "a deleted entry is gone from the next read" {
  let db = open_entries_db("delete")
  let entry = db.insert_entry("K", "temporary", "")
  assert_eq(db.all_entries().length(), 1)
  assert_true(db.delete_entry(entry.id))
  assert_eq(db.all_entries().length(), 0)
  db.close()
  drop_db("test_entries_delete.db")
}

///|
/// Deleting something that is not there reports false, which is what lets the
/// API answer 404 instead of a 200 that claims to have removed a row.
async test "deleting an id that was never issued reports false" {
  let db = open_entries_db("delete_missing")
  ignore(db.insert_entry("K", "kept", ""))
  assert_true(!db.delete_entry(9999L))
  // And it must not have taken the other row with it.
  assert_eq(db.all_entries().length(), 1)
  db.close()
  drop_db("test_entries_delete_missing.db")
}

///|
/// Entries and pages are separate tables on purpose: a user record must never
/// be able to put itself into the site navigation.
async test "an entry does not appear as a page" {
  let db = open_entries_db("separation")
  db.seed(@backend.seed_pages())
  let before = db.all_pages().length()
  ignore(db.insert_entry("M", "not a page", ""))
  assert_eq(db.all_pages().length(), before)
  db.close()
  drop_db("test_entries_separation.db")
}
