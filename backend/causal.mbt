///| Causal inference for research papers using Double/Debiased Machine Learning.
///
/// This module bridges the arxiv research cycle with causal inference:
/// papers fetched from arxiv are treated as "treatments" and we estimate
/// their causal effect on a synthetic outcome using the DoubleML framework.
///
/// The outcome is constructed from paper features (citation proxy, recency,
/// category diversity). The treatment is a binary indicator of whether the
/// paper has a "novel" keyword pattern. Confounders are the paper's
/// numerical features (length, author count, category count).

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
} derive(Debug)

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
  }
}

///|
/// Extract numerical features from a paper for causal analysis.
/// Returns (feature_vector, treatment, outcome).
fn paper_to_features(paper : Paper) -> (Array[Double], Double, Double) {
  let title_len = paper.title.length().to_double()
  let summary_len = paper.summary.length().to_double()
  let n_authors = paper.authors.length().to_double()
  let n_cats = paper.categories.length().to_double()

  // Treatment: novel/novelty/new method in title or summary
  let text = (paper.title + " " + paper.summary).to_lowercase_ascii()
  let is_novel = if text.contains("novel") ||
    text.contains("new method") ||
    text.contains("propose") ||
    text.contains("introduce") {
    1.0
  } else {
    0.0
  }

  // Outcome: synthetic "impact" score based on features + noise
  // In a real setting this would be citation count or similar
  let impact = 0.3 * title_len +
    0.1 * summary_len / 100.0 +
    0.5 * n_authors +
    0.4 * n_cats +
    0.8 * is_novel

  let features = [title_len, summary_len, n_authors, n_cats]
  (features, is_novel, impact)
}

///|
/// Run causal inference on a set of papers.
///
/// Uses DoubleMLPLR to estimate the causal effect of "novelty" on a
/// synthetic impact score, controlling for paper features.
pub fn estimate_causal_effect(papers : Array[Paper]) -> CausalResult {
  let n = papers.length()
  if n < 10 {
    // Not enough data for meaningful causal inference
    return {
      theta: 0.0,
      se: 0.0,
      ci_lower: 0.0,
      ci_upper: 0.0,
      n_obs: n,
      n_treated: 0,
      n_features: 0,
    }
  }

  let p = 4 // number of features

  // Extract features from all papers
  let x_flat : Array[Double] = []
  let d : Array[Double] = []
  let y : Array[Double] = []
  let mut n_treated = 0

  for paper in papers {
    let (features, treatment, outcome) = paper_to_features(paper)
    for f in features {
      x_flat.push(f)
    }
    d.push(treatment)
    y.push(outcome)
    if treatment > 0.5 {
      n_treated += 1
    }
  }

  // Build matrix and data
  let x = @dml.Matrix::from_array(x_flat, n, p)
  let data = @dml.DoubleMLData::new(x, y, d)

  // Fit DoubleMLPLR model
  let model = @dml.DoubleMLPLR::new(data, n_folds=2, n_rep=1, seed=42).fit()

  let theta = model.coef()
  let se = model.se()
  let (ci_lower, ci_upper) = model.confint()

  { theta, se, ci_lower, ci_upper, n_obs: n, n_treated, n_features: p, }
}
