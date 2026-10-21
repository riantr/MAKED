///| Tests for the Society layer.
///
/// The society machine is pyroduct's and the words for it are the
/// vocabulary file's, and these tests pin both: the machine is read, not
/// restated, and the words have to cover every position and every trigger
/// it has.
///
/// A vocabulary that falls behind the machine is the failure these exist
/// to catch. It is invisible in the sense that nothing breaks -- the panel
/// still renders, the collective still moves -- and the reader is left
/// looking at a position with no name.

///|
/// A vocabulary, as the file carries it.
fn vocabulary_payload() -> Json {
  let payload : Json = {
    "format": "maked.society.v1",
    "positions": [
      { "id": "World", "label": "Lifeworld", "gloss": "Where speakers meet." },
      {
        "id": "Claim",
        "label": "Validity claim",
        "gloss": "A candidate for agreement.",
      },
    ],
    "phases": [{ "id": "Life", "label": "Life" }],
    "triggers": [
      { "id": "RaiseClaims", "label": "Raise a validity claim" },
      { "id": "Filter", "label": "Filter through discourse" },
    ],
  }
  payload
}

///|
/// The vocabulary MAKED runs when nothing else is installed.
fn builtin() -> @backend.SocietyVocabulary {
  @backend.SocietyVocabulary::builtin()
}

///|
/// A vocabulary is read out of a file's shape.
///
/// The format is asked for, the way every other MAKED file asks for its own.
test "a society vocabulary is read out of a file" {
  match
    @backend.SocietyVocabulary::from_json("society.yaml", vocabulary_payload()) {
    @backend.Accepted(vocabulary) => {
      assert_eq(vocabulary.path, "society.yaml")
      assert_eq(
        @backend.society_position_label(
          vocabulary,
          "World",
          @backend.Lang::english(),
        ),
        "Lifeworld",
      )
      assert_eq(
        @backend.society_trigger_label(
          vocabulary,
          "RaiseClaims",
          @backend.Lang::english(),
        ),
        "Raise a validity claim",
      )
    }
    @backend.Rejected(reason) => fail("the vocabulary was refused: " + reason)
  }
}

///|
/// A file from another version is refused rather than read as if it were
/// this one.
test "a society vocabulary in another format is refused" {
  let payload : Json = {
    "format": "maked.society.v9",
    "positions": [],
    "phases": [],
    "triggers": [],
  }
  match @backend.SocietyVocabulary::from_json("society.yaml", payload) {
    @backend.Rejected(reason) =>
      assert_true(reason.contains("maked.society.v1"))
    @backend.Accepted(_) => fail("a vocabulary in another format was accepted")
  }
}

///|
/// A name the machine does not have is refused.
///
/// It is a word about nowhere, and a vocabulary carrying one is a
/// vocabulary that has drifted away from the machine it names.
test "a society vocabulary naming a position the machine does not have is refused" {
  let payload : Json = {
    "format": "maked.society.v1",
    "positions": [{ "id": "Nowhere", "label": "Nowhere" }],
    "phases": [],
    "triggers": [],
  }
  match @backend.SocietyVocabulary::from_json("society.yaml", payload) {
    @backend.Rejected(reason) => assert_true(reason.contains("Nowhere"))
    @backend.Accepted(_) => fail("a vocabulary naming nowhere was accepted")
  }
}

///|
/// The built-in vocabulary names every position the machine has.
///
/// This is the guard that catches pyroduct adding a position: the built-in
/// vocabulary would then be missing a word, and the panel would show a
/// position with no name.
test "the built-in vocabulary names every position the machine has" {
  assert_eq(@backend.society_vocabulary_gaps(builtin()).length(), 0)
}

///|
/// The built-in vocabulary names every trigger the machine has.
test "the built-in vocabulary names every trigger the machine has" {
  let gaps = @backend.society_vocabulary_gaps(builtin())
  for gap in gaps {
    assert_false(gap.contains("trigger"))
  }
}

///|
/// The built-in vocabulary names every phase the machine has.
test "the built-in vocabulary names every phase the machine has" {
  let gaps = @backend.society_vocabulary_gaps(builtin())
  for gap in gaps {
    assert_false(gap.contains("phase"))
  }
}

///|
/// A vocabulary that is behind the machine reports the gap.
///
/// The gap is reported rather than hidden, because a position with no name
/// reads as "the machine has a position nobody has a word for" rather than
/// as "the file is behind the machine".
test "a vocabulary that is behind the machine reports the gap" {
  let vocabulary = @backend.SocietyVocabulary::builtin()
  let trimmed : @backend.SocietyVocabulary = {
    positions: Map([]),
    phases: vocabulary.phases,
    triggers: vocabulary.triggers,
    path: "",
  }
  let gaps = @backend.society_vocabulary_gaps(trimmed)
  assert_eq(gaps.length(), 13)
}

///|
/// The machine's positions are served, in pyroduct's order.
test "the society machine's positions are served" {
  let positions = @backend.society_positions(
    builtin(),
    @backend.Lang::english(),
  )
  assert_eq(positions.length(), 13)
  assert_eq(positions[0].id, "World")
  assert_eq(positions[0].label, "Lifeworld")
  assert_true(positions[0].gloss.length() > 0)
}

///|
/// The machine's transitions are served.
test "the society machine's transitions are served" {
  let transitions = @backend.society_transitions()
  assert_eq(transitions.length(), 28)
}

///|
/// Every transition names positions the machine has.
///
/// A transition to nowhere is a move that goes nowhere while looking
/// exactly like a move.
test "every society transition names positions the machine has" {
  for transition in @backend.society_transitions() {
    assert_true(@backend.society_position_from_id(transition.from) is Some(_))
    assert_true(@backend.society_position_from_id(transition.to) is Some(_))
    assert_true(@backend.society_trigger_from_id(transition.trigger) is Some(_))
  }
}

///|
/// The collective starts at the machine's first position.
test "the collective starts where the machine starts" {
  let state = @backend.get_loop_state()
  assert_eq(@backend.society_position_id(state.society_state), "World")
}

///|
/// A move the machine has takes the collective there.
test "a move the machine has takes the collective there" {
  let step = @backend.society_step(
    builtin(),
    @society.World,
    "RaiseClaims",
    @backend.Lang::english(),
  )
  match step {
    @backend.Advanced(trigger, to) => {
      assert_eq(trigger, "RaiseClaims")
      assert_eq(to, "Claim")
    }
    _ => fail("a move the machine has did not take the collective there")
  }
}

///|
/// A move the machine does not have is refused with a reason.
///
/// A refusal that says nothing looks exactly like a move that did nothing.
test "a move the machine does not have is refused with a reason" {
  let step = @backend.society_step(
    builtin(),
    @society.World,
    "NotAMove",
    @backend.Lang::english(),
  )
  match step {
    @backend.Refused(trigger, reason) => {
      assert_eq(trigger, "NotAMove")
      assert_true(reason.contains("NotAMove"))
    }
    _ => fail("a move that does not exist was not refused")
  }
}

///|
/// A move that is not out of this position is refused, in the vocabulary's
/// words.
///
/// The reason names the position and the move the way the reader can read
/// them, because pyroduct's own reason is in Chinese.
test "a move that is not out of this position is refused in the reader's words" {
  let step = @backend.society_step(
    builtin(),
    @society.World,
    "Distort",
    @backend.Lang::english(),
  )
  match step {
    @backend.Refused(_, reason) => {
      assert_true(reason.contains("Lifeworld"))
      assert_true(reason.contains("Distort communication"))
    }
    _ => fail("a move that is not out of this position was not refused")
  }
}

///|
/// The moves available from a position are the ones the machine offers.
test "the moves available from a position are the ones the machine offers" {
  let moves = @backend.society_moves(@society.World)
  assert_true(moves.length() > 0)
  for edge in moves {
    assert_eq(edge.from, "World")
    assert_true(@backend.society_position_from_id(edge.to) is Some(_))
  }
}

///|
/// The outcome kind is the vocabulary the whole of MAKED uses.
///
/// The subject machine and the society machine answer with the same four
/// shapes, and the frontend reads one vocabulary for both.
test "the outcome kind is the vocabulary the whole of MAKED uses" {
  let moved = @backend.society_step(
    builtin(),
    @society.World,
    "RaiseClaims",
    @backend.Lang::english(),
  )
  assert_eq(moved.society_step_kind(), "moved")
  let refused = @backend.society_step(
    builtin(),
    @society.World,
    "NotAMove",
    @backend.Lang::english(),
  )
  assert_eq(refused.society_step_kind(), "block")
}

///|
/// Stepping the collective installs the new position on the state.
///
/// The state carries it rather than a module cell, so a session that is
/// replayed can say where the collective was.
test "stepping the collective installs the new position on the state" {
  let before = @backend.get_loop_state()
  let after = before.with_society_state(@society.Claim)
  assert_eq(@backend.society_position_id(after.society_state), "Claim")
  assert_eq(@backend.society_position_id(before.society_state), "World")
}

///|
/// The vocabulary is written back in the shape it was read in.
test "the society vocabulary writes itself back" {
  let vocabulary = builtin()
  let json = vocabulary.to_json()
  match json {
    Object(fields) => {
      assert_true(fields.get("format") is Some(_))
      assert_true(fields.get("positions") is Some(_))
      assert_true(fields.get("triggers") is Some(_))
    }
    _ => fail("the vocabulary did not write itself back as an object")
  }
}

///|
/// A field of a JSON object.
///
/// The backend's own accessor is private, and a test is a blackbox package
/// that can see `pub` items and nothing else -- so the test carries its own.
fn field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
/// A string field of a JSON object.
fn text_of(json : Json, key : String) -> String {
  match field(json, key) {
    Some(String(s)) => s
    _ => ""
  }
}

///|
/// How long a list field is, or -1 when it is not a list.
fn list_length(json : Json, key : String) -> Int32 {
  match field(json, key) {
    Some(Array(items)) => items.length()
    _ => -1
  }
}

///|
/// The payload carries the collective's position and the moves from it.
test "the society payload carries the collective's position and the moves from it" {
  let payload = @backend.society_payload(
    builtin(),
    @society.World,
    @backend.SocietyOutcome::none(),
    @backend.Lang::english(),
  )
  assert_eq(text_of(payload, "state"), "World")
  assert_eq(text_of(payload, "state_label"), "Lifeworld")
  assert_eq(text_of(payload, "phase"), "Life")
  assert_true(list_length(payload, "moves") > 0)
  assert_eq(list_length(payload, "gaps"), 0)
}

///|
/// The payload carries the gaps in the vocabulary.
///
/// The built-in vocabulary has no gaps, so a payload built from it cannot
/// tell a reader that the gaps were dropped on the way out -- an assertion
/// of "no gaps" passes just as well when the gaps are never reported. This
/// one uses a vocabulary that is behind the machine, which is the only case
/// where the difference shows.
test "the payload carries the gaps in the vocabulary" {
  let vocabulary = @backend.SocietyVocabulary::builtin()
  let behind : @backend.SocietyVocabulary = {
    positions: Map([]),
    phases: vocabulary.phases,
    triggers: vocabulary.triggers,
    path: "",
  }
  let payload = @backend.society_payload(
    behind,
    @society.World,
    @backend.SocietyOutcome::none(),
    @backend.Lang::english(),
  )
  assert_eq(list_length(payload, "gaps"), 13)
}

///|
/// A refused move still carries the machine and the reason.
///
/// The payload has one shape on purpose. A body that carried only a reason
/// on refusal would leave the panel holding two shapes and no way to tell
/// which one it had been handed -- and the failure of a panel that guesses
/// wrong is that it goes blank while the collective is perfectly well
/// defined.
test "a refused move still carries the machine and the reason" {
  let outcome : @backend.SocietyOutcome = {
    kind: "block",
    reason: "there is no such move",
    from: "World",
  }
  let payload = @backend.society_payload(
    builtin(),
    @society.World,
    outcome,
    @backend.Lang::english(),
  )
  assert_eq(text_of(payload, "kind"), "block")
  assert_eq(text_of(payload, "reason"), "there is no such move")
  assert_eq(text_of(payload, "from"), "World")
  assert_eq(text_of(payload, "from_label"), "Lifeworld")
  assert_eq(list_length(payload, "positions"), 13)
  assert_eq(list_length(payload, "transitions"), 28)
}

///|
/// A move that lands says where the collective came from.
///
/// "The collective is now at a validity claim" is a fact with no history in
/// it. A reader watching the collective move cannot tell a first step from
/// a return without knowing where the move started.
test "a landed move says where the collective came from" {
  let outcome : @backend.SocietyOutcome = {
    kind: "moved",
    reason: "",
    from: "World",
  }
  let payload = @backend.society_payload(
    builtin(),
    @society.Claim,
    outcome,
    @backend.Lang::english(),
  )
  assert_eq(text_of(payload, "state"), "Claim")
  assert_eq(text_of(payload, "from"), "World")
  assert_eq(text_of(payload, "from_label"), "Lifeworld")
  assert_eq(text_of(payload, "reason"), "")
}

///|
/// A collective that has not moved yet says so with an empty kind.
///
/// The empty kind is what tells the panel "no move has been taken" apart
/// from "a move was taken and did nothing" -- two states that look the
/// same if the kind is read as a word.
test "a collective that has not moved yet has no outcome kind" {
  let payload = @backend.society_payload(
    builtin(),
    @society.World,
    @backend.SocietyOutcome::none(),
    @backend.Lang::english(),
  )
  assert_eq(text_of(payload, "kind"), "")
  assert_eq(text_of(payload, "reason"), "")
  assert_eq(text_of(payload, "from"), "")
}

///|
/// The collective's Chinese is the table's own.
///
/// The vocabulary file is the reader's own words, and it is written in
/// English. The Chinese is pyroduct's: a position is called 世界 because
/// pyroduct calls it that, and the gloss is the authority's own. The split is
/// the same one the subject machine makes, and the reason for it is the same
/// too -- a reader who wants to know what the machine calls something should
/// not have to take MAKED's word for it.
test "the collective is named in the table's own Chinese" {
  let payload = @backend.society_payload(
    builtin(),
    @society.World,
    @backend.SocietyOutcome::none(),
    @backend.Lang::chinese(),
  )
  // The position: 世界, and the authority's own gloss rather than a blank.
  assert_eq(text_of(payload, "state_label"), "世界")
  assert_true(text_of(payload, "state_gloss").contains("生活世界"))
  // The phase: 生活, the two-character name the authority gives it.
  assert_eq(text_of(payload, "phase"), "Life")
  let positions = match field(payload, "positions") {
    Some(Array(items)) => items
    _ => []
  }
  assert_eq(positions.length(), 13)
  assert_eq(json_str(positions[0], "label"), "世界")
  assert_eq(json_str(positions[0], "phase_label"), "生活")
  // The gloss in the list is the authority's own as well, not the vocabulary
  // file's English one. A Chinese reader is owed a Chinese sentence about
  // the place, not an English one with a Chinese name beside it -- and the
  // two are separate words in the payload, so the name being right says
  // nothing about the sentence.
  assert_true(json_str(positions[0], "gloss").contains("生活世界"))
}

///|
/// The English is the English it was.
///
/// The Chinese was written beside the English rather than over it, so the
/// vocabulary file still says what it said.
test "the collective is still named in the vocabulary's English" {
  let payload = @backend.society_payload(
    builtin(),
    @society.World,
    @backend.SocietyOutcome::none(),
    @backend.Lang::english(),
  )
  assert_eq(text_of(payload, "state_label"), "Lifeworld")
  assert_eq(
    text_of(payload, "state_gloss"),
    "The prior place where speakers and listeners meet, organised by language.",
  )
  let positions = match field(payload, "positions") {
    Some(Array(items)) => items
    _ => []
  }
  // The count is checked before the first position is read, and the order
  // matters: reading an element of a list that turned out to be empty takes
  // the whole test binary down, and a test binary that dies prints no
  // summary at all -- which reads as "the mutation did not compile" rather
  // than as the failure it is.
  assert_eq(positions.length(), 13)
  assert_eq(json_str(positions[0], "label"), "Lifeworld")
  assert_eq(json_str(positions[0], "phase_label"), "Life")
}

///|
/// The moves are named in the table's own Chinese too.
///
/// A move is a sentence the authority writes about what the move does, and
/// the Chinese is that sentence rather than a shortened version of it.
test "the moves are named in the table's own Chinese" {
  let payload = @backend.society_payload(
    builtin(),
    @society.World,
    @backend.SocietyOutcome::none(),
    @backend.Lang::chinese(),
  )
  let moves = match field(payload, "moves") {
    Some(Array(items)) => items
    _ => []
  }
  assert_true(moves.length() > 0)
  let first = json_str(moves[0], "trigger_label")
  assert_true(first != "")
  assert_true(first != json_str(moves[0], "to_label"))
  // The move names the authority's own words, and the landing place is one
  // of the authority's two-character names.
  assert_true(json_str(moves[0], "to_label").length() <= 4)
  // Every move is named in Chinese rather than in the English the vocabulary
  // file carries. The two are different sentences -- the file's is a label
  // and the authority's is a claim about what the move does -- so a Chinese
  // reader handed the file's English has been handed the wrong language, and
  // a check that only asked "is it different from the landing place" would
  // have said yes.
  let vocabulary = builtin()
  for m in moves {
    let id = json_str(m, "trigger")
    let english = @backend.society_trigger_label(
      vocabulary,
      id,
      @backend.Lang::english(),
    )
    assert_true(json_str(m, "trigger_label") != english)
  }
}

///|
/// A refused move is refused in the language that was asked for.
///
/// The reason names the position and the move, and a reader who asked for
/// Chinese must not be handed an English sentence.
test "a refused move says so in the language" {
  let step = @backend.society_step(
    builtin(),
    @society.World,
    "Distort",
    @backend.Lang::chinese(),
  )
  let reason = @backend.society_step_reason(
    builtin(),
    step,
    @backend.Lang::chinese(),
  )
  assert_true(reason.contains("没有可以走的"))
  // The place the refusal starts from is named in Chinese as well. A Chinese
  // sentence with an English place in it is a half-written sentence, and the
  // name of the place is a separate word in the reason, so the frame being
  // Chinese says nothing about it.
  assert_true(reason.contains("世界"))
  assert_false(reason.contains("Lifeworld"))
  // The reason is written when the move is taken, so the same refusal in
  // English is a different move taken in English.
  let english_step = @backend.society_step(
    builtin(),
    @society.World,
    "Distort",
    @backend.Lang::english(),
  )
  let english = @backend.society_step_reason(
    builtin(),
    english_step,
    @backend.Lang::english(),
  )
  assert_true(english.contains("there is no"))
}

///|
/// A move that does not exist is refused in the language too.
test "a move that is not in the machine is refused in the language" {
  let step = @backend.society_step(
    builtin(),
    @society.World,
    "NotAMove",
    @backend.Lang::chinese(),
  )
  let reason = @backend.society_step_reason(
    builtin(),
    step,
    @backend.Lang::chinese(),
  )
  assert_true(reason.contains("没有叫作"))
  assert_true(reason.contains("NotAMove"))
}

///|
/// The collective that stayed says so in the language.
///
/// The move that leads back where it came from is the machine's own
/// self-loop, and the sentence that says so names the place it leads to.
test "a collective that stayed says so in the language" {
  let step = @backend.society_step(
    builtin(),
    @society.Suprasubjective,
    "SpeakLanguage",
    @backend.Lang::chinese(),
  )
  let reason = @backend.society_step_reason(
    builtin(),
    step,
    @backend.Lang::chinese(),
  )
  assert_true(reason.contains("集体停在原地"))
  assert_true(reason.contains("超体"))
}

///|
/// The agent's collective is in the language as well.
///
/// The agent's server is the same surface as the panel, and a caller that
/// asked for Chinese must not get the English names of the same machine.
test "the agent's collective is in the language" {
  let chinese = @backend.agent_society(@backend.Lang::chinese())
  assert_eq(json_str(chinese, "the_collective"), "世界")
  let english = @backend.agent_society(@backend.Lang::english())
  assert_eq(json_str(english, "the_collective"), "Lifeworld")
}
