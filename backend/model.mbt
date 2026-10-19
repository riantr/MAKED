///| MAKED's machine, as data.
///
/// A model is the whole of the state machine MAKED runs: the domains it is
/// shown through, the positions the subject can stand at, the slots that can
/// drive it, and the rule for every (position, slot) pair. It is a value,
/// not a program, and it can be written down, read back, and handed to
/// somebody else.
///
/// That is the point of this file. Until now the machine was the pyroduct
/// package itself -- 34 positions, 8 slots and 53 transitions, reached
/// through its own types -- so the only loop MAKED could run was
/// pyroproduct's. A model as data means the machine can be a file, including
/// a file somebody else wrote, and MAKED runs it.
///
/// The built-in model is still pyroproduct's: `Model::pyroduct` reads the
/// table out of the package and writes it down here, in MAKED's own
/// vocabulary. `backend/model_test.mbt` then checks the two against each
/// other over every one of the 272 combinations, so the translation is
/// proved rather than assumed -- and the proof is what makes the next step
/// safe, which is running the loop off a model instead of off the package.
///
/// Two vocabularies, deliberately:
////
///   - An **id** is a name this file owns: `standing`, `occasion`. It is
///     what a rule refers to and what a URL carries, so it has to be stable
///     and it has to be ASCII.
///   - A **label** is what a reader sees: "Standing", "Situation". It
///     belongs to the model, and a model is free to rename anything.
///
/// The edge between a position and the next is a **rule**, and a rule that
/// the table leaves open offers **candidates** rather than a destination.
/// The name of the edge is carried too, because the prose that explains a
/// step ("Take stand → Freedom") is the edge's own name, and inventing a
/// description of an edge would be claiming something the model does not say.

///|
/// One of the lenses the loop is shown through.
pub(all) struct DomainSpec {
  /// The id this domain is referred to by.
  id : String
  /// The single letter the ring is drawn with.
  letter : String
  /// The name of the domain.
  title : String
  /// What the domain is, in one phrase: "the model formulator".
  role : String
  /// The position this domain starts at.
  anchor : String
} derive(Eq, Debug)

///|
pub extend DomainSpec with Eq::{not_equal, equal}

///|
pub extend DomainSpec with Debug::{to_repr}

///|
/// A position the subject can stand at.
pub(all) struct PositionSpec {
  id : String
  /// What a reader sees: "Standing".
  label : String
  /// One sentence about what the position is.
  gloss : String
  /// The domain this position belongs to, or "" when it belongs to none.
  /// Most positions belong to no domain: a domain is a lens, not a place.
  domain : String
} derive(Eq, Debug)

///|
pub extend PositionSpec with Eq::{not_equal, equal}

///|
pub extend PositionSpec with Debug::{to_repr}

///|
/// A slot that can drive the subject.
pub(all) struct SlotSpec {
  id : String
  /// What a reader sees: "Situation".
  designation : String
  /// One sentence about what the slot is.
  gloss : String
} derive(Eq, Debug)

///|
pub extend SlotSpec with Eq::{not_equal, equal}

///|
pub extend SlotSpec with Debug::{to_repr}

///|
/// One of the successors the table offered and would not choose between.
pub(all) struct Candidate {
  /// The name of the edge that leads there.
  edge : String
  /// The position it leads to.
  to : String
  /// What the edge does to the subject: "moved", "held" or "same".
  kind : String
} derive(Eq, Debug)

///|
pub extend Candidate with Eq::{not_equal, equal}

///|
pub extend Candidate with Debug::{to_repr}

///|
/// What one rule does.
///
/// The five shapes are the ones a table can hand back, and they are the ones
/// the loop already understands: the subject moved, the table held it there,
/// the table settled it, the table offered several successors and declined
/// to choose, or there is no way out at all.
pub(all) enum Move {
  /// The subject moved to a position, along an edge the table names.
  Moved(String, String)
  /// The table held the subject at a position, along an edge it names.
  Held(String, String)
  /// The table settled the subject: it stays where it is, reached by one of
  /// these edges.
  Same(Array[String], String)
  /// The table offered these successors and declined to choose between them.
  Open(Array[Candidate])
  /// No way out of this position. The reason is the table's own.
  Block(String)
} derive(Eq, Debug)

///|
pub extend Move with Eq::{not_equal, equal}

///|
pub extend Move with Debug::{to_repr}

///|
/// One rule: what happens when a slot is used at a position.
pub(all) struct Rule {
  /// The position the rule is about.
  from : String
  /// The slot the rule is about.
  slot : String
  /// What it does.
  transition : Move
} derive(Eq, Debug)

///|
pub extend Rule with Eq::{not_equal, equal}

///|
pub extend Rule with Debug::{to_repr}

///|
/// A successor reachable from a position in so many steps, with the slot
/// that opens the way.
///
/// Continuations are the model's own answer to "what could happen next",
/// and they are kept as data rather than recomputed, because the depth of
/// the lookahead is a property of the model and not of the reader.
pub(all) struct Continuation {
  from : String
  slot : String
  to : String
  steps : Int32
} derive(Eq, Debug)

///|
pub extend Continuation with Eq::{not_equal, equal}

///|
pub extend Continuation with Debug::{to_repr}

///|
/// The whole machine.
pub(all) struct Model {
  /// What the model is called.
  name : String
  /// The domains, in the order they are shown.
  domains : Array[DomainSpec]
  /// Every position the subject can stand at.
  positions : Array[PositionSpec]
  /// Every slot that can drive the subject.
  slots : Array[SlotSpec]
  /// The rule for every (position, slot) pair.
  rules : Array[Rule]
  /// The successors, and how far away they are.
  continuations : Array[Continuation]
} derive(Eq, Debug)

///|
pub extend Model with Eq::{not_equal, equal}

///|
pub extend Model with Debug::{to_repr}

///|
/// The format this file writes and reads, so that a model saved by one
/// version can be recognised by the next.
pub const MODEL_FORMAT : String = "maked.model.v1"

///|
/// The model MAKED is running.
///
/// Held in a one-element array because MoonBit has no mutable module-level
/// binding, and the element is mutable in place. It is built once, at
/// start-up, because building it means asking the table about all 272
/// combinations and the answer does not change while the server runs.
let g_model : Array[Model] = [Model::pyroduct()]

///|
/// The model MAKED is running.
pub fn current_model() -> Model {
  g_model[0]
}

///|
/// A URL-safe id for a label: lower case, and spaces become hyphens.
///
/// The id is a name this file owns, so it has to be ASCII and it has to be
/// derivable from the label without a lookup table. Only the letters and the
/// hyphen survive; a label with anything else in it keeps the other
/// characters, because a position called "Self-binding" should be
/// "self-binding" and not "selfbinding".
fn slug(label : String) -> String {
  label.to_lower().replace_all(old=" ", new="-")
}

///|
/// The id of a position, derived from the name a reader sees.
pub fn position_id_of(state : @sm.SubjectState) -> String {
  slug(state.en_label())
}

///|
/// The id of a slot.
///
/// These are MAKED's own names, and they are the ones that appear in URLs
/// and in the session record. They are kept here, in one place, because the
/// API path, the stored history and the slot list have to agree on them: a
/// name that changes in one of them and not the others is a session that
/// cannot be replayed.
pub fn slot_id_of(slot : @sm.Slot) -> String {
  match slot {
    @sm.Occasion => "occasion"
    @sm.Orientation => "orientation"
    @sm.Antecedent => "antecedent"
    @sm.Act => "act"
    @sm.Feedback => "feedback"
    @sm.Hold => "hold"
    @sm.CoBeing => "cobeing"
    @sm.Unveil => "unveil"
  }
}

///|
/// The id of a domain.
pub fn domain_id_of(domain : Domain) -> String {
  match domain {
    Model => "model"
    Data => "data"
    Experience => "experience"
    Attack => "attack"
    Knowledge => "knowledge"
  }
}

///|
/// The domain a position id is the anchor of, if any.
pub fn domain_of_anchor(model : Model, position : String) -> String {
  for domain in model.domains {
    if domain.anchor == position {
      return domain.id
    }
  }
  ""
}

///|
/// What one outcome does, in MAKED's own vocabulary.
///
/// The state is needed as well as the outcome, because an open branch has to
/// say what each of its candidates would *do*, and only the table knows
/// that: the candidate is the edge, and the edge's receipt is the table's
/// answer to it.
pub fn Move::of(state : @sm.SubjectState, outcome : @sm.Outcome) -> Move {
  match outcome {
    @sm.Moved(tr, to) => Moved(tr.en_label(), position_id_of(to))
    @sm.Held(tr, to) => Held(tr.en_label(), position_id_of(to))
    @sm.Same(_, named, to) => {
      let edges = []
      for tr in named {
        edges.push(tr.en_label())
      }
      Same(edges, position_id_of(to))
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
        candidates.push({
          edge: edge.en_label(),
          to: position_id_of(target),
          kind,
        })
      }
      Open(candidates)
    }
    @sm.Block(reason) => Block(reason)
  }
}

///|
/// What the outcome is called, in the words a reader sees.
///
/// The five names are the ones the table's own English rendering uses, so a
/// reader sees one vocabulary rather than two. They are the outcome's *kind*
/// dressed in words. The kind itself -- "moved", "open" -- is what the
/// machine matches on, and it is what travels in the JSON beside the label,
/// so a client never has to recognise a sentence to know what happened.
pub fn Move::label(self : Move) -> String {
  match self {
    Moved(_, _) => "Moved"
    Held(_, _) => "Held"
    Same(_, _) => "Converge"
    Open(_) => "Undecided"
    Block(_) => "No-way"
  }
}

///|
/// The outcome's kind, in the words the machine matches on.
pub fn Move::kind(self : Move) -> String {
  match self {
    Moved(_, _) => "moved"
    Held(_, _) => "held"
    Same(_, _) => "same"
    Open(_) => "open"
    Block(_) => "block"
  }
}

///|
/// The slot with this name, if the model has one.
///
/// The name may be the slot's id ("occasion") or the name a reader sees
/// ("Situation"), and the match ignores case: the reader asks for what the
/// panel showed them, and the panel shows the designation.
pub fn Model::slot_from_name(self : Model, s : String) -> String? {
  let needle = s.to_lower()
  for slot in self.slots {
    if slot.id.to_lower() == needle || slot.designation.to_lower() == needle {
      return Some(slot.id)
    }
  }
  None
}

///|
/// The successors reachable from a position through one slot.
///
/// The same list as `continuations`, but for a single slot: the slot-by-slot
/// view is where the alternative routes belong.
pub fn Model::continuations_for(
  self : Model,
  from : String,
  slot : String,
  depth : Int32,
) -> Array[(String, Int32)] {
  let out = []
  for continuation in self.continuations {
    if continuation.from == from &&
      continuation.slot == slot &&
      continuation.steps <= depth {
      out.push((continuation.to, continuation.steps))
    }
  }
  out
}

///|
/// The position a domain starts at.
pub fn Model::domain_anchor(self : Model, domain : String) -> String {
  match self.domain(domain) {
    Some(spec) => spec.anchor
    None => ""
  }
}

///|
/// The domain that starts at a position, if one does.
pub fn Model::domain_anchored_at(self : Model, position : String) -> String? {
  for domain in self.domains {
    if domain.anchor == position {
      return Some(domain.id)
    }
  }
  None
}

///|
/// The ids of the model's domains, in the order they are shown.
pub fn Model::domain_ids(self : Model) -> Array[String] {
  let ids = []
  for domain in self.domains {
    ids.push(domain.id)
  }
  ids
}

///|
/// The ids of the model's positions.
pub fn Model::position_ids(self : Model) -> Array[String] {
  let ids = []
  for position in self.positions {
    ids.push(position.id)
  }
  ids
}

///|
/// The ids of the model's slots.
pub fn Model::slot_ids(self : Model) -> Array[String] {
  let ids = []
  for slot in self.slots {
    ids.push(slot.id)
  }
  ids
}

///|
/// The built-in model: pyroproduct's table, written down.
///
/// Every (position, slot) pair is asked of the package and written down,
/// including the 228 that have no way out. A model that only listed the
/// edges that exist would be smaller, but it would also be a model whose
/// gaps had to be inferred -- and "no road from here" is a fact about the
/// table that a reader is entitled to see stated.
pub fn Model::pyroduct() -> Model {
  let positions : Array[PositionSpec] = []
  for state in @sm.all_states() {
    positions.push({
      id: position_id_of(state),
      label: state.en_label(),
      gloss: state.en_gloss(),
      domain: "",
    })
  }
  let slots : Array[SlotSpec] = []
  for slot in @sm.all_slots() {
    slots.push({
      id: slot_id_of(slot),
      designation: slot.en_designation(),
      gloss: slot.en_gloss(),
    })
  }
  // The domains are read out of MAKED's own vocabulary rather than written
  // down here, so that there is one place that says what the five domains
  // are. The model file will own them once the loop reads its machine from
  // a model; until then this is the direction of the dependency, and it is
  // the safe one to move in.
  let domains : Array[DomainSpec] = []
  for domain in ring_domains_loop() {
    domains.push({
      id: domain_id_of(domain),
      letter: domain.letter(),
      title: domain.title(),
      role: domain.role(),
      anchor: domain_anchor_of(domain),
    })
  }
  let rules : Array[Rule] = []
  for state in @sm.all_states() {
    for slot in @sm.all_slots() {
      rules.push({
        from: position_id_of(state),
        slot: slot_id_of(slot),
        transition: Move::of(state, @sm.step(state, slot)),
      })
    }
  }
  // The continuations are the model's own answer to "what could happen
  // next", and they are asked of the table at the same depth MAKED has
  // always used, so the numbers do not move when the model is written down.
  let continuations : Array[Continuation] = []
  for state in @sm.all_states() {
    for slot in @sm.all_slots() {
      for pair in @sm.after_open(state, slot, 3) {
        let (next, steps) = pair
        continuations.push({
          from: position_id_of(state),
          slot: slot_id_of(slot),
          to: position_id_of(next),
          steps,
        })
      }
    }
  }
  { name: "MAKED (pyroduct)", domains, positions, slots, rules, continuations, }
}

///|
/// The rule for a (position, slot) pair, if the model has one.
pub fn Model::rule(self : Model, from : String, slot : String) -> Rule? {
  for rule in self.rules {
    if rule.from == from && rule.slot == slot {
      return Some(rule)
    }
  }
  None
}

///|
/// What happens when a slot is used at a position.
///
/// A model that has no rule for a pair has no way out of it, which is the
/// same answer the table gives for a blocked combination. A model that is
/// asked about a pair it does not know is not asked a question the model
/// can answer.
pub fn Model::step(self : Model, from : String, slot : String) -> Move {
  match self.rule(from, slot) {
    Some(rule) => rule.transition
    None => Block("the model has no rule for this pair")
  }
}

///|
/// The slots that have an edge out of a position.
pub fn Model::exitable_slots(self : Model, from : String) -> Array[String] {
  let usable = []
  for slot in self.slots {
    match self.rule(from, slot.id) {
      Some(rule) =>
        match rule.transition {
          Block(_) => ()
          _ => usable.push(slot.id)
        }
      None => ()
    }
  }
  usable
}

///|
/// The slot to drive a position with, chosen from the model rather than by
/// meaning.
///
/// A slot whose outcome is a move is preferred; failing that, the first slot
/// with any edge at all. A position with no outgoing edge has no drive slot,
/// and the caller has to report that rather than paper over it.
pub fn Model::drive_slot(self : Model, from : String) -> String? {
  let moving = []
  let staying = []
  for slot in self.exitable_slots(from) {
    match self.step(from, slot) {
      Moved(_, _) => moving.push(slot)
      _ => staying.push(slot)
    }
  }
  if moving.length() > 0 {
    Some(moving[0])
  } else if staying.length() > 0 {
    Some(staying[0])
  } else {
    None
  }
}

///|
/// Whether the model offers several successors from a position and refuses
/// to pick between them.
pub fn Model::is_undecided(self : Model, from : String) -> Bool {
  for slot in self.exitable_slots(from) {
    match self.step(from, slot) {
      Open(_) => return true
      _ => ()
    }
  }
  false
}

///|
/// The candidates the model offers from a position through a slot.
pub fn Model::candidates(
  self : Model,
  from : String,
  slot : String,
) -> Array[Candidate] {
  match self.step(from, slot) {
    Open(cands) => cands
    _ => []
  }
}

///|
/// The successors reachable from a position, and how many steps away they
/// are.
///
/// A successor reached twice is listed once, at the shorter distance: two
/// routes to the same position are one future, and the slot-by-slot view is
/// where the alternative routes belong.
pub fn Model::continuations(
  self : Model,
  from : String,
  depth : Int32,
) -> Array[(String, Int32)] {
  let seen : Array[(String, Int32)] = []
  let out : Array[(String, Int32)] = []
  for continuation in self.continuations {
    if continuation.from != from || continuation.steps > depth {
      continue
    }
    let mut index = -1
    let mut at = 0
    for prev in seen {
      if prev.0 == continuation.to {
        index = at
      }
      at += 1
    }
    if index == -1 {
      seen.push((continuation.to, continuation.steps))
      out.push((continuation.to, continuation.steps))
    } else if continuation.steps < out[index].1 {
      seen[index] = (continuation.to, continuation.steps)
      out[index] = (continuation.to, continuation.steps)
    }
  }
  out
}

///|
/// The position with this id, if the model has one.
pub fn Model::position(self : Model, id : String) -> PositionSpec? {
  for position in self.positions {
    if position.id == id {
      return Some(position)
    }
  }
  None
}

///|
/// The slot with this id, if the model has one.
pub fn Model::slot(self : Model, id : String) -> SlotSpec? {
  for slot in self.slots {
    if slot.id == id {
      return Some(slot)
    }
  }
  None
}

///|
/// The domain with this id, if the model has one.
pub fn Model::domain(self : Model, id : String) -> DomainSpec? {
  for domain in self.domains {
    if domain.id == id {
      return Some(domain)
    }
  }
  None
}

///|
/// The name a reader sees for a position.
///
/// A position the model does not have has no name, and the empty string is
/// the honest answer: a missing position is not a position called "".
pub fn Model::position_label(self : Model, id : String) -> String {
  match self.position(id) {
    Some(position) => position.label
    None => ""
  }
}

///|
/// What a position is, in one sentence.
pub fn Model::position_gloss(self : Model, id : String) -> String {
  match self.position(id) {
    Some(position) => position.gloss
    None => ""
  }
}

///|
/// The name a reader sees for a slot.
pub fn Model::slot_designation(self : Model, id : String) -> String {
  match self.slot(id) {
    Some(slot) => slot.designation
    None => ""
  }
}

///|
/// What a slot is, in one sentence.
pub fn Model::slot_gloss(self : Model, id : String) -> String {
  match self.slot(id) {
    Some(slot) => slot.gloss
    None => ""
  }
}

///|
/// The domain a position belongs to, by its id.
pub fn Model::domain_of_position(self : Model, id : String) -> String {
  match self.position(id) {
    Some(position) => position.domain
    None => ""
  }
}

/// -- JSON -------------------------------------------------------------------

///|
fn json_field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
/// A number field of a JSON object, or zero when it is missing or is not a
/// number.
///
/// `json_string` in `entries.mbt` is the package's own reader for a string
/// field and is used here too, rather than a second one written beside it.
fn model_int(json : Json, key : String) -> Int32 {
  match json_field(json, key) {
    Some(Number(n, ..)) => n.to_int()
    _ => 0
  }
}

///|
fn json_array(json : Json, key : String) -> Array[Json] {
  match json_field(json, key) {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn json_strings(json : Json, key : String) -> Array[String] {
  let out = []
  for item in json_array(json, key) {
    match item {
      String(s) => out.push(s)
      _ => ()
    }
  }
  out
}

///|
/// A move, as JSON.
pub fn Move::to_json(self : Move) -> Json {
  match self {
    Moved(edge, to) => { "kind": "moved", "edge": edge, "to": to }
    Held(edge, to) => { "kind": "held", "edge": edge, "to": to }
    Same(edges, to) =>
      // The edges are written as a plain array of strings, so that a model
      // file reads the way a person would write it.
      { "kind": "same", "edges": edges, "to": to }
    Open(candidates) => {
      let items : Array[Json] = []
      for candidate in candidates {
        items.push({
          "edge": candidate.edge,
          "to": candidate.to,
          "kind": candidate.kind,
        })
      }
      { "kind": "open", "candidates": [..items] }
    }
    Block(reason) => { "kind": "block", "reason": reason }
  }
}

///|
/// A move, from JSON. Returns None when the JSON does not describe a move
/// this file understands: a model written for a newer version must be
/// refused, not half-read.
pub fn Move::from_json(json : Json) -> Move? {
  let kind = json_string(json, "kind")
  match kind {
    "moved" => Some(Moved(json_string(json, "edge"), json_string(json, "to")))
    "held" => Some(Held(json_string(json, "edge"), json_string(json, "to")))
    "same" => Some(Same(json_strings(json, "edges"), json_string(json, "to")))
    "open" => {
      let candidates = []
      for item in json_array(json, "candidates") {
        candidates.push({
          edge: json_string(item, "edge"),
          to: json_string(item, "to"),
          kind: json_string(item, "kind"),
        })
      }
      Some(Open(candidates))
    }
    "block" => Some(Block(json_string(json, "reason")))
    _ => None
  }
}

///|
/// The model, as JSON.
///
/// This is the form a reader can edit and hand back. Every name the model
/// uses is written down, so the file is the model and not a pointer to one.
pub fn Model::to_json(self : Model) -> Json {
  let domains : Array[Json] = []
  for domain in self.domains {
    domains.push({
      "id": domain.id,
      "letter": domain.letter,
      "title": domain.title,
      "role": domain.role,
      "anchor": domain.anchor,
    })
  }
  let positions : Array[Json] = []
  for position in self.positions {
    positions.push({
      "id": position.id,
      "label": position.label,
      "gloss": position.gloss,
      "domain": position.domain,
    })
  }
  let slots : Array[Json] = []
  for slot in self.slots {
    slots.push({
      "id": slot.id,
      "designation": slot.designation,
      "gloss": slot.gloss,
    })
  }
  let rules : Array[Json] = []
  for rule in self.rules {
    rules.push({
      "from": rule.from,
      "slot": rule.slot,
      "outcome": rule.transition.to_json(),
    })
  }
  let continuations : Array[Json] = []
  for continuation in self.continuations {
    continuations.push({
      "from": continuation.from,
      "slot": continuation.slot,
      "to": continuation.to,
      "steps": continuation.steps,
    })
  }
  {
    "format": MODEL_FORMAT,
    "name": self.name,
    "domains": [..domains],
    "positions": [..positions],
    "slots": [..slots],
    "rules": [..rules],
    "continuations": [..continuations],
  }
}

///|
/// A model, from JSON.
///
/// Returns None when the file is not a model this version understands, or
/// when it names something it does not define: a rule about a position that
/// is not in the model is a rule about nowhere, and reading it would mean
/// inventing a position to hold it.
///
/// The refusal says which rule is the problem, because "your model is
/// wrong" is not something a reader can act on.
pub fn Model::from_json(json : Json) -> Model? {
  let format = json_string(json, "format")
  if format != MODEL_FORMAT {
    return None
  }
  let domains : Array[DomainSpec] = []
  for item in json_array(json, "domains") {
    domains.push({
      id: json_string(item, "id"),
      letter: json_string(item, "letter"),
      title: json_string(item, "title"),
      role: json_string(item, "role"),
      anchor: json_string(item, "anchor"),
    })
  }
  let positions : Array[PositionSpec] = []
  for item in json_array(json, "positions") {
    positions.push({
      id: json_string(item, "id"),
      label: json_string(item, "label"),
      gloss: json_string(item, "gloss"),
      domain: json_string(item, "domain"),
    })
  }
  let slots : Array[SlotSpec] = []
  for item in json_array(json, "slots") {
    slots.push({
      id: json_string(item, "id"),
      designation: json_string(item, "designation"),
      gloss: json_string(item, "gloss"),
    })
  }
  let rules : Array[Rule] = []
  for item in json_array(json, "rules") {
    let transition = match
      Move::from_json(
        json_field(item, "outcome").unwrap_or(Json::empty_object()),
      ) {
      Some(transition) => transition
      None => return None
    }
    rules.push({
      from: json_string(item, "from"),
      slot: json_string(item, "slot"),
      transition,
    })
  }
  let continuations : Array[Continuation] = []
  for item in json_array(json, "continuations") {
    continuations.push({
      from: json_string(item, "from"),
      slot: json_string(item, "slot"),
      to: json_string(item, "to"),
      steps: model_int(item, "steps"),
    })
  }
  let model = Model::{
    name: json_string(json, "name"),
    domains,
    positions,
    slots,
    rules,
    continuations,
  }
  if model.first_broken_rule() is Some(_) {
    return None
  }
  Some(model)
}

///|
/// The first rule that names something the model does not define.
///
/// A rule about a position that is not in the model, or a slot that is not
/// in the model, or a destination that is not in the model. The first one is
/// enough: the reader fixes that one, and the next refusal is about the
/// next.
pub fn Model::first_broken_rule(self : Model) -> String? {
  for rule in self.rules {
    if self.position(rule.from) is None {
      return Some(rule.from)
    }
    if self.slot(rule.slot) is None {
      return Some(rule.slot)
    }
    match rule.transition {
      Moved(_, to) => if self.position(to) is None { return Some(to) }
      Held(_, to) => if self.position(to) is None { return Some(to) }
      Same(_, to) => if self.position(to) is None { return Some(to) }
      Open(candidates) =>
        for candidate in candidates {
          if self.position(candidate.to) is None {
            return Some(candidate.to)
          }
        }
      Block(_) => ()
    }
  }
  for continuation in self.continuations {
    if self.position(continuation.from) is None {
      return Some(continuation.from)
    }
    if self.position(continuation.to) is None {
      return Some(continuation.to)
    }
  }
  None
}
