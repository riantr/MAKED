///| The society panel: the collective, and the moves it can make.
///
/// MAKED has three layers and had two. The subject layer is the ring of five
/// domains -- the one the loop panel drives. The society layer is the
/// collective: a lifeworld, a claim, a consensus, a norm, and the moves that
/// take it from one to another.
///
/// The panel is deliberately shaped like the rest of MAKED's panels, and that
/// is not a matter of taste. The subject machine answers with four shapes --
/// a move, a hold, an opening, a block -- and so does this one, so the
/// frontend reads one vocabulary for both and a reader who has learned one
/// does not have to learn another.
///
/// Two things this panel must not do:
///
///   - It must not show a move as if it happened when it did not. The
///     collective has no drive slots and no blocked combinations: the reader
///     chooses the move and the machine answers. Every answer says what
///     happened, including "there is no such move from here".
///   - It must not show a position with no name. The machine has thirteen
///     positions and the vocabulary file has words for them; when the file
///     falls behind the machine, the panel says so in as many words rather
///     than rendering a blank.
///
/// The decoding lives here rather than in the markup, because a panel that
/// reads a field with the wrong accessor is a panel that shows a fallback
/// and looks fine doing it.

///|
/// One position of the society machine, as the panel reads it.
pub(all) struct SocietyPositionSummary {
  /// The machine's own name for the position.
  id : String
  /// The name as the reader should see it.
  label : String
  /// A sentence saying what the position means.
  gloss : String
  /// The phase the position belongs to, by the machine's name.
  phase : String
  /// The name of that phase as the reader should see it.
  phase_label : String
}

///|
/// One move available from where the collective stands.
pub(all) struct SocietyMoveSummary {
  /// The machine's own name for the move.
  trigger : String
  /// The name of the move as the reader should see it.
  trigger_label : String
  /// Where the move lands, by the machine's name.
  to : String
  /// Where the move lands, as the reader should see it.
  to_label : String
}

///|
/// One transition of the society machine.
pub(all) struct SocietyTransitionSummary {
  from : String
  trigger : String
  trigger_label : String
  to : String
  to_label : String
}

///|
/// The whole collective, as the panel reads it.
pub(all) struct SocietySummary {
  /// Where the collective stands, by the machine's name.
  state : String
  /// Where the collective stands, as the reader should see it.
  state_label : String
  /// A sentence saying what that position means.
  state_gloss : String
  /// The phase the collective is in, by the machine's name.
  phase : String
  /// Where the collective stood before the last move.
  from : String
  /// Where the collective stood before the last move, in words.
  from_label : String
  /// What the last move did: "moved", "held", "open" or "block". Empty when
  /// no move has been taken yet.
  kind : String
  /// Why the collective did not go where the reader asked, in words.
  reason : String
  /// Every position the machine has.
  positions : Array[SocietyPositionSummary]
  /// Every move the machine has.
  transitions : Array[SocietyTransitionSummary]
  /// The moves available from where the collective stands.
  moves : Array[SocietyMoveSummary]
  /// The names the machine has and the vocabulary does not.
  gaps : Array[String]
  /// The file the words came from; empty when they are the built-in ones.
  path : String
}

///|
/// The positions of the machine, as the panel reads them.
fn society_positions(json : Json) -> Array[SocietyPositionSummary] {
  let out : Array[SocietyPositionSummary] = []
  match field(json, "positions") {
    Some(Array(items)) =>
      for item in items {
        out.push({
          id: get_string(item, "id", ""),
          label: get_string(item, "label", ""),
          gloss: get_string(item, "gloss", ""),
          phase: get_string(item, "phase", ""),
          phase_label: get_string(item, "phase_label", ""),
        })
      }
    _ => ()
  }
  out
}

///|
/// The moves available from where the collective stands.
fn society_moves(json : Json) -> Array[SocietyMoveSummary] {
  let out : Array[SocietyMoveSummary] = []
  match field(json, "moves") {
    Some(Array(items)) =>
      for item in items {
        out.push({
          trigger: get_string(item, "trigger", ""),
          trigger_label: get_string(item, "trigger_label", ""),
          to: get_string(item, "to", ""),
          to_label: get_string(item, "to_label", ""),
        })
      }
    _ => ()
  }
  out
}

///|
/// Every move the machine has.
fn society_transitions(json : Json) -> Array[SocietyTransitionSummary] {
  let out : Array[SocietyTransitionSummary] = []
  match field(json, "transitions") {
    Some(Array(items)) =>
      for item in items {
        out.push({
          from: get_string(item, "from", ""),
          trigger: get_string(item, "trigger", ""),
          trigger_label: get_string(item, "trigger_label", ""),
          to: get_string(item, "to", ""),
          to_label: get_string(item, "to_label", ""),
        })
      }
    _ => ()
  }
  out
}

///|
/// Decode the backend's society payload.
///
/// Every field has a fallback, because the backend is the only writer and a
/// missing field is a backend change, not a reason for the page to die.
pub fn society_summary(json : Json) -> SocietySummary {
  {
    state: get_string(json, "state", ""),
    state_label: labelled_or(json, "state_label", "state"),
    state_gloss: get_string(json, "state_gloss", ""),
    phase: get_string(json, "phase", ""),
    from: get_string(json, "from", ""),
    from_label: labelled_or(json, "from_label", "from"),
    kind: get_string(json, "kind", ""),
    reason: get_string(json, "reason", ""),
    positions: society_positions(json),
    transitions: society_transitions(json),
    moves: society_moves(json),
    gaps: get_strings(json, "gaps"),
    path: get_string(json, "path", ""),
  }
}

///|
/// A name, falling back to the machine's own name for it.
///
/// The reader is shown "Lifeworld" rather than "World" when the vocabulary
/// has a word, and "World" rather than nothing when it does not. A blank
/// where a name should be reads as "the machine has a state nobody has a
/// word for", which is a different claim from the truth.
fn labelled_or(json : Json, label_key : String, id_key : String) -> String {
  let label = get_string(json, label_key, "")
  if label == "" {
    get_string(json, id_key, "")
  } else {
    label
  }
}

///|
/// What the last move did, in one sentence.
///
/// A move that landed is reported as a move from one place to another. The
/// collective's history is what makes the panel readable: "the collective is
/// now at a validity claim" tells a reader nothing about whether anything
/// happened.
pub fn society_outcome_sentence(summary : SocietySummary) -> String {
  match summary.kind {
    "moved" =>
      if summary.from_label == "" {
        "The collective moved to " + summary.state_label + "."
      } else {
        "The collective moved from " +
        summary.from_label +
        " to " +
        summary.state_label +
        "."
      }
    "held" => "The collective stayed where it was."
    "open" => "The move left the collective more than one place to be."
    "block" => "The collective did not move."
    _ => ""
  }
}

///|
/// The society panel: the collective, the moves from where it stands, and
/// what the last move did.
pub fn society_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let button = @html.div(class="maked-society-buttons", [
    @html.button(
      class="maked-btn maked-btn-society",
      on_click=emit(SocietyReadClicked),
      "Read the Collective",
    ),
  ])
  let result = match model.society {
    None =>
      @html.p(
        class="maked-society-empty",
        "The collective has not been read yet. MAKED will ask the machine where it stands.",
      )
    Some(json) => society_body(json, emit)
  }
  let error = if model.society_error == "" {
    @html.nothing
  } else {
    @html.p(class="maked-society-error", model.society_error)
  }
  @html.section(class="maked-society", [
    @html.h2(class="maked-society-title", "Society"),
    @html.p(
      class="maked-society-lede",
      "The collective: where it stands, what it can do from there, and what the last move actually did.",
    ),
    button,
    result,
    error,
  ])
}

///|
/// The collective, as it stands.
fn society_body(json : Json, emit : @cmd.Emit[Msg]) -> @html.Html {
  let summary = society_summary(json)
  let outcome = society_outcome_sentence(summary)
  let outcome_view = if outcome == "" {
    @html.nothing
  } else {
    let reason = if summary.reason == "" {
      @html.nothing
    } else {
      @html.p(class="maked-society-reason", summary.reason)
    }
    @html.div(class="maked-society-outcome", [
      @html.p(class="maked-society-outcome-sentence", outcome),
      reason,
    ])
  }
  let gaps = if summary.gaps.length() == 0 {
    @html.nothing
  } else {
    let items : Array[@html.Html] = []
    for gap in summary.gaps {
      items.push(@html.li(class="maked-society-gap", gap))
    }
    @html.div(class="maked-society-gaps", [
      @html.h3(
        class="maked-society-subtitle",
        "The vocabulary is behind the machine",
      ),
      @html.p(
        class="maked-society-gap-note",
        "These are names the machine has and the vocabulary file does not. The panel shows them rather than rendering the positions blank.",
      ),
      @html.ul(class="maked-society-gap-list", items),
    ])
  }
  let words = if summary.path == "" {
    "the words MAKED ships with"
  } else {
    summary.path
  }
  @html.div(class="maked-society-results", [
    @html.h3(class="maked-society-subtitle", "Where the collective stands"),
    @html.dl(class="maked-society-position", [
      @html.dt("Position"),
      @html.dd(class="maked-society-state-label", summary.state_label),
      @html.dt("Phase"),
      @html.dd(class="maked-society-phase", summary.phase),
      @html.dt("What it means"),
      @html.dd(class="maked-society-gloss", summary.state_gloss),
    ]),
    outcome_view,
    @html.h3(class="maked-society-subtitle", "What it can do from here"),
    society_move_table(summary.moves, emit),
    @html.h3(class="maked-society-subtitle", "The machine"),
    @html.dl(class="maked-society-machine", [
      @html.dt("Positions"),
      @html.dd(
        class="maked-society-position-count",
        summary.positions.length().to_string(),
      ),
      @html.dt("Moves in the machine"),
      @html.dd(
        class="maked-society-transition-count",
        summary.transitions.length().to_string(),
      ),
      @html.dt("The words come from"),
      @html.dd(class="maked-society-path", words),
    ]),
    gaps,
  ])
}

///|
/// The moves from where the collective stands, each one a button.
///
/// The button carries the machine's own name for the move, not its label:
/// the label is for the reader and can be changed in the vocabulary file,
/// while the name is what the machine understands.
fn society_move_table(
  moves : Array[SocietyMoveSummary],
  emit : @cmd.Emit[Msg],
) -> @html.Html {
  if moves.length() == 0 {
    return @html.p(
      class="maked-society-empty",
      "No move leads out of this position. The collective is stuck here until something else changes.",
    )
  }
  let body : Array[@html.Html] = []
  for edge in moves {
    body.push(
      @html.tr(class="maked-society-move-row", [
        @html.td(class="maked-society-move-cell", [
          @html.button(
            class="maked-btn maked-btn-society-move",
            on_click=emit(SocietyStepClicked(edge.trigger)),
            edge.trigger_label,
          ),
        ]),
        @html.td(class="maked-society-move-target", edge.to_label),
      ]),
    )
  }
  @html.table(class="maked-society-moves", [
    @html.thead(class="maked-society-move-head", [
      @html.tr([@html.th("Move"), @html.th("Lands at")]),
    ]),
    @html.tbody(class="maked-society-move-body", body),
  ])
}
