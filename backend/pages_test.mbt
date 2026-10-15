///| Pages module tests.
///
/// The pages module provides the seed data and helper functions for the five
/// domains. These tests pin down the ring order, the page structure, and the
/// JSON shape that the frontend depends on.

///|
/// ring_domains returns five domains in MDEAK order.
test "ring_domains returns five domains in MDEAK order" {
  let domains = @backend.ring_domains()
  assert_eq(domains.length(), 5)
  assert_eq(domains[0].0, "model")
  assert_eq(domains[0].2, "M")
  assert_eq(domains[1].0, "data")
  assert_eq(domains[1].2, "D")
  assert_eq(domains[2].0, "experience")
  assert_eq(domains[2].2, "E")
  assert_eq(domains[3].0, "attack")
  assert_eq(domains[3].2, "A")
  assert_eq(domains[4].0, "knowledge")
  assert_eq(domains[4].2, "K")
}

///|
/// Each domain tuple has the expected shape.
test "ring_domains tuples have non-empty fields" {
  for (slug, title, letter, role) in @backend.ring_domains() {
    assert_true(slug != "")
    assert_true(title != "")
    assert_true(letter != "")
    assert_true(role != "")
  }
}

///|
/// seed_pages returns eight pages: five domains + three utility pages.
test "seed_pages returns eight pages" {
  let pages = @backend.seed_pages()
  assert_eq(pages.length(), 8)
}

///|
/// seed_pages starts with the five domain pages in ring order.
test "seed_pages starts with MDEAK domain pages" {
  let pages = @backend.seed_pages()
  let letters = pages.map(fn(p) { p.letter })
  assert_eq(letters, ["M", "D", "E", "A", "K", "", "", ""])
}

///|
/// The first five seed pages have navigation enabled.
test "first five seed_pages have in_navigation true" {
  let pages = @backend.seed_pages()
  for i in 0..<5 {
    assert_true(pages[i].in_navigation)
  }
}

///|
/// home_page has the expected slug.
test "home_page has slug 'index'" {
  let home = @backend.home_page()
  assert_eq(home.slug, "index")
}

///|
/// home_page is not in the domain ring.
test "home_page has empty letter" {
  let home = @backend.home_page()
  assert_eq(home.letter, "")
}

///|
/// not_found_page has the expected slug.
test "not_found_page has slug '404'" {
  let nf = @backend.not_found_page()
  assert_eq(nf.slug, "404")
}

///|
/// not_found_page is not in navigation.
test "not_found_page has in_navigation false" {
  let nf = @backend.not_found_page()
  assert_true(!nf.in_navigation)
}

///|
/// Page::to_json produces the expected shape.
test "Page::to_json contains all required fields" {
  let page : @backend.Page = {
    slug: "test",
    title: "Test Page",
    letter: "T",
    role: "test role",
    summary: "test summary",
    body: "<p>test body</p>",
    in_navigation: true,
    sort: 5,
  }
  let json = page.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("slug") is Some(_))
      assert_true(fields.get("title") is Some(_))
      assert_true(fields.get("letter") is Some(_))
      assert_true(fields.get("role") is Some(_))
      assert_true(fields.get("summary") is Some(_))
      assert_true(fields.get("body") is Some(_))
      assert_true(fields.get("in_navigation") is Some(_))
      assert_true(fields.get("sort") is Some(_))
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// Page::to_json preserves string content.
test "Page::to_json preserves slug and title" {
  let page : @backend.Page = {
    slug: "my-slug",
    title: "My Title",
    letter: "X",
    role: "role",
    summary: "sum",
    body: "body",
    in_navigation: false,
    sort: 0,
  }
  let json = page.to_json()
  match json {
    Object(fields) => {
      match fields.get("slug") {
        Some(String(s)) => assert_eq(s, "my-slug")
        _ => fail("slug is not a string")
      }
      match fields.get("title") {
        Some(String(s)) => assert_eq(s, "My Title")
        _ => fail("title is not a string")
      }
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// Page::to_json preserves boolean and numeric fields.
test "Page::to_json preserves in_navigation and sort" {
  let page : @backend.Page = {
    slug: "s",
    title: "t",
    letter: "L",
    role: "r",
    summary: "s",
    body: "b",
    in_navigation: true,
    sort: 42,
  }
  let json = page.to_json()
  match json {
    Object(fields) => {
      match fields.get("in_navigation") {
        Some(True) => ()
        _ => fail("in_navigation is not true")
      }
      match fields.get("sort") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 42)
        _ => fail("sort is not a number")
      }
    }
    _ => fail("to_json did not return an object")
  }
}
