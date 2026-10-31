///| Causal inference for the documents a corpus holds.
///
/// This module bridges the research cycle with causal inference: the documents
/// the corpus produced are treated as "treatments" and MAKED estimates their
/// causal effect on an impact score using the DoubleML framework.
///
/// The reader's first question about any causal number is "which variables
/// did you control for?" -- and a number without that answer is a number
/// nobody can argue with, which is the opposite of what a causal estimate is
/// for. So the estimate is reported together with:
///
///   - the **named** variables that were controlled, in words rather than as
///     four anonymous columns;
///   - the **balance** of each of them between the treated and the untreated
///     documents, because a controlled variable that the two groups differ
///     wildly on is a controlled variable that is not doing its job;
///   - a **sensitivity interval**: how strong an unobserved confounder would
///     have to be before the estimate's sign could flip. A point estimate
///     with a confidence interval answers "how noisy is this?"; the
///     sensitivity answer is "how wrong could this be?".
///
/// The outcome is synthetic -- MAKED has no citation counts for the reader's
/// own notes, so it scores documents on length, authorship and breadth, and
/// calls that an impact score. That is stated plainly in the panel rather
/// than dressed up as a finding about the literature, because a reader who
/// thinks MAKED measured impact will read the number as a fact about the
/// world.
///
/// The documents are whatever the corpus holds. The analysis does not care
/// whether they came from arxiv, from a feed or from the reader's own
/// folder, because the features are read from the text either way.

///|
/// The variables the estimate controls for, in the order they are used.
///
/// Named rather than anonymous, because "we controlled for four things" is
/// not an answer a reader can check.
pub fn confounders() -> Array[String] {
  ["title length", "abstract length", "author count", "category count"]
}

///|
/// The treatment: whether a document claims to be new.
///
/// The words are the ones a paper uses to say it is novel. A treatment
/// defined by keywords is a crude instrument, and the panel says so.
pub fn treatment_name() -> String {
  "claims to be new"
}

///|
/// The outcome: the impact score.
///
/// MAKED cannot count citations in a reader's own notes, so it scores a
/// document on its length, its authorship and its breadth. The name says
/// what it is.
pub fn outcome_name() -> String {
  "impact score"
}

///|
/// The words that make a document "treated".
///
/// A document that says it proposes or introduces something is treated. The
/// list is a keyword heuristic, and a keyword heuristic is a measurement of
/// how a paper talks, not of what it does.
pub fn novelty_words() -> Array[String] {
  ["novel", "new method", "propose", "introduce", "we present a new"]
}

///|
/// How much noise the impact score carries.
///
/// The impact score used to be a formula of the document's own features with
/// no noise at all, which made it exactly predictable -- and a quantity
/// that is exactly predictable has a standard error of zero and a confidence
/// interval with no width. The panel then reported a tight interval around
/// a number that was really just the formula, read back.
///
/// The noise is what makes the interval mean something. It is deterministic
/// -- derived from the document's own text -- so the same corpus gives the
/// same answer every time, and a reader who re-runs the estimate gets the
/// number they were shown rather than a different one.
const NOISE_SCALE : Double = 1.6

///|
/// Result of a causal inference run.
pub(all) struct CausalResult {
  theta : Double
  se : Double
  ci_lower : Double
  ci_upper : Double
  n_obs : Int32
  n_treated : Int32
  n_features : Int32
  /// The name of the treatment, so the reader knows what was treated.
  treatment : String
  /// The name of the outcome, so the reader knows what was measured.
  outcome : String
  /// The variables that were controlled for, named.
  confounders : Array[String]
  /// The balance of each controlled variable between the two groups.
  balance : Array[BalanceRow]
  /// Whether the two groups overlap at all, and how much.
  overlap : Overlap
  /// The sensitivity of the estimate to an unobserved confounder.
  sensitivity : Sensitivity
} derive(Debug)

///|
pub extend CausalResult with Debug::{to_repr}

///|
/// Whether the two groups overlap, and how much.
///
/// The overlap is the assumption the whole estimate rests on: there must be
/// documents that could have gone either way, or nothing in the corpus says
/// what an untreated document that looked like a treated one would have
/// scored.
///
/// When the treated documents are entirely unlike the untreated ones --
/// every treated title a different length from every untreated title, say --
/// the propensity score is a step function and the estimate is not
/// identified at all. The fit still returns a number, and the number is
/// enormous: a standard error of a hundred billion is not a measurement,
/// it is the arithmetic saying there is nothing to measure. So the overlap
/// is measured and reported, and the estimate says so.
pub(all) struct Overlap {
  /// Whether the two groups overlap at all.
  overlaps : Bool
  /// How much of the treatment the propensity score leaves unexplained.
  ///
  /// The variance of the treatment residual, `d - m(x)`. It is zero when
  /// the controls predict the treatment perfectly, and it is the quantity
  /// the estimator's variance is inversely proportional to.
  residual_variance : Double
  /// The lowest propensity score the controls gave a document.
  ///
  /// The propensity score is a probability -- how likely the controls say
  /// it was that a document of this shape was treated -- so it cannot be
  /// below zero. A score below zero means the model is not predicting a
  /// probability at all, and every statement about overlap that follows
  /// from it is a statement about a number that cannot be one.
  propensity_min : Double
  /// The highest propensity score the controls gave a document.
  ///
  /// The other end of the same bound: a probability cannot be above one.
  propensity_max : Double
  /// A sentence saying what the overlap means, in words.
  reading : String
} derive(Debug)

///|
pub extend Overlap with Debug::{to_repr}

///|
/// How one controlled variable compares between the treated and the
/// untreated documents.
///
/// The standardized difference is the mean gap divided by the pooled
/// spread. It is the number to read: a variable whose two groups differ by
/// more than a tenth of a standard deviation is a variable the two groups
/// do not really have in common, and controlling for it does not make the
/// groups comparable.
pub(all) struct BalanceRow {
  /// The variable's name, in words.
  name : String
  /// The mean of the variable among the treated documents.
  treated_mean : Double
  /// The mean of the variable among the untreated documents.
  untreated_mean : Double
  /// The standardized difference between the two means.
  standardized_difference : Double
  /// Whether the two groups are close enough on this variable.
  balanced : Bool
  /// Whether the two groups do not overlap on this variable at all.
  ///
  /// A variable that is the same for every treated document and a different
  /// constant for every untreated one has no spread to measure the gap
  /// against, so the standardized difference is not a number. It is the
  /// worst case there is, and it is reported as the flag it is rather than
  /// as a difference of zero -- a zero there would say the groups are
  /// alike, which is the opposite of the truth.
  separated : Bool
} derive(Debug)

///|
pub extend BalanceRow with Debug::{to_repr}

///|
/// How much an unobserved confounder would have to do to change the answer.
///
/// The robustness value is the factor by which the confounding strength
/// would have to grow before the estimate's sign could flip. A value above
/// one means the estimate survives a confounder stronger than the one the
/// reader would have to invent to break it; a value below one means a
/// plausible confounder could already have flipped it.
pub(all) struct Sensitivity {
  /// The robustness value: the multiple of confounding that would flip the
  /// sign of the estimate.
  robustness_value : Double
  /// The interval the estimate takes when the worst case is allowed for.
  lower : Double
  /// The interval the estimate takes when the worst case is allowed for.
  upper : Double
  /// A sentence saying what the robustness value means, in words.
  reading : String
  /// Whether the estimate's sign survives the worst case.
  ///
  /// This is the confounding question alone -- the confidence interval is
  /// not part of it. "The estimate could be zero" and "a confounder could
  /// flip the estimate" are two different weaknesses, and folding them into
  /// one flag would hide the second behind the first: an estimate that is
  /// merely noisy would be reported as fragile, and an estimate that is
  /// merely fragile would be reported as noisy.
  robust : Bool
} derive(Debug)

///|
pub extend Sensitivity with Debug::{to_repr}

///|
/// The threshold at which two groups are said to differ on a variable.
///
/// A tenth of a pooled standard deviation. It is the conventional cut-off
/// and it is written down so the reader does not have to guess.
const BALANCE_THRESHOLD : Double = 0.1

///|
/// Convert a CausalResult to JSON for the API.
pub fn CausalResult::to_json(self : CausalResult) -> Json {
  {
    "theta": self.theta,
    "se": self.se,
    "ci_lower": self.ci_lower,
    "ci_upper": self.ci_upper,
    "n_obs": self.n_obs,
    "n_treated": self.n_treated,
    "n_features": self.n_features,
    "treatment": self.treatment,
    "outcome": self.outcome,
    "confounders": self.confounders,
    "balance": [..self.balance.map(fn(row) { row.to_json() })],
    "overlap": self.overlap.to_json(),
    "sensitivity": self.sensitivity.to_json(),
  }
}

///|
/// Convert a balance row to JSON.
pub fn BalanceRow::to_json(self : BalanceRow) -> Json {
  {
    "name": self.name,
    "treated_mean": self.treated_mean,
    "untreated_mean": self.untreated_mean,
    "standardized_difference": self.standardized_difference,
    "balanced": self.balanced,
    "separated": self.separated,
  }
}

///|
/// Convert the overlap reading to JSON.
pub fn Overlap::to_json(self : Overlap) -> Json {
  {
    "overlaps": self.overlaps,
    "residual_variance": self.residual_variance,
    "propensity_min": self.propensity_min,
    "propensity_max": self.propensity_max,
    "reading": self.reading,
  }
}

///|
/// Convert the sensitivity reading to JSON.
pub fn Sensitivity::to_json(self : Sensitivity) -> Json {
  {
    "robustness_value": self.robustness_value,
    "lower": self.lower,
    "upper": self.upper,
    "reading": self.reading,
    "robust": self.robust,
  }
}

///|
/// The result of an estimate that could not be made.
///
/// A causal estimate that cannot be made is not a zero. Saying "0.0" when
/// the documents do not support an estimate is a number that reads as a
/// finding, and this project does not trade in numbers that read as
/// findings when they are not.
///
/// A refusal carries its evidence. "These two groups do not overlap" is a
/// statement the reader cannot check without the table that shows *which*
/// variables do not overlap, so the balance travels with the refusal.
pub(all) struct CausalRefusal {
  /// Why the estimate was not made, in words.
  reason : String
  /// The balance of the two groups, where there is one to report.
  balance : Array[BalanceRow]
} derive(Debug)

///|
pub extend CausalRefusal with Debug::{to_repr}

///|
/// The result of a causal run: an estimate, or a refusal.
pub(all) enum CausalOutcome {
  Estimated(CausalResult)
  Refused(CausalRefusal)
}

///|
/// A refusal that says the corpus could not be read.
///
/// The reason is the one the reader of the corpus was given, not a reason
/// about the size of the corpus. "Only 0 documents; a causal estimate needs
/// at least 10" would be a true statement about an empty corpus and a false
/// one about a corpus that could not be read at all, and the reader who
/// cannot tell the two apart is left to go and look for a corpus that is
/// large enough instead of one that is there.
pub fn CausalOutcome::refused_because(reason : String) -> CausalOutcome {
  Refused({ reason, balance: [], })
}

///|

///|
/// The features of one document: the numbers, or the name of the controlled
/// variable that has no feature to read.
pub(all) struct FeatureRow {
  values : Array[Double]
  unreadable : String?
}

///|
/// The value of one controlled variable, read from a document.
///
/// The controlled variables are named by `confounders()`, and this is where
/// each name says where its number comes from. One list and one count: the
/// width of the feature vector is the number of names, and a name with no
/// feature to read is a refusal rather than a silent zero -- a control that
/// is always zero is not a control, and an estimate that says it controlled
/// for something it did not is worse than no estimate at all.
fn feature_of(document : Document, name : String) -> Double? {
  match name {
    "title length" => Some(document.title.length().to_double())
    "abstract length" => Some(document.summary.length().to_double())
    "author count" => Some(document.authors.length().to_double())
    "category count" => Some(document.categories.length().to_double())
    _ => None
  }
}

///|
/// Extract numerical features from a document for causal analysis.
///
/// Returns the feature vector, the treatment indicator, the outcome, and the
/// noise the outcome carries. The features are in the order `confounders()`
/// names them -- the width of the vector is the number of names, not a
/// number written down here, because a width that is written down and a
/// list that is written down are two things that can drift apart, and a
/// feature vector that does not fit the matrix takes the server down.
fn document_to_features(
  document : Document,
  names : Array[String],
) -> (FeatureRow, Double, Double, Double) {
  let title_len = document.title.length().to_double()
  let summary_len = document.summary.length().to_double()
  let n_authors = document.authors.length().to_double()
  let n_cats = document.categories.length().to_double()

  // The treatment: the document claims to be new.
  let text = (document.title + " " + document.summary).to_lowercase_ascii()
  let mut is_novel = 0.0
  for word in novelty_words() {
    if text.contains(word) {
      is_novel = 1.0
    }
  }

  // The outcome: an impact score built from the document's own shape.
  //
  // The score is deliberately simple and deliberately synthetic. MAKED has
  // no citation counts for a reader's own notes, so it says what it can
  // measure and names it for what it is.
  let impact = 0.3 * title_len +
    0.1 * summary_len / 100.0 +
    0.5 * n_authors +
    0.4 * n_cats +
    0.8 * is_novel

  // The noise the score carries, derived from the document's own text so
  // that the same corpus always gives the same answer.
  let noise = document_noise(document)

  // The features, in the order the names give.
  let values : Array[Double] = []
  for name in names {
    match feature_of(document, name) {
      Some(value) => values.push(value)
      None =>
        return (
          { values: [], unreadable: Some(name), },
          is_novel,
          impact + noise,
          noise,
        )
    }
  }
  ({ values, unreadable: None, }, is_novel, impact + noise, noise)
}

///|
/// The noise a document's impact score carries.
///
/// Derived from the document's own text, so it is the same on every run and
/// on every machine: a reader who re-runs the estimate gets the number they
/// were shown, and a test can pin it.
///
/// The hash is FNV-1a over the text, and the two halves of the result drive
/// a Box-Muller pair, so the noise is normally distributed rather than
/// uniform. A uniform noise would put too much probability exactly on the
/// score, and a normal one is what a reader expects a "random" term to be.
fn document_noise(document : Document) -> Double {
  let text = document.id + "|" + document.title + "|" + document.summary
  let h = fnv1a(text)
  // The high 32 bits and the low 32 bits, as two independent-ish uniforms.
  let u1 = ((h >> 32) & 0xFFFFFFFFL).to_double() / 4294967296.0
  let u2 = (h & 0xFFFFFFFFL).to_double() / 4294967296.0
  // Box-Muller: one normal variate from two uniforms.
  //
  // `u1` is pushed away from zero first, because `ln(0)` is not a number
  // and a hash that lands on exactly zero is rare but not impossible.
  let safe = if u1 < 1.0e-12 { 1.0e-12 } else { u1 }
  let radius = (-2.0 * @math.ln(safe)).sqrt()
  let angle = 2.0 * 3.141592653589793 * u2
  NOISE_SCALE * radius * @math.cos(angle)
}

///|
/// FNV-1a over a string, as a 64-bit value.
///
/// The multiplication wraps on overflow, which is the behaviour the hash
/// wants: the arithmetic is defined modulo 2^64.
///
/// The constants are the 64-bit FNV prime and an offset basis that fits in
/// a signed 64-bit integer. The canonical offset basis
/// (14695981039346656037) is larger than `Int64`'s maximum, so it is
/// written as the value that fits: the same bits, read as signed.
fn fnv1a(text : String) -> Int64 {
  let mut hash : Int64 = 6364136223846793005L
  let prime : Int64 = 1099511628211L
  for ch in text.iter() {
    hash = hash ^ ch.to_int().to_int64()
    hash = hash * prime
  }
  hash
}

///|
/// The learner that estimates the propensity score.
///
/// The propensity score is `P(treated | the controls)`: a probability. The
/// DoubleML port's default for this slot is a linear regression, which
/// predicts the treatment as a plain number -- and a number outside zero
/// and one is not a probability. It works for the estimator's arithmetic,
/// but it makes the overlap diagnostic say things that are not true: a
/// propensity of minus two does not mean "there are documents that could
/// have gone either way".
///
/// The treatment here is binary, so a logistic regression is the honest
/// instrument for it.
fn propensity_learner() -> @dml.LearnerDispatch {
  @dml.LearnerDispatch::logistic_regression(@dml.LogisticRegression::new())
}

///|
/// The balance of the two groups on each controlled variable.
///
/// One row per variable in `confounders()`. The standardized difference is
/// the mean gap over the pooled standard deviation, which is the number
/// that says whether the two groups are comparable on that variable.
fn balance_of(
  x_flat : Array[Double],
  d : Array[Double],
  n : Int32,
  p : Int32,
) -> Array[BalanceRow] {
  let rows : Array[BalanceRow] = []
  for j in 0..<p {
    let name = confounders()[j]
    let mut sum_t = 0.0
    let mut sum_u = 0.0
    let mut sum_t2 = 0.0
    let mut sum_u2 = 0.0
    let mut n_t = 0
    let mut n_u = 0
    for i in 0..<n {
      let value = x_flat[i * p + j]
      if d[i] > 0.5 {
        sum_t = sum_t + value
        sum_t2 = sum_t2 + value * value
        n_t += 1
      } else {
        sum_u = sum_u + value
        sum_u2 = sum_u2 + value * value
        n_u += 1
      }
    }
    if n_t == 0 || n_u == 0 {
      // A group with nobody in it has no mean. The row says so rather than
      // reporting a number nobody can interpret.
      rows.push({
        name,
        treated_mean: 0.0,
        untreated_mean: 0.0,
        standardized_difference: 0.0,
        balanced: false,
        separated: false,
      })
      continue
    }
    let mean_t = sum_t / n_t.to_double()
    let mean_u = sum_u / n_u.to_double()
    // The pooled variance, with each group's own degrees of freedom.
    let var_t = if n_t > 1 {
      (sum_t2 - n_t.to_double() * mean_t * mean_t) / (n_t - 1).to_double()
    } else {
      0.0
    }
    let var_u = if n_u > 1 {
      (sum_u2 - n_u.to_double() * mean_u * mean_u) / (n_u - 1).to_double()
    } else {
      0.0
    }
    let pooled = ((var_t + var_u) / 2.0).sqrt()
    let gap = mean_t - mean_u
    // A variable that does not vary at all in either group has no scale to
    // measure the gap against.
    //
    // The two cases are different facts and are reported differently. When
    // the gap is zero too, the groups really are alike on this variable.
    // When the gap is not zero, the two groups sit on different constants
    // and do not overlap at all -- the worst case there is. Reporting a
    // standardized difference of zero there would say the groups are alike,
    // which is the opposite of the truth, and it is how a diagnostic ends
    // up lying about the corpus it was asked about.
    let separated = pooled <= 1.0e-12 && gap.abs() > 1.0e-12
    let standardized = if pooled > 1.0e-12 { gap / pooled } else { 0.0 }
    rows.push({
      name,
      treated_mean: mean_t,
      untreated_mean: mean_u,
      standardized_difference: standardized,
      balanced: !separated && standardized.abs() <= BALANCE_THRESHOLD,
      separated,
    })
  }
  rows
}

///|
/// Whether the two groups overlap, and how much.
///
/// The overlap is measured on the treatment residual the estimator actually
/// works with: `d - m(x)`, the part of the treatment the controls cannot
/// account for. The variance of that residual is the quantity the
/// estimator's variance is inversely proportional to, so it is the honest
/// measure of how much the corpus leaves to chance.
///
/// `m(x)` is a probability here -- the propensity score -- so a residual
/// that is large means the document was a coin flip: the controls did not
/// decide it, and something the corpus does not record did.
///
/// A residual variance of zero means the controls predict the treatment
/// perfectly: every treated document looks like a treated document and
/// every untreated one like an untreated one, with nothing in between. The
/// estimate is then not identified, and the fit's enormous standard error
/// is the arithmetic saying so. This says so in words.
fn overlap_of(model : @dml.DoubleMLPLR, d : Array[Double]) -> Overlap {
  let n = d.length()
  let m_hat = model.predictions_m()
  let mut ss = 0.0
  let mut lowest = m_hat[0]
  let mut highest = m_hat[0]
  for i in 0..<n {
    let v = d[i] - m_hat[i]
    ss = ss + v * v
    if m_hat[i] < lowest {
      lowest = m_hat[i]
    }
    if m_hat[i] > highest {
      highest = m_hat[i]
    }
  }
  let variance = ss / n.to_double()
  // A residual variance below this is zero for every purpose that matters:
  // it is a hundred billion times smaller than the variance of a coin
  // toss, and the estimate built on it has a standard error to match.
  let overlaps = variance > 1.0e-8
  let reading = if overlaps {
    "The two groups overlap: there are documents that could have gone either way."
  } else {
    "The two groups do not overlap. Every treated document is unlike every untreated one, so the corpus cannot say what an untreated document that looked like a treated one would have scored, and this estimate is not identified."
  }
  {
    overlaps,
    residual_variance: variance,
    propensity_min: lowest,
    propensity_max: highest,
    reading,
  }
}

///|
/// The sensitivity of the estimate to an unobserved confounder.
///
/// The robustness value comes from the DoubleML port's Cinelli & Hazlett
/// implementation. It is the multiple by which the confounding strength
/// would have to grow before the estimate's sign could flip: above one the
/// estimate survives, below one a confounder weaker than the one already
/// assumed could have broken it.
///
/// The interval is the estimate's own interval widened by the worst-case
/// bias, which is the question a reader is really asking -- not "how noisy
/// is this number?" but "how wrong could this number be?".
fn sensitivity_of(
  model : @dml.DoubleMLPLR,
  theta : Double,
  ci_lower : Double,
  ci_upper : Double,
) -> Sensitivity {
  let sens = model.sensitivity_analysis(cf_y=0.05, cf_d=0.05) catch {
    _ => return Sensitivity::unknown()
  }
  let rv = sens.rv
  // The worst case: the estimate could move by as much as the maximum
  // bias the confounder could introduce.
  let worst = sens.max_bias.abs()
  let lower = ci_lower - worst
  let upper = ci_upper + worst
  // The sign survives if the worst-case bias does not carry it across zero.
  //
  // The confidence interval is deliberately not part of this. The interval
  // says how noisy the estimate is; the worst case says how wrong it could
  // be because of something the controls did not include. Keeping them
  // apart is what lets the panel say which of the two is the problem.
  let robust = if theta > 0.0 {
    theta - worst > 0.0
  } else if theta < 0.0 {
    theta + worst < 0.0
  } else {
    // An estimate of exactly zero has no sign to keep.
    false
  }
  let reading = if rv >= 1.0e30 {
    "The estimate is exactly zero, so no confounder can change its sign."
  } else if rv > 1.0 {
    "An unobserved confounder would have to be " +
    rv.to_string() +
    " times stronger than the ones already controlled for before it could flip this estimate."
  } else {
    "A confounder only " +
    rv.to_string() +
    " times as strong as the ones already controlled for would be enough to flip this estimate."
  }
  { robustness_value: rv, lower, upper, reading, robust, }
}

///|
/// The sensitivity of an estimate that could not be made.
pub fn Sensitivity::unknown() -> Sensitivity {
  {
    robustness_value: 0.0,
    lower: 0.0,
    upper: 0.0,
    reading: "No estimate was made, so there is nothing to be sensitive to.",
    robust: false,
  }
}

///|
/// Run causal inference on a set of documents.
///
/// Uses DoubleMLPLR to estimate the causal effect of claiming to be new on
/// the impact score, controlling for the document's shape.
///
/// Refuses rather than guesses: too few documents, or a corpus where every
/// document is treated or none is, is a corpus that cannot support an
/// estimate, and an estimate that is not supported is a number that reads
/// as a finding.
pub fn estimate_causal_effect(documents : Array[Document]) -> CausalOutcome {
  let n = documents.length()
  if n < 10 {
    return Refused({
      reason: "Only " +
      n.to_string() +
      " documents; a causal estimate needs at least 10 to mean anything.",
      balance: [],
    })
  }

  // The number of controlled variables, read from the list that names them.
  //
  // It used to be a number written here as well, and the two could drift
  // apart: a list of three names and a count of four made the balance read
  // past the end of the list, and reading past the end of a list in MoonBit
  // is not an error the reader sees -- it takes the server down with it.
  // One list, one count.
  let names = confounders()
  let p = names.length()

  // Extract features from all documents.
  let x_flat : Array[Double] = []
  let d : Array[Double] = []
  let y : Array[Double] = []
  let mut n_treated = 0

  for document in documents {
    let (row, treatment, outcome, _) = document_to_features(document, names)
    match row.unreadable {
      Some(name) =>
        return Refused({
          reason: "The controlled variable \"" +
          name +
          "\" has no feature to read, so there is nothing to control for.",
          balance: [],
        })
      None => ()
    }
    for f in row.values {
      x_flat.push(f)
    }
    d.push(treatment)
    y.push(outcome)
    if treatment > 0.5 {
      n_treated += 1
    }
  }

  // A corpus where every document is treated, or none is, has no contrast
  // to estimate. The DoubleML fit would return a number, and the number
  // would be NaN dressed up as an estimate.
  //
  // There is no balance to report here: a comparison between a group of
  // everybody and a group of nobody is not a balance.
  if n_treated == 0 {
    return Refused({
      reason: "None of the " +
      n.to_string() +
      " documents claims to be new, so there is no contrast to estimate.",
      balance: [],
    })
  }
  if n_treated == n {
    return Refused({
      reason: "Every one of the " +
      n.to_string() +
      " documents claims to be new, so there is no contrast to estimate.",
      balance: [],
    })
  }

  // Build matrix and data.
  let x = @dml.Matrix::from_array(x_flat, n, p)
  let data = @dml.DoubleMLData::new(x, y, d)

  // Fit DoubleMLPLR model.
  //
  // The outcome model is left as the port's default -- a linear regression
  // -- because the impact score is a continuous number. The propensity
  // model is not: the treatment is binary, so its learner is a logistic
  // regression and its prediction is a probability.
  let model = @dml.DoubleMLPLR::new(
    data,
    n_folds=2,
    n_rep=1,
    seed=42,
    learner_m=propensity_learner(),
  ).fit()

  let theta = model.coef()
  let se = model.se()
  let (ci_lower, ci_upper) = model.confint()

  let balance = balance_of(x_flat, d, n, p)
  let overlap = overlap_of(model, d)

  // A corpus whose two groups do not overlap cannot support an estimate.
  // The fit still returns one, and the fit's standard error is enormous --
  // a hundred billion is not a measurement, it is the arithmetic saying
  // there is nothing to measure. Reporting it as an estimate with a
  // confidence interval would put a number in the reader's hands that
  // means nothing at all, which is the one thing this panel exists to stop
  // doing.
  //
  // The balance travels with the refusal: it is the evidence for it.
  if !overlap.overlaps {
    return Refused({ reason: overlap.reading, balance, })
  }

  let sensitivity = sensitivity_of(model, theta, ci_lower, ci_upper)

  Estimated({
    theta,
    se,
    ci_lower,
    ci_upper,
    n_obs: n,
    n_treated,
    n_features: p,
    treatment: treatment_name(),
    outcome: outcome_name(),
    confounders: confounders(),
    balance,
    overlap,
    sensitivity,
  })
}

///|
/// The result of a causal run, as the API hands it back.
///
/// A refusal is a refusal: it says why in words, and it does not carry a
/// theta, because a theta of zero next to no data is a finding nobody made.
pub fn CausalOutcome::to_json(self : CausalOutcome) -> Json {
  match self {
    Estimated(result) => {
      let body = result.to_json()
      match body {
        Object(fields) => {
          let out = fields.copy()
          out["refused"] = Json::string("")
          out["reason"] = Json::string("")
          Json::object(out)
        }
        _ => body
      }
    }
    Refused(refusal) =>
      {
        "refused": "the estimate was not made",
        "reason": refusal.reason,
        "theta": Json::null(),
        "se": Json::null(),
        "ci_lower": Json::null(),
        "ci_upper": Json::null(),
        "n_obs": 0,
        "n_treated": 0,
        "n_features": 0,
        "treatment": treatment_name(),
        "outcome": outcome_name(),
        "confounders": confounders(),
        "balance": [..refusal.balance.map(fn(row) { row.to_json() })],
        "sensitivity": Sensitivity::unknown().to_json(),
      }
  }
}
