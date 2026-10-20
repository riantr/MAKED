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
        "outcome": "No-way",
        "detail": "No road from Standing through Co-being",
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
  assert_eq(event.outcome, "No-way")
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
        "outcome_kind": "moved",
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
  assert_eq(open.outcome_kind, "moved")
  // `targets` is a list of one-element lists; the reader keeps the destination.
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
        "outcome_kind": "open",
        "targets": [],
      },
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Moved",
        "outcome_kind": "moved",
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
/// The way out of a position the model declined to decide.
///
/// The slot the model declined at carries the candidates it would have
/// chosen between. The panel turns them into buttons, and the reader picks
/// one. Without this the run is stuck: the slot is there, it says
/// "Undecided", and every click through it lands nowhere.
test "the undecided slot is found, with the candidates it offers" {
  let json : Json = {
    "current_domain": "M",
    "undecided": true,
    "open_slots": [
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Moved",
        "outcome_kind": "moved",
        "targets": [["Freedom"]],
      },
      {
        "name": "occasion",
        "designation": "Situation",
        "outcome": "Undecided",
        "outcome_kind": "open",
        "targets": [["Urgency"], ["Alienation"]],
      },
    ],
  }
  let status = @frontend.decode_loop_status(json)
  match @frontend.find_undecided_slot(status) {
    Some(open) => {
      assert_eq(open.name, "occasion")
      assert_eq(open.designation, "Situation")
      assert_eq(open.outcome, "Undecided")
      assert_eq(open.outcome_kind, "open")
      assert_eq(open.targets.length(), 2)
      assert_eq(open.targets[0], "Urgency")
      assert_eq(open.targets[1], "Alienation")
    }
    None => assert_true(false)
  }
}

///|
/// The way out is found by the outcome's *kind*, not by the word "Undecided".
///
/// The label is the part a model file is meant to be able to change, so a
/// client that matches on the label stops working the day somebody renames
/// a model. The kind is the part that means "the model would not choose".
///
/// Both directions are checked, because either one alone would pass: a
/// renamed label must still be found, and a slot that merely happens to be
/// called "Undecided" must not be mistaken for a way out.
test "the way out is found by the outcome's kind, not by its label" {
  // The label says something else entirely, and the kind says "open": it is
  // still the way out.
  let renamed : Json = {
    "open_slots": [
      {
        "name": "occasion",
        "designation": "Situation",
        "outcome": "The model is thinking",
        "outcome_kind": "open",
        "targets": [["Urgency"], ["Alienation"]],
      },
    ],
  }
  let status = @frontend.decode_loop_status(renamed)
  match @frontend.find_undecided_slot(status) {
    Some(open) => assert_eq(open.name, "occasion")
    None => assert_true(false)
  }
  // The label says "Undecided" and the kind says it is an ordinary move: it
  // is not a way out, and offering it as one would send the reader down a
  // road the model never offered.
  let mislabelled : Json = {
    "open_slots": [
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Undecided",
        "outcome_kind": "moved",
        "targets": [["Freedom"]],
      },
    ],
  }
  let other = @frontend.decode_loop_status(mislabelled)
  assert_true(absent(@frontend.find_undecided_slot(other)))
}

///|
/// A position the table did decide about has no way out to offer, and the
/// panel must not show one.
test "a decided position offers no way out" {
  let json : Json = {
    "current_domain": "M",
    "undecided": false,
    "open_slots": [
      {
        "name": "act",
        "designation": "Action",
        "outcome": "Moved",
        "targets": [["Freedom"]],
      },
    ],
  }
  let status = @frontend.decode_loop_status(json)
  assert_true(absent(@frontend.find_undecided_slot(status)))
}

///|
test "decode_slots reads the backend's slot list instead of a hard-coded one" {
  let json : Json = {
    "slots": [
      {
        "name": "occasion",
        "designation": "Situation",
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
  assert_eq(slots[0].designation, "Situation")
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
    research_documents: [],
    research_triggers: [],
    research_error: "",
    research_corpus: None,
    research_notice: "",
    research_config: None,
    research_config_path: "",
    research_config_text: "",
    research_config_error: "",
    research_config_notice: "",
    causal_result: None,
    causal_error: "",
    entries: [],
    entry_domains: ["M", "D", "E", "A", "K"],
    draft_domain: "",
    draft_title: "",
    draft_body: "",
    workspace_error: "",
    workspace_notice: "",
    sessions: [],
    active_session: @frontend.empty_session(),
    session_path: [],
    session_others: [],
    session_summary: "",
    session_metrics: @frontend.empty_metric_report(),
    session_error: "",
    session_notice: "",
    session_name_draft: "",
    session_rename_draft: "",
    session_delete_pending: 0,
  }
}

///|
test "Model Eq distinguishes the workspace fields" {
  // rabbita drops an update whose new model compares equal to the old one
  // (see the note on the Some/None test below). A workspace field that
  // compared equal would be a field the screen silently refuses to show.
  let m = bare_model()
  assert_true(!Eq::equal(m, { ..m, draft_title: "a model", }))
  assert_true(!Eq::equal(m, { ..m, draft_body: "what happened", }))
  assert_true(!Eq::equal(m, { ..m, draft_domain: "M", }))
  assert_true(!Eq::equal(m, { ..m, workspace_error: "refused", }))
  assert_true(!Eq::equal(m, { ..m, workspace_notice: "saved", }))
  assert_true(!Eq::equal(m, { ..m, entry_domains: ["M"], }))
}

///|
test "Model Eq distinguishes one entry from none" {
  // The entry list is the other half of the workspace: if adding a record
  // compared equal to an empty list, the save would land on the server and
  // never reach the screen.
  let m = bare_model()
  let entry : @frontend.Entry = {
    id: 1,
    domain: "M",
    title: "a model",
    body: "",
    created_at: "2026-10-19 00:00:00",
  }
  assert_true(!Eq::equal(m, { ..m, entries: [entry], }))
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

///|
test "decode_entries reads the list the backend sends" {
  // The id is a string here because the backend holds it as an `Int64` and
  // MoonBit encodes an `Int64` as a string. Decoding this as a number would
  // give every record the id 0, and every Delete button would then ask the
  // server to remove record 0.
  let json : Json = {
    "entries": [
      {
        "id": "1",
        "domain": "M",
        "title": "a model",
        "body": "what it does",
        "created_at": "2026-10-19 09:00:00",
      },
      {
        "id": "2",
        "domain": "K",
        "title": "a dataset",
        "body": "",
        "created_at": "2026-10-19 09:01:00",
      },
    ],
  }
  let entries = @frontend.decode_entries(json)
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].id, 1)
  assert_eq(entries[0].domain, "M")
  assert_eq(entries[0].title, "a model")
  assert_eq(entries[0].body, "what it does")
  assert_eq(entries[1].id, 2)
  assert_eq(entries[1].domain, "K")
  assert_eq(entries[1].body, "")
}

///|
test "decode_entries accepts a numeric id as well" {
  // The rest of the JSON in this project uses plain numbers, so both
  // spellings have to decode to the same id.
  let json : Json = {
    "entries": [{ "id": 7, "domain": "M", "title": "a model", "body": "" }],
  }
  assert_eq(@frontend.decode_entries(json)[0].id, 7)
}

///|
test "decode_entries on a payload with no entries is empty, not a crash" {
  // A malformed row must not take the whole workspace down: one bad record
  // should cost that record, not the screen.
  let json : Json = { "entries": [] }
  assert_eq(@frontend.decode_entries(json).length(), 0)
  assert_eq(@frontend.decode_entries({ "pages": [] }).length(), 0)
}

///|
test "decode_created_entry finds the entry the server stored" {
  let json : Json = {
    "entry": {
      "id": "7",
      "domain": "E",
      "title": "a failure",
      "body": "it did not work",
      "created_at": "2026-10-19 09:02:00",
    },
  }
  match @frontend.decode_created_entry(json) {
    Some(entry) => {
      assert_eq(entry.id, 7)
      assert_eq(entry.domain, "E")
      assert_eq(entry.title, "a failure")
    }
    None => assert_true(false)
  }
}

///|
test "decode_created_entry on a refusal is None, not a fake entry" {
  // The refusal body has no "entry" key. Decoding it as an entry would put an
  // empty record on the screen and hide the reason.
  let json : Json = {
    "error": "invalid_entry",
    "reason": "title must not be empty",
  }
  match @frontend.decode_created_entry(json) {
    Some(_) => assert_true(false)
    None => assert_true(true)
  }
}

///|
test "decode_error_reason prefers the reason over the error code" {
  // The status code never reaches the client, so the body is the only place a
  // reason can come from. A refusal that showed "invalid_entry" instead of
  // the sentence would be no better than a silent one.
  let json : Json = {
    "error": "invalid_entry",
    "reason": "title must not be empty",
  }
  assert_eq(@frontend.decode_error_reason(json), "title must not be empty")
  assert_eq(
    @frontend.decode_error_reason({ "error": "not_found" }),
    "not_found",
  )
  assert_eq(@frontend.decode_error_reason({}), "")
}

///|
test "decode_entry_domains takes the ring from the server" {
  let json : Json = { "entry_domains": ["M", "D", "E", "A", "K"] }
  let letters = @frontend.decode_entry_domains(json)
  assert_eq(letters.length(), 5)
  assert_eq(letters[0], "M")
  assert_eq(letters[4], "K")
}

///|
test "decode_entry_domains falls back to the five ring letters" {
  // The server is the source of the vocabulary, but a payload that arrives
  // without it must not leave the workspace with no domains to choose from.
  let letters = @frontend.decode_entry_domains({})
  assert_eq(letters.length(), 5)
  assert_eq(letters[0], "M")
  assert_eq(@frontend.decode_entry_domains({ "entry_domains": [] }).length(), 5)
}

///|
test "draft_problem names the thing that is missing" {
  let domains = ["M", "D", "E", "A", "K"]
  assert_eq(
    @frontend.draft_problem(domains, "", "a title"),
    "choose a domain first",
  )
  assert_eq(
    @frontend.draft_problem(domains, "Z", "a title"),
    "the domain must be one of M, D, E, A, K",
  )
  assert_eq(@frontend.draft_problem(domains, "M", ""), "give the entry a title")
  assert_eq(
    @frontend.draft_problem(domains, "M", "   "),
    "give the entry a title",
  )
  assert_eq(@frontend.draft_problem(domains, "M", "a title"), "")
}

///|
/// An emitter that drops every message.
///
/// `Emit` is a tuple struct with a public field, so a test can build one. The
/// tests below only care about the model the update returns, so what happens
/// to the message afterwards does not matter.
fn silent_emit() -> @cmd.Emit[@frontend.Msg] {
  @cmd.Emit(fn(_msg) { @cmd.none })
}

///|
/// A stand-in for a failed request.
///
/// `Error` is the builtin error type and every suberror is a value of it, so
/// a suberror is how a test produces the `Err` half of a `Result`.
priv suberror TestError {
  TestError(String)
}

///|
test "update on a domain click records the chosen domain" {
  // The workspace has five buttons and they all funnel into one message. If
  // this arm does not run, the save has no domain to send and the server
  // refuses it -- with no error shown, because the refusal is a silent
  // nothing from the button's point of view.
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::DraftDomainClicked("M"),
    silent_emit(),
  )
  assert_eq(model.draft_domain, "M")
}

///|
test "update on a title change records the typed text" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::DraftTitleChanged("the model I actually use"),
    silent_emit(),
  )
  assert_eq(model.draft_title, "the model I actually use")
}

///|
test "update on a body change records the typed text" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::DraftBodyChanged("linear fit on 200 rows"),
    silent_emit(),
  )
  assert_eq(model.draft_body, "linear fit on 200 rows")
}

///|
test "update on a save with no domain says so instead of saving nothing" {
  // The whole point of the workspace: a save that cannot happen must say
  // why. A silent no-op here is the failure this project exists to remove.
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::DraftSubmitClicked,
    silent_emit(),
  )
  assert_eq(model.workspace_error, "choose a domain first")
  assert_eq(model.workspace_notice, "")
}

///|
test "update on a save with no title says so instead of saving nothing" {
  let (model, _) = @frontend.update(
    { ..bare_model(), draft_domain: "M", },
    @frontend.Msg::DraftSubmitClicked,
    silent_emit(),
  )
  assert_eq(model.workspace_error, "give the entry a title")
}

///|
test "update on a valid save says it is saving" {
  // A valid draft reaches the request. The notice is what the panel shows
  // while the request is in flight, and it is replaced by the confirmation
  // when the answer comes back.
  let (model, _) = @frontend.update(
    { ..bare_model(), draft_domain: "M", draft_title: "a model", },
    @frontend.Msg::DraftSubmitClicked,
    silent_emit(),
  )
  assert_eq(model.workspace_error, "")
  assert_eq(model.workspace_notice, "Saving…")
}

///|
test "update on a created entry puts it at the top and clears the draft" {
  let json : Json = {
    "entry": {
      "id": "7",
      "domain": "M",
      "title": "a model",
      "body": "what it does",
      "created_at": "2026-10-19 09:02:00",
    },
  }
  let (model, _) = @frontend.update(
    { ..bare_model(), draft_domain: "M", draft_title: "a model", },
    @frontend.Msg::EntryCreated(Ok(json)),
    silent_emit(),
  )
  assert_eq(model.entries.length(), 1)
  assert_eq(model.entries[0].id, 7)
  assert_eq(model.entries[0].title, "a model")
  assert_eq(model.draft_title, "")
  assert_eq(model.draft_body, "")
  assert_eq(model.workspace_error, "")
  assert_true(model.workspace_notice.contains("a model"))
}

///|
test "update on a refused entry shows the reason the server gave" {
  // The status code never reaches the client, so the body is the only place a
  // reason can come from. If this arm shows "invalid_entry" instead of the
  // sentence, the user is left with a code rather than an explanation.
  let json : Json = {
    "error": "invalid_entry",
    "reason": "title must not be empty",
  }
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::EntryCreated(Ok(json)),
    silent_emit(),
  )
  assert_eq(model.workspace_error, "title must not be empty")
  assert_eq(model.entries.length(), 0)
}

///|
test "update on an unreachable server says so" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::EntryCreated(Err(TestError("network down"))),
    silent_emit(),
  )
  assert_eq(model.workspace_error, "could not reach the server")
  assert_eq(model.workspace_notice, "")
}

///|
test "update on a deleted entry removes it from the list" {
  let entry : @frontend.Entry = {
    id: 7,
    domain: "M",
    title: "a model",
    body: "",
    created_at: "2026-10-19 09:02:00",
  }
  let (model, _) = @frontend.update(
    { ..bare_model(), entries: [entry], },
    @frontend.Msg::EntryDeleted(Ok({ "deleted": 7 })),
    silent_emit(),
  )
  assert_eq(model.entries.length(), 0)
  assert_eq(model.workspace_error, "")
}

///|
/// A session payload, shaped like the one the server sends.
///
/// The ids are deliberately in both spellings the wire uses: a session id
/// arrives as a *string* because the backend holds it as an `Int64`, and the
/// step counts arrive as numbers. A decoder that read only one of them would
/// report zero sessions or zero steps, and the page would look empty rather
/// than wrong.
fn session_payload() -> Json {
  {
    "sessions": [
      {
        "id": "1",
        "name": "First exploration",
        "parent_id": "0",
        "forked_step_id": "0",
        "head_step_id": "2",
        "start_cursor": "M",
        "mode": "structured",
        "created_at": "2026-10-19T18:27:45Z",
        "updated_at": "2026-10-19T18:28:00Z",
        "steps": 2,
        "total_steps": 3,
        "active": true,
      },
    ],
    "active_session_id": 1,
    "session": {
      "id": "1",
      "name": "First exploration",
      "parent_id": "0",
      "forked_step_id": "0",
      "head_step_id": "2",
      "start_cursor": "M",
      "mode": "structured",
      "created_at": "2026-10-19T18:27:45Z",
      "updated_at": "2026-10-19T18:28:00Z",
    },
    "path": [
      {
        "id": "1",
        "index": 1,
        "domain": "M",
        "domain_title": "Model",
        "slot": "act",
        "slot_designation": "Action",
        "outcome": "Moved",
        "detail": "Standing -> Freedom",
        "position_before": "Standing",
        "position_after": "Freedom",
        "cursor_after": "D",
        "group_state": "Converging",
        "source": "drive",
        "why": "1 of the 8 slots had an outgoing edge here",
        "narration": "The model formulator moved from Standing to Freedom through Action. Action was the slot the table drives with here, and the cursor advanced to the data turbine.",
        "available": [["act"]],
        "blocked": [["hold"], ["unveil"]],
        "created_at": "2026-10-19T18:27:45Z",
      },
    ],
    "other_steps": [
      {
        "id": "3",
        "index": 2,
        "domain": "D",
        "domain_title": "Data",
        "slot": "hold",
        "slot_designation": "Holding",
        "outcome": "No-way",
        "detail": "No road from Encounter through Holding",
        "position_before": "Encounter",
        "position_after": "Encounter",
        "cursor_after": "D",
        "group_state": "Converging",
        "source": "explicit",
        "why": "no slot had an outgoing edge here",
        "narration": "Nothing could move the data turbine at Encounter through Holding: that slot has no road out of there. The cursor stayed on the data turbine.",
        "available": [],
        "blocked": [["hold"], ["unveil"]],
        "created_at": "2026-10-19T18:28:00Z",
      },
    ],
    "summary": "The last step was in the model formulator. It moved a position. The group is Converging.",
    "metrics": {
      "window": 5,
      "window_steps": 2,
      "metrics": [
        {
          "key": "new_ground",
          "label": "New ground",
          "value": 2,
          "of": 2,
          "sentence": "2 of the last 2 steps reached a position the run had not been on before.",
        },
        {
          "key": "settling",
          "label": "Settling",
          "value": 0,
          "of": 0,
          "sentence": "The last step reached a position the run had not been on before, so the run is still finding new ground.",
        },
      ],
      "comparison": "The run has 2 steps, so its beginning and its end cannot be compared yet: the comparison needs 10.",
    },
  }
}

///|
test "a step decodes the sentence the backend wrote for it" {
  // The sentence says what the step did, in a reader's words. It is written
  // by the server for the same reason the "why" is: a second copy of that
  // rule in the client would be a second thing to keep in step with the
  // first, and the two would eventually disagree.
  let state = @frontend.decode_session_state(session_payload())
  let step = state.path[0]
  assert_true(step.narration.contains("moved from Standing to Freedom"))
  assert_true(step.narration.contains("the data turbine"))
  // The step off the path carries its own sentence: it is a step that was
  // really taken, and a reader of the branches should be able to read it.
  assert_true(state.other_steps[0].narration.contains("Nothing could move"))
}

///|
test "the session state decodes the summary of the run" {
  let state = @frontend.decode_session_state(session_payload())
  assert_true(
    state.summary.contains("The last step was in the model formulator."),
  )
  assert_true(state.summary.contains("The group is Converging."))
}

///|
test "a state without a summary decodes to an empty one" {
  // A missing field is not a reason to fail: the panel leaves the line out
  // rather than printing something it does not know.
  let empty = @frontend.decode_session_state(Json::empty_object())
  assert_eq(empty.summary, "")
}

///|
test "the session state decodes the measures of the run" {
  // The number and the reading arrive together, and the client shows both
  // without deriving either. A client that worked out its own idea of "new
  // ground" would be measuring something slightly different from the one
  // the server is reporting.
  let state = @frontend.decode_session_state(session_payload())
  assert_eq(state.metrics.metrics.length(), 2)
  assert_eq(state.metrics.window, 5)
  assert_eq(state.metrics.window_steps, 2)
  let ground = state.metrics.metrics[0]
  assert_eq(ground.key, "new_ground")
  assert_eq(ground.label, "New ground")
  assert_eq(ground.value, 2)
  assert_eq(ground.of, 2)
  assert_true(
    ground.sentence.contains("reached a position the run had not been on"),
  )
  // And the comparison between the run's beginning and its end.
  assert_true(state.metrics.comparison.contains("cannot be compared yet"))
}

///|
test "a state without measures decodes to an empty report" {
  // The measures are an addition to the session state, and an addition that
  // is missing must not be able to break the state that was there.
  let empty = @frontend.decode_session_state(Json::empty_object())
  assert_eq(empty.metrics.metrics.length(), 0)
  assert_eq(empty.metrics.comparison, "")
}

///|
test "a step response carries the session state, and the model takes it" {
  // A step response is the loop status with the session state folded in.
  // Without it the panel's step count stopped moving after the first click,
  // because the count it showed was the one from start-up.
  let response : Json = {
    "current_domain": "D",
    "history_length": 3,
    "session_state": session_payload(),
  }
  let state = @frontend.session_state_of(response)
  match state {
    Some(value) => {
      assert_eq(value.path.length(), 1)
      assert_true(value.summary.contains("The last step was in the model"))
    }
    None => fail("the step response should carry the session state")
  }
  // A response without one leaves the model alone: a missing field must not
  // be able to erase the sessions a person has.
  let bare : Json = { "current_domain": "D" }
  assert_true(@frontend.session_state_of(bare) is None)
}

///|
test "the session state decodes the list, the active session and the path" {
  let state = @frontend.decode_session_state(session_payload())
  assert_eq(state.sessions.length(), 1)
  assert_eq(state.sessions[0].name, "First exploration")
  assert_eq(state.sessions[0].id, 1)
  assert_eq(state.sessions[0].steps, 2)
  assert_eq(state.sessions[0].total_steps, 3)
  assert_true(state.sessions[0].active)
  assert_eq(state.active_session_id, 1)
  assert_eq(state.session.name, "First exploration")
  assert_eq(state.path.length(), 1)
  assert_eq(state.other_steps.length(), 1)
}

///|
test "a step decodes the reason the backend wrote for it" {
  // The "why" is written by the server, on purpose: a second copy of that
  // rule in the client would be a second thing to keep in step with the
  // first, and the two would eventually disagree.
  let state = @frontend.decode_session_state(session_payload())
  let step = state.path[0]
  assert_eq(step.why, "1 of the 8 slots had an outgoing edge here")
  assert_eq(step.domain, "M")
  assert_eq(step.slot_designation, "Action")
  assert_eq(step.outcome, "Moved")
  assert_eq(step.position_before, "Standing")
  assert_eq(step.position_after, "Freedom")
  assert_eq(step.source, "drive")
}

///|
test "the slot lists are unwrapped from the one-element arrays" {
  // The backend sends a list of strings as a list of one-element arrays,
  // because that is the shape MoonBit's `Json` builder accepts. A decoder
  // that forgot the unwrapping would show "[[act]]" where "[act]" belongs.
  let state = @frontend.decode_session_state(session_payload())
  assert_eq(state.path[0].available, ["act"])
  assert_eq(state.path[0].blocked, ["hold", "unveil"])
  // An empty list is an empty list, not one empty piece.
  assert_eq(state.other_steps[0].available.length(), 0)
}

///|
test "the session state survives a malformed payload without raising" {
  let empty = @frontend.decode_session_state(Json::empty_object())
  assert_eq(empty.sessions.length(), 0)
  assert_eq(empty.path.length(), 0)
  assert_eq(empty.session.name, "")
  let wrong_shape : Json = { "sessions": "not-an-array", "path": 7 }
  let state = @frontend.decode_session_state(wrong_shape)
  assert_eq(state.sessions.length(), 0)
  assert_eq(state.path.length(), 0)
}

///|
test "a refused session request is recognised and explained" {
  // The HTTP status never reaches the client, so the body is the only place
  // a refusal can be seen. Without this the page would show a refusal as
  // though it were a success.
  let refusal : Json = {
    "error": "invalid_name",
    "reason": "give the session a name",
  }
  assert_true(@frontend.session_refused(refusal))
  assert_eq(
    @frontend.session_refusal_reason(refusal),
    "give the session a name",
  )
  assert_true(!@frontend.session_refused(session_payload()))
}

///|
test "a branch is named after the session it came from" {
  assert_eq(
    @frontend.branch_name("First exploration"),
    "First exploration (branch)",
  )
  // A session with no name still gets a name a person can find it by.
  assert_eq(@frontend.branch_name(""), "Branch")
  assert_eq(@frontend.branch_name("   "), "Branch")
}

///|
test "update on a new session with no name says so instead of posting nothing" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::NewSessionClicked,
    silent_emit(),
  )
  assert_eq(model.session_error, "give the session a name")
  assert_eq(model.session_notice, "")
}

///|
test "update on a new session takes the typed name" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::SessionNameChanged("the run that failed"),
    silent_emit(),
  )
  assert_eq(model.session_name_draft, "the run that failed")
}

///|
test "update on a created session puts the new timeline in the model" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::SessionCreated(Ok(session_payload())),
    silent_emit(),
  )
  assert_eq(model.sessions.length(), 1)
  assert_eq(model.active_session.name, "First exploration")
  assert_eq(model.session_path.length(), 1)
  assert_eq(model.session_others.length(), 1)
  assert_eq(model.session_error, "")
  assert_true(model.session_notice != "")
}

///|
test "update on a refused session request shows the reason" {
  let refusal : Json = { "error": "not_on_path", "step": 9 }
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::SessionReplayed(Ok(refusal)),
    silent_emit(),
  )
  assert_eq(model.session_error, "not_on_path")
  assert_eq(model.session_notice, "")
}

///|
test "update on an unreachable session server says so" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::SessionBranched(Err(TestError("boom"))),
    silent_emit(),
  )
  assert_eq(model.session_error, "could not reach the server")
  assert_eq(model.session_notice, "")
}

///|
test "a delete takes two presses, and the first says so" {
  // A history is worth more than the click that deletes it.
  let (armed, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::DeleteSessionClicked(4),
    silent_emit(),
  )
  assert_eq(armed.session_delete_pending, 4)
  assert_true(armed.session_notice.contains("again"))
  // A delete of a different session arms that one instead.
  let (other, _) = @frontend.update(
    armed,
    @frontend.Msg::DeleteSessionClicked(5),
    silent_emit(),
  )
  assert_eq(other.session_delete_pending, 5)
}

///|
test "the session fields are distinguished by the model's equality" {
  // rabbita drops an update whose new model compares equal to the old one
  // (see the note on the Some/None test below). A session field that
  // compared equal would be a field the screen silently refuses to show.
  let m = bare_model()
  assert_true(!Eq::equal(m, { ..m, session_name_draft: "a name", }))
  assert_true(!Eq::equal(m, { ..m, session_notice: "something happened", }))
  assert_true(!Eq::equal(m, { ..m, session_error: "something went wrong", }))
  assert_true(!Eq::equal(m, { ..m, session_rename_draft: "another name", }))
  assert_true(!Eq::equal(m, { ..m, session_delete_pending: 3, }))
}

///|
test "the bootstrap's nested session state is found and decoded" {
  // The bootstrap carries the session state under `session_state`, not at the
  // top level. Decoding the wrong level does not fail -- it yields an empty
  // list, and the page says "No sessions yet" while the server has one.
  let bootstrap : Json = {
    "pages": [],
    "entries": [],
    "entry_domains": ["M", "D", "E", "A", "K"],
    "session_state": session_payload(),
  }
  let state = @frontend.decode_bootstrap_session_state(bootstrap)
  assert_eq(state.sessions.length(), 1)
  assert_eq(state.session.name, "First exploration")
  assert_eq(state.path.length(), 1)
  assert_eq(state.other_steps.length(), 1)
  // A bootstrap without one decodes to nothing rather than raising.
  let empty = @frontend.decode_bootstrap_session_state(Json::empty_object())
  assert_eq(empty.sessions.length(), 0)
  assert_eq(empty.path.length(), 0)
}

///|
/// An emitter that keeps the messages the view hands it.
///
/// The view builds a button by calling the emitter with the message that
/// button carries, so what comes out of here is exactly what a click would
/// send. It is the only way to check a button from a test: the browser
/// cannot be driven from here, and a button that renders the right words and
/// sends the wrong thing is the failure worth catching.
fn capturing_emit(seen : Array[@frontend.Msg]) -> @cmd.Emit[@frontend.Msg] {
  @cmd.Emit(fn(msg) {
    seen.push(msg)
    @cmd.none
  })
}

///|
/// The loop status at a position the table declined to decide.
///
/// Two candidates, offered through the slot whose edge the table left open.
fn undecided_status() -> Json {
  {
    "current_domain": "M",
    "current_title": "Model formulator",
    "current_position": "Freedom",
    "current_position_label": "Freedom",
    "current_gloss": "The model formulator is free.",
    "next_domain": "D",
    "drive_slot": "Situation",
    "drive_slot_name": "occasion",
    "blocked": false,
    "undecided": true,
    "open_slots": [
      {
        "name": "occasion",
        "designation": "Situation",
        "outcome": "Undecided",
        "outcome_kind": "open",
        "targets": [["Urgency"], ["Alienation"]],
      },
    ],
    "history_length": 6,
  }
}

///|
/// The way out is only a way out if the click carries the candidate.
///
/// The button is drawn from the table's own candidates, and the click has to
/// carry the one the reader picked. A button that renders the right words
/// and sends an empty target is a dead button with a confident look.
test "the way out sends the candidate the table offered" {
  let seen : Array[@frontend.Msg] = []
  let status = @frontend.decode_loop_status(undecided_status())
  let model = { ..bare_model(), loop_status: Some(status), }
  let _ = @frontend.loop_view(capturing_emit(seen), model)
  let choices : Array[(String, String)] = []
  for msg in seen {
    match msg {
      @frontend.Msg::TargetStepClicked(slot, target) =>
        choices.push((slot, target))
      _ => ()
    }
  }
  assert_eq(choices.length(), 2)
  assert_eq(choices[0].0, "occasion")
  assert_eq(choices[0].1, "Urgency")
  assert_eq(choices[1].0, "occasion")
  assert_eq(choices[1].1, "Alienation")
}

///|
/// The click has to become a request to the step endpoint.
///
/// The command the update returns is the request itself, and the endpoint it
/// will be sent to can be read back out of it. The endpoint is the one thing
/// the server sees first: a request to the wrong path is a request the
/// server answers with "not found" and no reason.
test "the choice reaches the server as a request to the step endpoint" {
  let (_, cmd) = @frontend.update(
    bare_model(),
    @frontend.Msg::TargetStepClicked("occasion", "Urgency"),
    silent_emit(),
  )
  let request = cmd.to_repr().to_string()
  assert_true(request.contains("/api/loop/step/occasion"))
}

///|
/// The request has to name the successor the reader picked.
///
/// The server reads the successor out of one field, and refuses a request
/// that does not carry it -- naming the ones it does accept, so the reader
/// can see what went wrong. A body that leaves the field out is therefore a
/// dead button with a 400 behind it, and the field is the whole message.
test "the request names the successor the reader picked" {
  let (path, body) = @frontend.target_step_request("occasion", "Urgency")
  assert_eq(path, "/api/loop/step/occasion")
  assert_eq(@frontend.get_string(body, "target", ""), "Urgency")
}

///|
/// A candidate list that holds more than one name still offers the destination.
///
/// The backend sends one name per list, because a bare `Array[String]` does
/// not spread into `Json`. A list that ever holds a pair holds the position
/// the run came from first, and offering that as a way out of it would send
/// the reader back where they already were.
test "a candidate list that holds a pair still offers the destination" {
  let json : Json = {
    "open_slots": [
      {
        "name": "occasion",
        "designation": "Situation",
        "outcome": "Undecided",
        "outcome_kind": "open",
        "targets": [["Freedom", "Urgency"]],
      },
    ],
  }
  let status = @frontend.decode_loop_status(json)
  assert_eq(status.open_slots[0].targets.length(), 1)
  assert_eq(status.open_slots[0].targets[0], "Urgency")
}

///|
/// A mapping table, shaped like the one the server sends.
fn config_payload() -> Json {
  {
    "config": {
      "format": "maked.research.v1",
      "mapping": [
        {
          "keywords": ["reproduce", "replication"],
          "label": "A reproduction",
          "notes": "",
          "slot": "hold",
        },
      ],
      "fallback": { "label": "Anything else", "slot": "act" },
    },
    "path": "research/table.yaml",
    "writable": true,
  }
}

///|
/// The table the reader edits is the table the server is running.
///
/// The editor starts from what is in force rather than from a blank box: a
/// reader who opens the panel to change one rule should not have to retype
/// the other four to find out what they are.
test "the table the reader edits is the table the server is running" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchConfigLoaded(Ok(config_payload())),
    silent_emit(),
  )
  assert_true(model.research_config_text.contains("A reproduction"))
  assert_true(model.research_config_text.contains("replication"))
  assert_eq(model.research_config_path, "research/table.yaml")
  assert_eq(model.research_config_error, "")
}

///|
/// The typed text is the text the reader typed.
test "update on a table edit records the typed text" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchConfigTextChanged("{\"mapping\": []}"),
    silent_emit(),
  )
  assert_eq(model.research_config_text, "{\"mapping\": []}")
}

///|
/// A table that is not JSON is refused before it is sent.
///
/// The refusal has to say so: a save that cannot happen and says nothing
/// is the failure this project exists to remove.
test "a table that is not JSON is refused before it is sent" {
  let (model, cmd) = @frontend.update(
    { ..bare_model(), research_config_text: "not json at all", },
    @frontend.Msg::ResearchConfigSaveClicked,
    silent_emit(),
  )
  assert_true(model.research_config_error.contains("not JSON"))
  assert_eq(model.research_config_notice, "")
  // Nothing is sent: the request would have carried a table that is not one.
  assert_true(!cmd.to_repr().to_string().contains("/api/research/config"))
}

///|
/// The table reaches the server as a request to the config endpoint.
///
/// The verb matters as much as the path: a table that is *replaced* is
/// put, and the server's route is a PUT. A POST to the same path would be
/// answered with "not found" and no reason.
test "the table reaches the server as a request to the config endpoint" {
  let (_, cmd) = @frontend.update(
    {
      ..bare_model(),
      research_config_text: "{\"format\": \"maked.research.v1\"}",
    },
    @frontend.Msg::ResearchConfigSaveClicked,
    silent_emit(),
  )
  let request = cmd.to_repr().to_string()
  assert_true(request.contains("/api/research/config"))
  assert_true(request.contains("Put"))
}

///|
/// The table is fetched from the server when the reader asks to see it.
test "the table is fetched from the server when the reader asks to see it" {
  let (_, cmd) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchConfigEditClicked,
    silent_emit(),
  )
  let request = cmd.to_repr().to_string()
  assert_true(request.contains("/api/research/config"))
  assert_true(request.contains("Get"))
}

///|
/// A refused table shows the reason the server gave.
///
/// The reason is the whole of the answer: "your table is wrong" is not
/// something a reader can act on, and "rule 0 names the slot \"ship\",
/// which this model does not have" is.
test "a refused table shows the reason the server gave" {
  let json : Json = {
    "error": "invalid_config",
    "reason": "rule 0 names the slot \"ship\", which this model does not have",
  }
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchConfigSaved(Ok(json)),
    silent_emit(),
  )
  assert_true(model.research_config_error.contains("ship"))
  assert_eq(model.research_config_notice, "")
}

///|
/// A saved table says what the server said about it.
test "a saved table says what the server said about it" {
  let json : Json = {
    "config": {
      "format": "maked.research.v1",
      "mapping": [],
      "fallback": { "label": "Anything else", "slot": "act" },
    },
    "path": "research/table.yaml",
    "saved": true,
    "notice": "The table is running, and it was written back to research/table.yaml.",
  }
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchConfigSaved(Ok(json)),
    silent_emit(),
  )
  assert_eq(model.research_config_error, "")
  assert_true(model.research_config_notice.contains("research/table.yaml"))
}

///|
/// The panel's button is the save the reader expects.
test "the mapping table panel sends the save click" {
  let seen : Array[@frontend.Msg] = []
  let model = { ..bare_model(), research_config_text: "{}", }
  let _ = @frontend.research_config_view(capturing_emit(seen), model)
  let mut saves = 0
  for msg in seen {
    match msg {
      @frontend.Msg::ResearchConfigSaveClicked => saves += 1
      _ => ()
    }
  }
  assert_eq(saves, 1)
}

///|
/// The panel's other button fetches the table.
test "the mapping table panel sends the fetch click" {
  let seen : Array[@frontend.Msg] = []
  let _ = @frontend.research_config_view(capturing_emit(seen), bare_model())
  let mut fetches = 0
  for msg in seen {
    match msg {
      @frontend.Msg::ResearchConfigEditClicked => fetches += 1
      _ => ()
    }
  }
  assert_eq(fetches, 1)
}

///|
/// A corpus, shaped like the one the server sends.
fn corpus_payload() -> Json {
  {
    "documents": [
      {
        "id": "notes/launch.md",
        "title": "What we learned",
        "summary": "We fail at scale.",
        "authors": [],
        "categories": [],
        "published": "",
        "link": "",
      },
    ],
    "triggers": [
      {
        "document_id": "notes/launch.md",
        "rule": "A reported failure",
        "slot": "Feedback",
      },
    ],
    "count": 1,
    "corpus": {
      "kind": "local",
      "source": "local: ./notes",
      "path": "corpus.yaml",
      "max_results": 20,
    },
    "notice": "",
  }
}

///|
/// The documents the server sent are the documents the panel holds.
///
/// The corpus is the reader's own documents now, and a document that is
/// called something else in the panel than in the answer is a document the
/// reader cannot match up with what they put in.
test "the documents the server sent are the documents the panel holds" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchLoaded(Ok(corpus_payload())),
    silent_emit(),
  )
  assert_eq(model.research_documents.length(), 1)
  assert_eq(model.research_triggers.length(), 1)
  let title = @frontend.get_string(model.research_documents[0], "title", "")
  assert_eq(title, "What we learned")
}

///|
/// The panel says which corpus it is reading.
///
/// An empty panel means one thing for arxiv and another for a folder of
/// the reader's own notes, so the reader has to be able to see which one
/// they are looking at.
test "the panel says which corpus it is reading" {
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchLoaded(Ok(corpus_payload())),
    silent_emit(),
  )
  match model.research_corpus {
    Some(corpus) =>
      assert_true(
        @frontend.get_string(corpus, "source", "").contains("./notes"),
      )
    None => fail("the corpus was not kept")
  }
}

///|
/// An empty corpus says so, rather than showing nothing.
test "an empty corpus says so rather than showing nothing" {
  let json : Json = {
    "documents": [],
    "triggers": [],
    "count": 0,
    "corpus": { "kind": "local", "source": "local: ./notes" },
    "notice": "The corpus (local: ./notes) held no documents.",
  }
  let (model, _) = @frontend.update(
    bare_model(),
    @frontend.Msg::ResearchLoaded(Ok(json)),
    silent_emit(),
  )
  assert_true(model.research_notice.contains("held no documents"))
  assert_eq(model.research_documents.length(), 0)
}

///|
/// The read button asks the server for the documents.
test "the read button asks the server for the documents" {
  let (_, cmd) = @frontend.update(
    bare_model(),
    @frontend.Msg::ReadCorpusClicked,
    silent_emit(),
  )
  let request = cmd.to_repr().to_string()
  assert_true(request.contains("/api/research/documents"))
  assert_true(request.contains("Get"))
}

///|
/// The corpus panel's button sends the read click.
test "the corpus panel sends the read click" {
  let seen : Array[@frontend.Msg] = []
  let _ = @frontend.research_view(capturing_emit(seen), bare_model())
  let mut reads = 0
  for msg in seen {
    match msg {
      @frontend.Msg::ReadCorpusClicked => reads += 1
      _ => ()
    }
  }
  assert_eq(reads, 1)
}
