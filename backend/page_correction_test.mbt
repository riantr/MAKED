///| Page-correction tests: what a reader may change, and what survives.
///
/// The property this file is about is durability. A page is seeded on every
/// start-up, and the seed overwrites what it owns, so a correction that was
/// written into the seeded columns would be gone the next time the server
/// started. The correction therefore lives in columns of its own, and the
/// first test here is the one that says so.

///|
async fn open_correction_db(name : String) -> @backend.Database {
  let path = "test_page_correction_" + name + ".db"
  drop_db(path)
  @backend.Database::open(path)
}

///|
/// The reason a correction was refused, or the empty string if it was accepted.
fn correction_reason_of(draft : @backend.PageCorrection) -> String {
  match draft {
    Accepted(_, _) => ""
    Rejected(reason) => reason
  }
}

///|
/// The reader's words, as the validator cleaned them.
fn correction_words_of(draft : @backend.PageCorrection) -> (String, String) {
  match draft {
    Accepted(title, body) => (title, body)
    Rejected(_) => ("", "")
  }
}

///|
/// A string field out of a JSON object, for reading the server's answer.
fn string_field(json : Json, key : String) -> String {
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
/// A correction is the reader's words, and the page says them.
///
/// The seeded text is what the page says until the reader says otherwise, and
/// after that the page says the reader's words.
async test "a corrected page says the reader's words" {
  let db = open_correction_db("words")
  db.seed(@backend.seed_pages())
  let pages = db.all_pages()
  assert_true(pages.length() > 0)
  let slug = pages[0].slug
  assert_true(db.update_page(slug, en(), "A better name", "The body I meant."))
  let corrected = db.page_by_slug(slug)
  match corrected {
    Some(page) => {
      // The page keeps the seed's words beside the reader's, and says the
      // reader's.
      assert_eq(page.corrected_title_of(en()), "A better name")
      assert_eq(page.corrected_body_of(en()), "The body I meant.")
      assert_true(page.corrected_in(en()))
      assert_true(page.corrected_at != "")
      assert_eq(string_field(page.to_json(en()), "title"), "A better name")
    }
    None => fail("the page was not there after the correction")
  }
  db.close()
  drop_db("test_page_correction_words.db")
}

///|
/// The correction survives the next seed.
///
/// This is the whole reason the correction has columns of its own. The seed
/// runs on every start-up and overwrites the columns it owns, so a correction
/// written into the seeded columns would be gone the moment the server
/// restarted -- and a correction that does not outlive the process that took
/// it is not a correction.
async test "a correction survives the next seed" {
  let db = open_correction_db("survives")
  db.seed(@backend.seed_pages())
  let slug = db.all_pages()[0].slug
  assert_true(db.update_page(slug, en(), "Still mine", "And still this."))
  // The seed runs again, exactly as it does on the next start-up.
  db.seed(@backend.seed_pages())
  let page = db.page_by_slug(slug)
  match page {
    Some(page) => {
      assert_eq(page.corrected_title_of(en()), "Still mine")
      assert_eq(page.corrected_body_of(en()), "And still this.")
      assert_true(page.corrected_in(en()))
      // And the page the reader sees says the reader's words, not the seed's.
      assert_eq(string_field(page.to_json(en()), "title"), "Still mine")
      assert_eq(string_field(page.to_json(en()), "body"), "And still this.")
    }
    None => fail("the page was not there after the seed")
  }
  db.close()
  drop_db("test_page_correction_survives.db")
}

///|
/// A page that was never corrected is not marked as corrected.
///
/// The flag is what tells the reader whose words they are reading, so a page
/// that says the seed's words must not claim to be the reader's.
async test "a page that was never corrected is not marked as corrected" {
  let db = open_correction_db("unmarked")
  db.seed(@backend.seed_pages())
  let page = db.all_pages()[0]
  assert_true(!page.corrected_in(en()))
  assert_true(!page.corrected_in(zh()))
  assert_eq(page.corrected_at, "")
  db.close()
  drop_db("test_page_correction_unmarked.db")
}

///|
/// A correction is in the language the reader read the page in.
///
/// A correction made in Chinese leaves the English prose alone, because the
/// two are the same page said twice: saying one of them differently is not
/// saying both of them differently.
async test "a correction in one language leaves the other alone" {
  let db = open_correction_db("language")
  db.seed(@backend.seed_pages())
  let slug = db.all_pages()[0].slug
  let seeded = db.page_by_slug(slug)
  let english_before = match seeded {
    Some(page) => page.title
    None => ""
  }
  assert_true(
    db.update_page(slug, zh(), "我改的名字", "我写的正文。"),
  )
  let page = db.page_by_slug(slug)
  match page {
    Some(page) => {
      assert_true(page.corrected_in(zh()))
      assert_true(!page.corrected_in(en()))
      assert_eq(page.corrected_title_of(zh()), "我改的名字")
      assert_eq(page.corrected_body_of(zh()), "我写的正文。")
      // The English is still the seed's English.
      assert_eq(page.title, english_before)
    }
    None => fail("the page was not there after the correction")
  }
  db.close()
  drop_db("test_page_correction_language.db")
}

///|
/// A correction does not move the page.
///
/// The slug, the place in the navigation and the order are the site's shape
/// rather than its prose. A reader who could move a page into the navigation
/// bar would be editing the site rather than its content, and that is not
/// what this is for.
async test "a correction does not move the page" {
  let db = open_correction_db("moves")
  db.seed(@backend.seed_pages())
  let before = db.all_pages()
  let slug = before[0].slug
  let sort_before = before[0].sort
  let nav_before = before[0].in_navigation
  assert_true(db.update_page(slug, en(), "A name", "A body."))
  let after = db.all_pages()
  assert_eq(after.length(), before.length())
  assert_eq(after[0].slug, slug)
  assert_eq(after[0].sort, sort_before)
  assert_eq(after[0].in_navigation, nav_before)
  db.close()
  drop_db("test_page_correction_moves.db")
}

///|
/// Correcting a page that is not there reports false, which is what lets the
/// API answer 404 instead of a 200 that claims to have changed something.
async test "correcting a page that is not there reports false" {
  let db = open_correction_db("missing")
  db.seed(@backend.seed_pages())
  assert_true(!db.update_page("no-such-page", en(), "A name", "A body."))
  db.close()
  drop_db("test_page_correction_missing.db")
}

///|
/// A correction without a title is refused.
///
/// A page with no name is not a page, and a correction that leaves the page
/// nameless is a deletion dressed up as an edit.
test "a correction without a title is refused" {
  let reason = correction_reason_of(
    @backend.Page::validate_correction("   ", "a body"),
  )
  assert_true(reason.contains("title must not be empty"))
}

///|
/// A correction may leave the body empty.
///
/// A reader may want a page to say less, and an empty body says exactly that.
/// The title is the one field that must be there.
test "a correction may leave the body empty" {
  let (title, body) = correction_words_of(
    @backend.Page::validate_correction("A name", "   "),
  )
  assert_eq(title, "A name")
  assert_eq(body, "")
}

///|
/// The reader's words are trimmed, like every other title in the project.
test "a correction is trimmed" {
  let (title, body) = correction_words_of(
    @backend.Page::validate_correction("  A name  ", "  a body  "),
  )
  assert_eq(title, "A name")
  assert_eq(body, "a body")
}

///|
/// A correction that is too long is refused rather than stored.
///
/// The limit is a backstop rather than a product decision, but a runaway
/// client must not be able to fill the database in one request.
test "an over-long correction is refused" {
  let mut long : String = ""
  let mut i = 0
  while i <= @backend.MAX_PAGE_TITLE {
    long = long + "x"
    i = i + 1
  }
  let reason = correction_reason_of(
    @backend.Page::validate_correction(long, "a body"),
  )
  assert_true(reason.contains("the limit is"))
}

///|
/// The page as JSON says the reader's words, and says that they are the
/// reader's.
///
/// The flag travels with the text because a page that speaks the reader's
/// words without saying so is a page the reader cannot trust: they cannot tell
/// their own sentence from the seed's.
async test "the page as JSON says whose words they are" {
  let db = open_correction_db("json")
  db.seed(@backend.seed_pages())
  let slug = db.all_pages()[0].slug
  assert_true(db.update_page(slug, en(), "A better name", "The body I meant."))
  let page = db.page_by_slug(slug)
  match page {
    Some(page) => {
      let json = page.to_json(en())
      assert_eq(string_field(json, "title"), "A better name")
      assert_eq(string_field(json, "body"), "The body I meant.")
      match json {
        Object(fields) => {
          match fields.get("corrected") {
            Some(True) => ()
            _ => fail("the page does not say that it was corrected")
          }
          assert_eq(string_field(json, "corrected_at"), page.corrected_at)
        }
        _ => fail("to_json did not return an object")
      }
    }
    None => fail("the page was not there after the correction")
  }
  db.close()
  drop_db("test_page_correction_json.db")
}

///|
/// A page that was never corrected says so in its JSON as well.
async test "an uncorrected page says it is not corrected" {
  let db = open_correction_db("json_plain")
  db.seed(@backend.seed_pages())
  let page = db.all_pages()[0]
  let json = page.to_json(en())
  match json {
    Object(fields) =>
      match fields.get("corrected") {
        Some(False) => ()
        _ => fail("the page claims a correction it does not have")
      }
    _ => fail("to_json did not return an object")
  }
  db.close()
  drop_db("test_page_correction_json_plain.db")
}
