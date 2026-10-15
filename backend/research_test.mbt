///| Research module tests.
///
/// The research module parses arxiv Atom XML and maps papers to pyroduct
/// triggers. These tests pin down the keyword heuristics and the public API
/// that would silently break if the mapping logic changed.

///|
/// paper_to_trigger maps SOTA keywords to AbsorbGlory.
test "paper_to_trigger maps SOTA to AbsorbGlory" {
  let paper : @backend.Paper = {
    id: "1",
    title: "State-of-the-Art SNN",
    summary: "We outperform all baselines",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.AbsorbGlory)
}

///|
/// paper_to_trigger maps limitation keywords to Sting.
test "paper_to_trigger maps limitation to Sting" {
  let paper : @backend.Paper = {
    id: "2",
    title: "Challenges in SNN",
    summary: "Current methods fail at scale",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.Sting)
}

///|
/// paper_to_trigger maps novel keywords to ActInFreedom.
test "paper_to_trigger maps novel to ActInFreedom" {
  let paper : @backend.Paper = {
    id: "3",
    title: "A Novel Approach to SNN",
    summary: "We propose a new method",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.ActInFreedom)
}

///|
/// paper_to_trigger maps survey keywords to KeepContinuity.
test "paper_to_trigger maps survey to KeepContinuity" {
  let paper : @backend.Paper = {
    id: "4",
    title: "A Survey of SNN Methods",
    summary: "Review of the field",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.KeepContinuity)
}

///|
/// paper_to_trigger maps benchmark keywords to FeelFinitude.
test "paper_to_trigger maps benchmark to FeelFinitude" {
  let paper : @backend.Paper = {
    id: "5",
    title: "SNN Benchmark Dataset",
    summary: "Evaluation framework",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.FeelFinitude)
}

///|
/// paper_to_trigger defaults to TouchFuture for neutral papers.
test "paper_to_trigger defaults to TouchFuture" {
  let paper : @backend.Paper = {
    id: "6",
    title: "SNN Implementation Details",
    summary: "Technical report on spiking networks",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.TouchFuture)
}

///|
/// paper_to_trigger priority: SOTA > limitation > novel > survey > benchmark.
test "paper_to_trigger respects priority order" {
  let paper : @backend.Paper = {
    id: "7",
    title: "Novel SOTA SNN with Challenges",
    summary: "We propose and outperform but also fail",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(@backend.paper_to_trigger(paper) is @sm.AbsorbGlory)
}

///|
/// trigger_to_slot returns the correct slot for each trigger.
test "trigger_to_slot maps triggers to slots" {
  assert_eq(@backend.trigger_to_slot(@sm.AbsorbGlory), @sm.Feedback)
  assert_eq(@backend.trigger_to_slot(@sm.Sting), @sm.Feedback)
  assert_eq(@backend.trigger_to_slot(@sm.ActInFreedom), @sm.Act)
  assert_eq(@backend.trigger_to_slot(@sm.KeepContinuity), @sm.Hold)
  assert_eq(@backend.trigger_to_slot(@sm.FeelFinitude), @sm.Occasion)
  assert_eq(@backend.trigger_to_slot(@sm.TouchFuture), @sm.Antecedent)
}

///|
/// Paper::to_json produces the expected shape.
test "Paper::to_json contains all fields" {
  let paper : @backend.Paper = {
    id: "test-id",
    title: "Test Title",
    summary: "Test Summary",
    authors: ["Alice", "Bob"],
    categories: ["cs.AI"],
    published: "2024-01-01",
    link: "http://example.com",
  }
  let json = paper.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("id") is Some(_))
      assert_true(fields.get("title") is Some(_))
      assert_true(fields.get("summary") is Some(_))
      assert_true(fields.get("authors") is Some(_))
      assert_true(fields.get("categories") is Some(_))
      assert_true(fields.get("published") is Some(_))
      assert_true(fields.get("link") is Some(_))
    }
    _ => fail("Paper::to_json did not return an object")
  }
}

///|
/// Paper::to_json preserves string content.
test "Paper::to_json preserves title and id" {
  let paper : @backend.Paper = {
    id: "my-id",
    title: "My Title",
    summary: "s",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  let json = paper.to_json()
  match json {
    Object(fields) => {
      match fields.get("id") {
        Some(String(s)) => assert_eq(s, "my-id")
        _ => fail("id is not a string")
      }
      match fields.get("title") {
        Some(String(s)) => assert_eq(s, "My Title")
        _ => fail("title is not a string")
      }
    }
    _ => fail("Paper::to_json did not return an object")
  }
}

///|
/// Paper equality works correctly.
test "Paper equality" {
  let p1 : @backend.Paper = {
    id: "1",
    title: "T",
    summary: "S",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  let p2 : @backend.Paper = {
    id: "1",
    title: "T",
    summary: "S",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  let p3 : @backend.Paper = {
    id: "2",
    title: "T",
    summary: "S",
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
  assert_true(p1 == p2)
  assert_true(p1 != p3)
}

///|
/// to_lowercase_ascii_for_test converts ASCII uppercase to lowercase.
test "to_lowercase_ascii_for_test converts ASCII uppercase" {
  let result = @backend.to_lowercase_ascii_for_test("Hello World")
  assert_eq(result, "hello world")
}

///|
/// to_lowercase_ascii_for_test handles empty string.
test "to_lowercase_ascii_for_test handles empty string" {
  let result = @backend.to_lowercase_ascii_for_test("")
  assert_eq(result, "")
}
