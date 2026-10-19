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
    match rule.move {
      @backend.Move::Open(candidates) => {
        for candidate in candidates {
          assert_true(candidate.edge != "")
          assert_true(candidate.to != "")
        }
        let json = rule.move.to_json()
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
