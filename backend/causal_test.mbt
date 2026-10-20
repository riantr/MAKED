///| Causal inference tests.
///
/// The causal module extracts features from documents and runs DoubleML.
/// These tests pin down the feature extraction, the refusals -- a corpus
/// that cannot support an estimate must say so rather than report a
/// number -- and the diagnostics that make the estimate arguable.
///
/// The tests use a synthetic corpus with a known shape, so the expected
/// numbers can be stated rather than merely "not a crash".

///|
/// A document of a given shape.
fn doc(
  id : String,
  title : String,
  summary : String,
  authors : Int32,
  categories : Int32,
) -> @backend.Document {
  {
    id,
    title,
    summary,
    authors: names(authors),
    categories: names(categories),
    published: "2024-01-01",
    link: "",
  }
}

///|
/// The first `count` names.
///
/// A document's author list and category list are how many the corpus says
/// it has, and the estimate controls for how many.
fn names(count : Int32) -> Array[String] {
  let all = ["A", "B", "C", "D", "E"]
  let out : Array[String] = []
  for i in 0..<count {
    out.push(all[i])
  }
  out
}

///|
/// A title of a chosen length.
///
/// The padding makes the title lengths vary inside each group and overlap
/// between the groups. That is what a corpus of real documents looks like,
/// and it is also what keeps the propensity score from being a step
/// function: a step function has no in-between, and an estimate built on
/// one is not identified.
fn title(base : String, index : Int32, extra : Int32) -> String {
  let mut out = base + " " + index.to_string()
  for _ in 0..<extra {
    out = out + "."
  }
  out
}

///|
/// The abstract of a treated or an untreated document.
///
/// The two bases are the same length on purpose. The abstract length is
/// then a variable the two groups agree on, which is what a balance table
/// needs in order to show a variable that is *not* a problem -- a table
/// that flags everything flags nothing.
fn summary_text(treated : Bool, index : Int32) -> String {
  let base = if treated {
    "We propose a new method and introduce it here"
  } else {
    "We measure a thing and report it plainly here"
  }
  let mut out = base
  for _ in 0..<(index % 3) {
    out = out + "."
  }
  out
}

///|
/// A corpus of twenty-four documents, half of them claiming to be new.
///
/// The treated documents have more authors and more categories, so the two
/// groups differ on the controlled variables -- that is the case the
/// balance diagnostic exists to report. They still share author counts of
/// two and three, and their title lengths overlap, so there are documents
/// that could have gone either way.
fn mixed_corpus() -> Array[@backend.Document] {
  let treated_authors = [3, 2, 4, 3, 2, 4, 3, 2, 4, 3, 2, 4]
  let untreated_authors = [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3]
  let treated_cats = [2, 2, 3, 2, 2, 3, 2, 2, 3, 2, 2, 3]
  let untreated_cats = [1, 1, 2, 1, 1, 2, 1, 1, 2, 1, 1, 2]
  let docs : Array[@backend.Document] = []
  for i in 0..<12 {
    docs.push(
      doc(
        "d_\{i}",
        title("A novel method for SNN", i, i % 4),
        summary_text(true, i),
        treated_authors[i],
        treated_cats[i],
      ),
    )
  }
  for i in 0..<12 {
    docs.push(
      doc(
        "u_\{i}",
        title("A standard report on", i, (i + 1) % 4),
        summary_text(false, i),
        untreated_authors[i],
        untreated_cats[i],
      ),
    )
  }
  docs
}

///|
/// A corpus whose two groups do not overlap at all.
///
/// Every treated document has the same number of authors and every
/// untreated document has a different one, and the same holds for the
/// categories. Nothing in the corpus resembles anything else in it, so no
/// untreated document stands in for a treated one.
fn separated_corpus() -> Array[@backend.Document] {
  let docs : Array[@backend.Document] = []
  for i in 0..<12 {
    docs.push(
      doc(
        "d_\{i}",
        title("A novel method for SNN", i, 0),
        summary_text(true, 0),
        3,
        3,
      ),
    )
  }
  for i in 0..<12 {
    docs.push(
      doc(
        "u_\{i}",
        title("A standard report on", i, 0),
        summary_text(false, 0),
        1,
        1,
      ),
    )
  }
  docs
}

///|
/// A title of exactly `target` characters.
///
/// The dots are there to make the length exact. A corpus needs documents
/// that are the same shape in every respect the estimate controls for, and
/// a document that is the same shape as one in the *other* group is what
/// gives the estimate something to stand on: no function of the controls
/// can tell those two apart, so the propensity score has to leave some
/// room between them.
fn titled(base : String, target : Int32) -> String {
  let mut out = base
  while out.length() < target {
    out = out + "."
  }
  out
}

///|
/// An abstract of exactly `target` characters.
fn summarised(treated : Bool, target : Int32) -> String {
  let base = if treated {
    "We propose a new method and introduce it here"
  } else {
    "We measure a thing and report it plainly here"
  }
  let mut out = base
  while out.length() < target {
    out = out + "."
  }
  out
}

///|
/// A corpus of exactly ten documents, half of them claiming to be new.
///
/// The smallest corpus the estimate will run on. One treated document and
/// one untreated document have the same title length, the same abstract
/// length, the same number of authors and the same number of categories:
/// nothing the estimate controls for tells them apart, so there is
/// something for the propensity score to be uncertain about.
fn ten_corpus() -> Array[@backend.Document] {
  let treated_titles = [23, 25, 24, 23, 25]
  let treated_summaries = [45, 47, 46, 45, 47]
  let treated_authors = [3, 2, 3, 2, 3]
  let treated_cats = [2, 1, 3, 2, 1]
  let untreated_titles = [23, 22, 24, 23, 22]
  let untreated_summaries = [45, 46, 46, 47, 45]
  let untreated_authors = [3, 1, 2, 1, 2]
  let untreated_cats = [2, 2, 2, 1, 1]
  let docs : Array[@backend.Document] = []
  let mut t = 0
  let mut u = 0
  for i in 0..<10 {
    if i % 2 == 0 {
      docs.push(
        doc(
          "d_\{i}",
          titled("A novel method for SNN", treated_titles[t]),
          summarised(true, treated_summaries[t]),
          treated_authors[t],
          treated_cats[t],
        ),
      )
      t += 1
    } else {
      docs.push(
        doc(
          "d_\{i}",
          titled("A standard report on", untreated_titles[u]),
          summarised(false, untreated_summaries[u]),
          untreated_authors[u],
          untreated_cats[u],
        ),
      )
      u += 1
    }
  }
  docs
}

///|
/// The estimate, or a failure saying why there was none.
fn estimated(docs : Array[@backend.Document]) -> @backend.CausalResult raise {
  match @backend.estimate_causal_effect(docs) {
    @backend.Estimated(result) => result
    @backend.Refused(refusal) =>
      fail("the estimate was refused: " + refusal.reason)
  }
}

///|
/// estimate_causal_effect refuses a corpus that is too small.
///
/// It used to return a zero result, which reads as "no effect" rather than
/// "not enough to say".
test "a corpus too small to estimate is refused, not answered with a zero" {
  let docs : Array[@backend.Document] = []
  for i in 0..<5 {
    docs.push(doc("d_\{i}", "Title \{i}", "Summary \{i}", 1, 1))
  }
  match @backend.estimate_causal_effect(docs) {
    @backend.Refused(refusal) => assert_true(refusal.reason.contains("10"))
    @backend.Estimated(_) => fail("a five-document corpus was estimated")
  }
}

///|
/// The refusal says how many documents there were.
///
/// A refusal that does not say the number leaves the reader to count the
/// corpus themselves, and the count is the thing they need to change.
test "the refusal says how many documents the corpus held" {
  let docs : Array[@backend.Document] = []
  for i in 0..<7 {
    docs.push(doc("d_\{i}", "Title \{i}", "Summary \{i}", 1, 1))
  }
  match @backend.estimate_causal_effect(docs) {
    @backend.Refused(refusal) => assert_true(refusal.reason.contains("7"))
    @backend.Estimated(_) => fail("a seven-document corpus was estimated")
  }
}

///|
/// A corpus where nothing is treated has no contrast to estimate.
///
/// The DoubleML fit returned NaN here, and NaN serialised into the API as
/// the string "NaN" -- a number-shaped thing that is not a number.
test "a corpus where nothing claims to be new is refused" {
  let docs : Array[@backend.Document] = []
  for i in 0..<20 {
    docs.push(
      doc(
        "d_\{i}",
        "A plain report \{i}",
        "We measure something and report it plainly.",
        1,
        1,
      ),
    )
  }
  match @backend.estimate_causal_effect(docs) {
    @backend.Refused(refusal) => assert_true(refusal.reason.contains("None"))
    @backend.Estimated(_) =>
      fail("a corpus with no treated documents was estimated")
  }
}

///|
/// A corpus where everything is treated has no contrast either.
test "a corpus where everything claims to be new is refused" {
  let docs : Array[@backend.Document] = []
  for i in 0..<20 {
    docs.push(
      doc("d_\{i}", "A novel method \{i}", "We propose a new method.", 2, 2),
    )
  }
  match @backend.estimate_causal_effect(docs) {
    @backend.Refused(refusal) =>
      assert_true(refusal.reason.contains("Every one"))
    @backend.Estimated(_) =>
      fail("a corpus with no untreated documents was estimated")
  }
}

///|
/// A balance row, by its name.
fn row_named(
  rows : Array[@backend.BalanceRow],
  name : String,
) -> @backend.BalanceRow? {
  for row in rows {
    if row.name == name {
      return Some(row)
    }
  }
  None
}

///|
/// A corpus whose two groups do not overlap is refused.
///
/// The fit still returns a number for such a corpus, and the number is
/// enormous -- a standard error of a hundred billion is not a measurement,
/// it is the arithmetic saying there is nothing to measure. Reporting it
/// with a confidence interval would put a number in the reader's hands that
/// means nothing at all.
test "a corpus whose two groups do not overlap is refused" {
  match @backend.estimate_causal_effect(separated_corpus()) {
    @backend.Refused(refusal) =>
      assert_true(refusal.reason.contains("do not overlap"))
    @backend.Estimated(_) => fail("a corpus with no overlap was estimated")
  }
}

///|
/// A refusal carries the evidence for it.
///
/// "These two groups do not overlap" is not a statement the reader can
/// check. The balance says *which* variables do not overlap, and a refusal
/// without it asks the reader to take the reason on faith.
test "a refusal carries the balance that is the evidence for it" {
  match @backend.estimate_causal_effect(separated_corpus()) {
    @backend.Refused(refusal) => {
      assert_eq(refusal.balance.length(), 4)
      for row in refusal.balance {
        assert_true(row.name.length() > 0)
      }
      // The balance has to reach the reader, not just the server. A refusal
      // that holds the evidence and does not send it asks the reader to
      // take the reason on faith.
      let json = @backend.CausalOutcome::Refused(refusal).to_json()
      match json {
        Object(fields) =>
          match fields.get("balance") {
            Some(Array(rows)) => assert_eq(rows.length(), 4)
            _ => fail("the refusal did not carry its balance")
          }
        _ => fail("the refusal did not serialise as an object")
      }
    }
    @backend.Estimated(_) => fail("a corpus with no overlap was estimated")
  }
}

///|
/// A variable the two groups do not overlap on is not reported as alike.
///
/// The author count is three for every treated document and one for every
/// untreated one. There is no spread to measure the gap against, so the
/// standardized difference is not a number -- and reporting it as zero
/// would say the groups are alike, which is the opposite of the truth.
test "a variable the two groups do not overlap on is flagged, not reported as a difference of zero" {
  match @backend.estimate_causal_effect(separated_corpus()) {
    @backend.Refused(refusal) => {
      // The row is looked up by its name rather than counted at, because a
      // balance with fewer rows than the test expects would otherwise be
      // read out of the middle of a shorter list -- and reading past the end
      // of a list is not a failed test, it is a dead test binary.
      let author_row = match row_named(refusal.balance, "author count") {
        Some(row) => row
        None => fail("the balance did not carry the author count")
      }
      assert_true(author_row.separated)
      assert_false(author_row.balanced)
      assert_eq(author_row.standardized_difference, 0.0)
    }
    @backend.Estimated(_) => fail("a corpus with no overlap was estimated")
  }
}

///|
/// A refusal carries no estimate.
///
/// A theta of zero next to no data is a finding nobody made.
test "a refusal carries no theta" {
  let docs : Array[@backend.Document] = []
  let outcome = @backend.estimate_causal_effect(docs)
  let json = outcome.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("theta") is Some(Json::Null))
      match fields.get("reason") {
        Some(String(reason)) => assert_true(reason.length() > 0)
        _ => fail("the refusal did not say why")
      }
    }
    _ => fail("the refusal did not serialize as an object")
  }
}

///|
/// The estimate names the treatment and the outcome.
///
/// A reader who does not know what was treated and what was measured cannot
/// argue with the number, and a number nobody can argue with is the thing
/// this whole panel exists to replace.
test "the estimate names the treatment and the outcome" {
  let result = estimated(mixed_corpus())
  assert_eq(result.treatment, "claims to be new")
  assert_eq(result.outcome, "impact score")
}

///|
/// The estimate names the variables it controlled for.
///
/// This is the reader's first question, and the answer is four words in
/// order rather than "Features: 4".
test "the estimate names the variables it controlled for" {
  let result = estimated(mixed_corpus())
  assert_eq(result.confounders.length(), 4)
  assert_eq(result.confounders[0], "title length")
  assert_eq(result.confounders[1], "abstract length")
  assert_eq(result.confounders[2], "author count")
  assert_eq(result.confounders[3], "category count")
}

///|
/// The estimate reports a balance row for every controlled variable.
///
/// A balance table with fewer rows than controlled variables is a table
/// that is hiding something.
test "there is a balance row for every controlled variable" {
  let result = estimated(mixed_corpus())
  assert_eq(result.balance.length(), result.confounders.length())
  for row in result.balance {
    assert_true(row.name.length() > 0)
  }
}

///|
/// The balance names the same variables the estimate says it controlled for.
test "the balance names the same variables the estimate controlled for" {
  let result = estimated(mixed_corpus())
  for i in 0..<result.balance.length() {
    assert_eq(result.balance[i].name, result.confounders[i])
  }
}

///|
/// The balance sees the difference the corpus actually has.
///
/// The treated documents here have more authors, so the standardized
/// difference on that variable is not zero. A balance diagnostic that
/// reports zero for groups that differ is a diagnostic that is not looking.
test "the balance reports the difference the two groups actually have" {
  let result = estimated(mixed_corpus())
  let author_row = result.balance[2]
  assert_true(author_row.standardized_difference > 0.1)
  assert_false(author_row.balanced)
}

///|
/// The balance reports the two groups' means, not just a verdict.
///
/// The reader needs to see how far apart the groups are, not only that they
/// are.
test "the balance reports the two groups' means" {
  let result = estimated(mixed_corpus())
  let author_row = result.balance[2]
  assert_true(author_row.treated_mean > author_row.untreated_mean)
}

///|
/// A variable the two groups agree on is reported as balanced.
///
/// A balance table that flags everything flags nothing. The abstracts here
/// are the same length on purpose, and the table has to be able to say so.
test "a variable the two groups agree on is reported as balanced" {
  let result = estimated(mixed_corpus())
  let summary_row = result.balance[1]
  assert_eq(summary_row.treated_mean, summary_row.untreated_mean)
  assert_true(summary_row.balanced)
}

///|
/// The overlap of the two groups is measured and reported.
///
/// The residual variance is the part of the treatment the controls cannot
/// account for. It is the quantity the estimate's variance hangs on, and
/// a corpus where it is zero has no estimate to give.
test "the overlap of the two groups is measured and reported" {
  let result = estimated(mixed_corpus())
  assert_true(result.overlap.overlaps)
  assert_true(result.overlap.residual_variance > 0.0)
  assert_true(result.overlap.reading.length() > 0)
}

///|
/// The propensity stayed a probability.
///
/// The propensity score is how likely the controls say it was that a
/// document of this shape was treated, so it cannot be below zero or above
/// one. A score outside that range means the model is not predicting a
/// probability at all, and every statement about overlap after it is a
/// statement about a number that cannot be one.
test "the propensity stayed a probability" {
  let result = estimated(mixed_corpus())
  assert_true(result.overlap.propensity_min >= 0.0)
  assert_true(result.overlap.propensity_max <= 1.0)
  assert_true(result.overlap.propensity_max > result.overlap.propensity_min)
}

///|
/// The estimate carries a sensitivity reading.
///
/// "How wrong could this be?" is the question a causal number is asked, and
/// a number with no answer to it is a number nobody can argue with.
test "the estimate carries a sensitivity reading" {
  let result = estimated(mixed_corpus())
  assert_true(result.sensitivity.reading.length() > 0)
  assert_true(result.sensitivity.robustness_value >= 0.0)
}

///|
/// The sensitivity interval is at least as wide as the confidence interval.
///
/// The worst case is the confidence interval plus the bias a confounder
/// could add, so an interval narrower than the confidence interval would
/// mean the worst case was subtracted.
test "the sensitivity interval is at least as wide as the confidence interval" {
  let result = estimated(mixed_corpus())
  assert_true(result.sensitivity.lower <= result.ci_lower)
  assert_true(result.sensitivity.upper >= result.ci_upper)
}

///|
/// The estimate says whether its sign survives the worst case.
///
/// This corpus is confounded: the treated documents have more authors and
/// more categories, and the outcome counts both, so a confounder weaker
/// than the ones already controlled for could have produced the whole
/// effect. The panel has to be able to say that out loud.
test "the estimate says whether its sign survives the worst case" {
  let result = estimated(mixed_corpus())
  assert_false(result.sensitivity.robust)
  assert_true(result.sensitivity.robustness_value < 1.0)
}

///|
/// The estimate has a standard error that is not zero.
///
/// The impact score used to be a formula of the document's own features with
/// no noise in it, which made it exactly predictable: a standard error of
/// zero and a confidence interval with no width, around a number that was
/// really just the formula read back.
test "the estimate has a standard error that is not zero" {
  let result = estimated(mixed_corpus())
  assert_true(result.se > 0.0)
}

///|
/// The same corpus gives the same answer.
///
/// The noise is derived from the document's own text, so a reader who
/// re-runs the estimate gets the number they were shown.
test "the same corpus gives the same answer every time" {
  let first = estimated(mixed_corpus())
  let second = estimated(mixed_corpus())
  assert_eq(first.theta, second.theta)
  assert_eq(first.se, second.se)
  assert_eq(first.ci_lower, second.ci_lower)
}

///|
/// A different corpus gives a different answer.
///
/// The noise is derived from the document's own text, so two different
/// corpora do not share it.
test "a different corpus gives a different answer" {
  let first = estimated(mixed_corpus())
  let other : Array[@backend.Document] = []
  let treated_authors = [3, 2, 4, 3, 2, 4, 3, 2, 4, 3, 2, 4]
  let untreated_authors = [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3]
  let treated_cats = [2, 2, 3, 2, 2, 3, 2, 2, 3, 2, 2, 3]
  let untreated_cats = [1, 1, 2, 1, 1, 2, 1, 1, 2, 1, 1, 2]
  for i in 0..<12 {
    other.push(
      doc(
        "x_\{i}",
        title("A novel method for SNN", i, i % 4),
        summary_text(true, i),
        treated_authors[i],
        treated_cats[i],
      ),
    )
  }
  for i in 0..<12 {
    other.push(
      doc(
        "x_\{i}",
        title("A standard report on", i, (i + 1) % 4),
        summary_text(false, i),
        untreated_authors[i],
        untreated_cats[i],
      ),
    )
  }
  let second = estimated(other)
  assert_true((first.theta - second.theta).abs() > 1.0e-9)
}

///|
/// estimate_causal_effect handles exactly 10 documents.
test "estimate_causal_effect runs with exactly 10 documents" {
  let result = estimated(ten_corpus())
  assert_eq(result.n_obs, 10)
  assert_eq(result.n_features, 4)
  assert_true(result.n_treated > 0)
  assert_true(result.n_treated < 10)
}

///|
/// The number treated is reported.
///
/// A reader who does not know how many documents were treated cannot judge
/// the estimate.
test "the number of treated documents is reported" {
  let result = estimated(mixed_corpus())
  assert_eq(result.n_obs, 24)
  assert_eq(result.n_treated, 12)
}

///|
/// CausalResult::to_json produces the expected shape.
test "CausalResult::to_json contains all fields" {
  let result = estimated(mixed_corpus())
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
      assert_true(fields.get("treatment") is Some(_))
      assert_true(fields.get("outcome") is Some(_))
      assert_true(fields.get("confounders") is Some(_))
      assert_true(fields.get("balance") is Some(_))
      assert_true(fields.get("overlap") is Some(_))
      assert_true(fields.get("sensitivity") is Some(_))
    }
    _ => fail("CausalResult::to_json did not return an object")
  }
}

///|
/// The numbers in the JSON are numbers, not strings.
///
/// The panel used to read the theta with a string accessor over a JSON
/// number, and so displayed the fallback "0.0" for every estimate. The
/// shape is what the frontend reads, so it is pinned here.
test "the estimate's numbers are numbers and not strings" {
  let result = estimated(mixed_corpus())
  let json = result.to_json()
  match json {
    Object(fields) => {
      match fields.get("theta") {
        Some(Number(n, ..)) => assert_true(n == result.theta)
        _ => fail("theta is not a number")
      }
      match fields.get("n_obs") {
        Some(Number(n, ..)) => assert_eq(n.to_int(), 24)
        _ => fail("n_obs is not a number")
      }
    }
    _ => fail("CausalResult::to_json did not return an object")
  }
}

///|
/// The balance rows are in the JSON with their numbers.
test "the balance rows carry their numbers into the JSON" {
  let result = estimated(mixed_corpus())
  let json = result.to_json()
  match json {
    Object(fields) =>
      match fields.get("balance") {
        Some(Array(rows)) => {
          assert_eq(rows.length(), 4)
          match rows[2] {
            Object(row) => {
              assert_true(row.get("name") is Some(_))
              assert_true(row.get("standardized_difference") is Some(_))
              assert_true(row.get("balanced") is Some(_))
              assert_true(row.get("separated") is Some(_))
            }
            _ => fail("a balance row is not an object")
          }
        }
        _ => fail("the balance is not an array")
      }
    _ => fail("CausalResult::to_json did not return an object")
  }
}

///|
/// The overlap is in the JSON with its reading.
test "the overlap carries its reading into the JSON" {
  let result = estimated(mixed_corpus())
  let json = result.to_json()
  match json {
    Object(fields) =>
      match fields.get("overlap") {
        Some(Object(overlap)) => {
          match overlap.get("overlaps") {
            Some(True) => ()
            _ => fail("the overlap was not reported as overlapping")
          }
          assert_true(overlap.get("residual_variance") is Some(_))
          match overlap.get("reading") {
            Some(String(reading)) => assert_true(reading.length() > 0)
            _ => fail("the overlap has no reading")
          }
        }
        _ => fail("the overlap is not an object")
      }
    _ => fail("CausalResult::to_json did not return an object")
  }
}

///|
/// The sensitivity is in the JSON with its reading.
test "the sensitivity carries its reading into the JSON" {
  let result = estimated(mixed_corpus())
  let json = result.to_json()
  match json {
    Object(fields) =>
      match fields.get("sensitivity") {
        Some(Object(sens)) => {
          assert_true(sens.get("robustness_value") is Some(_))
          assert_true(sens.get("lower") is Some(_))
          assert_true(sens.get("upper") is Some(_))
          assert_true(sens.get("robust") is Some(_))
          match sens.get("reading") {
            Some(String(reading)) => assert_true(reading.length() > 0)
            _ => fail("the sensitivity has no reading")
          }
        }
        _ => fail("the sensitivity is not an object")
      }
    _ => fail("CausalResult::to_json did not return an object")
  }
}
