///| Tests for the model: MAKED's machine as data.
///
/// The model is the thing the loop is going to run on instead of a
/// package, so the tests here are mostly about one question: **does the
/// machine that was written down say the same thing as the machine that
/// was read?**
///
/// A translation that is nearly right is the dangerous kind. If the written
/// model and pyroproduct's table agree on most pairs and differ on one, the
/// loop would be wrong in a place nobody looks -- and the wrongness would
/// look like the model, not like a mistake. So the two are compared over
/// every one of the 272 combinations, and the comparison is not a sample.
///
/// The other half of the file is the point of writing a machine down: a
/// model that is *not* pyroproduct's. The toy model in here has two
/// domains, three positions and two slots, and it is not a product
/// iteration loop or a clinical path -- it is the smallest thing that can
/// show the format carries a machine rather than a particular machine.

///|
/// The outcome pyroproduct would give, in the model's own words.
///
/// Written out again here rather than reused from `model.mbt`, because a
/// test that shares the code it is checking proves nothing: if the
/// translation were wrong, both sides would be wrong in the same way and
/// the comparison would pass.
fn expected_move(
  state : @sm.SubjectState,
  outcome : @sm.Outcome,
) -> @backend.Move {
  match outcome {
    @sm.Moved(tr, to) =>
      @backend.Move::Moved(tr.en_label(), @backend.position_id_of(to))
    @sm.Held(tr, to) =>
      @backend.Move::Held(tr.en_label(), @backend.position_id_of(to))
    @sm.Same(_, named, to) => {
      let edges = []
      for tr in named {
        edges.push(tr.en_label())
      }
      @backend.Move::Same(edges, @backend.position_id_of(to))
    }
    @sm.Open(cands) => {
      let candidates = []
      for c in cands {
        let (edge, target) = c
        let kind = match @sm.step_by_trigger(state, edge) {
          @sm.Moved(_, _) => "moved"
          @sm.Held(_, _) => "held"
          _ => "same"
        }
        candidates.push(@backend.Candidate::{
          edge: edge.en_label(),
          to: @backend.position_id_of(target),
          kind,
        })
      }
      @backend.Move::Open(candidates)
    }
    @sm.Block(reason) => @backend.Move::Block(reason)
  }
}

///|
/// The built-in model says what pyroduct says, for every combination.
test "the written-down model agrees with the table on every combination" {
  let model = @backend.Model::pyroduct()
  let mut checked = 0
  for state in @sm.all_states() {
    for slot in @sm.all_slots() {
      let from = @backend.position_id_of(state)
      let slot_id = @backend.slot_id_of(slot)
      let written = model.step(from, slot_id)
      let expected = expected_move(state, @sm.step(state, slot))
      assert_eq(written, expected)
      checked += 1
    }
  }
  // Not "all of them": the number. A loop that checked nothing would also
  // pass the assertion above.
  assert_eq(checked, 272)
}

///|
/// The shape of the built-in model is the shape of the table.
test "the built-in model has the table's shape" {
  let model = @backend.Model::pyroduct()
  assert_eq(model.domains.length(), 5)
  assert_eq(model.positions.length(), 34)
  assert_eq(model.slots.length(), 8)
  assert_eq(model.rules.length(), 272)
}

///|
/// Every position and every slot has an id of its own.
///
/// Two positions with one id would be two positions the model cannot tell
/// apart, and a rule about one of them would be a rule about both.
test "the ids in the model are unique" {
  let model = @backend.Model::pyroduct()
  let position_ids = []
  for position in model.positions {
    assert_false(position_ids.contains(position.id))
    position_ids.push(position.id)
  }
  let slot_ids = []
  for slot in model.slots {
    assert_false(slot_ids.contains(slot.id))
    slot_ids.push(slot.id)
  }
}

///|
/// The ids are URL-safe, because they are what a URL carries.
///
/// Lower case, and no spaces: a path segment with a space in it is a path
/// that has to be escaped before it can be asked for, and an id that needs
/// escaping is an id that will be escaped differently in two places.
test "the ids in the model are safe to put in a URL" {
  let model = @backend.Model::pyroduct()
  for position in model.positions {
    assert_true(position.id != "")
    assert_false(position.id.contains(" "))
    assert_eq(position.id.to_lower(), position.id)
  }
  for slot in model.slots {
    assert_true(slot.id != "")
    assert_false(slot.id.contains(" "))
    assert_eq(slot.id.to_lower(), slot.id)
  }
}

///|
/// The model survives a trip through JSON.
test "the model round-trips through JSON" {
  let model = @backend.Model::pyroduct()
  let json = model.to_json()
  let back = @backend.Model::from_json(json)
  assert_true(back is Some(_))
  let read = back.unwrap()
  assert_eq(read, model)
}

///|
/// The JSON says which format it is, so a file written by a later version
/// is refused rather than half-read.
test "the model's JSON names its format" {
  let json = @backend.Model::pyroduct().to_json()
  match json {
    Object(fields) =>
      match fields.get("format") {
        Some(String(format)) => assert_eq(format, "maked.model.v1")
        _ => fail("the model JSON should say which format it is")
      }
    _ => fail("the model JSON should be an object")
  }
}

///|
/// A file that is not a model is not read as one.
test "a file in another format is refused" {
  let json : Json = { "format": "somebody.elses.model.v9", "name": "Not ours" }
  assert_true(@backend.Model::from_json(json) is None)
}

///|
/// A model that names a position it does not define is refused.
///
/// The rule is about a position that is not there, so reading it would mean
/// inventing a position to hold it -- and a model that invents a position
/// is a model that lies about its own size.
test "a rule about a position the model does not define is refused" {
  let json : Json = {
    "format": "maked.model.v1",
    "name": "Broken",
    "domains": [],
    "positions": [{ "id": "here", "label": "Here", "gloss": "", "domain": "" }],
    "slots": [{ "id": "act", "designation": "Act", "gloss": "" }],
    "rules": [
      {
        "from": "here",
        "slot": "act",
        "outcome": { "kind": "moved", "edge": "e", "to": "nowhere" },
      },
    ],
    "continuations": [],
  }
  assert_true(@backend.Model::from_json(json) is None)
}

///|
/// A model somebody else wrote: two domains, three positions, two slots.
///
/// This is the shape of a product-iteration loop rather than a model of a
/// person, and the point of it is that nothing in the format assumes
/// pyroproduct's sizes. A model with three positions is not a model with a
/// missing domain.
fn toy_model() -> Json {
  {
    "format": "maked.model.v1",
    "name": "Product iteration",
    "domains": [
      {
        "id": "idea",
        "letter": "I",
        "title": "Idea",
        "role": "the idea",
        "anchor": "raw",
      },
      {
        "id": "ship",
        "letter": "S",
        "title": "Ship",
        "role": "the shipping",
        "anchor": "built",
      },
    ],
    "positions": [
      {
        "id": "raw",
        "label": "Raw idea",
        "gloss": "Nobody has built it yet.",
        "domain": "idea",
      },
      {
        "id": "talked",
        "label": "Talked about",
        "gloss": "Someone has heard it.",
        "domain": "idea",
      },
      {
        "id": "built",
        "label": "Built",
        "gloss": "It exists.",
        "domain": "ship",
      },
    ],
    "slots": [
      { "id": "ask", "designation": "Ask", "gloss": "Talk to a customer." },
      { "id": "build", "designation": "Build", "gloss": "Make the thing." },
    ],
    "rules": [
      {
        "from": "raw",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said no",
          "to": "talked",
        },
      },
      {
        "from": "raw",
        "slot": "build",
        "outcome": { "kind": "moved", "edge": "It was built", "to": "built" },
      },
      {
        "from": "talked",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said yes",
          "to": "built",
        },
      },
      {
        "from": "talked",
        "slot": "build",
        "outcome": { "kind": "block", "reason": "nothing to build yet" },
      },
      {
        "from": "built",
        "slot": "ask",
        "outcome": { "kind": "block", "reason": "it is built" },
      },
      {
        "from": "built",
        "slot": "build",
        "outcome": { "kind": "held", "edge": "Shipped", "to": "built" },
      },
    ],
    "continuations": [
      { "from": "raw", "slot": "ask", "to": "talked", "steps": 1 },
      { "from": "raw", "slot": "ask", "to": "built", "steps": 2 },
    ],
  }
}

///|
/// A model that is not pyroproduct's is read, and answers questions.
test "a model somebody else wrote is read" {
  let model = @backend.Model::from_json(toy_model())
  assert_true(model is Some(_))
  let read = model.unwrap()
  assert_eq(read.name, "Product iteration")
  assert_eq(read.domains.length(), 2)
  assert_eq(read.positions.length(), 3)
  assert_eq(read.slots.length(), 2)
  assert_eq(read.rules.length(), 6)
}

///|
/// The drive slot is read out of the model, not chosen by meaning.
///
/// The toy model has no slot that *means* "the right one" -- "Ask" and
/// "Build" are both slots, and which one drives depends on the rules. What
/// matters is that the answer comes from the rules and not from the names.
test "the drive slot comes from the model's rules" {
  let model = @backend.Model::from_json(toy_model()).unwrap()
  assert_eq(model.drive_slot("raw"), Some("ask"))
  assert_eq(model.drive_slot("talked"), Some("ask"))
  // "built" has no slot that moves: "Build" holds it there.
  assert_eq(model.drive_slot("built"), Some("build"))
}

///|
/// A position with no way out is reported as such.
test "a position with no way out has no drive slot" {
  let json : Json = {
    "format": "maked.model.v1",
    "name": "Blocked",
    "domains": [],
    "positions": [
      { "id": "stuck", "label": "Stuck", "gloss": "", "domain": "" },
    ],
    "slots": [{ "id": "act", "designation": "Act", "gloss": "" }],
    "rules": [
      {
        "from": "stuck",
        "slot": "act",
        "outcome": { "kind": "block", "reason": "nowhere" },
      },
    ],
    "continuations": [],
  }
  let blocked = @backend.Model::from_json(json).unwrap()
  assert_eq(blocked.drive_slot("stuck"), None)
  assert_eq(blocked.exitable_slots("stuck").length(), 0)
  assert_false(blocked.is_undecided("stuck"))
}

///|
/// A table that offers several successors and refuses to choose is
/// recognised as such, in a model that is not pyroproduct's.
test "a model can offer a choice it will not make" {
  let json : Json = {
    "format": "maked.model.v1",
    "name": "Undecided",
    "domains": [],
    "positions": [
      { "id": "here", "label": "Here", "gloss": "", "domain": "" },
      { "id": "there", "label": "There", "gloss": "", "domain": "" },
      { "id": "elsewhere", "label": "Elsewhere", "gloss": "", "domain": "" },
    ],
    "slots": [{ "id": "choose", "designation": "Choose", "gloss": "" }],
    "rules": [
      {
        "from": "here",
        "slot": "choose",
        "outcome": {
          "kind": "open",
          "candidates": [
            { "edge": "one way", "to": "there", "kind": "moved" },
            { "edge": "another way", "to": "elsewhere", "kind": "moved" },
          ],
        },
      },
    ],
    "continuations": [],
  }
  let model = @backend.Model::from_json(json).unwrap()
  assert_true(model.is_undecided("here"))
  let candidates = model.candidates("here", "choose")
  assert_eq(candidates.length(), 2)
  assert_eq(candidates[0].to, "there")
  assert_eq(candidates[1].to, "elsewhere")
}

///|
/// The names a reader sees are the model's, not the package's.
test "the model carries the names a reader sees" {
  let model = @backend.Model::pyroduct()
  assert_eq(model.position_label("standing"), "Standing")
  assert_eq(model.slot_designation("occasion"), "Situation")
  assert_eq(model.slot_designation("cobeing"), "Co-being")
  // A position the model does not have has no name.
  assert_eq(model.position_label("nowhere"), "")
}

///|
/// The candidates of an open branch are written as objects, not as text.
///
/// A record that is turned into JSON by accident becomes a string of its own
/// field names -- `"@{edge=...; to=...; kind=...}"` -- and a model file
/// full of those cannot be read back, because the reader of the file has no
/// way to know that the text stands for a candidate. The JSON is checked
/// here rather than the record, because the record is fine either way: it
/// is the writing down that can go wrong.
test "the candidates of an open branch are written as objects" {
  let model = @backend.Model::pyroduct()
  let mut checked = 0
  for rule in model.rules {
    match rule.transition {
      @backend.Move::Open(candidates) => {
        for candidate in candidates {
          assert_true(candidate.edge != "")
          assert_true(candidate.to != "")
        }
        let json = rule.transition.to_json()
        match json {
          Object(fields) =>
            match fields.get("candidates") {
              Some(Array(items)) =>
                for item in items {
                  match item {
                    Object(inner) => {
                      assert_true(inner.get("edge") is Some(_))
                      assert_true(inner.get("to") is Some(_))
                      assert_true(inner.get("kind") is Some(_))
                    }
                    _ => fail("a candidate should be an object, not a string")
                  }
                }
              _ => fail("the candidates of an open branch should be a list")
            }
          _ => fail("an outcome should be an object")
        }
        checked += 1
      }
      _ => ()
    }
  }
  // Not "all of them": the number. A model with no open branch would pass
  // the loop above without checking anything.
  assert_true(checked > 0)
}

///|
/// The continuations are the model's, and a successor reached twice is
/// listed once at the shorter distance.
test "the model's continuations are read back as they were written" {
  let model = @backend.Model::from_json(toy_model()).unwrap()
  let out = model.continuations("raw", 3)
  assert_eq(out.length(), 2)
  assert_eq(out[0].0, "talked")
  assert_eq(out[0].1, 1)
  assert_eq(out[1].0, "built")
  assert_eq(out[1].1, 2)
}

///|
/// A model that leaves a pair undefined reports no way out there.
///
/// A model file does not have to write a rule for every (position, slot)
/// pair -- and where it does not, the honest answer is that there is no road
/// out of that position, not that some slot would do. Offering one anyway
/// would be the model claiming an edge it does not have, which is the one
/// thing the whole format is for not doing.
test "a pair the model leaves undefined has no way out" {
  let json : Json = {
    "format": "maked.model.v1",
    "name": "Partial",
    "domains": [],
    "positions": [
      { "id": "here", "label": "Here", "gloss": "", "domain": "" },
      { "id": "there", "label": "There", "gloss": "", "domain": "" },
    ],
    "slots": [{ "id": "act", "designation": "Act", "gloss": "" }],
    "rules": [
      {
        "from": "here",
        "slot": "act",
        "outcome": { "kind": "moved", "edge": "e", "to": "there" },
      },
    ],
    "continuations": [],
  }
  let model = @backend.Model::from_json(json).unwrap()
  // The pair the model does define has a road out of it.
  assert_eq(model.exitable_slots("here"), ["act"])
  // The pair it leaves undefined has none -- and says so rather than
  // inventing a slot to drive.
  assert_eq(model.exitable_slots("there"), [])
  assert_eq(model.drive_slot("there"), None)
  assert_eq(model.step("there", "act").kind(), "block")
}

///|
/// The ring is the model's, and it is as long as the model says.
///
/// MAKED's built-in model has five domains, so its ring has five steps. A
/// model written by somebody else can have two, and then its ring has two:
/// the ring is a property of the machine, not of MAKED.
test "the ring is as long as the model says" {
  let built_in = @backend.Model::pyroduct()
  assert_eq(built_in.domains.length(), 5)
  let toy = @backend.Model::from_json(toy_model()).unwrap()
  assert_eq(toy.domains.length(), 2)
  let idea = toy.domain_by_id("idea").unwrap()
  let ship = toy.domain_by_id("ship").unwrap()
  // Two domains: one step, and back to the first.
  assert_eq(toy.next_domain(idea), ship)
  assert_eq(toy.next_domain(ship), idea)
}

///|
/// The domains are found by letter, by id and by title.
///
/// The letter is how the ring is drawn and how a domain is named in a URL;
/// the id is the stable name; the title is the one a reader sees. A model
/// file may give a domain any title it likes, so all three are accepted.
test "a domain is found by its letter, its id and its title" {
  let toy = @backend.Model::from_json(toy_model()).unwrap()
  assert_eq(toy.domain_by_letter("I").map(fn(d) { d.id }), Some("idea"))
  assert_eq(toy.domain_by_letter("i").map(fn(d) { d.id }), Some("idea"))
  assert_eq(toy.domain_by_name("Idea").map(fn(d) { d.id }), Some("idea"))
  assert_eq(toy.domain_by_name("idea").map(fn(d) { d.id }), Some("idea"))
  assert_true(toy.domain_by_letter("Z") is None)
  assert_true(toy.domain_by_name("nowhere") is None)
}

///|
/// A domain whose anchor is not a position in the model is refused.
///
/// Such a domain starts nowhere, and a loop that put a subject there would
/// be putting it in a position the file does not describe.
test "a domain that anchors nowhere is refused" {
  let json : Json = {
    "format": "maked.model.v1",
    "name": "Nowhere",
    "domains": [
      {
        "id": "idea",
        "letter": "I",
        "title": "Idea",
        "role": "the idea",
        "anchor": "not-a-position",
      },
    ],
    "positions": [
      { "id": "raw", "label": "Raw idea", "gloss": "", "domain": "idea" },
    ],
    "slots": [{ "id": "ask", "designation": "Ask", "gloss": "" }],
    "rules": [],
    "continuations": [],
  }
  assert_true(@backend.Model::from_json(json) is None)
}

///|
/// A model that writes no continuations down has them worked out.
///
/// A hand-written model usually does not list its lookahead: the author
/// writes the rules, and the rules already say what can follow what. So the
/// model is walked instead -- from the raw idea, "talked" and "built" are
/// one step away, and neither is listed twice.
test "a model with no continuations has them worked out from its rules" {
  let json : Json = {
    "format": "maked.model.v1",
    "name": "Worked out",
    "domains": [],
    "positions": [
      { "id": "raw", "label": "Raw idea", "gloss": "", "domain": "" },
      { "id": "talked", "label": "Talked about", "gloss": "", "domain": "" },
      { "id": "built", "label": "Built", "gloss": "", "domain": "" },
    ],
    "slots": [
      { "id": "ask", "designation": "Ask", "gloss": "" },
      { "id": "build", "designation": "Build", "gloss": "" },
    ],
    "rules": [
      {
        "from": "raw",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said no",
          "to": "talked",
        },
      },
      {
        "from": "raw",
        "slot": "build",
        "outcome": { "kind": "moved", "edge": "It was built", "to": "built" },
      },
      {
        "from": "talked",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said yes",
          "to": "built",
        },
      },
      {
        "from": "built",
        "slot": "build",
        "outcome": { "kind": "held", "edge": "Shipped", "to": "built" },
      },
    ],
    "continuations": [],
  }
  let model = @backend.Model::from_json(json).unwrap()
  let out = model.continuations("raw", 3)
  // Both successors are one step away, and nothing is listed twice.
  assert_eq(out.length(), 2)
  let mut talked = -1
  let mut built = -1
  for pair in out {
    if pair.0 == "talked" {
      talked = pair.1
    }
    if pair.0 == "built" {
      built = pair.1
    }
  }
  assert_eq(talked, 1)
  assert_eq(built, 1)
  // And through one slot: "Ask" first, then whatever the model offers.
  let through_ask = model.continuations_for("raw", "ask", 3)
  assert_eq(through_ask.length(), 2)
  assert_eq(through_ask[0].0, "talked")
  assert_eq(through_ask[0].1, 1)
  assert_eq(through_ask[1].0, "built")
  assert_eq(through_ask[1].1, 2)
}

///|
/// A model with two domains drives a two-domain loop.
///
/// The domains are the model's now, so a model with two of them has a loop
/// with two -- not MAKED's five, and not five lenses standing over a
/// two-position machine.
///
/// The model is *carried* by the state rather than installed over the one
/// MAKED runs. That is not a detail: installing a model takes the installed
/// machine away from every other thread, and the test suite runs its blocks
/// side by side. A test that swapped the installed model was a race with
/// every other test, and the race showed up as a crash in a test that had
/// nothing to do with models.
test "a model with two domains drives a two-domain loop" {
  let toy = @backend.Model::from_json(toy_model()).unwrap()
  // Two domains, and the loop starts on the model's first.
  assert_eq(toy.domains.length(), 2)
  let state = @backend.LoopState::new_for(toy)
  assert_eq(state.current.id, "idea")
  // Each domain stands at its own anchor, from the model rather than from a
  // table of MAKED's own.
  let idea = toy.domain_by_id("idea").unwrap()
  let ship = toy.domain_by_id("ship").unwrap()
  assert_eq(state.domain_state(idea).position, "raw")
  assert_eq(state.domain_state(ship).position, "built")
  // And the ring is two steps, not five.
  assert_eq(toy.next_domain(idea).id, "ship")
  assert_eq(toy.next_domain(ship).id, "idea")
}

///|
/// MAKED's built-in machine is five lenses, and they carry these letters.
///
/// The letters are not decoration: the ring is drawn with them, a domain is
/// named by one in a URL, and the session history is counted in them. Nothing
/// tested them, so a letter could have been renamed and the whole suite would
/// have stayed green -- while the ring was drawn in a different alphabet than
/// the one the site narrates.
test "the built-in machine has the five lenses it says it has" {
  let model = @backend.current_model()
  let ids = model.domains.map(fn(d) { d.id })
  let letters = model.domains.map(fn(d) { d.letter })
  assert_eq(ids, ["model", "data", "experience", "attack", "knowledge"])
  assert_eq(letters, ["M", "D", "E", "A", "K"])
}

///|
/// A model somebody else wrote, with its own words for the outcomes.
///
/// The vocabulary is part of the model, so a file that renames an outcome
/// renames it everywhere: in the panel, in the history, in the export. It is
/// also allowed to say nothing about some kinds, and then the kind is the
/// word -- honest, because the outcome happened and the file has no name
/// for it.
fn toy_model_with_words() -> Json {
  {
    "format": "maked.model.v1",
    "name": "Renamed",
    "domains": [
      {
        "id": "idea",
        "letter": "I",
        "title": "Idea",
        "role": "the idea",
        "anchor": "raw",
      },
    ],
    "positions": [
      {
        "id": "raw",
        "label": "Raw idea",
        "gloss": "Nobody has built it yet.",
        "domain": "idea",
      },
      {
        "id": "talked",
        "label": "Talked about",
        "gloss": "Someone has heard it.",
        "domain": "idea",
      },
    ],
    "slots": [
      { "id": "ask", "designation": "Ask", "gloss": "Talk to a customer." },
    ],
    "rules": [
      {
        "from": "raw",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said no",
          "to": "talked",
        },
      },
    ],
    "continuations": [],
    "outcomes": [
      { "kind": "moved", "label": "Advanced" },
      { "kind": "open", "label": "Undecided" },
    ],
  }
}

///|
/// Every outcome the model can produce has a word.
///
/// The words are the model's, and a model that produces an outcome it cannot
/// name is a model with a hole in it: the reader would see the kind spelled
/// out in the panel and would have no way of knowing the model had not said
/// anything about it.
test "every outcome the model can produce has a word" {
  let model = @backend.Model::pyroduct()
  for rule in model.rules {
    let kind = rule.transition.kind()
    let word = model.outcome_label(kind)
    assert_false(word == "")
    // The built-in model's words are words, not the kinds again.
    assert_false(word == kind)
  }
}

///|
/// The built-in model's words are the table's own.
///
/// The model collects them from the table as it walks it, and this asks the
/// table again -- the same way the 272 rules are compared -- so a word that
/// drifted from the table's rendering would be caught here rather than in a
/// reader's eye.
test "the built-in model's words are the table's own" {
  let model = @backend.Model::pyroduct()
  for state in @sm.all_states() {
    for slot in @sm.all_slots() {
      let outcome = @sm.step(state, slot)
      let kind = @backend.Move::of(state, outcome).kind()
      assert_eq(model.outcome_label(kind), outcome.en_label())
    }
  }
}

///|
/// A model file's own words are the words.
///
/// The vocabulary is part of the model, so a file that renames an outcome
/// renames it: the word a reader sees is the file's, not MAKED's.
test "a model file's own words are the words" {
  let toy = @backend.Model::from_json(toy_model_with_words()).unwrap()
  assert_eq(toy.outcome_label("moved"), "Advanced")
  assert_eq(toy.outcome_label("open"), "Undecided")
  // And a kind the file says nothing about falls back to the kind itself.
  assert_eq(toy.outcome_label("held"), "held")
}

///|
/// The vocabulary survives a trip through JSON with the rest of the model.
///
/// A file that was written down and read back has to say the same thing, and
/// the words are part of what it says.
test "the words survive a trip through JSON" {
  let toy = @backend.Model::from_json(toy_model_with_words()).unwrap()
  let back = @backend.Model::from_json(toy.to_json()).unwrap()
  assert_eq(back.outcome_label("moved"), "Advanced")
  assert_eq(back.outcome_label("open"), "Undecided")
}

///|
/// A loop on a model of its own answers from that model.
///
/// The state carries the machine it was built for, and every question about
/// the state -- the outcome's word, the position's label, the ring -- is
/// asked of that machine. A state that asked the *installed* model would be
/// half on one machine and half on another: the ring walked with the wrong
/// lenses, and a word borrowed from a machine nobody took the step on.
///
/// The installed model is left alone throughout, and the last line says so.
test "a loop on a model of its own answers from that model" {
  let toy = @backend.Model::from_json(toy_model_with_words()).unwrap()
  let state = @backend.LoopState::new_for(toy)
  let after = state.step_with_slot("ask")
  let event = after.history[0]
  // The word is the model's.
  assert_eq(event.outcome_label, "Advanced")
  // And the kind is the kind, whatever the model calls it.
  assert_eq(event.outcome_kind, "moved")
  // The position's label is the model's too -- not the installed model's.
  assert_eq(event.position_label, "Raw idea")
  assert_eq(event.outcome_detail, "A customer said no → Talked about")
  // The installed model was neither consulted nor changed.
  assert_eq(@backend.current_model().outcome_label("moved"), "Moved")
  assert_eq(@backend.current_model().domain_ids().length(), 5)
}

///|
/// The built-in model with a different name, and nothing else changed.
///
/// The point of it is that it is *the same machine*. A test that installs a
/// model with different domains changes what every other test in the suite
/// sees while it is installed, and the suite runs its blocks side by side --
/// which is how a test that swapped the model used to crash a test that had
/// nothing to do with models. A model that differs only in its name can be
/// installed without changing a single answer any other test reads.
fn renamed_built_in() -> @backend.Model {
  let model = @backend.Model::pyroduct()
  {
    name: "Renamed",
    domains: model.domains,
    positions: model.positions,
    slots: model.slots,
    rules: model.rules,
    continuations: model.continuations,
    outcomes: model.outcomes,
  }
}

///|
/// The model that was read is the model that runs.
///
/// A server that read a file and then ran the built-in machine anyway would
/// answer every request confidently and about the wrong loop. The install is
/// what closes that gap.
///
/// The model installed here is the built-in one with a new name, so the check
/// cannot disturb a test running beside it: every answer it gives is the
/// answer the built-in model gives, and only the name is different.
test "the model that is installed is the model that runs" {
  let built_in = @backend.current_model()
  let renamed = renamed_built_in()
  @backend.install_model(renamed)
  let installed = @backend.current_model()
  // The built-in one goes back before anything is asserted, so the window in
  // which the installed model is not the built-in one is as short as it can
  // be.
  @backend.install_model(built_in)
  assert_eq(installed.name, "Renamed")
  // And the built-in model is back, answering as it did.
  assert_eq(@backend.current_model().name, built_in.name)
  assert_eq(@backend.current_model().domain_ids().length(), 5)
}

///|
/// Every domain of the model has a state.
///
/// The per-domain map is keyed by the model's own domain id, and every
/// domain the model declares has an entry in it. That is the invariant that
/// makes a lookup answerable rather than a crash: the state and the model
/// are the same object, so a domain the state is asked about is a domain the
/// state has.
///
/// The check reads the map rather than asking the state, so that a broken
/// key fails the test instead of taking the whole test binary down with it.
test "every domain of the model has a state" {
  let model = @backend.current_model()
  let state = @backend.LoopState::new_for(model)
  for domain in model.domains {
    assert_true(state.domain_states.get(domain.id) is Some(_))
  }
  // And a model of somebody else's has the same shape.
  let toy = @backend.Model::from_json(toy_model()).unwrap()
  let toy_state = @backend.LoopState::new_for(toy)
  for domain in toy.domains {
    assert_true(toy_state.domain_states.get(domain.id) is Some(_))
  }
}
