///| MAKED Loop: five domains as a pyroduct-driven state cycle.
///
/// The five MAKED domains (M/D/E/A/K) are mapped to five positions on pyroduct's
/// subject state machine. Navigation around the ring is a `step(position, slot)`
/// call; the Outcome (Moved / Held / Open / Same / Block) is recorded in an
/// append-only history so the cycle is observable, not just navigable.
///
/// Mapping rationale (each domain names the structural relation the position
/// denotes, not the domain's content):
///
///   M Model      → Standing  立位  the model stands, one foot in past one in future
///   D Data       → Encounter 相遇  the model meets the other (data as other)
///   E Experience → Honor     受赏  experience absorbed as reward from the idol
///   A Attack     → Evil      受挫  attack as the hard cold thing that shrinks the horizon
///   K Knowledge  → Discipline 修习  knowledge distilled through enduring and removing reefs
///
/// The ring order M → D → E → A → K → M is preserved; each step names the
/// drive slot that *would* move the subject from the current position toward
/// the next domain. Whether the step actually moves, holds, or blocks is
/// answered by pyroduct's migration table -- the loop never invents a move.

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
    Structured => "结构"
    Free => "自由"
  }
}

///|
pub fn LoopMode::gloss(self : LoopMode) -> String {
  match self {
    Structured => "遵循环序 M→D→E→A→K，每域使用驱动槽"
    Free => "任意槽驱动，探索状态空间"
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
/// The drive slot that names the structural relation between this domain and
/// the next one in the ring. The slot is the *kind* of push that would move
/// the subject from the current position toward the next domain's position.
pub fn Domain::slot_to_next(self : Domain) -> @sm.Slot {
  match self {
    // Standing → Encounter: the model meets data as other → CoBeing
    Model => @sm.CoBeing
    // Encounter → Honor: experience absorbed as feedback → Feedback
    Data => @sm.Feedback
    // Honor → Evil: attack as unconcealment of遮蔽 → Unveil
    Experience => @sm.Unveil
    // Evil → Discipline: attack's residue held and沉淀 → Hold
    Attack => @sm.Hold
    // Discipline → Standing: knowledge re-orients the model → Orientation
    Knowledge => @sm.Orientation
  }
}

///|
/// Parse a slot designation (两字定名) back into a Slot value.
/// Returns None if the string does not match any slot.
pub fn slot_from_designation(s : String) -> @sm.Slot? {
  match s {
    "处境" => Some(@sm.Occasion)
    "取向" => Some(@sm.Orientation)
    "先行" => Some(@sm.Antecedent)
    "行动" => Some(@sm.Act)
    "反馈" => Some(@sm.Feedback)
    "持存" => Some(@sm.Hold)
    "共在" => Some(@sm.CoBeing)
    "揭蔽" => Some(@sm.Unveil)
    _ => None
  }
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
  outcome_label : String // 迁/守/未定/同归/无路
  outcome_detail : String // human-readable detail
  position_designation : String // 两字定名
  position_label : String // 原文名
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
/// Take one step: record the current position × slot outcome, advance to the
/// next domain. The outcome comes from pyroduct's migration table -- the loop
/// never invents a move.
///
/// In Structured mode, always advances to the next domain (ring order).
/// In Free mode, only advances if the outcome is not Block ("无路").
pub fn LoopState::step(self : LoopState) -> LoopState {
  let domain = self.current
  let domain_state = self.domain_states[domain]
  let slot = domain.slot_to_next()
  let new_domain_state = domain_state.step(slot)
  let history = self.history
  let mode = self.mode
  // Get the last event from the new domain state's history
  match new_domain_state.history.last() {
    Some(event) => {
      history.push(event)
      let domain_states = self.domain_states
      domain_states[domain] = new_domain_state
      let group_state = compute_group_state(domain_states)
      // In Structured mode, always advance. In Free mode, only advance if not Block.
      let next_domain = match mode {
        Structured => domain.next()
        Free =>
          if event.outcome_label == "无路" {
            domain
          } else {
            domain.next()
          }
      }
      { current: next_domain, domain_states, group_state, history, mode, }
    }
    None => {
      let group_state = compute_group_state(self.domain_states)
      // This should never happen since step() always adds an event
      {
        current: domain.next(),
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
/// Preserves the current mode (Structured/Free).
pub fn LoopState::step_with_slot(
  self : LoopState,
  slot : @sm.Slot,
) -> LoopState {
  let domain = self.current
  let domain_state = self.domain_states[domain]
  let new_domain_state = domain_state.step(slot)
  let history = self.history
  let mode = self.mode
  // Get the last event from the new domain state's history
  match new_domain_state.history.last() {
    Some(event) => {
      history.push(event)
      let domain_states = self.domain_states
      domain_states[domain] = new_domain_state
      let group_state = compute_group_state(domain_states)
      // Only advance if the outcome is not Block ("无路")
      let next_domain = if event.outcome_label == "无路" {
        domain
      } else {
        domain.next()
      }
      { current: next_domain, domain_states, group_state, history, mode, }
    }
    None => {
      let group_state = compute_group_state(self.domain_states)
      // This should never happen since step() always adds an event
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
fn event_from_outcome(
  domain : Domain,
  slot : @sm.Slot,
  position : @sm.SubjectState,
  outcome : @sm.Outcome,
) -> LoopEvent {
  let detail = outcome_detail(outcome)
  {
    domain,
    slot,
    outcome_label: outcome.label(),
    outcome_detail: detail,
    position_designation: position.designation(),
    position_label: position.label(),
  }
}

///|
fn outcome_detail(outcome : @sm.Outcome) -> String {
  match outcome {
    @sm.Moved(tr, to) =>
      "\{tr.label()} → \{to.designation()}（\{to.label()}）"
    @sm.Held(tr, s) =>
      "\{tr.label()} → 守于 \{s.designation()}（\{s.label()}）"
    @sm.Open(cands) => {
      let parts = []
      for c in cands {
        parts.push("\{c.0.label()} → \{c.1.designation()}")
      }
      "未定: " + parts.join(" / ")
    }
    @sm.Same(sl, named, to) => {
      let names = []
      for tr in named {
        names.push(tr.label())
      }
      "\{sl.designation()} 同归 → \{to.designation()}（\{names.join(" / ")}）"
    }
    @sm.Block(msg) => msg
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
/// Set the loop mode (Structured or Free).
pub fn set_loop_mode(mode : LoopMode) -> LoopState {
  let current = g_loop_state[0]
  let new_state = {
    current: current.current,
    domain_states: current.domain_states,
    group_state: current.group_state,
    history: current.history,
    mode,
  }
  g_loop_state[0] = new_state
  new_state
}

///|
/// All eight drive slots with their designation and gloss, for the frontend.
pub fn all_slots_info() -> Array[(String, String, String, String)] {
  let slots = @sm.all_slots()
  let result = []
  for slot in slots {
    result.push(
      (slot_english_name(slot), slot.designation(), slot.gloss(), slot.source()),
    )
  }
  result
}

///|
/// JSON shape for the loop status API.
pub fn LoopState::to_json(self : LoopState) -> Json {
  let current_pos = self.current.position()
  let history_json = []
  for e in self.history {
    let item : Json = {
      "domain": e.domain.letter(),
      "slot": e.slot.designation(),
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
      "position": ds.position.designation(),
      "position_label": ds.position.label(),
      "history_length": ds.history.length(),
    }
    domain_states_json.push(item)
  }
  {
    "current_domain": self.current.letter(),
    "current_title": self.current.title(),
    "current_position": current_pos.designation(),
    "current_position_label": current_pos.label(),
    "current_gloss": current_pos.gloss(),
    "next_domain": self.current.next().letter(),
    "drive_slot": self.current.slot_to_next().designation(),
    "history_length": self.history.length(),
    "history": [..history_json],
    "domain_states": [..domain_states_json],
    "group_state": self.group_state.designation(),
    "group_state_gloss": self.group_state.gloss(),
    "mode": match self.mode {
      Structured => "structured"
      Free => "free"
    },
    "mode_designation": self.mode.designation(),
    "mode_gloss": self.mode.gloss(),
  }
}
