///| MAKED Loop: five domains as a pyroduct-driven state cycle.
///
/// The five MAKED domains (M/D/E/A/K) are anchors on pyroduct's subject state
/// machine. Each domain carries its own position and its own history, so the
/// five evolve independently rather than as one ring. Navigation is a
/// `step(position, slot)` call; the Outcome (Moved / Held / Open / Same /
/// Block) is recorded in an append-only history so the cycle is observable,
/// not just navigable.
///
/// Mapping (each domain names the structural relation the position denotes,
/// not the domain's content):
///
///   M Model      → Standing   the model stands, one foot in past one in future
///   D Data       → Encounter  the model meets the other (data as other)
///   E Experience → Honor      experience absorbed as reward from the idol
///   A Attack     → Evil       attack as the hard cold thing that shrinks the horizon
///   K Knowledge  → Discipline knowledge distilled through enduring and removing reefs
///
/// **The drive slot is read from pyroduct's table, never chosen by meaning.**
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
/// The five domains, in ring order.
pub(all) enum Domain {
  Model // M
  Data // D
  Experience // E
  Attack // A
  Knowledge // K
} derive(Eq, Debug, Hash)

///|
pub extend Domain with Eq::{not_equal, equal}

///|
pub extend Domain with Debug::{to_repr}

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
pub fn StepEffect::of(outcome : @sm.Outcome) -> StepEffect {
  match outcome {
    @sm.Moved(_, _) => Advanced
    @sm.Held(_, _) => Advanced
    @sm.Same(_, _, _) => Advanced
    @sm.Open(_) => Undecided
    @sm.Block(_) => Blocked
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
pub fn Domain::letter(self : Domain) -> String {
  match self {
    Model => "M"
    Data => "D"
    Experience => "E"
    Attack => "A"
    Knowledge => "K"
  }
}

///|
pub fn Domain::title(self : Domain) -> String {
  match self {
    Model => "Model"
    Data => "Data"
    Experience => "Experience"
    Attack => "Attack"
    Knowledge => "Knowledge"
  }
}

///|
pub fn Domain::role(self : Domain) -> String {
  match self {
    Model => "the model formulator"
    Data => "the data turbine"
    Experience => "the experience absorber"
    Attack => "the attack generator"
    Knowledge => "the knowledge distiller"
  }
}

///|
/// The slots that pyroduct's table says can actually move `state`.
///
/// Read from the table rather than assumed. Of the 34 x 8 = 272 combinations,
/// 228 are Block -- a slot is only usable where the table has a real edge, so
/// any slot list hard-coded from the *meaning* of a domain will eventually name
/// a combination the table has no edge for. That is not hypothetical: the
/// mapping this replaced named five slots, and all five were Block.
pub fn exitable_slots(state : @sm.SubjectState) -> Array[@sm.Slot] {
  let usable = []
  for slot in @sm.all_slots() {
    if @sm.exitable(state, slot) {
      usable.push(slot)
    }
  }
  usable
}

///|
/// The slot to drive `state` with, chosen from the table rather than by
/// semantics.
///
/// Preference order, and why:
///
///   1. a slot whose outcome is `Moved` -- a domain would otherwise sit on a
///      `Same` self-edge while a real move sits one slot later;
///   2. otherwise the first exitable slot in canonical order, which covers
///      `Held` and `Same` (Converge): both are legitimate receipts that keep
///      the subject where it is, so taking one is not inventing anything.
///
/// Returns None when the position has no outgoing edge at all -- a real gap in
/// the table. The caller must report that, never paper over it.
pub fn drive_slot(state : @sm.SubjectState) -> @sm.Slot? {
  let moving = []
  let staying = []
  for slot in exitable_slots(state) {
    match @sm.step(state, slot) {
      @sm.Moved(_, _) => moving.push(slot)
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
/// Whether the table offers several successors from `state` and refuses to
/// pick between them (`Open` / Undecided). pyroduct's own position is that a
/// gap and an undecided branch are both legitimate receipts: better to stop
/// where you are than to invent a next step. The loop takes the same position
/// -- it surfaces the candidates and waits.
pub fn is_undecided(state : @sm.SubjectState) -> Bool {
  let usable = exitable_slots(state)
  if usable.length() == 0 {
    return false
  }
  for slot in usable {
    match @sm.step(state, slot) {
      @sm.Open(_) => return true
      _ => ()
    }
  }
  false
}

///|
/// The successor positions reachable from `state` in at most `depth` steps,
/// with pyroduct picking no slot for the subject: `after_open` is the model's
/// own answer to "what could happen next", as opposed to `expand`, which
/// requires the caller to name the slot sequence in advance.
///
/// Returns `Array[(SubjectState, Int)]` exactly as pyroduct does -- state and
/// the number of steps that reach it.
pub fn continuations(
  state : @sm.SubjectState,
  depth : Int32,
) -> Array[(@sm.SubjectState, Int32)] {
  let usable = exitable_slots(state)
  // `SubjectState` derives Eq but not Hash, so a Map keyed by it will not
  // compile, and the element type has to be named for the tuple fields to
  // resolve. Dedup with a linear scan instead: the candidate list is at most a
  // few dozen entries, and this runs once per API call, not per step.
  let seen : Array[(@sm.SubjectState, Int32)] = []
  let out : Array[(@sm.SubjectState, Int32)] = []
  for slot in usable {
    for pair in @sm.after_open(state, slot, depth) {
      let (next, steps) = pair
      let mut index = -1
      let mut at = 0
      for prev in seen {
        if prev.0 == next {
          index = at
        }
        at += 1
      }
      if index == -1 {
        seen.push((next, steps))
        out.push((next, steps))
      } else if steps < out[index].1 {
        // Same position by a shorter route. Without this, Opening appears twice
        // from Encounter -- one step via CoBeing, two via Holding -- which reads
        // as two distinct futures when it is one position reached two ways. The
        // slot-by-slot view is where alternative routes belong.
        seen[index] = (next, steps)
        out[index] = (next, steps)
      }
    }
  }
  out
}

///|
/// Parse a slot designation back into a Slot value.
///
/// Accepts either the English designation as displayed ("Co-being",
/// "Situation") or the URL-safe name ("cobeing", "occasion"),
/// case-insensitively. Returns None if the string does not match any slot.
///
/// The designation table is read back out of pyroduct instead of being copied
/// into MAKED. The copy went stale the moment pyroduct renamed two of the
/// eight -- 0.1.32 moved "Occasion" to "Situation" and "Anticipation" to
/// "Antecedent" -- and the symptom was a parser that had quietly stopped
/// accepting two of the words MAKED's own API was advertising. A rename in the
/// dependency is now a rename here, with nothing to keep in sync.
pub fn slot_from_designation(s : String) -> @sm.Slot? {
  let needle = s.to_lower()
  for slot in @sm.all_slots() {
    if slot.en_designation().to_lower() == needle ||
      slot_english_name(slot).to_lower() == needle {
      return Some(slot)
    }
  }
  None
}

///|
/// English name for a slot, for use in URL-safe API paths.
pub fn slot_english_name(slot : @sm.Slot) -> String {
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
/// Parse a slot from its English name.
pub fn slot_from_english(s : String) -> @sm.Slot? {
  match s {
    "occasion" => Some(@sm.Occasion)
    "orientation" => Some(@sm.Orientation)
    "antecedent" => Some(@sm.Antecedent)
    "act" => Some(@sm.Act)
    "feedback" => Some(@sm.Feedback)
    "hold" => Some(@sm.Hold)
    "cobeing" => Some(@sm.CoBeing)
    "unveil" => Some(@sm.Unveil)
    _ => None
  }
}

///|
/// Domain → pyroduct position.
pub fn Domain::position(self : Domain) -> @sm.SubjectState {
  match self {
    Model => @sm.Standing
    Data => @sm.Encounter
    Experience => @sm.Honor
    Attack => @sm.Evil
    Knowledge => @sm.Discipline
  }
}

///|
/// pyroduct position → Domain (inverse of `position`; returns None for the 29
/// positions that are not MAKED domain anchors).
pub fn position_to_domain(state : @sm.SubjectState) -> Domain? {
  match state {
    @sm.Standing => Some(Model)
    @sm.Encounter => Some(Data)
    @sm.Honor => Some(Experience)
    @sm.Evil => Some(Attack)
    @sm.Discipline => Some(Knowledge)
    _ => None
  }
}

///|
/// The next domain in the ring (M→D→E→A→K→M).
pub fn Domain::next(self : Domain) -> Domain {
  match self {
    Model => Data
    Data => Experience
    Experience => Attack
    Attack => Knowledge
    Knowledge => Model
  }
}

///|
/// Parse a domain from its letter (M, D, E, A, K).
pub fn domain_from_letter(s : String) -> Domain? {
  match s {
    "M" => Some(Model)
    "D" => Some(Data)
    "E" => Some(Experience)
    "A" => Some(Attack)
    "K" => Some(Knowledge)
    _ => None
  }
}

///|
/// Parse a domain from its English name (case-insensitive).
pub fn domain_from_english(s : String) -> Domain? {
  // Simple lowercase conversion for ASCII
  let lower = {
    let result = []
    for i in 0..<s.length() {
      let c = s[i]
      let code = c.to_int()
      if code >= 65 && code <= 90 {
        result.push((code + 32).to_uint16())
      } else {
        result.push(c)
      }
    }
    let bytes : Array[UInt16] = result
    bytes
    .map(fn(b) {
      match b.to_char() {
        Some(c) => c.to_string()
        None => ""
      }
    })
    .join("")
  }
  match lower {
    "model" => Some(Model)
    "data" => Some(Data)
    "experience" => Some(Experience)
    "attack" => Some(Attack)
    "knowledge" => Some(Knowledge)
    _ => None
  }
}

///|
/// All five domains in ring order.
pub fn ring_domains_loop() -> Array[Domain] {
  [Model, Data, Experience, Attack, Knowledge]
}

///|
/// One recorded step in the loop history.
pub(all) struct LoopEvent {
  domain : Domain
  slot : @sm.Slot
  outcome_label : String // Moved/Held/Undecided/Converge/No-way
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
/// on the pyroduct state space and its own history of events.
pub(all) struct DomainState {
  domain : Domain
  position : @sm.SubjectState
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
pub fn DomainState::step(self : DomainState, slot : @sm.Slot) -> DomainState {
  let outcome = @sm.step(self.position, slot)
  let event = event_from_outcome(self.domain, slot, self.position, outcome)
  let history = self.history
  history.push(event)
  // Update position if the step landed somewhere
  let new_position = match outcome.landing() {
    Some(landing) => landing
    None => self.position
  }
  { domain: self.domain, position: new_position, history, }
}

///|
/// The loop state: current domain + per-domain independent state machines + group state + mode.
pub(all) struct LoopState {
  current : Domain
  domain_states : Map[Domain, DomainState]
  group_state : @group.GroupState
  history : Array[LoopEvent]
  mode : LoopMode
} derive(Eq)

///|
pub extend LoopState with Eq::{not_equal, equal}

///|
pub fn LoopState::new() -> LoopState {
  let domain_states = Map([], capacity=8)
  for domain in ring_domains_loop() {
    domain_states[domain] = DomainState::new(domain)
  }
  {
    current: Model,
    domain_states,
    group_state: @group.Scattered,
    history: [],
    mode: Structured,
  }
}

///|
/// Create a new loop state starting from the specified domain.
/// Each domain's state machine still starts at its own anchor position;
/// only the `current` pointer changes.
pub fn LoopState::new_from(domain : Domain) -> LoopState {
  let domain_states = Map([], capacity=8)
  for d in ring_domains_loop() {
    domain_states[d] = DomainState::new(d)
  }
  {
    current: domain,
    domain_states,
    group_state: @group.Scattered,
    history: [],
    mode: Structured,
  }
}

///|
/// Create a new loop state in the specified mode.
pub fn LoopState::new_with_mode(mode : LoopMode) -> LoopState {
  let domain_states = Map([], capacity=8)
  for domain in ring_domains_loop() {
    domain_states[domain] = DomainState::new(domain)
  }
  {
    current: Model,
    domain_states,
    group_state: @group.Scattered,
    history: [],
    mode,
  }
}

///|
/// Get the state of a specific domain.
pub fn LoopState::domain_state(
  self : LoopState,
  domain : Domain,
) -> DomainState {
  self.domain_states[domain]
}

///|
/// Compute the group state based on the configuration of all domain states.
/// The group emerges from how the domains relate to each other.
fn compute_group_state(
  domain_states : Map[Domain, DomainState],
) -> @group.GroupState {
  // Count how many domains have moved from their initial positions
  let mut moved_count = 0
  for domain in ring_domains_loop() {
    let ds = domain_states[domain]
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
fn copy_domain_states(
  source : Map[Domain, DomainState],
) -> Map[Domain, DomainState] {
  let copy = Map([], capacity=8)
  for domain in ring_domains_loop() {
    match source.get(domain) {
      Some(state) => copy[domain] = state
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
  let domain_state = self.domain_states[domain]
  // Derived once: the table is the authority, and asking it twice could in
  // principle answer differently mid-call.
  let chosen = drive_slot(domain_state.position)
  let blocked = chosen is None
  self.step_domain_with(
    domain,
    match chosen {
      Some(slot) => slot
      // No road out of here. Record the gap honestly and stay put,
      // rather than drive a slot the table does not have.
      None => @sm.Hold
    },
    blocked,
  )
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
  slot : @sm.Slot,
  blocked : Bool,
) -> LoopState {
  let domain_state = self.domain_states[domain]
  let new_domain_state = domain_state.step(slot)
  let history = self.history
  let mode = self.mode
  match new_domain_state.history.last() {
    Some(event) => {
      history.push(event)
      // Copied, not shared: see `copy_domain_states`. The state this step
      // came from has to stay readable as it was.
      let domain_states = copy_domain_states(self.domain_states)
      domain_states[domain] = new_domain_state
      let group_state = compute_group_state(domain_states)
      // Advance only when the subject actually went somewhere. Judged by
      // StepEffect rather than by the outcome label string: Blocked was the
      // only case checked before, so Undecided -- the table declining to
      // choose -- still advanced the cursor.
      let effect = StepEffect::of(@sm.step(domain_state.position, slot))
      // `blocked` -- that the derived drive had no edge -- is a second,
      // independent reason not to advance: the cursor may be asked to advance
      // for a step that landed nowhere even when the table did have edges.
      let next_domain = if effect.moved() && !blocked {
        domain.next()
      } else {
        domain
      }
      { current: next_domain, domain_states, group_state, history, mode, }
    }
    None => {
      let group_state = compute_group_state(self.domain_states)
      {
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
pub fn LoopState::step_with_slot(
  self : LoopState,
  slot : @sm.Slot,
) -> LoopState {
  self.step_domain_with(self.current, slot, false)
}

///|
fn event_from_outcome(
  domain : Domain,
  slot : @sm.Slot,
  position : @sm.SubjectState,
  outcome : @sm.Outcome,
) -> LoopEvent {
  let detail = outcome_detail(outcome, position, slot)
  {
    domain,
    slot,
    outcome_label: outcome.en_label(),
    outcome_detail: detail,
    position_designation: position.en_label(),
    position_label: position.en_label(),
  }
}

///|
/// A human-readable account of what one step did.
///
/// `Block` carries a message that pyroduct writes in Chinese, so it is rebuilt
/// here from the slot and position, which is both English and more precise than
/// reusing the model's own wording.
fn outcome_detail(
  outcome : @sm.Outcome,
  at : @sm.SubjectState,
  slot : @sm.Slot,
) -> String {
  match outcome {
    @sm.Moved(tr, to) => "\{tr.en_label()} → \{to.en_label()}"
    @sm.Held(tr, s) => "\{tr.en_label()} → held at \{s.en_label()}"
    @sm.Open(cands) => {
      let parts = []
      for c in cands {
        parts.push("\{c.0.en_label()} → \{c.1.en_label()}")
      }
      "Undecided: " + parts.join(" / ")
    }
    @sm.Same(sl, named, to) => {
      let names = []
      for tr in named {
        names.push(tr.en_label())
      }
      "\{sl.en_designation()} converge → \{to.en_label()} (\{names.join(" / ")})"
    }
    @sm.Block(_) =>
      "No road from \{at.en_label()} through \{slot.en_designation()}"
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
pub fn step_loop_with_slot(slot : @sm.Slot) -> LoopState {
  let new_state = g_loop_state[0].step_with_slot(slot)
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
  let slots = @sm.all_slots()
  let result = []
  for slot in slots {
    result.push(
      (slot_english_name(slot), slot.en_designation(), slot.en_gloss()),
    )
  }
  result
}

///|
/// JSON shape for an exitable slot at the current position.
fn open_slot_json(state : @sm.SubjectState, slot : @sm.Slot) -> Json {
  let outcome = @sm.step(state, slot)
  let targets = []
  match outcome {
    @sm.Moved(_, to) => targets.push(to.en_label())
    @sm.Held(_, to) => targets.push(to.en_label())
    @sm.Same(_, _, to) => targets.push(to.en_label())
    @sm.Open(cands) =>
      for c in cands {
        targets.push(c.1.en_label())
      }
    @sm.Block(_) => ()
  }
  let item : Json = {
    "name": slot_english_name(slot),
    "designation": slot.en_designation(),
    "outcome": outcome.en_label(),
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
  let current_ds = self.domain_states[self.current]
  let current_pos = current_ds.position
  let history_json = []
  for e in self.history {
    let item : Json = {
      "domain": e.domain.letter(),
      "slot": e.slot.en_designation(),
      "outcome": e.outcome_label,
      "detail": e.outcome_detail,
      "position": e.position_designation,
      "position_label": e.position_label,
    }
    history_json.push(item)
  }
  // Build per-domain states
  let domain_states_json = []
  for domain in ring_domains_loop() {
    let ds = self.domain_states[domain]
    let item : Json = {
      "domain": domain.letter(),
      "title": domain.title(),
      "position": ds.position.en_label(),
      "position_label": ds.position.en_label(),
      "history_length": ds.history.length(),
      "drivable": drive_slot(ds.position) is Some(_),
      "at_anchor": ds.position == domain.position(),
    }
    domain_states_json.push(item)
  }
  let open_slots_json = []
  for slot in exitable_slots(current_pos) {
    open_slots_json.push(open_slot_json(current_pos, slot))
  }
  {
    "current_domain": self.current.letter(),
    "current_title": self.current.title(),
    "current_position": current_pos.en_label(),
    "current_position_label": current_pos.en_label(),
    "current_gloss": current_pos.en_gloss(),
    "next_domain": self.current.next().letter(),
    // Empty string when the table offers no road out of here. An empty
    // drive slot is a true statement; a plausible-looking slot that always
    // reports No-way is not.
    "drive_slot": match drive_slot(current_pos) {
      Some(slot) => slot.en_designation()
      None => ""
    },
    "drive_slot_name": match drive_slot(current_pos) {
      Some(slot) => slot_english_name(slot)
      None => ""
    },
    "blocked": exitable_slots(current_pos).length() == 0,
    "undecided": is_undecided(current_pos),
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
