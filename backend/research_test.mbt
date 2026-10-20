///| Research module tests.
///
/// The research module parses arxiv Atom XML and reads papers through the
/// mapping table. These tests pin down what the built-in table says, and
/// that a table of the reader's own decides for itself.

///|
/// A paper with the given words in it.
fn paper_with(title : String, summary : String) -> @backend.Paper {
  {
    id: "1",
    title,
    summary,
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
}

///|
/// The slot the built-in table gives a paper, and the rule that said so.
fn built_in_slot(paper : @backend.Paper) -> (String, String) {
  @backend.paper_to_slot(@backend.ResearchConfig::builtin(), paper)
}

///|
/// The built-in table maps SOTA to the feedback slot.
test "the built-in table maps a claim of superiority to feedback" {
  let (slot, _) = built_in_slot(
    paper_with("State-of-the-Art SNN", "We outperform all baselines"),
  )
  assert_eq(slot, "feedback")
}

///|
/// The built-in table maps limitation to the feedback slot.
test "the built-in table maps a reported failure to feedback" {
  let (slot, _) = built_in_slot(
    paper_with("Challenges in SNN", "Current methods fail at scale"),
  )
  assert_eq(slot, "feedback")
}

///|
/// The built-in table maps novel to the act slot.
test "the built-in table maps a new method to act" {
  let (slot, _) = built_in_slot(
    paper_with("A Novel Approach to SNN", "We propose a new method"),
  )
  assert_eq(slot, "act")
}

///|
/// The built-in table maps survey to the hold slot.
test "the built-in table maps a survey to hold" {
  let (slot, _) = built_in_slot(
    paper_with("A Survey of SNN Methods", "Review of the field"),
  )
  assert_eq(slot, "hold")
}

///|
/// The built-in table maps benchmark to the occasion slot.
test "the built-in table maps an evaluation to occasion" {
  let (slot, _) = built_in_slot(
    paper_with("SNN Benchmark Dataset", "Evaluation framework"),
  )
  assert_eq(slot, "occasion")
}

///|
/// The built-in table leaves a neutral paper to the fallback.
test "the built-in table leaves a neutral paper to the fallback" {
  let (slot, label) = built_in_slot(
    paper_with(
      "SNN Implementation Details", "Technical report on spiking networks",
    ),
  )
  assert_eq(slot, "antecedent")
  assert_eq(label, "Anything else")
}

///|
/// The built-in table's order is the priority.
test "the built-in table's order is the priority" {
  let (slot, _) = built_in_slot(
    paper_with(
      "Novel SOTA SNN with Challenges", "We propose and outperform but also fail",
    ),
  )
  assert_eq(slot, "feedback")
}

///|
/// A table of the reader's own decides for itself.
///
/// The table is not asked what it "should" say: a rule that says "reproduce"
/// drives the hold slot, and the built-in table's rules do not get a vote.
test "a table of the reader's own decides for itself" {
  let config = @backend.ResearchConfig::{
    rules: [
      {
        keywords: ["reproduce", "replication"],
        slot: "hold",
        label: "A reproduction",
        notes: "",
      },
    ],
    fallback_slot: "act",
    fallback_label: "Anything else",
    path: "",
  }
  let (slot, label) = @backend.paper_to_slot(
    config,
    paper_with("A reproduction study", "We reproduce every result"),
  )
  assert_eq(slot, "hold")
  assert_eq(label, "A reproduction")
}

///|
/// A table with no rule of its own falls back to what it says.
test "a table falls back to what it says" {
  let config = @backend.ResearchConfig::{
    rules: [
      {
        keywords: ["reproduce"],
        slot: "hold",
        label: "A reproduction",
        notes: "",
      },
    ],
    fallback_slot: "act",
    fallback_label: "Anything else",
    path: "",
  }
  let (slot, _) = @backend.paper_to_slot(
    config,
    paper_with("A new method", "We propose"),
  )
  assert_eq(slot, "act")
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
