///| MAKED Loop: the domains as a model-driven state cycle.
///
/// The domains are the model's. MAKED's built-in model has five -- M/D/E/A/K --
/// and they are anchors on pyroduct's subject state machine; a model file
/// may have two, or seven, or one. Each domain carries its own position and
/// its own history, so the domains evolve independently rather than as one
/// ring. Navigation is a `step(position, slot)` call; the Outcome (Moved /
/// Held / Open / Same / Block) is recorded in an append-only history so the
/// cycle is observable, not just navigable.
///
/// The built-in model's mapping (each domain names the structural relation
/// the position denotes, not the domain's content):
///
///   M Model      → Standing   the model stands, one foot in past one in future
///   D Data       → Encounter  the model meets the other (data as other)
///   E Experience → Honor      experience absorbed as reward from the idol
///   A Attack     → Evil       attack as the hard cold thing that shrinks the horizon
///   K Knowledge  → Discipline knowledge distilled through enduring and removing reefs
///
/// **The drive slot is read from the model's table, never chosen by meaning.**
/// An earlier version hard-coded one slot per domain on the reasoning that the
/// slot should name the structural relation to the next domain -- Model meets
/// data, so CoBeing. That reasoning produced five slots, and the table has no
/// edge for any of them: stepping the loop recorded Moved-looking history while
/// every position stayed exactly where it started, and the ring pointer
/// rotated so the page looked like it was working. The table is the authority;
/// `drive_slot` derives from it, `exitable_slots` reports what it offers, and a
/// position with no outgoing edge is reported as blocked instead of advanced.
///
/// The ring order M → D → E → A → K → M is still the *presentation* order --
/// it is the order the logo draws, and it is how the site narrates itself. It
/// is no longer mistaken for a claim that the state machine moved.

///|
/// The five domains, as the ring order M→D→E→A→K→M.
///
/// The ring order is still the *presentation* order -- it is the order the
/// logo draws, and it is how the site narrates itself. It is no longer
/// mistaken for a claim that the state machine moved.

///|
/// What a step did to the subject.
///
/// The distinction the cursor depends on. `Advanced` covers Moved and Held --
/// the position changed, or the table deliberately held it there. `Undecided`
/// and `Blocked` both mean the subject did *not* go anywhere, and neither is
/// progress: Undecided is a question the table declined to answer, Blocked is a
/// gap. So the cursor stays put for both.
///
/// This type exists because the cursor previously advanced by comparing
/// `outcome_label` against a label string, which missed Undecided entirely -- a
/// step the table explicitly refused to make still advanced the cursor, and the
/// page looked like it was moving. Comparing a label string to learn whether
/// the subject moved is the bug this replaces.
pub(all) enum StepEffect {
  /// Moved, Held or Converge: the position changed, or the table settled it.
  Advanced
  /// Undecided: the table offers several successors and picks none.
  Undecided
  /// No-way: the table offers no road out of this position.
  Blocked
} derive(Eq, Debug)

///|
pub extend StepEffect with Eq::{not_equal, equal}

///|
pub extend StepEffect with Debug::{to_repr}

///|
pub fn StepEffect::of(transition : Move) -> StepEffect {
  match transition {
    Moved(_, _) => Advanced
    Held(_, _) => Advanced
    Same(_, _) => Advanced
    Open(_) => Undecided
    Block(_) => Blocked
  }
}

///|
/// Whether the subject actually went anywhere.
pub fn StepEffect::moved(self : StepEffect) -> Bool {
  match self {
    Advanced => true
    Undecided | Blocked => false
  }
}

///|
/// The loop mode: structured (follow ring order) or free (explore state space).
pub(all) enum LoopMode {
  /// Structured mode: each domain uses its designated drive slot, following
  /// the ring order M→D→E→A→K. This is the philosophical default.
  Structured
  /// Free mode: any slot can be used at any position, allowing exploration
  /// of different trajectories through the pyroduct state space.
  Free
} derive(Eq, Debug)

///|
pub extend LoopMode with Eq::{not_equal, equal}

///|
pub extend LoopMode with Debug::{to_repr}

///|
pub fn LoopMode::designation(self : LoopMode) -> String {
  match self {
    Structured => "Structured"
    Free => "Free"
  }
}

///|
pub fn LoopMode::gloss(self : LoopMode) -> String {
  match self {
    Structured =>
      "Follows the ring order M→D→E→A→K, each domain driven by its slot"
    Free => "Any slot may drive, exploring the state space"
  }
}

///|
/// The domain's letter, as the ring is drawn with it.
pub fn Domain::letter(self : Domain) -> String {
  self.letter
}

///|
/// The domain's name, as a reader sees it.
pub fn Domain::title(self : Domain) -> String {
  self.title
}

///|
/// The domain's role, as a phrase with its article.
pub fn Domain::role(self : Domain) -> String {
  self.role
}

///|
/// The slots that have an edge out of a position.
///
/// Read from the model rather than assumed. A slot list hard-coded from the
/// *meaning* of a domain will eventually name a combination the table has no
/// edge for. That is not hypothetical: the mapping this replaced named five
/// slots, and all five were Block.
pub fn exitable_slots(position : String) -> Array[String] {
  exitable_slots_of(current_model(), position)
}

///|
/// The slots that have an edge out of a position, in a given model.
///
/// The loop asks its own model, so a state can run on a machine other than
/// the installed one. The installed-model version above is for the API,
/// which serves the machine that is installed.
fn exitable_slots_of(model : Model, position : String) -> Array[String] {
  model.exitable_slots(position)
}

///|
/// The slot to drive a position with, chosen from the model rather than by
/// semantics.
///
/// A slot whose outcome is a move is preferred -- a domain would otherwise
/// sit on a self-edge while a real move sits one slot later. Failing that,
/// the first exitable slot in the model's own order, which covers "held" and
/// "converge": both are legitimate receipts that keep the subject where it
/// is, so taking one is not inventing anything.
///
/// None when the position has no outgoing edge at all -- a real gap in the
/// model. The caller must report that, never paper over it.
pub fn drive_slot(position : String) -> String? {
  drive_slot_of(current_model(), position)
}

///|
/// The slot to drive a position with, in a given model.
fn drive_slot_of(model : Model, position : String) -> String? {
  model.drive_slot(position)
}

///|
/// Whether the model offers several successors from a position and refuses
/// to pick between them. A gap and an undecided branch are both legitimate
/// receipts: better to stop where you are than to invent a next step. The
/// loop takes the same position -- it surfaces the candidates and waits.
pub fn is_undecided(position : String) -> Bool {
  is_undecided_of(current_model(), position)
}

///|
/// Whether a given model offers several successors from a position.
fn is_undecided_of(model : Model, position : String) -> Bool {
  model.is_undecided(position)
}

///|
/// The successor positions reachable from a position in at most `depth`
/// steps, with the number of steps that reach each one.
///
/// This is the model's own answer to "what could happen next", as opposed to
/// `expand`, which requires the caller to name the slot sequence in advance.
pub fn continuations(
  position : String,
  depth : Int32,
) -> Array[(String, Int32)] {
  current_model().continuations(position, depth)
}

///|
/// Parse a slot name back into the model's id for it.
///
/// Accepts either the name as displayed ("Co-being", "Situation") or the
/// URL-safe id ("cobeing", "occasion"), case-insensitively. Returns None if
/// the string does not match any slot.
///
/// The names are read back out of the model instead of being copied into
/// MAKED. A copy went stale the moment the table renamed two of the eight --
/// 0.1.32 moved "Occasion" to "Situation" and "Anticipation" to
/// "Antecedent" -- and the symptom was a parser that had quietly stopped
/// accepting two of the words MAKED's own API was advertising. A rename in
/// the model is now a rename here, with nothing to keep in sync.
pub fn slot_from_designation(s : String) -> String? {
  current_model().slot_from_name(s)
}

///|
/// Parse a slot from its English name.
pub fn slot_from_english(s : String) -> String? {
  current_model().slot_from_name(s)
}

///|
/// The position a domain starts at.
///
/// The anchor is the model's, not MAKED's: the model says where each domain
/// begins, and the anchor is a position id like any other.
pub fn Domain::position(self : Domain) -> String {
  self.anchor
}

///|
/// The domain that starts at a position -- the inverse of `position`. None
/// for the positions that are not domain anchors.
pub fn position_to_domain(position : String) -> Domain? {
  match current_model().domain_anchored_at(position) {
    Some(id) => domain_from_id(id)
    None => None
  }
}

///|
/// The domain with this id.
pub fn domain_from_id(s : String) -> Domain? {
  current_model().domain_by_id(s)
}

///|
/// The next domain in the ring.
///
/// The ring is the model's own order, so it is as long as the model says and
/// no longer: MAKED's built-in model has five, and a model file may have
/// two, or one, or seven.
pub fn Domain::next(self : Domain) -> Domain {
  current_model().next_domain(self)
}

///|
/// Parse a domain from its letter (M, D, E, A, K -- or whatever the model's
/// own letters are).
pub fn domain_from_letter(s : String) -> Domain? {
  current_model().domain_by_letter(s)
}

///|
/// Parse a domain from its name (case-insensitive).
///
/// The name may be the domain's id or its title, because a reader will type
/// whichever one they were shown and a model file may give a domain any
/// title it likes.
pub fn domain_from_english(s : String) -> Domain? {
  current_model().domain_by_name(s)
}

///|
/// The domains, in ring order.
///
/// The domains are the model's. MAKED's built-in model has five of them --
/// Model, Data, Experience, Attack, Knowledge -- and a model file may have a
/// different number entirely, so this list is whatever the model says it is
/// and the ring is whatever length that is.
pub fn ring_domains_loop() -> Array[Domain] {
  current_model().domains
}

///|
/// The domain the loop starts on: the model's first.
///
/// A model with no domains cannot have a loop, and `Model::from_json`
/// refuses one, so the empty case here is unreachable -- but it is answered
/// rather than crashed on, because a crash in the model's own constructor
/// is a worse place to find out.
pub fn starting_domain() -> Domain {
  let domains = current_model().domains
  if domains.length() == 0 {
    return { id: "", letter: "", title: "", role: "", anchor: "", }
  }
  domains[0]
}

///|
/// One recorded step in the loop history.
pub(all) struct LoopEvent {
  domain : Domain
  /// The slot's id, as the model spells it.
  slot : String
  /// The word the model calls the outcome: "Moved", "Held", "Converge",
  /// "Undecided" or "No-way" -- or whatever a model file says instead.
  outcome_label : String
  /// The outcome's kind: "moved", "held", "same", "open" or "block". This is
  /// what the machine matches on, and it travels beside the label so nobody
  /// has to recognise a word to know what happened.
  outcome_kind : String
  outcome_detail : String // human-readable detail
  position_designation : String // the state name
  position_label : String // the state name (English collapses the two source layers)
} derive(Eq, Debug)

///|
pub extend LoopEvent with Eq::{not_equal, equal}

///|
pub extend LoopEvent with Debug::{to_repr}

///|
/// Individual state machine for one domain. Each domain has its own position
/// in the model and its own history of events.
pub(all) struct DomainState {
  domain : Domain
  /// The position id the subject stands at.
  position : String
  history : Array[LoopEvent]
} derive(Eq, Debug)

///|
pub extend DomainState with Eq::{not_equal, equal}

///|
pub extend DomainState with Debug::{to_repr}

///|
pub fn DomainState::new(domain : Domain) -> DomainState {
  { domain, position: domain.position(), history: [], }
}

///|
/// Step this domain's state machine with the given slot.
pub fn DomainState::step(self : DomainState, slot : String) -> DomainState {
  let model = current_model()
  self.step_by_outcome(model, slot, model.step(self.position, slot))
}

///|
/// Step this domain's state machine with a move that is already known.
///
/// The move is a parameter rather than something derived here, so that a step
/// decided by a candidate the reader picked and a step decided by the slot's
/// own outcome travel the same road: one event, one position, one history.
///
/// The model comes in with the move, because the event is written in the
/// model's own words -- the position's label, the slot's designation, the
/// word the model calls the outcome. A state that took its words from
/// somewhere else would be recording a step that nobody took.
pub fn DomainState::step_by_outcome(
  self : DomainState,
  model : Model,
  slot : String,
  transition : Move,
) -> DomainState {
  let event = event_from_outcome(
    model,
    self.domain,
    slot,
    self.position,
    transition,
  )
  let history = self.history
  history.push(event)
  // Update position if the step landed somewhere
  let new_position = match transition {
    Moved(_, to) => to
    Held(_, to) => to
    Same(_, to) => to
    Open(_) => self.position
    Block(_) => self.position
  }
  { domain: self.domain, position: new_position, history, }
}

///|
/// The loop state: current domain + per-domain independent state machines + group state + mode.
///
/// The model is part of the state, and that is not decoration. A state whose
/// domains came from one model and whose lookups were answered by another is
/// a state that cannot be read: the ring would be walked with the wrong
/// lenses, and a domain the state does not know about would be a lookup that
/// crashes rather than a lookup that misses.
///
/// So a state carries the model it belongs to, and every question about it is
/// asked of that model. It is also what makes a model change safe: installing
/// a new model resets the loop, and the state that is left behind keeps
/// running on the model it was built for, consistently, instead of half
/// running on the new one.
pub(all) struct LoopState {
  /// The model this state is running.
  model : Model
  current : Domain
  domain_states : Map[String, DomainState]
  group_state : @group.GroupState
  history : Array[LoopEvent]
  mode : LoopMode
} derive(Eq)

///|
pub extend LoopState with Eq::{not_equal, equal}

///|
pub fn LoopState::new() -> LoopState {
  LoopState::new_for(current_model())
}

///|
/// A new loop state running on a given model.
///
/// This is the reason the state carries its model. A state that was built for
/// one machine and asked its questions of another cannot be read: the ring
/// would be walked with the wrong lenses, and a domain the state does not
/// know about would be a lookup that crashes rather than a lookup that
/// misses.
///
/// So a state can be built on *any* model -- the installed one, or one that
/// belongs to somebody else -- and every question about it is asked of that
/// model. It is also what makes a model change safe: installing a new model
/// resets the loop, and the state that is left behind keeps running on the
/// model it was built for, consistently, instead of half running on the new
/// one.
pub fn LoopState::new_for(model : Model) -> LoopState {
  {
    model,
    current: starting_domain_of(model),
    domain_states: domain_states_of(model),
    group_state: @group.Scattered,
    history: [],
    mode: Structured,
  }
}

///|
/// A fresh set of per-domain states, one for each domain of the model.
fn domain_states_of(model : Model) -> Map[String, DomainState] {
  let domain_states = Map([], capacity=8)
  for domain in model.domains {
    domain_states[domain.id] = DomainState::new(domain)
  }
  domain_states
}

///|
/// Create a new loop state starting from the specified domain.
/// Each domain's state machine still starts at its own anchor position;
/// only the `current` pointer changes.
pub fn LoopState::new_from(domain : Domain) -> LoopState {
  let model = current_model()
  {
    model,
    current: domain,
    domain_states: domain_states_of(model),
    group_state: @group.Scattered,
    history: [],
    mode: Structured,
  }
}

///|
/// Create a new loop state in the specified mode.
pub fn LoopState::new_with_mode(mode : LoopMode) -> LoopState {
  let model = current_model()
  {
    model,
    current: starting_domain_of(model),
    domain_states: domain_states_of(model),
    group_state: @group.Scattered,
    history: [],
    mode,
  }
}

///|
/// The first domain of the ring, in a model that has one.
///
/// A model with no domains at all still has to give the loop somewhere to
/// stand, so the empty domain is the answer -- and it is an answer that says
/// "nowhere" rather than one that crashes.
fn starting_domain_of(model : Model) -> Domain {
  if model.domains.length() == 0 {
    return { id: "", letter: "", title: "", role: "", anchor: "", }
  }
  model.domains[0]
}

///|
/// The state of one domain, by name.
///
/// A miss here is a bug, not an empty state: a state whose domains came from
/// one model and whose lookups are answered by another is a state that cannot
/// be read. The state and the model are one object now, so the miss is
/// unreachable by construction -- and the invariant that says so is pinned by
/// a test rather than by a crash.
///
/// A crash here would take the whole test binary down with it, and with it
/// every other test's result. A guard whose failure mode is "the run died" is
/// a guard whose result cannot be read, and a bug report that arrives as
/// "the suite crashed" is a bug report that costs an afternoon.
///
/// So the miss is loud and survivable: the inconsistency is said out loud,
/// with the name of the place that asked, and the domain is answered with a
/// state at its own anchor -- a domain with no history has not moved, which
/// is a true statement about it.
fn domain_state_at(
  states : Map[String, DomainState],
  domain : Domain,
  site : String,
) -> DomainState {
  match states.get(domain.id) {
    Some(state) => state
    None => {
      println(
        "loop: no state for domain '\{domain.id}' at \{site}: the state and the model disagree",
      )
      DomainState::new(domain)
    }
  }
}

///|
/// Get the state of a specific domain.
pub fn LoopState::domain_state(
  self : LoopState,
  domain : Domain,
) -> DomainState {
  domain_state_at(self.domain_states, domain, "domain_state")
}

///|
/// Compute the group state based on the configuration of all domain states.
/// The group emerges from how the domains relate to each other.
///
/// The model comes in with the states, because the ring is the model's and
/// the states are the loop's: walking one model's domains against another
/// model's states is a lookup that cannot be answered.
pub fn compute_group_state(
  model : Model,
  domain_states : Map[String, DomainState],
) -> @group.GroupState {
  // Count how many domains have moved from their initial positions
  let mut moved_count = 0
  for domain in model.domains {
    let ds = domain_state_at(domain_states, domain, "compute_group_state")
    if ds.position != domain.position() {
      moved_count += 1
    }
  }
  // Group emergence logic based on domain activity
  // Scattered: no domain has moved
  // Converging: some domains starting to move
  // CommonTongue: majority have moved, forming coordination
  // Settled: all domains have moved and are in stable positions
  if moved_count == 0 {
    @group.Scattered
  } else if moved_count <= 2 {
    @group.Converging
  } else if moved_count <= 4 {
    @group.CommonTongue
  } else {
    @group.Settled
  }
}

///|
/// Copy the per-domain states, so a new state and the one it came from do
/// not share a map.
///
/// MoonBit's `Map` is mutable and is not copy-on-write, so
/// `domain_states[domain] = new_state` would change the map that the
/// *previous* state still points at. That is invisible while the previous
/// state is thrown away, and it is wrong the moment anybody wants to compare
/// the two: the position a step started from would read as the position it
/// landed on, and a session recording "where I was" would record "where I
/// ended up" instead.
///
/// The copy is five entries, so it costs nothing that matters, and it makes
/// `LoopState` a value: a state can be kept, compared, and replayed.
///
/// The model's own domains are the ones copied, because the state's map is
/// keyed by the domains the state was built for -- the model's, not
/// whichever model happens to be installed now.
fn copy_domain_states(
  model : Model,
  source : Map[String, DomainState],
) -> Map[String, DomainState] {
  let copy = Map([], capacity=8)
  for domain in model.domains {
    match source.get(domain.id) {
      Some(state) => copy[domain.id] = state
      None => ()
    }
  }
  copy
}

///|
/// Take one step: record the current position x slot outcome, then move the
/// viewing cursor to the next domain.
///
/// The slot comes from `drive_slot`, evaluated against the domain's **actual**
/// current position -- not its anchor. A domain that has already moved keeps
/// being driven from wherever it now is.
///
/// Both modes refuse to advance on a Block. The cursor advances because a step
/// was *recorded*, not because the subject *moved*; when nothing could move,
/// saying "next domain" would be the loop narrating progress it did not make.
///
/// Structured and Free differ only in who picks the slot: structured takes the
/// one `drive_slot` derives from the table, free takes whatever the caller
/// names. Neither mode invents an edge.
pub fn LoopState::step(self : LoopState) -> LoopState {
  let domain = self.current
  let domain_state = domain_state_at(self.domain_states, domain, "step")
  // Derived once: the model is the authority, and asking it twice could in
  // principle answer differently mid-call.
  let chosen = drive_slot_of(self.model, domain_state.position)
  let blocked = chosen is None
  self.step_domain_with(
    domain,
    match chosen {
      Some(slot) => slot
      // No road out of here. Record the gap honestly and stay put, rather
      // than drive a slot the model does not have. The event still has to
      // name a slot, because the record is per-slot: the first one in the
      // model's order will do, and it is blocked too -- when nothing has an
      // edge, nothing has an edge.
      None => first_slot_id_of(self.model)
    },
    blocked,
  )
}

///|
/// The first slot in the model's order, or "" when it has none.
///
/// Used only to name a slot in an event that is about a position with no way
/// out at all. The model that owns the state is the one asked, so the event
/// names a slot of the machine the step was taken on.
fn first_slot_id_of(model : Model) -> String {
  let slots = model.slot_ids()
  if slots.length() == 0 {
    return ""
  }
  slots[0]
}

///|
/// Step the given domain with the given slot and update the cursor.
///
/// `blocked` records that the default drive had no edge. Kept as a parameter
/// rather than re-derived so the recorded reason matches the decision that was
/// actually taken.
pub fn LoopState::step_domain_with(
  self : LoopState,
  domain : Domain,
  slot : String,
  blocked : Bool,
) -> LoopState {
  let domain_state = domain_state_at(
    self.domain_states,
    domain,
    "step_domain_with",
  )
  self.step_domain_by_outcome(
    domain,
    slot,
    self.model.step(domain_state.position, slot),
    blocked,
  )
}

///|
/// Step the given domain to one of the successors the model offered.
///
/// The reader's choice, not the machine's: the model has already said which
/// positions are reachable from here, and this picks one of them. The
/// candidate carries what the edge would have done, so obeying it is the
/// same motion the model would have made.
pub fn LoopState::step_domain_with_candidate(
  self : LoopState,
  domain : Domain,
  slot : String,
  candidate : Candidate,
) -> LoopState {
  let transition = match candidate.kind {
    "held" => Held(candidate.edge, candidate.to)
    "same" => Same([candidate.edge], candidate.to)
    _ => Moved(candidate.edge, candidate.to)
  }
  self.step_domain_by_outcome(domain, slot, transition, false)
}

///|
/// Record a step whose outcome is already known, and move the cursor.
///
/// The outcome is passed in rather than asked for a second time. It used to
/// be derived twice -- once for the event and once to judge whether the
/// cursor should advance -- and a table that could answer differently
/// mid-call would have made the recorded reason and the recorded outcome
/// disagree.
fn LoopState::step_domain_by_outcome(
  self : LoopState,
  domain : Domain,
  slot : String,
  transition : Move,
  blocked : Bool,
) -> LoopState {
  let domain_state = domain_state_at(
    self.domain_states,
    domain,
    "step_domain_by_outcome",
  )
  let new_domain_state = domain_state.step_by_outcome(
    self.model,
    slot,
    transition,
  )
  let history = self.history
  let mode = self.mode
  match new_domain_state.history.last() {
    Some(event) => {
      history.push(event)
      // Copied, not shared: see `copy_domain_states`. The state this step
      // came from has to stay readable as it was.
      let domain_states = copy_domain_states(self.model, self.domain_states)
      domain_states[domain.id] = new_domain_state
      let group_state = compute_group_state(self.model, domain_states)
      // Advance only when the subject actually went somewhere. Judged by
      // StepEffect rather than by the outcome label string: Blocked was the
      // only case checked before, so Undecided -- the table declining to
      // choose -- still advanced the cursor.
      let effect = StepEffect::of(transition)
      // `blocked` -- that the derived drive had no edge -- is a second,
      // independent reason not to advance: the cursor may be asked to advance
      // for a step that landed nowhere even when the table did have edges.
      //
      // The next domain comes from *this state's* model, not from whichever
      // model happens to be installed now.
      let next_domain = if effect.moved() && !blocked {
        self.model.next_domain(domain)
      } else {
        domain
      }
      {
        model: self.model,
        current: next_domain,
        domain_states,
        group_state,
        history,
        mode,
      }
    }
    None => {
      let group_state = compute_group_state(self.model, self.domain_states)
      {
        model: self.model,
        current: domain,
        domain_states: self.domain_states,
        group_state,
        history,
        mode,
      }
    }
  }
}

///|
/// Step by an explicit slot (for the API: let the caller choose the drive).
///
/// Preserves the current mode. A slot the table has no edge for records a Block
/// and leaves the cursor where it was, whatever the mode.
pub fn LoopState::step_with_slot(self : LoopState, slot : String) -> LoopState {
  self.step_domain_with(self.current, slot, false)
}

///|
/// The model's own candidates for a slot at a position, when it declines to
/// choose between them.
///
/// The open outcome carries them: the successors the model could have taken,
/// and the edge each one would take. This is the way out of a position the
/// machine cannot decide for itself. The machine may not invent a choice the
/// model declined to make -- that would be a lie about what the model says --
/// but a reader may make one, and this is the list they make it from.
pub fn open_candidates(position : String, slot : String) -> Array[Candidate] {
  open_candidates_of(current_model(), position, slot)
}

///|
/// The model's own candidates for a slot at a position, in a given model.
///
/// The loop asks its own model here, so a state running on somebody else's
/// machine offers that machine's candidates and not the installed one's.
fn open_candidates_of(
  model : Model,
  position : String,
  slot : String,
) -> Array[Candidate] {
  model.candidates(position, slot)
}

///|
/// The candidate whose target is the one named, if the model offers it.
///
/// Two names are accepted, because a client may hold either: the position's
/// **id** ("no-past"), which is what a model file and a URL carry, and the
/// position's **label** ("No Past"), which is what the panel shows a reader.
/// The two are not the same string -- an id is a slug -- so accepting only one
/// of them means a client that reads the id is refused by the very endpoint
/// that hands the id out.
///
/// The match ignores case, the way the slot names are matched: the reader asks
/// for what they were shown.
pub fn candidate_named(
  candidates : Array[Candidate],
  target : String,
) -> Candidate? {
  candidate_named_of(current_model(), candidates, target)
}

///|
/// The candidate whose target is the one named, in a given model.
///
/// The label is read from that model: the label of a position is the model's
/// word for it, and two machines may call the same position different things.
fn candidate_named_of(
  model : Model,
  candidates : Array[Candidate],
  target : String,
) -> Candidate? {
  let needle = target.to_lower()
  for candidate in candidates {
    if candidate.to.to_lower() == needle ||
      model.position_label(candidate.to).to_lower() == needle {
      return Some(candidate)
    }
  }
  None
}

///|
/// The names of the candidates, for an answer that has to list them.
pub fn candidate_names(candidates : Array[Candidate]) -> Array[String] {
  candidate_names_of(current_model(), candidates)
}

///|
/// The names of the candidates, in a given model.
fn candidate_names_of(
  model : Model,
  candidates : Array[Candidate],
) -> Array[String] {
  let names : Array[String] = []
  for candidate in candidates {
    names.push(model.position_label(candidate.to))
  }
  names
}

///|
/// Step to one of the successors the model offered and declined to choose.
///
/// The reader's choice, not the machine's: the model has already said which
/// positions are reachable from here, and this picks one of them. A target
/// the model does not offer is refused by the caller rather than guessed at.
pub fn LoopState::step_with_target(
  self : LoopState,
  slot : String,
  target : String,
) -> LoopState {
  let domain = self.current
  let domain_state = domain_state_at(
    self.domain_states,
    domain,
    "step_with_target",
  )
  let candidates = open_candidates_of(self.model, domain_state.position, slot)
  match candidate_named_of(self.model, candidates, target) {
    Some(candidate) => self.step_domain_with_candidate(domain, slot, candidate)
    None => self
  }
}

///|
fn event_from_outcome(
  model : Model,
  domain : Domain,
  slot : String,
  position : String,
  transition : Move,
) -> LoopEvent {
  let detail = outcome_detail(model, transition, position, slot)
  let kind = transition.kind()
  {
    domain,
    slot,
    outcome_label: model.outcome_label(kind),
    outcome_kind: kind,
    outcome_detail: detail,
    position_designation: model.position_label(position),
    position_label: model.position_label(position),
  }
}

///|
/// A human-readable account of what one step did.
///
/// The words are the model's: the edge's own name, the position's label, the
/// slot's designation, and the word the model calls the outcome -- including
/// the word it calls an undecided step, which used to be written out here as
/// "Undecided" and is now whatever the model says it is. A blocked step is
/// rebuilt from the position and the slot rather than reusing the model's
/// reason, because the model's reason is written in its own language and the
/// reader is reading this one.
fn outcome_detail(
  model : Model,
  transition : Move,
  at : String,
  slot : String,
) -> String {
  match transition {
    Moved(edge, to) => "\{edge} → \{model.position_label(to)}"
    Held(edge, to) => "\{edge} → held at \{model.position_label(to)}"
    Open(candidates) => {
      let parts = []
      for candidate in candidates {
        parts.push(
          "\{candidate.edge} → \{model.position_label(candidate.to)}",
        )
      }
      model.outcome_label("open") + ": " + parts.join(" / ")
    }
    Same(edges, to) =>
      "\{model.slot_designation(slot)} converge → \{model.position_label(to)} (\{edges.join(" / ")})"
    Block(_) =>
      "No road from \{model.position_label(at)} through \{model.slot_designation(slot)}"
  }
}

///|
/// Module-level loop state, stored in a one-element array. The binding itself
/// is immutable (MoonBit has no `let mut` at module scope), but the array
/// element is mutable in place — this is the standard MoonBit pattern for a
/// mutable global cell in a single-process server.
let g_loop_state : Array[LoopState] = [LoopState::new()]

///|
pub fn get_loop_state() -> LoopState {
  g_loop_state[0]
}

///|
pub fn step_loop() -> LoopState {
  let new_state = g_loop_state[0].step()
  g_loop_state[0] = new_state
  new_state
}

///|
/// Step with a caller-chosen slot instead of the domain's default drive.
pub fn step_loop_with_slot(slot : String) -> LoopState {
  let new_state = g_loop_state[0].step_with_slot(slot)
  g_loop_state[0] = new_state
  new_state
}

///|
/// Step to a caller-chosen successor, for the API: let the caller choose the
/// successor as well as the slot.
///
/// The way out of a position the transition table declined to decide. The
/// caller is answering a question the table asked, not inventing an edge.
pub fn step_loop_with_target(slot : String, target : String) -> LoopState {
  let new_state = g_loop_state[0].step_with_target(slot, target)
  g_loop_state[0] = new_state
  new_state
}

///|
/// The same loop state with the viewing cursor moved to `domain`.
///
/// Separate from `reset_to`, which rebuilds every state machine. This only
/// changes which domain is on screen, which is what "look at Knowledge next"
/// means. Exposed because the API has no other way to aim the cursor, and
/// because rebuilding from scratch to inspect a domain would destroy history.
pub fn LoopState::focus(self : LoopState, domain : Domain) -> LoopState {
  {
    model: self.model,
    current: domain,
    domain_states: self.domain_states,
    group_state: self.group_state,
    history: self.history,
    mode: self.mode,
  }
}

///|
/// Reset the loop to its initial state (Model, empty history).
pub fn reset_loop() -> LoopState {
  let fresh = LoopState::new()
  g_loop_state[0] = fresh
  fresh
}

///|
/// Reset the loop to start from the specified domain (empty history).
/// Each domain's state machine still starts at its own anchor position.
pub fn reset_to(domain : Domain) -> LoopState {
  let fresh = LoopState::new_from(domain)
  g_loop_state[0] = fresh
  fresh
}

///|
/// Get the current loop mode.
pub fn get_loop_mode() -> LoopMode {
  g_loop_state[0].mode
}

///|
/// The same state with a different loop mode.
///
/// The mode is a property of the *session* as much as of the live state, so
/// it is set on a value rather than on the module cell: a session that is
/// replayed has to be able to say which mode it was in, and that is a
/// question about the state, not about the process.
pub fn LoopState::with_mode(self : LoopState, mode : LoopMode) -> LoopState {
  {
    model: self.model,
    current: self.current,
    domain_states: self.domain_states,
    group_state: self.group_state,
    history: self.history,
    mode,
  }
}

///|
/// Install a loop state as the live one.
///
/// Used by the session layer: a session is put back in front of the user by
/// replaying its steps, and the result has to become the live state. Kept
/// apart from `reset_loop`, which builds a *fresh* state rather than
/// installing one.
pub fn set_loop_state(state : LoopState) -> Unit {
  g_loop_state[0] = state
}

///|
/// Set the loop mode (Structured or Free).
pub fn set_loop_mode(mode : LoopMode) -> LoopState {
  let new_state = g_loop_state[0].with_mode(mode)
  g_loop_state[0] = new_state
  new_state
}

///|
/// All eight drive slots with their English designation and gloss, for the
/// frontend.
///
/// pyroduct's `Slot::source()` is the Chinese source quote, and it is the one
/// field deliberately not carried here: the source layer exists to trace a
/// name back to the original Chinese text, so there is no English form of it,
/// and inventing one would break exactly the traceability it is for.
pub fn all_slots_info() -> Array[(String, String, String)] {
  let result = []
  for slot in current_model().slots {
    result.push((slot.id, slot.designation, slot.gloss))
  }
  result
}

///|
/// JSON shape for an exitable slot at the current position.
///
/// The outcome travels as two things: the label a reader sees, and the kind
/// the machine matches on. A client that has to recognise the *word*
/// "Undecided" to know that the table declined to choose is a client that
/// breaks the moment the model is renamed.
fn open_slot_json(model : Model, position : String, slot : String) -> Json {
  let transition = model.step(position, slot)
  let targets = []
  match transition {
    Moved(_, to) => targets.push(model.position_label(to))
    Held(_, to) => targets.push(model.position_label(to))
    Same(_, to) => targets.push(model.position_label(to))
    Open(candidates) =>
      for candidate in candidates {
        targets.push(model.position_label(candidate.to))
      }
    Block(_) => ()
  }
  let item : Json = {
    "name": slot,
    "designation": model.slot_designation(slot),
    "outcome": model.outcome_label(transition.kind()),
    "outcome_kind": transition.kind(),
    "targets": targets_json(targets),
  }
  item
}

///|
/// Lift a list of strings into a `Json` array.
///
/// Measured, not assumed: `Array[Json]` spreads into `Json`, `Array[String]`
/// does not, and pushing a `String` into an `Array[Json]` is rejected with an
/// `Expr Type Mismatch`. The one form that works is a one-element array
/// *literal* per element, collected and spread.
fn targets_json(names : Array[String]) -> Json {
  let items : Array[Json] = []
  for name in names {
    // A one-element array literal is the form that coerces to `Json`; the
    // element itself stays a `String`.
    items.push([name])
  }
  [..items]
}

///|
/// The same eight slots as `all_slots_info`, in the JSON shape the frontend
/// decodes. Shared by `GET /api/loop/slots` and by the `slots` field of the
/// status response, so the two can never drift apart.
pub fn slots_json() -> Json {
  let items = []
  for (english, designation, gloss) in all_slots_info() {
    let item : Json = {
      "name": english,
      "designation": designation,
      "gloss": gloss,
    }
    items.push(item)
  }
  [..items]
}

///|
/// JSON shape for the loop status API.
///
/// `current_position` and `drive_slot` are read from the domain's **actual**
/// position. They used to be read from `Domain::position`, the static anchor,
/// which meant a domain that had genuinely moved still reported its starting
/// position -- the status contradicted the history sitting next to it in the
/// same response. `open_slots` is the replacement for the old hard-coded slot:
/// it is what the table offers here, so a caller never has to guess.
pub fn LoopState::to_json(self : LoopState) -> Json {
  let model = self.model
  let current_ds = domain_state_at(
    self.domain_states,
    self.current,
    "to_json_current",
  )
  let current_pos = current_ds.position
  let history_json = []
  for e in self.history {
    let item : Json = {
      "domain": e.domain.letter(),
      "slot": model.slot_designation(e.slot),
      "outcome": e.outcome_label,
      "outcome_kind": e.outcome_kind,
      "detail": e.outcome_detail,
      "position": e.position_designation,
      "position_label": e.position_label,
    }
    history_json.push(item)
  }
  // Build per-domain states
  let domain_states_json = []
  for domain in model.domains {
    let ds = domain_state_at(self.domain_states, domain, "to_json_domains")
    let item : Json = {
      "domain": domain.letter(),
      "title": domain.title(),
      "position": model.position_label(ds.position),
      "position_label": model.position_label(ds.position),
      "history_length": ds.history.length(),
      "drivable": drive_slot_of(model, ds.position) is Some(_),
      "at_anchor": ds.position == domain.position(),
    }
    domain_states_json.push(item)
  }
  let open_slots_json = []
  for slot in exitable_slots_of(model, current_pos) {
    open_slots_json.push(open_slot_json(model, current_pos, slot))
  }
  {
    "current_domain": self.current.letter(),
    "current_title": self.current.title(),
    "current_position": model.position_label(current_pos),
    "current_position_label": model.position_label(current_pos),
    "current_gloss": model.position_gloss(current_pos),
    "next_domain": self.model.next_domain(self.current).letter(),
    // Empty string when the model offers no road out of here. An empty
    // drive slot is a true statement; a plausible-looking slot that always
    // reports No-way is not.
    "drive_slot": match drive_slot_of(model, current_pos) {
      Some(slot) => model.slot_designation(slot)
      None => ""
    },
    "drive_slot_name": match drive_slot_of(model, current_pos) {
      Some(slot) => slot
      None => ""
    },
    "blocked": exitable_slots_of(model, current_pos).length() == 0,
    "undecided": is_undecided_of(model, current_pos),
    "open_slots": [..open_slots_json],
    // The full eight-slot vocabulary travels with the status, so one request
    // is enough to render the whole loop panel. It used to be a second
    // endpoint the client had to fetch afterwards, which made the panel depend
    // on a three-step request chain: pages -> slots -> status. That chain
    // stalled intermittently after the second step -- the request reached the
    // server and answered 200, but the reply never reached `update`, with
    // nothing logged anywhere. Folding the vocabulary in here removes the step
    // that stalled rather than working around it.
    "slots": slots_json(),
    "history_length": self.history.length(),
    "history": [..history_json],
    "domain_states": [..domain_states_json],
    "group_state": self.group_state.en_designation(),
    "group_state_gloss": self.group_state.en_gloss(),
    "mode": match self.mode {
      Structured => "structured"
      Free => "free"
    },
    "mode_designation": self.mode.designation(),
    "mode_gloss": self.mode.gloss(),
  }
}
