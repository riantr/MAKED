///| Causal inference tests.
///
/// The causal module extracts features from papers and runs DoubleML. These
/// tests pin down the feature extraction logic and the edge case of too-few
/// papers, without requiring network access.

///|
/// estimate_causal_effect returns zero result for fewer than 10 papers.
test "estimate_causal_effect returns zero for small input" {
  let papers : Array[@backend.Paper] = []
  for i in 0..<5 {
    papers.push({
      id: "paper_\{i}",
      title: "Title \{i}",
      summary: "Summary \{i}",
      authors: ["Author"],
      categories: ["cs.AI"],
      published: "2024-01-01",
      link: "",
    })
  }
  let result = @backend.estimate_causal_effect(papers)
  assert_eq(result.n_obs, 5)
  assert_eq(result.n_treated, 0)
  assert_eq(result.n_features, 0)
  assert_eq(result.theta, 0.0)
  assert_eq(result.se, 0.0)
}

///|
/// estimate_causal_effect handles exactly 10 papers.
test "estimate_causal_effect runs with exactly 10 papers" {
  let papers : Array[@backend.Paper] = []
  for i in 0..<10 {
    let title = if i % 2 == 0 {
      "Novel method \{i}"
    } else {
      "Standard approach \{i}"
    }
    papers.push({
      id: "paper_\{i}",
      title,
      summary: "Summary for paper \{i} with enough text",
      authors: ["A", "B"],
      categories: ["cs.AI", "cs.LG"],
      published: "2024-01-0\{i}",
      link: "",
    })
  }
  let result = @backend.estimate_causal_effect(papers)
  assert_eq(result.n_obs, 10)
  assert_eq(result.n_features, 4)
  assert_true(result.n_treated >= 0)
  assert_true(result.n_treated <= 10)
}

///|
/// estimate_causal_effect handles 20 papers with mixed novelty.
test "estimate_causal_effect with mixed novelty papers" {
  let papers : Array[@backend.Paper] = []
  for i in 0..<20 {
    let title = if i < 10 {
      "Novel approach to SNN \{i}"
    } else {
      "Standard SNN method \{i}"
    }
    papers.push({
      id: "paper_\{i}",
      title,
      summary: "Abstract \{i}",
      authors: ["Author\{i}"],
      categories: ["cs.NE"],
      published: "2024-01-01",
      link: "",
    })
  }
  let result = @backend.estimate_causal_effect(papers)
  assert_eq(result.n_obs, 20)
  assert_eq(result.n_features, 4)
  assert_true(result.n_treated > 0)
}

///|
/// CausalResult::to_json produces the expected shape.
test "CausalResult::to_json contains all fields" {
  let result : @backend.CausalResult = {
    theta: 1.5,
    se: 0.3,
    ci_lower: 0.9,
    ci_upper: 2.1,
    n_obs: 100,
    n_treated: 40,
    n_features: 4,
  }
  let json = result.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("theta") is Some(_))
      assert_true(fields.get("se") is Some(_))
      assert_true(fields.get("ci_lower") is Some(_))
      assert_true(fields.get("ci_upper") is Some(_))
      assert_true(fields.get("n_obs") is Some(_))
      assert_true(fields.get("n_treated") is Some(_))
      assert_true(fields.get("n_features") is Some(_))
    }
    _ => fail("CausalResult::to_json did not return an object")
  }
}

///|
/// CausalResult::to_json preserves numeric values.
test "CausalResult::to_json preserves theta and n_obs" {
  let result : @backend.CausalResult = {
    theta: 2.5,
    se: 0.4,
    ci_lower: 1.7,
    ci_upper: 3.3,
    n_obs: 50,
    n_treated: 20,
    n_features: 4,
  }
  let json = result.to_json()
  match json {
    Object(fields) => {
      match fields.get("theta") {
        Some(Number(n, ..)) => assert_true((n - 2.5).abs() < 0.001)
        _ => fail("theta is not a number")
      }
      match fields.get("n_obs") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 50)
        _ => fail("n_obs is not a number")
      }
    }
    _ => fail("CausalResult::to_json did not return an object")
  }
}

///|
/// CausalResult with zero values serializes correctly.
test "CausalResult::to_json handles zero values" {
  let result : @backend.CausalResult = {
    theta: 0.0,
    se: 0.0,
    ci_lower: 0.0,
    ci_upper: 0.0,
    n_obs: 0,
    n_treated: 0,
    n_features: 0,
  }
  let json = result.to_json()
  match json {
    Object(fields) =>
      match fields.get("n_obs") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 0)
        _ => fail("n_obs is not a number")
      }
    _ => fail("CausalResult::to_json did not return an object")
  }
}
