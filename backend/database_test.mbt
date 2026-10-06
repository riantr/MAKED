///| Storage-layer tests.
///
/// The three SQLite behaviours that shaped this layer are the ones worth
/// pinning down, because all three fail *silently* rather than loudly:
///
///   1. `prepare` does not execute. A never-stepped statement is discarded by
///      `finalize`, so a missing step yields "no error, no table".
///   2. A completed statement must be `reset` before reuse.
///   3. `finalize` re-reports the last evaluation's error.
///
/// Each test here is written so that removing the corresponding safeguard
/// makes it fail, not merely change shape. A test that passes either way is
/// not evidence, so where a guard exists the test asserts on the *outcome*
/// the guard protects rather than on the guard itself.

///|
fn temp_db(name : String) -> String {
  "test_" + name + ".db"
}

///|
async fn drop_db(path : String) -> Unit {
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

///|
async fn open_fresh(name : String) -> Database {
  let path = temp_db(name)
  drop_db(path)
  Database::open(path)
}

///|
async test "seeded pages round-trip through SQLite" {
  let db = open_fresh("roundtrip")
  let pages = seed_pages()
  db.seed(pages)
  let loaded = db.all_pages()
  assert_eq(loaded.length(), pages.length())
  db.close()
  drop_db(temp_db("roundtrip"))
}

///|
async test "ring order survives storage: M D E A K" {
  let db = open_fresh("ring")
  db.seed(seed_pages())
  let loaded = db.all_pages()
  let domains = loaded.filter(fn(p) { p.letter != "" })
  // This is the load-bearing property: the order the logo draws the ring in,
  // not the order the name is spelled.
  assert_eq(
    domains.map(fn(p) { p.letter }),
    ["M", "D", "E", "A", "K"],
  )
  db.close()
  drop_db(temp_db("ring"))
}

///|
async test "re-seeding updates in place instead of duplicating" {
  let db = open_fresh("reseed")
  db.seed(seed_pages())
  let first = db.all_pages().length()
  db.seed(seed_pages())
  let second = db.all_pages().length()
  // Seed runs on every start-up, so it has to be idempotent.
  assert_eq(first, second)
  db.close()
  drop_db(temp_db("reseed"))
}

///|
async test "text content survives the round trip byte for byte" {
  let db = open_fresh("cjk")
  let page : Page = {
    slug: "cjk",
    title: "标题",
    letter: "字",
    role: "的角色",
    summary: "摘要 — 带破折号",
    body: "<p>模型攻击与对抗 — 太极环 &amp; more</p>",
    in_navigation: true,
    sort: 7,
  }
  db.seed([page])
  match db.page_by_slug("cjk") {
    Some(loaded) => {
      // The site content is CJK plus HTML entities; a lossy round trip would
      // show up here as mojibake rather than as an error.
      assert_eq(loaded.title, "标题")
      assert_eq(loaded.letter, "字")
      assert_eq(loaded.role, "的角色")
      assert_eq(loaded.summary, "摘要 — 带破折号")
      assert_eq(loaded.body, "<p>模型攻击与对抗 — 太极环 &amp; more</p>")
      assert_eq(loaded.in_navigation, true)
      assert_eq(loaded.sort, 7)
    }
    None => fail("page was not stored")
  }
  db.close()
  drop_db(temp_db("cjk"))
}

///|
async test "seeding two pages in one call does not repeat the first" {
  let db = open_fresh("tworows")
  // One seed call, two pages, one reused prepared statement. If `seed` forgot
  // to reset between iterations, the second insert would fail or carry the
  // first row's bindings, and this would catch it.
  db.seed([
    { slug: "one", title: "One", letter: "", role: "", summary: "s1",
      body: "b1", in_navigation: true, sort: 0 },
    { slug: "two", title: "Two", letter: "", role: "", summary: "s2",
      body: "b2", in_navigation: false, sort: 1 },
  ])
  assert_eq(db.all_pages().length(), 2)
  match db.page_by_slug("one") {
    Some(p) => {
      assert_eq(p.title, "One")
      assert_eq(p.summary, "s1")
      assert_eq(p.body, "b1")
      assert_eq(p.in_navigation, true)
    }
    None => fail("first page missing")
  }
  match db.page_by_slug("two") {
    Some(p) => {
      assert_eq(p.title, "Two")
      assert_eq(p.summary, "s2")
      assert_eq(p.body, "b2")
      assert_eq(p.in_navigation, false)
    }
    None => fail("second page missing")
  }
  db.close()
  drop_db(temp_db("tworows"))
}

///|
async test "a query for a missing slug returns None rather than raising" {
  let db = open_fresh("missing")
  db.seed(seed_pages())
  // Asserted by matching rather than `assert_eq` on an Option: that would
  // require a Debug impl on Page just to print a failure.
  assert_true(db.page_by_slug("no-such-page") is None)
  db.close()
  drop_db(temp_db("missing"))
}

///|
async test "migrate is idempotent and exec really executes" {
  // `Database::open` calls `migrate`, which creates the table. Opening the
  // same file twice is only safe if the DDL actually ran the first time AND
  // the schema statement is idempotent. A never-stepped DDL statement would
  // leave no table, and the seed below would fail with "no such table".
  let path = temp_db("migrate")
  drop_db(path)
  let first = Database::open(path)
  first.seed(seed_pages())
  first.close()
  let second = Database::open(path)
  assert_true(second.all_pages().length() > 0)
  second.close()
  drop_db(path)
}

///|
async test "navigation and lookup see seeded content" {
  let db = open_fresh("nav")
  db.seed(seed_pages())
  db.seed([home_page(), not_found_page()])
  let all = db.all_pages()
  // index sorts first, then the five domains in ring order, then utilities.
  assert_eq(all[0].slug, "index")
  assert_eq(all.length(), 10)
  match db.page_by_slug("about") {
    Some(p) => assert_true(p.body.contains("MoonBit"))
    None => fail("about page missing")
  }
  db.close()
  drop_db(temp_db("nav"))
}
