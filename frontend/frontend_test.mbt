///| Frontend tests.
///
/// MoonBit compiles a `_test.mbt` file as a *blackbox* package: it can see
/// `pub` items and nothing else, and it wants every cross-file name qualified
/// as `@frontend.<name>` (an unqualified name is a `test_unqualified_package`
/// warning). That is why `slug_of`, `nodes`, `node_xy`, `node_percent`, `CX`,
/// `CY` and `RING_R` are `pub` in the sources despite nothing calling them.
///
/// These cover the logic that fails *silently* rather than loudly:
///
///   - `slug_of` decides which page a URL shows. If it stops stripping the
///     leading slash, deep links render the not-found view with no error.
///   - `decode_pages` is total by design: a missing field falls back rather
///     than raising, so a backend change would otherwise show up as a blank
///     page instead of a failure.
///   - the ring geometry. The order M -> D -> E -> A -> K is inherited from
///     the logo, and a plausible "tidying" into spelling order would still
///     produce five evenly spaced nodes that merely look wrong.

///|
fn page(
  slug : String,
  letter : String,
  sort : Int32,
  nav : Bool,
) -> @frontend.Page {
  {
    slug,
    title: slug,
    letter,
    role: "role",
    summary: "summary",
    body: "<p>body</p>",
    in_navigation: nav,
    sort,
  }
}

///|
/// Parse a `node_percent` component back to a number.
///
/// The `chars=` label is not optional: `String::trim_end` is declared
/// `(String, chars? : StringView)`, but passing that argument positionally is
/// rejected with "requires 1 positional arguments, but is given 2" -- method
/// call and `String::trim_end(s, ..)` alike. Only the labelled form compiles.
fn percent_of(value : String) -> Double {
  @string.parse_double(value.trim_end(chars="%")) catch {
    _ => -1.0
  }
}

///|
/// The five node centres in SVG coordinates, read off the original mark: M at
/// the top, then clockwise to D on the right, E at the lower right, A at the
/// lower left, and K on the left.
///
/// These are literals on purpose. Recomputing them from `CX`, `CY`, `RING_R`
/// and the angle formula would only restate the implementation: shrinking the
/// radius to 64 leaves both the nodes and the recomputed expectation moving
/// together, and the test stays green while the mark stops matching the
/// original. A mutation check is what caught that -- the first version of this
/// file compared the node distance against `RING_R` and survived.
fn expected_centres() -> Array[(Int32, Int32)] {
  [
    (100, 32), // M, top
    (165, 79), // D, right
    (140, 155), // E, lower right
    (60, 155), // A, lower left
    (35, 79), // K, left
  ]
}

///|
/// The viewBox edge, as a literal for the same reason as `expected_centres`.
const VIEW_EDGE : Double = 200.0

///|
/// The ring radius the original mark uses, also as a literal.
const EXPECTED_RING_R : Double = 68.0

///|
test "slug_of maps urls to page slugs" {
  assert_eq(@frontend.slug_of("/"), "index")
  assert_eq(@frontend.slug_of("/index"), "index")
  assert_eq(@frontend.slug_of("/about"), "about")
  assert_eq(@frontend.slug_of("/knowledge"), "knowledge")
  // No leading slash at all still resolves rather than returning "".
  assert_eq(@frontend.slug_of("about"), "about")
  // An unmapped path must reach the not-found view under its own name rather
  // than collapsing into the index.
  assert_eq(@frontend.slug_of("/nope"), "nope")
}

///|
test "navigation keeps ring order and drops non-nav pages" {
  let pages = [
    page("index", "", -1, false),
    page("model", "M", 0, true),
    page("data", "D", 1, true),
    page("experience", "E", 2, true),
    page("attack", "A", 3, true),
    page("knowledge", "K", 4, true),
    page("tutorial", "", 5, true),
  ]
  let nav = @frontend.navigation(pages)
  assert_eq(nav.map(fn(p) { p.slug }), [
    "model", "data", "experience", "attack", "knowledge", "tutorial",
  ])
  // The ring order specifically: not the order the name is spelled.
  assert_eq(nav.filter(fn(p) { p.letter != "" }).map(fn(p) { p.letter }), [
    "M", "D", "E", "A", "K",
  ])
}

///|
test "find_page looks up by slug and returns None when absent" {
  let pages = [page("about", "", 0, true), page("tasks", "", 1, true)]
  assert_true(@frontend.find_page(pages, "about") is Some(_))
  assert_true(@frontend.find_page(pages, "nope") is None)
}

///|
test "decode_pages reads the backend payload" {
  let json : Json = {
    "pages": [
      {
        "slug": "model",
        "title": "Model",
        "letter": "M",
        "role": "the model formulator",
        "summary": "s",
        "body": "<p>b</p>",
        "in_navigation": true,
        "sort": 0,
      },
      {
        "slug": "about",
        "title": "About",
        "letter": "",
        "role": "",
        "summary": "what this is",
        "body": "<p>a</p>",
        "in_navigation": true,
        "sort": 6,
      },
    ],
  }
  let pages = @frontend.decode_pages(json)
  assert_eq(pages.length(), 2)
  assert_eq(pages[0].slug, "model")
  assert_eq(pages[0].letter, "M")
  assert_true(pages[0].in_navigation)
  assert_eq(pages[1].slug, "about")
  assert_eq(pages[1].letter, "")
  assert_eq(pages[1].sort, 6)
}

///|
test "decode_pages survives malformed payloads without raising" {
  // The accessors are total on purpose. A backend that drops a field should
  // render a degraded page, not blank the whole site.
  // `Json::empty_object()` rather than `{}`: a bare `{}` is ambiguous among
  // four things, Map included.
  assert_eq(@frontend.decode_pages(Json::empty_object()).length(), 0)
  let wrong_shape : Json = { "pages": "not-an-array" }
  assert_eq(@frontend.decode_pages(wrong_shape).length(), 0)
  let partial : Json = { "pages": [{ "slug": "x" }] }
  let pages = @frontend.decode_pages(partial)
  assert_eq(pages.length(), 1)
  assert_eq(pages[0].slug, "x")
  // Everything absent takes the documented fallback.
  assert_eq(pages[0].title, "")
  assert_eq(pages[0].letter, "")
  assert_true(!pages[0].in_navigation)
  assert_eq(pages[0].sort, 0)
}

///|
test "ring node centres are where the mark puts them" {
  // This is the geometry the logo depends on. Asserting the coordinates
  // outright catches a trig error, a wrong radius or a flipped start angle --
  // all of which still draw five evenly spaced dots and merely look wrong.
  let expected = expected_centres()
  assert_eq(expected.length(), 5)
  for i in 0..<5 {
    let (x, y) = @frontend.node_xy(i)
    let (ex, ey) = expected[i]
    assert_eq((x, y), (ex, ey))
  }
}

///|
test "ring nodes lie on the radius of the original mark" {
  for i in 0..<5 {
    let (x, y) = @frontend.node_xy(i)
    // Centre at (100, 100) -- again literal rather than `CX`/`CY`.
    let dx = (x - 100).to_double()
    let dy = (y - 100).to_double()
    let distance = (dx * dx + dy * dy).sqrt()
    // Integer rounding puts each node within a pixel of the ring.
    assert_true((distance - EXPECTED_RING_R).abs() <= 1.0)
  }
}

///|
test "ring percentages scale the svg coordinates into 0..100" {
  // The overlay is positioned in percentages, so a wrong divisor or a missing
  // *100 is invisible in the SVG and shows up as letters sitting off their
  // nodes. Compared against the node's own centre, not merely against the
  // 0..100 range: a value that was already small would still pass a range
  // check with the scale dropped.
  for i in 0..<5 {
    let (x, y) = @frontend.node_xy(i)
    let (left, top) = @frontend.node_percent(i)
    assert_true(left.has_suffix("%"))
    assert_true(top.has_suffix("%"))
    assert_true(
      (percent_of(left) - x.to_double() * 100.0 / VIEW_EDGE).abs() <= 0.5,
    )
    assert_true(
      (percent_of(top) - y.to_double() * 100.0 / VIEW_EDGE).abs() <= 0.5,
    )
  }
  // Node 0 is the top node, so its vertical offset must be above the middle.
  let (_, top0) = @frontend.node_percent(0)
  assert_true(percent_of(top0) < 50.0)
}

///|
test "the ring uses the letters and colours of the original logo" {
  let ring = @frontend.nodes()
  assert_eq(ring.map(fn(n) { n.0 }), ["M", "D", "E", "A", "K"])
  assert_eq(ring.map(fn(n) { n.1 }), [
    "#2c3e9e", "#27ae60", "#e74c3c", "#f1c40f", "#7f8c8d",
  ])
}

///|
test "decode_loop_status reads the backend loop payload" {
  let json : Json = {
    "current_domain": "M",
    "current_title": "Model",
    "current_position": "Standing",
    "current_position_label": "Standing",
    "current_gloss": "The person stands with both feet on the ground...",
    "next_domain": "D",
    "drive_slot": "Co-being",
    "history_length": 0,
    "history": [],
  }
  let status = @frontend.decode_loop_status(json)
  assert_eq(status.current_domain, "M")
  assert_eq(status.current_title, "Model")
  assert_eq(status.current_position, "Standing")
  assert_eq(status.next_domain, "D")
  assert_eq(status.drive_slot, "Co-being")
  assert_eq(status.history_length, 0)
  assert_eq(status.history.length(), 0)
}

///|
test "decode_loop_status reads history events" {
  let json : Json = {
    "current_domain": "D",
    "current_title": "Data",
    "current_position": "Encounter",
    "current_position_label": "Encounter",
    "current_gloss": "Unavoidably, the person encounters the other...",
    "next_domain": "E",
    "drive_slot": "Feedback",
    "history_length": 1,
    "history": [
      {
        "domain": "M",
        "slot": "Co-being",
        "outcome": "No Edge",
        "detail": "No outgoing edge for Co-being at Standing",
        "position": "Standing",
        "position_label": "Standing",
      },
    ],
  }
  let status = @frontend.decode_loop_status(json)
  assert_eq(status.history_length, 1)
  assert_eq(status.history.length(), 1)
  let event = status.history[0]
  assert_eq(event.domain, "M")
  assert_eq(event.slot, "Co-being")
  assert_eq(event.outcome, "No Edge")
  assert_eq(event.position, "Standing")
}

///|
test "decode_loop_status survives malformed payloads" {
  // Empty object should give defaults
  let empty = @frontend.decode_loop_status(Json::empty_object())
  assert_eq(empty.current_domain, "")
  assert_eq(empty.history_length, 0)
  assert_eq(empty.history.length(), 0)
  // Missing history array should give empty array
  let no_history : Json = { "current_domain": "M", "history_length": 5 }
  let status = @frontend.decode_loop_status(no_history)
  assert_eq(status.current_domain, "M")
  assert_eq(status.history_length, 5)
  assert_eq(status.history.length(), 0)
}

///|
/// The shape the backend actually sends, captured from a running server.
///
/// It is pasted here rather than built up field by field so that a change to
/// the backend's `open_slots` encoding fails here instead of silently
/// decoding to an empty list -- which would put every slot back to "no edge
/// here" and look like a model that cannot move.
test "decode_loop_status reads the reasons a step may do nothing" {
  let json : Json = {
    "current_domain": "M",
    "current_position": "Standing",
    "drive_slot": "Action",
    "drive_slot_name": "act",
    "blocked": false,
    "undecided": false,
    "open_slots": [
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Moved",
        "targets": [["Freedom"]],
      },
    ],
    "history_length": 0,
  }
  let status = @frontend.decode_loop_status(json)
  assert_eq(status.drive_slot_name, "act")
  assert_true(!status.blocked)
  assert_true(!status.undecided)
  assert_eq(status.open_slots.length(), 1)
  let open = status.open_slots[0]
  assert_eq(open.name, "act")
  assert_eq(open.outcome, "Moved")
  // `targets` is a list of [from, to] pairs; the reader keeps the destinations.
  assert_eq(open.targets.length(), 1)
  assert_eq(open.targets[0], "Freedom")
}

///|
/// `assert_eq` against `None` would require `OpenSlot: Debug`, which the
/// production type does not derive for a test's convenience. Match instead.
fn absent(v : @frontend.OpenSlot?) -> Bool {
  match v {
    Some(_) => false
    None => true
  }
}

///|
test "a blocked position with no open slots decodes as such" {
  let json : Json = {
    "current_domain": "M",
    "blocked": true,
    "undecided": false,
    "open_slots": [],
  }
  let status = @frontend.decode_loop_status(json)
  assert_true(status.blocked)
  assert_eq(status.open_slots.length(), 0)
  assert_true(absent(@frontend.find_open_slot(status, "act")))
}

///|
test "find_open_slot distinguishes the slots the table offers from those it does not" {
  let json : Json = {
    "open_slots": [
      {
        "name": "cobeing",
        "designation": "Co-being",
        "outcome": "Undecided",
        "targets": [],
      },
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Moved",
        "targets": [["Freedom"]],
      },
    ],
  }
  let status = @frontend.decode_loop_status(json)
  match @frontend.find_open_slot(status, "act") {
    Some(s) => assert_eq(s.outcome, "Moved")
    None => assert_true(false)
  }
  match @frontend.find_open_slot(status, "cobeing") {
    Some(s) => assert_eq(s.outcome, "Undecided")
    None => assert_true(false)
  }
  // A slot with no outgoing edge here must be absent, not defaulted.
  assert_true(absent(@frontend.find_open_slot(status, "hold")))
}

///|
test "decode_slots reads the backend's slot list instead of a hard-coded one" {
  let json : Json = {
    "slots": [
      {
        "name": "occasion",
        "designation": "Occasion",
        "gloss": "a giving not initiated",
      },
      {
        "name": "unveil",
        "designation": "Unveiling",
        "gloss": "unveiling and concealing",
      },
    ],
  }
  let slots = @frontend.decode_slots(json)
  assert_eq(slots.length(), 2)
  assert_eq(slots[0].name, "occasion")
  assert_eq(slots[0].designation, "Occasion")
  assert_eq(slots[1].name, "unveil")
  // The slug is what POST /api/loop/step/:slot takes, so it must survive.
  assert_eq(slots[1].name, "unveil")
}

///|
test "decode_slots survives a payload with no slots array" {
  assert_eq(@frontend.decode_slots(Json::empty_object()).length(), 0)
}

///|
/// The panel is rendered from one response. This is the contract that replaced
/// the three-hop request chain: the loop status and the slot vocabulary arrive
/// in the same payload, so a client never has to fetch the vocabulary first and
/// wait on it before asking for the status.
test "one status payload decodes both the position and the slot vocabulary" {
  let json : Json = {
    "current_domain": "M",
    "current_position": "Standing",
    "blocked": false,
    "undecided": false,
    "open_slots": [
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Moved",
        "targets": [["Freedom"]],
      },
    ],
    "slots": [
      { "name": "act", "designation": "Action", "gloss": "acting" },
      { "name": "hold", "designation": "Holding", "gloss": "holding" },
      { "name": "cobeing", "designation": "Co-being", "gloss": "staying" },
    ],
  }
  let status = @frontend.decode_loop_status(json)
  let slots = @frontend.decode_slots(json)
  assert_eq(status.current_position, "Standing")
  assert_eq(status.open_slots.length(), 1)
  assert_eq(slots.length(), 3)
  // The two decoders are independent views of one payload, so a slot named in
  // `open_slots` has to match the slot of the same name in `slots`.
  let live = @frontend.find_open_slot(status, "act")
  match live {
    Some(open) => assert_eq(open.designation, "Action")
    None => assert_true(false)
  }
  assert_eq(slots[1].name, "hold")
}

///|
fn bare_model() -> @frontend.Model {
  {
    pages: [],
    current: "index",
    loaded: true,
    error: "",
    loop_status: None,
    loop_error: "",
    slots: [],
    research_papers: [],
    research_triggers: [],
    research_error: "",
    causal_result: None,
    causal_error: "",
  }
}

///|
test "Model Eq distinguishes a scalar field change" {
  let m = bare_model()
  assert_true(!Eq::equal(m, { ..m, current: "tutorial", }))
}

///|
test "Model Eq distinguishes Some(status) from None" {
  // rabbita gates every re-render on `Eq::equal(old_model, new_model)`
  // (rabbita/incremental.mbt: create_state_machine -> duplix.recompute). If a
  // changed field compares equal, the whole update is dropped and the view
  // silently keeps showing the previous state -- with no error anywhere.
  let payload : Json = {
    "current_domain": "M",
    "current_position": "Standing",
    "drive_slot": "Action",
    "history_length": 0,
    "history": [],
  }
  let with_status = {
    ..bare_model(),
    loop_status: Some(@frontend.decode_loop_status(payload)),
  }
  assert_true(!Eq::equal(with_status, bare_model()))
}

///|
test "Model Eq distinguishes two different loop statuses" {
  let a : Json = {
    "current_domain": "M",
    "current_position": "Standing",
    "drive_slot": "Action",
    "history_length": 0,
    "history": [],
  }
  let b : Json = {
    "current_domain": "D",
    "current_position": "Encounter",
    "drive_slot": "Co-being",
    "history_length": 1,
    "history": [],
  }
  let ma = {
    ..bare_model(),
    loop_status: Some(@frontend.decode_loop_status(a)),
  }
  let mb = {
    ..bare_model(),
    loop_status: Some(@frontend.decode_loop_status(b)),
  }
  assert_true(!Eq::equal(ma, mb))
  assert_true(Eq::equal(ma, ma))
}
