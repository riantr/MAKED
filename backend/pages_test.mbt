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
    title_zh: "测试页",
    role_zh: "测试角色",
    summary_zh: "测试摘要",
    body_zh: "<p>测试正文</p>",
  }
  let json = page.to_json(en())
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
    title_zh: "我的标题",
    role_zh: "角色",
    summary_zh: "摘要",
    body_zh: "正文",
  }
  let json = page.to_json(en())
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
    title_zh: "标题",
    role_zh: "角色",
    summary_zh: "摘要",
    body_zh: "正文",
  }
  let json = page.to_json(en())
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

///|
/// The page says what it says in the language it was handed.
///
/// The four words a page speaks -- its name, its role, its summary and its
/// body -- each have an English and a Chinese, and the language decides which
/// of the two is sent. This is the last surface that was still English in a
/// Chinese interface.
test "a page speaks in the language it was handed" {
  let page : @backend.Page = {
    slug: "s",
    title: "Model",
    letter: "M",
    role: "the model formulator",
    summary: "the model formulator",
    body: "<p>English body.</p>",
    in_navigation: true,
    sort: 0,
    title_zh: "模型",
    role_zh: "模型构建者",
    summary_zh: "模型构建者",
    body_zh: "<p>中文正文。</p>",
  }
  let english = page.to_json(en())
  let chinese = page.to_json(zh())
  match (english, chinese) {
    (Object(e), Object(z)) => {
      assert_eq(e.get("title"), Some(Json::string("Model")))
      assert_eq(e.get("body"), Some(Json::string("<p>English body.</p>")))
      assert_eq(z.get("title"), Some(Json::string("模型")))
      assert_eq(z.get("role"), Some(Json::string("模型构建者")))
      assert_eq(z.get("summary"), Some(Json::string("模型构建者")))
      assert_eq(z.get("body"), Some(Json::string("<p>中文正文。</p>")))
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// A page with no Chinese is shown in English rather than as a blank.
///
/// The same rule the model's own names follow, in the same place: an empty
/// Chinese name means "this page has no Chinese for it", and the reader gets
/// the English. A blank in the middle of a page is worse than a word in the
/// wrong language.
test "a page with no Chinese is shown in English" {
  let page : @backend.Page = {
    slug: "s",
    title: "Model",
    letter: "M",
    role: "the model formulator",
    summary: "the model formulator",
    body: "<p>English body.</p>",
    in_navigation: true,
    sort: 0,
    title_zh: "",
    role_zh: "",
    summary_zh: "",
    body_zh: "",
  }
  match page.to_json(zh()) {
    Object(fields) => {
      assert_eq(fields.get("title"), Some(Json::string("Model")))
      assert_eq(fields.get("role"), Some(Json::string("the model formulator")))
      assert_eq(fields.get("body"), Some(Json::string("<p>English body.</p>")))
    }
    _ => fail("to_json did not return an object")
  }
}

///|
/// Every page the server seeds has a Chinese to say.
///
/// A page with no Chinese body would fall back to its English -- which is
/// the rule, not a failure -- but the pages this project ships are written in
/// both languages, and one of them quietly losing its Chinese would be a hole
/// nobody would notice.
test "every seeded page has Chinese to say" {
  let pages = @backend.seed_pages()
  for page in pages {
    assert_true(page.title_zh != "")
    assert_true(page.body_zh != "")
  }
  assert_true(@backend.home_page().body_zh != "")
  assert_true(@backend.not_found_page().body_zh != "")
}

///|
/// The Chinese body is written in Chinese, not copied from the English.
///
/// The two are written separately rather than translated from one another, so
/// they do not have the same words in them. A Chinese body that is the
/// English body with a Chinese title over it is the failure this guards.
test "the Chinese body is written in Chinese" {
  for page in @backend.seed_pages() {
    assert_true(page.body_zh != page.body)
  }
  // The model page says what the ring is in each language: a transition
  // table in English, a transition table in Chinese.
  let model_page = @backend.seed_pages()[0]
  assert_true(model_page.body.contains("transition table"))
  assert_true(model_page.body_zh.contains("迁移表"))
}

///|
/// The page and the machine cannot call the same domain two different names.
///
/// The five domain pages are named by the machine -- the model knows a domain
/// in both languages, and the page takes the name it is given. This is the
/// one place the site and the machine could have drifted apart, so it is
/// pinned here rather than kept in step by hand.
test "a domain page is named the way the machine names it" {
  let model = @backend.current_model()
  for page in @backend.seed_pages() {
    if page.letter == "" {
      continue
    }
    let domain = model.domain_by_letter(page.letter).unwrap()
    assert_eq(page.title, domain.title)
    assert_eq(page.title_zh, domain.title_zh)
    assert_eq(page.role, domain.role)
    assert_eq(page.role_zh, domain.role_zh)
  }
}

///|
/// The pages do not still claim that the applications are empty.
///
/// The django deployment's pages said the cycle had never been written down,
/// that four of the five applications were empty scaffolds, and that nothing
/// routed from one domain to the next. That was true then. It is not true
/// now, and a page that says it is a page that lies about the program it
/// belongs to.
test "the pages do not still claim the applications are empty" {
  let pages = @backend.seed_pages()
  for page in pages {
    assert_true(!page.body.contains("scaffold"))
    assert_true(!page.body.contains("as a logo"))
  }
  assert_true(!@backend.home_page().body.contains("scaffold"))
  assert_true(!@backend.home_page().body.contains("as a logo"))
}
