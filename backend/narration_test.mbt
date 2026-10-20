///| Tests for the sentences: the ones that make the loop readable.
///
/// The sentences are the whole point of this layer, so they are tested as
/// sentences -- not as "the function returned a non-empty string". A
/// narration that said "the model formulator moved" when the model did not
/// move would pass a non-empty check and mislead every reader.
///
/// The facts are built by hand here rather than by taking real steps. The
/// transition table decides what a step does, and a test that took steps
/// would be testing the table as much as the sentence. A table that changed
/// would move the sentences with it, and the sentences are supposed to be
/// about what happened, whatever the table said.

///|
/// The facts of a step that moved.
fn moved_facts() -> @backend.StepFacts {
  {
    letter: "M",
    domain: "Model",
    role: "the model formulator",
    slot: "Action",
    outcome_kind: "moved",
    position_before: "Standing",
    position_after: "Freedom",
    cursor: "the data turbine",
    source: "drive",
    available: 3,
  }
}

///|
/// The facts of a step that moved nothing.
fn held_facts() -> @backend.StepFacts {
  {
    letter: "D",
    domain: "Data",
    role: "the data turbine",
    slot: "Holding",
    outcome_kind: "held",
    position_before: "Discipline",
    position_after: "Discipline",
    cursor: "the data turbine",
    source: "drive",
    available: 4,
  }
}

///|
/// The facts of a step that found no road at all.
fn blocked_facts(available : Int32) -> @backend.StepFacts {
  {
    letter: "K",
    domain: "Knowledge",
    role: "the knowledge distiller",
    slot: "Unveiling",
    outcome_kind: "block",
    position_before: "Veiled",
    position_after: "Veiled",
    cursor: "the knowledge distiller",
    source: "drive",
    available,
  }
}

///|
/// The facts of a step the table declined to choose for.
fn undecided_facts() -> @backend.StepFacts {
  {
    letter: "E",
    domain: "Experience",
    role: "the experience absorber",
    slot: "Situation",
    outcome_kind: "open",
    position_before: "Absorbed",
    position_after: "Absorbed",
    cursor: "the experience absorber",
    source: "drive",
    available: 5,
  }
}

///|
test "the first letter of a phrase is capitalised, and the rest is left alone" {
  // The sentence starts with the subject, so the subject's first letter has
  // to be capitalised -- and the rest of the phrase must not be, or the name
  // of a domain would change.
  assert_eq(@backend.capitalize("the model formulator"), "The model formulator")
  assert_eq(@backend.capitalize("a"), "A")
  assert_eq(@backend.capitalize(""), "")
}

///|
test "a step that moved is told as a sentence" {
  let sentence = @backend.step_sentence(moved_facts())
  // What moved, from where, and through what.
  assert_true(sentence.contains("moved from Standing to Freedom"))
  assert_true(sentence.contains("Action"))
  // Where the cursor went next: the reader has to know that the machine
  // moved on to the next domain, not that the model was left somewhere
  // else.
  assert_true(sentence.contains("the data turbine"))
  // And that the subject is named in the machine's own wording, not a
  // paraphrase. The sentence starts with it, so the first letter is
  // capitalised.
  assert_true(sentence.has_prefix("The model formulator"))
}

///|
test "a step says who chose the slot" {
  let driven = @backend.step_sentence(moved_facts())
  assert_true(driven.contains("the slot the table drives with here"))
  // The same step, taken by hand, says something different. "The table
  // chose this" and "you chose this" are different claims, and the outcome
  // alone does not tell them apart.
  let chosen = @backend.step_sentence({ ..moved_facts(), source: "explicit", })
  assert_true(chosen.contains("the slot you chose"))
  assert_true(!chosen.contains("the slot the table drives with here"))
}

///|
test "a step that moved nothing says so" {
  let sentence = @backend.step_sentence(held_facts())
  assert_true(sentence.contains("held at Discipline"))
  // The cursor stayed where it was, and the sentence says that rather than
  // leaving the reader to infer it from the absence of a new domain.
  assert_true(sentence.contains("stayed on the data turbine"))
}

///|
test "a step that found no road says that, and says which kind" {
  // No road at all: the position itself is a dead end.
  let dead_end = @backend.step_sentence(blocked_facts(0))
  assert_true(dead_end.contains("Nothing could move the knowledge distiller"))
  assert_true(dead_end.contains("no slot has a road out of there"))
  // A road that was tried and had none: a different sentence, because the
  // difference is the difference between "there is nowhere to go" and "that
  // way is closed".
  let closed = @backend.step_sentence(blocked_facts(3))
  assert_true(closed.contains("that slot has no road out of there"))
  assert_true(!closed.contains("no slot has a road out of there"))
}

///|
test "a step the table declined to choose says so" {
  let sentence = @backend.step_sentence(undecided_facts())
  assert_true(sentence.contains("declined to choose"))
  assert_true(sentence.contains("the experience absorber"))
}

///|
test "the summary says where the run went and what it moved" {
  let steps = [
    moved_facts(),
    moved_facts(),
    held_facts(),
    { ..held_facts(), letter: "E", role: "the experience absorber", },
  ]
  let summary = @backend.phase_summary(steps, "Converging")
  // Which domains the run visited, and how often.
  assert_true(summary.contains("the model formulator twice"))
  assert_true(summary.contains("the data turbine once"))
  assert_true(summary.contains("the experience absorber once"))
  // How many of the steps actually moved a position.
  assert_true(summary.contains("Two of them moved a position."))
  // And where the group stands.
  assert_true(summary.contains("The group is Converging."))
}

///|
test "the summary counts the steps it was given" {
  // One domain only reads better as "all in", and a summary that said
  // "the model formulator once" for five steps in the model would be
  // counting the domains rather than the steps.
  let steps = [moved_facts(), moved_facts(), moved_facts()]
  let summary = @backend.phase_summary(steps, "Scattered")
  assert_true(
    summary.contains("The last 3 steps were all in the model formulator."),
  )
  assert_true(summary.contains("Three of them moved a position."))
}

///|
test "a single step is summarised as a single step" {
  let summary = @backend.phase_summary([moved_facts()], "Scattered")
  assert_true(summary.contains("The last step was in the model formulator."))
  assert_true(summary.contains("It moved a position."))
  assert_true(!summary.contains("of them"))
}

///|
test "a summary of nothing is empty" {
  // Not "No steps yet.": the caller decides whether to show a line at all,
  // and a summary that invented a sentence for no steps would be a lie.
  assert_eq(@backend.phase_summary([], "Scattered"), "")
}

///|
test "a run of steps that moved nothing says that none of them moved" {
  let steps = [held_facts(), held_facts()]
  let summary = @backend.phase_summary(steps, "Scattered")
  assert_true(summary.contains("None of them moved a position."))
}

///|
async test "the summary of a session covers the last five steps and no more" {
  let db = open_session_db("summary_five")
  let session = fresh_session(db, "Seven steps")
  ignore(take_steps(db, 7))
  let path = db.steps_of_session(session.id)
  assert_eq(path.length(), 7)
  let summary = @backend.summary_of(path)
  // Five, not seven: a summary of the whole history stops being a summary,
  // and a reader cannot hold seven steps in their head. The sentence says
  // which five it is talking about, so the number is not a private choice.
  assert_true(summary.contains("The last 5 steps"))
  assert_true(!summary.contains("The last 7 steps"))
  db.close()
  drop_db(session_db_path("summary_five"))
}

///|
async test "the export carries the sentences and the summary too" {
  let db = open_session_db("export_narration")
  let session = fresh_session(db, "Taken away")
  ignore(take_steps(db, 3))
  let steps = db.steps_of_session(session.id)
  let markdown = @backend.export_markdown(db, reload(db, session.id))
  // The sentence is in the document, not only on the screen: the document is
  // the thing the user takes away, and it should say what happened in the
  // same words the page did.
  let sentence = @backend.step_sentence(@backend.facts_of(steps[0]))
  assert_true(markdown.contains(sentence))
  // And the account of the run is at the top of it.
  assert_true(markdown.contains("## The run so far"))
  // The JSON export carries the summary as well, so a consumer does not
  // have to work it out from the path.
  let json = @backend.export_json(db, reload(db, session.id))
  match json_field(json, "summary") {
    Some(Json::String(summary)) => assert_true(summary != "")
    _ => fail("the json export should carry the summary")
  }
  db.close()
  drop_db(session_db_path("export_narration"))
}

///|
async test "the step record carries the sentence and the state carries the summary" {
  let db = open_session_db("narration")
  let session = fresh_session(db, "Told in sentences")
  ignore(take_steps(db, 3))
  let steps = db.steps_of_session(session.id)
  assert_eq(steps.length(), 3)
  // The step's own JSON carries the sentence, so a reader of the timeline
  // gets it without asking for anything else.
  let step_json = steps[0].to_json(1)
  match json_field(step_json, "narration") {
    Some(Json::String(sentence)) => assert_true(sentence != "")
    _ => fail("the step should carry a sentence")
  }
  // And the session state carries the summary of the run.
  let state = @backend.session_state_json(db)
  match json_field(state, "summary") {
    Some(Json::String(summary)) => assert_true(summary != "")
    _ => fail("the session state should carry a summary")
  }
  db.close()
  drop_db(session_db_path("narration"))
}
