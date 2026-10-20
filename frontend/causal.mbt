///| The causal panel: what the estimate means, and what it rests on.
///
/// The backend sends a causal estimate, or a refusal with a reason. This
/// module turns either into something a reader can argue with:
///
///   - what was treated and what was measured, by name;
///   - the variables that were controlled for, by name;
///   - how far apart the two groups are on each of those variables;
///   - whether the two groups overlap at all;
///   - how strong an unobserved confounder would have to be before the
///     estimate's sign could flip.
///
/// The decoding lives here, away from the markup, because a panel that
/// reads a number with the wrong accessor is a panel that shows a fallback
/// and looks fine doing it. The last time that happened it showed "0.0"
/// for every estimate the server ever produced.

///|
/// One controlled variable, as the two groups sit on it.
pub(all) struct BalanceSummary {
  /// The variable's name, in words.
  name : String
  /// The mean among the treated documents.
  treated_mean : Double
  /// The mean among the untreated documents.
  untreated_mean : Double
  /// The standardized difference between the two means.
  standardized_difference : Double
  /// Whether the two groups are close enough on this variable.
  balanced : Bool
  /// Whether the two groups do not overlap on this variable at all.
  separated : Bool
}

///|
/// The whole causal reading, as the panel shows it.
pub(all) struct CausalSummary {
  /// Whether the estimate was refused.
  ///
  /// A refusal is not a zero. The backend says so in words, and the panel
  /// shows the words instead of a number that was never measured.
  refused : Bool
  /// Why the estimate was refused.
  reason : String
  /// What was treated, by name.
  treatment : String
  /// What was measured, by name.
  outcome : String
  /// The estimated effect.
  theta : Double
  /// The standard error.
  se : Double
  /// The lower end of the confidence interval.
  ci_lower : Double
  /// The upper end of the confidence interval.
  ci_upper : Double
  /// How many documents the corpus held.
  n_obs : Int32
  /// How many of them were treated.
  n_treated : Int32
  /// The variables that were controlled for, by name.
  confounders : Array[String]
  /// How the two groups compare on each of those variables.
  balance : Array[BalanceSummary]
  /// Whether the two groups overlap at all.
  overlaps : Bool
  /// A sentence saying what the overlap means.
  overlap_reading : String
  /// The multiple of confounding that would flip the estimate's sign.
  robustness_value : Double
  /// The interval the estimate takes when the worst case is allowed for.
  sensitivity_lower : Double
  /// The interval the estimate takes when the worst case is allowed for.
  sensitivity_upper : Double
  /// A sentence saying what the robustness value means.
  sensitivity_reading : String
  /// Whether the estimate's sign survives the worst case.
  robust : Bool
}

///|
/// Decode the backend's causal payload.
///
/// Every field has a fallback, because the backend is the only writer and
/// a missing field is a backend change, not a reason for the page to die.
pub fn causal_summary(json : Json) -> CausalSummary {
  let refusal = get_string(json, "refused", "")
  {
    refused: refusal != "",
    reason: get_string(json, "reason", ""),
    treatment: get_string(json, "treatment", "unknown"),
    outcome: get_string(json, "outcome", "unknown"),
    theta: get_double(json, "theta", 0.0),
    se: get_double(json, "se", 0.0),
    ci_lower: get_double(json, "ci_lower", 0.0),
    ci_upper: get_double(json, "ci_upper", 0.0),
    n_obs: get_int(json, "n_obs", 0),
    n_treated: get_int(json, "n_treated", 0),
    confounders: get_strings(json, "confounders"),
    balance: balance_summaries(json),
    overlaps: get_bool(sub(json, "overlap"), "overlaps", false),
    overlap_reading: get_string(sub(json, "overlap"), "reading", ""),
    robustness_value: get_double(
      sub(json, "sensitivity"),
      "robustness_value",
      0.0,
    ),
    sensitivity_lower: get_double(sub(json, "sensitivity"), "lower", 0.0),
    sensitivity_upper: get_double(sub(json, "sensitivity"), "upper", 0.0),
    sensitivity_reading: get_string(sub(json, "sensitivity"), "reading", ""),
    robust: get_bool(sub(json, "sensitivity"), "robust", false),
  }
}

///|
/// The balance rows of a causal payload.
pub fn balance_summaries(json : Json) -> Array[BalanceSummary] {
  let rows : Array[BalanceSummary] = []
  match field(json, "balance") {
    Some(Array(items)) =>
      for item in items {
        rows.push({
          name: get_string(item, "name", ""),
          treated_mean: get_double(item, "treated_mean", 0.0),
          untreated_mean: get_double(item, "untreated_mean", 0.0),
          standardized_difference: get_double(
            item, "standardized_difference", 0.0,
          ),
          balanced: get_bool(item, "balanced", false),
          separated: get_bool(item, "separated", false),
        })
      }
    _ => ()
  }
  rows
}

///|
/// What one balance row says, in words.
///
/// The verdict is the point of the row. A number without one is a number
/// the reader has to interpret alone, which is the thing this panel
/// exists to stop doing.
pub fn balance_verdict(row : BalanceSummary, c : Chrome) -> String {
  if row.separated {
    c.causal.verdict_no_overlap
  } else if row.balanced {
    c.causal.verdict_close
  } else {
    c.causal.verdict_differ
  }
}

///|
/// A number as it should be read on screen.
///
/// Four decimal places: enough to tell two estimates apart, short enough
/// that the interval beside it is still readable. A number with fifteen
/// decimals is not more precise than the corpus behind it.
///
/// A whole number keeps its decimal point. "2" and "2.0" are the same
/// number, but a column of estimates where some of them are integers and
/// some of them are not reads as two different kinds of measurement.
pub fn format_estimate(n : Double) -> String {
  let scaled = (n * 10000.0).round()
  let rounded = scaled / 10000.0
  // Negative zero is a zero.
  let text = if rounded == 0.0 { "0.0" } else { rounded.to_string() }
  if text.contains(".") {
    text
  } else {
    text + ".0"
  }
}

///|
/// An interval as it should be read on screen.
pub fn format_interval(lower : Double, upper : Double) -> String {
  "[" + format_estimate(lower) + ", " + format_estimate(upper) + "]"
}

///|
/// Causal inference panel: the effect of a document claiming to be new on
/// an impact score, with the variables that were controlled for, how well
/// the two groups match, and how wrong the answer could be.
pub fn causal_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let c = chrome(model.lang)
  let button = @html.div(class="maked-causal-buttons", [
    @html.button(
      class="maked-btn maked-btn-causal",
      on_click=emit(EstimateCausalClicked),
      c.causal.estimate_button,
    ),
  ])
  let result_view = match model.causal_result {
    None => @html.p(class="maked-causal-empty", c.causal.empty)
    Some(causal) => {
      let summary = causal_summary(causal)
      if summary.refused {
        @html.div(class="maked-causal-refused", [
          @html.h3(class="maked-causal-subtitle", c.causal.not_made),
          @html.p(class="maked-causal-reason", summary.reason),
          @html.h3(class="maked-causal-subtitle", c.causal.groups_looked),
          balance_table(summary.balance, c),
        ])
      } else {
        causal_estimate_view(summary, c)
      }
    }
  }
  let error = if model.causal_error == "" {
    @html.nothing
  } else {
    @html.p(class="maked-causal-error", model.causal_error)
  }
  @html.section(class="maked-causal", [
    @html.h2(class="maked-causal-title", c.causal.title),
    @html.p(class="maked-causal-lede", c.causal.lede),
    button,
    result_view,
    error,
  ])
}

///|
/// The estimate, with the three things that make it arguable.
fn causal_estimate_view(summary : CausalSummary, c : Chrome) -> @html.Html {
  let stats = @html.dl(class="maked-causal-stats", [
    @html.dt(c.causal.treatment),
    @html.dd(class="maked-causal-treatment", summary.treatment),
    @html.dt(c.causal.outcome),
    @html.dd(class="maked-causal-outcome", summary.outcome),
    @html.dt(c.causal.effect),
    @html.dd(class="maked-causal-value", format_estimate(summary.theta)),
    @html.dt(c.causal.standard_error),
    @html.dd(format_estimate(summary.se)),
    @html.dt(c.causal.confidence_interval),
    @html.dd(format_interval(summary.ci_lower, summary.ci_upper)),
    @html.dt(c.causal.documents),
    @html.dd(
      class="maked-causal-observations",
      documents_count(
        c,
        summary.n_obs.to_string(),
        summary.n_treated.to_string(),
      ),
    ),
  ])
  let confounders = if summary.confounders.length() == 0 {
    @html.p(class="maked-causal-empty", c.causal.controlled_nothing)
  } else {
    let items : Array[@html.Html] = []
    for name in summary.confounders {
      items.push(@html.li(class="maked-causal-confounder", name))
    }
    @html.ul(class="maked-causal-confounders", items)
  }
  let balance = balance_table(summary.balance, c)
  let sensitivity = @html.dl(class="maked-causal-sensitivity", [
    @html.dt(c.causal.robustness),
    @html.dd(
      class="maked-causal-robustness",
      format_estimate(summary.robustness_value),
    ),
    @html.dt(c.causal.worst_case),
    @html.dd(
      class="maked-causal-worst-case",
      format_interval(summary.sensitivity_lower, summary.sensitivity_upper),
    ),
    @html.dt(c.causal.sign_survives),
    @html.dd(
      class="maked-causal-robust",
      if summary.robust {
        c.causal.yes
      } else {
        c.causal.no
      },
    ),
  ])
  @html.div(class="maked-causal-results", [
    @html.h3(class="maked-causal-subtitle", c.causal.what_estimated),
    stats,
    @html.h3(class="maked-causal-subtitle", c.causal.what_controlled),
    confounders,
    @html.p(class="maked-causal-note", c.causal.confounders_note),
    @html.h3(class="maked-causal-subtitle", c.causal.balance),
    balance,
    @html.h3(class="maked-causal-subtitle", c.causal.overlap),
    @html.dl(class="maked-causal-overlap-stats", [
      @html.dt(c.causal.overlap_yes),
      @html.dd(
        class="maked-causal-overlap-verdict",
        if summary.overlaps {
          c.causal.yes
        } else {
          c.causal.no
        },
      ),
      @html.dt(c.causal.what_that_means),
      @html.dd(class="maked-causal-overlap-reading", summary.overlap_reading),
    ]),
    @html.h3(class="maked-causal-subtitle", c.causal.how_wrong),
    sensitivity,
    @html.p(
      class="maked-causal-sensitivity-reading",
      summary.sensitivity_reading,
    ),
    @html.p(class="maked-causal-caveat", c.causal.impact_note),
  ])
}

///|
/// The balance table: one row per controlled variable.
fn balance_table(rows : Array[BalanceSummary], c : Chrome) -> @html.Html {
  if rows.length() == 0 {
    return @html.p(class="maked-causal-empty", c.causal.no_balance)
  }
  let body : Array[@html.Html] = []
  for row in rows {
    body.push(
      @html.tr(class="maked-causal-balance-row", [
        @html.td(class="maked-causal-balance-name", row.name),
        @html.td(
          class="maked-causal-balance-treated",
          format_estimate(row.treated_mean),
        ),
        @html.td(
          class="maked-causal-balance-untreated",
          format_estimate(row.untreated_mean),
        ),
        @html.td(
          class="maked-causal-balance-difference",
          format_estimate(row.standardized_difference),
        ),
        @html.td(class="maked-causal-balance-verdict", balance_verdict(row, c)),
      ]),
    )
  }
  @html.table(class="maked-causal-balance", [
    @html.thead(class="maked-causal-balance-head", [
      @html.tr([
        @html.th(c.causal.variable),
        @html.th(c.causal.treated),
        @html.th(c.causal.untreated),
        @html.th(c.causal.difference),
        @html.th(c.causal.verdict),
      ]),
    ]),
    @html.tbody(class="maked-causal-balance-body", body),
  ])
}
