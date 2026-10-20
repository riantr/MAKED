///| Tests for the measures: is the run still finding ground, or going round

///| in circles?
///
/// The measures are tested as measures -- "the sentence says the run reached
/// no new ground", not "the function returned a number". A measure that
/// reported the wrong thing while looking like a measure would be worse than
/// no measure at all, because a reader would trust it.
///
/// The paths are built by hand rather than by taking real steps. The
/// transition table decides what a step does, and a test that took steps
/// would be testing the table as much as the measures. What is being tested
/// here is the reading of a run's shape, so the shape is written down.

///|
/// A step, built by hand.
fn metric_step(
  domain : String,
  slot : String,
  before : String,
  after : String,
) -> @backend.SessionStep {
  metric_step_outcome(
    domain,
    slot,
    before,
    after,
    if before == after {
      "held"
    } else {
      "moved"
    },
  )
}

///|
/// The word a reader would see for a kind.
///
/// The measures do not read this -- they read the kind -- but a step carries
/// both, and a fixture carrying only one of them would not be a step.
fn metric_outcome_word(kind : String) -> String {
  match kind {
    "moved" => "Moved"
    "held" => "Held"
    "same" => "Converge"
    "open" => "Undecided"
    "block" => "No-way"
    _ => kind
  }
}

///|
/// A step, built by hand, with the outcome stated.
///
/// The outcome is a separate argument because it matters on its own: a run
/// whose steps did not move the subject is stuck, and a run whose steps
/// moved into positions it already knew is settling. The same positions
/// with a different outcome are a different run.
///
/// It is the *kind* that is given, because the kind is what the measures read.
/// The word is derived from it, the way the model derives it.
fn metric_step_outcome(
  domain : String,
  slot : String,
  before : String,
  after : String,
  outcome_kind : String,
) -> @backend.SessionStep {
  {
    id: 0L,
    session_id: 0L,
    parent_step_id: 0L,
    domain,
    domain_title: domain,
    slot,
    slot_designation: slot,
    outcome: metric_outcome_word(outcome_kind),
    outcome_kind,
    detail: "",
    position_before: before,
    position_after: after,
    cursor_after: domain,
    group_state: "Common Tongue",
    mode: "structured",
    source: "drive",
    drive: "",
    undecided: false,
    available: "",
    blocked: "",
    created_at: "",
  }
}

///|
/// A path of steps, each one reaching the next position in the list.
///
/// The positions are the run's own: the first step comes from the first
/// position and reaches the second, the second comes from the second and
/// reaches the third, and so on.
fn metric_path(
  letters : Array[String],
  positions : Array[String],
) -> Array[@backend.SessionStep] {
  let out : Array[@backend.SessionStep] = []
  let mut i = 0
  while i + 1 < positions.length() {
    let domain = if i < letters.length() { letters[i] } else { "M" }
    out.push(metric_step(domain, "Action", positions[i], positions[i + 1]))
    i += 1
  }
  out
}

///|
/// The measure filed under a name.
fn metric_named(
  report : @backend.MetricReport,
  key : String,
) -> @backend.Metric raise {
  for metric in report.metrics {
    if metric.key == key {
      return metric
    }
  }
  fail("no measure named " + key)
}

///|
/// A run with no steps in it has nothing to measure.
///
/// The report says so by having no measures in it, the same way the run
/// summary is empty for an empty run. A client can then leave the block out
/// rather than print zeroes at someone.
async test "an empty run has nothing to measure" {
  let report = @backend.measure([])
  assert_eq(report.metrics.length(), 0)
  assert_eq(report.comparison, "")
}

///|
/// The first measure of all: did the run reach anywhere it had not been?
async test "a run that reaches new ground says so" {
  let path = metric_path(["M", "D", "E"], [
    "Standing", "Freedom", "Opening", "Habit",
  ])
  let report = @backend.measure(path)
  let ground = metric_named(report, "new_ground")
  assert_eq(ground.value, 3)
  assert_eq(ground.of, 3)
  assert_true(
    ground.sentence.contains(
      "reached a position the run had not been on before",
    ),
  )
}

///|
/// The measure that tells a run which is exploring from one which is
/// repeating itself.
///
/// A run that keeps landing on positions it has already been on has added
/// nothing to the map, however many steps it has taken. This is the number
/// that goes to zero, and the sentence has to say so plainly.
async test "a run that repeats itself reaches no new ground" {
  let path = metric_path(["M", "M", "M"], [
    "Standing", "Freedom", "Freedom", "Standing",
  ])
  let report = @backend.measure(path)
  let ground = metric_named(report, "new_ground")
  // The first step reached Freedom, which was new. The second came back to
  // Standing and the third left it for Freedom again: both of those
  // positions were already occupied.
  assert_eq(ground.value, 1)
  assert_true(ground.sentence.contains("1 of the last 3 steps"))
}

///|
/// A step that did not move is not new ground.
async test "a step that did not move reaches no new ground" {
  let path = metric_path(["M", "M"], ["Standing", "Standing", "Freedom"])
  let report = @backend.measure(path)
  let ground = metric_named(report, "new_ground")
  assert_eq(ground.value, 1)
  assert_true(ground.sentence.contains("1 of the last 2 steps"))
}

///|
/// The convergence: how long the run has gone without finding anything.
///
/// This counts the *trailing* steps, not the average, because "the last 3
/// steps reached nothing new" says something different from "3 of the last
/// 5 steps reached nothing new".
async test "the settling measure counts the trailing steps that found nothing" {
  let path = metric_path(["M", "M", "M", "M"], [
    "A0", "A1", "A2", "A1", "A2", "A1",
  ])
  let report = @backend.measure(path)
  let settling = metric_named(report, "settling")
  // The run reached A1, then A2, and then went back and forth between the
  // two for three steps without reaching anything it had not been on.
  assert_eq(settling.value, 3)
  assert_true(
    settling.sentence.contains("The last 3 steps reached nothing new"),
  )
}

///|
/// A run whose last step found something is not settling.
async test "a run still finding ground is not settling" {
  let path = metric_path(["M", "M"], ["A0", "A1", "A2"])
  let report = @backend.measure(path)
  let settling = metric_named(report, "settling")
  assert_eq(settling.value, 0)
  assert_true(settling.sentence.contains("still finding new ground"))
}

///|
/// A run that reached nothing new because it *moved* into a position it
/// already knew is settling. That is the goal, and calling it "stuck" would
/// be wrong.
async test "a run that moved into known ground is settling, not stuck" {
  let path = metric_path(["M", "M", "M"], ["A0", "A1", "A2", "A1", "A2"])
  let settling = metric_named(@backend.measure(path), "settling")
  assert_eq(settling.value, 2)
  assert_true(
    settling.sentence.contains("the run is settling rather than exploring"),
  )
}

///|
/// A run that reached nothing new because it did not move at all is stuck.
///
/// A step counter cannot tell these two apart: a run whose steps moved into
/// positions it already knew has arrived somewhere, and a run whose steps
/// did not move has stopped. The recorded outcome tells them apart -- "Moved"
/// is the only outcome that puts the subject somewhere else -- and the
/// measure has to say which one it is looking at. A reader who is told
/// "settling" about a run that cannot move will sit there waiting for a
/// convergence that is never coming.
async test "a run that did not move at all is stuck, not settling" {
  let path : Array[@backend.SessionStep] = [
    metric_step("M", "Action", "A0", "A1"),
    metric_step_outcome("M", "Situation", "A1", "A1", "open"),
    metric_step_outcome("M", "Situation", "A1", "A1", "open"),
  ]
  let settling = metric_named(@backend.measure(path), "settling")
  assert_eq(settling.value, 2)
  assert_true(settling.sentence.contains("did not move the subject at all"))
  assert_true(settling.sentence.contains("stuck, not settling"))
}

///|
/// The path diversity: how many of the eight slots the window used.
///
/// A run that always drives the same slot is walking one line through the
/// table, and the step counter cannot see the difference.
async test "the slot spread counts the slots the window used" {
  let path = metric_path(["M", "M", "M"], ["A0", "A1", "A2", "A3"])
  let spread = metric_named(@backend.measure(path), "slot_spread")
  assert_eq(spread.value, 1)
  assert_eq(spread.of, 8)
  assert_true(spread.sentence.contains("used 1 of the 8 slots"))
}

///|
/// A slot used more than once is named, because "3 of the 8 slots" does not
/// say whether the run walked three roads or one road three times.
async test "a slot used twice is named in the spread" {
  let path : Array[@backend.SessionStep] = [
    metric_step("M", "Action", "A0", "A1"),
    metric_step("M", "Holding", "A1", "A2"),
    metric_step("M", "Action", "A2", "A3"),
  ]
  let spread = metric_named(@backend.measure(path), "slot_spread")
  assert_eq(spread.value, 2)
  assert_true(spread.sentence.contains("Action was used 2 times"))
}

///|
/// The second half of the diversity: how many domains the window visited.
async test "the domain spread counts the domains the window visited" {
  let path = metric_path(["M", "D", "E", "A"], ["A0", "A1", "A2", "A3", "A4"])
  let spread = metric_named(@backend.measure(path), "domain_spread")
  assert_eq(spread.value, 4)
  assert_eq(spread.of, 5)
  assert_true(spread.sentence.contains("visited 4 of the 5 domains"))
}

///|
/// The position drift: how much of the state space the run has reached.
///
/// The denominator is read out of the model, so the test reads it from the
/// same place: a number written down in the test would be right only until
/// the table grew.
async test "the position drift counts the positions the run has stood on" {
  let path = metric_path(["M", "D", "E"], [
    "Standing", "Freedom", "Opening", "Habit",
  ])
  let drift = metric_named(@backend.measure(path), "position_drift")
  assert_eq(drift.value, 4)
  assert_eq(drift.of, @sm.all_states().length())
  assert_true(drift.sentence.contains("stood on 4 of the 34 positions"))
}

///|
/// How far each domain ranged, which is not a share of the whole: two
/// domains can stand on the same position, and then the parts add up to more
/// than the total. Here the model formulator and the data turbine both
/// stand on Standing, so the two ranges are 2 and 2 while the run has only
/// reached 3 positions.
async test "the drift names how far each domain ranged" {
  let path : Array[@backend.SessionStep] = [
    metric_step("M", "Action", "Standing", "Freedom"),
    metric_step("D", "Action", "Standing", "Honor"),
  ]
  let drift = metric_named(@backend.measure(path), "position_drift")
  assert_eq(drift.value, 3)
  assert_true(drift.sentence.contains("The model formulator has ranged over 2"))
  assert_true(drift.sentence.contains("the data turbine has ranged over 2"))
}

///|
/// The comparison needs two separate windows, so a short run cannot be
/// compared with itself yet. It says so rather than comparing overlapping
/// windows, which would put the last five steps inside the first five.
async test "a short run cannot be compared with itself yet" {
  let path = metric_path(["M", "M", "M"], [
    "A0", "A1", "A2", "A3", "A4", "A5", "A6",
  ])
  let report = @backend.measure(path)
  assert_true(report.comparison.contains("cannot be compared yet"))
}

///|
/// The measures are taken over the *window*, not over the whole run.
///
/// This is what makes two runs comparable. A run of ten steps that found
/// five new positions in its first five and nothing in its last five has
/// found five new positions, and the window says so: the last five steps
/// found none. Counting the whole run instead would report five for both
/// windows, and the run would look like it was still finding ground while
/// it was going round in circles.
async test "the new ground measure is taken over the window, not the whole run" {
  let path = metric_path(["M", "M", "M", "M", "M", "M", "M", "M", "M", "M"], [
    "A0", "A1", "A2", "A3", "A4", "A5", "A1", "A2", "A3", "A4", "A5",
  ])
  let report = @backend.measure(path)
  let ground = metric_named(report, "new_ground")
  // The whole run found five new positions; the last five steps found none.
  assert_eq(ground.value, 0)
  assert_eq(report.window_steps, 5)
}

///|
/// The comparison that answers the question the measures exist for: is a
/// longer run a better one?
///
/// Here the run's last five steps found nothing the first five had not
/// already found. The comparison has to say so, because "twenty steps" looks
/// like progress on a step counter and is not.
async test "a run that is finding less than it started with says so" {
  let path = metric_path(["M", "M", "M", "M", "M", "M", "M", "M", "M", "M"], [
    "A0", "A1", "A2", "A3", "A4", "A5", "A1", "A2", "A3", "A4", "A5",
  ])
  let report = @backend.measure(path)
  assert_true(
    report.comparison.contains("The last 5 steps reached 0 new positions"),
  )
  assert_true(report.comparison.contains("the first 5 reached 5"))
  assert_true(report.comparison.contains("finding less new ground"))
}

///|
/// A run that keeps finding ground at the rate it started with is holding
/// its rate, which is a different claim from finding less.
async test "a run holding its rate says so" {
  let path = metric_path(["M", "M", "M", "M", "M", "M", "M", "M", "M", "M"], [
    "A0", "A1", "A2", "A1", "A2", "A3", "A4", "A5", "A4", "A5", "A6",
  ])
  let report = @backend.measure(path)
  assert_true(report.comparison.contains("holding its rate"))
}

///|
/// The sentences do not stumble.
///
/// Two defects showed up in a real run and neither would be caught by a
/// check for a keyword: a phrase built by joining two halves said "The the
/// last 5 steps", and a clause that followed a full stop started in the
/// middle of the alphabet. A reader sees both as a machine talking to
/// itself, and a measure nobody trusts is not a measure.
///
/// The window is one step long at the start of every run, so the one-step
/// sentences are checked as well: a sentence that only ever appears in the
/// first minute of a session is a sentence nobody would have read.
async test "the sentences do not stumble" {
  let paths = [
    metric_path(["M", "M", "M"], ["A0", "A1", "A2", "A3"]),
    metric_path(["M"], ["A0", "A1"]),
  ]
  for path in paths {
    let report = @backend.measure(path)
    for metric in report.metrics {
      assert_true(
        !metric.sentence.contains(" the the ") &&
        !metric.sentence.contains("The the ") &&
        !metric.sentence.contains("  "),
        msg="the \{metric.key} sentence does not repeat a word",
      )
      // And every sentence starts with a capital or a number. A number is
      // allowed: "3 of the last 5 steps reached a position the run had not
      // been on before." leads with its count, which is the point of the
      // sentence.
      let first = metric.sentence[0]
      assert_true(
        (first >= 65 && first <= 90) || (first >= 48 && first <= 57),
        msg="the \{metric.key} sentence starts with a capital or a number",
      )
    }
    let drift = metric_named(report, "position_drift")
    assert_true(drift.sentence.contains(". The model formulator"))
  }
}

///|
/// The report reaches the API as numbers and sentences together, so a
/// client can show either without re-deriving anything.
async test "the report is reported as json" {
  let path = metric_path(["M", "D"], ["Standing", "Freedom", "Opening"])
  let json = @backend.measure(path).to_json()
  let metrics = match json {
    Object(fields) =>
      match fields.get("metrics") {
        Some(Array(items)) => items
        _ => []
      }
    _ => []
  }
  assert_eq(metrics.length(), 5)
  let comparison = match json {
    Object(fields) =>
      match fields.get("comparison") {
        Some(Json::String(text)) => text
        _ => ""
      }
    _ => ""
  }
  assert_true(comparison != "")
}

///|
/// The measures travel with the export, so a reader of the document can see
/// whether the run was getting anywhere -- not only what it did.
///
/// The Markdown export has its own section, and the JSON export has the
/// report itself. A document that listed the steps without saying whether
/// the run was improving would be the timeline again.
async test "the export carries the measures" {
  let db = open_session_db("export_metrics")
  let session = fresh_session(db, "Measured")
  ignore(take_steps(db, 3))
  let json = @backend.export_json(db, reload(db, session.id))
  match json_field(json, "metrics") {
    Some(Object(fields)) =>
      match fields.get("metrics") {
        Some(Array(items)) => assert_eq(items.length(), 5)
        _ => fail("the json export should carry the measures")
      }
    _ => fail("the json export should carry the measures")
  }
  let markdown = @backend.export_markdown(db, reload(db, session.id))
  assert_true(markdown.contains("## How the run is doing"))
  assert_true(markdown.contains("New ground"))
  db.close()
  drop_db(session_db_path("export_metrics"))
}
