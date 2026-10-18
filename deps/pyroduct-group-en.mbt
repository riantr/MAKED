///|
/// English renderings of the pyroduct *group* vocabulary.
///
/// The group machine (`riantr/pyroduct/group`) is Chinese-language for the same
/// reason the subject machine is: `designation()` and `gloss()` are its source
/// layer, kept verbatim for traceability. This file adds an English rendering
/// alongside them so an English-only surface can read the group state without
/// touching the source wording.
///
/// Nothing here participates in the machine. The 20 group states, their phases
/// and every transition are unchanged; a mistake here can only mislabel a state,
/// never create one.
///
/// ## Staging
///
/// `.mooncakes/` is gitignored -- a dependency cache, not source -- so
/// `build.ps1` copies this file into
/// `.mooncakes/riantr/pyroduct/group/en.mbt` before compiling. This file is the
/// source of truth; the copy is a build artefact.

///|
/// The English name of a group state.
pub fn GroupState::en_designation(self : GroupState) -> String {
  match self {
    Scattered => "Scattered"
    Converging => "Converging"
    CommonTongue => "Common Tongue"
    Discourse => "Discourse"
    Normed => "Normed"
    Consensus => "Consensus"
    Dissensus => "Dissensus"
    Confronting => "Confronting"
    Partitioned => "Partitioned"
    Projected => "Projected"
    Monologic => "Monologic"
    Disciplined => "Disciplined"
    Concealed => "Concealed"
    Wounded => "Wounded"
    Dispersed => "Dispersed"
    Returning => "Returning"
    Practicing => "Practicing"
    Widening => "Widening"
    Attuned => "Attuned"
    Settled => "Settled"
  }
}

///|
/// An English rendering of a group state's description.
pub fn GroupState::en_gloss(self : GroupState) -> String {
  match self {
    Scattered =>
      "The many are only a crowd, with no relation among them yet; the group is not yet a subject."
    Converging =>
      "Attention begins to gather, but there is as yet no common language, claim or rule."
    CommonTongue =>
      "Understanding and language are taken as supra-subjective events: it is language that speaks us."
    Discourse =>
      "Truth is taken as an inter-subjective claim, woven into a net that is horizontal (between members) and vertical (toward norms)."
    Normed =>
      "A common rule is raised by reason or by tradition; the order of the group first takes shape."
    Consensus =>
      "What was reached is only a temporary agreement; the revisable marker is never taken down."
    Dissensus =>
      "Difference is acknowledged as difference -- this is the state in which discussion can still continue."
    Confronting =>
      "The regimes are at odds: one calls the other radical subjectivism, the other replies that it still holds the legacy of subject philosophy."
    Partitioned =>
      "The frontier closes and each side holds its own ground; zones that may not be entered appear at group scale."
    Projected =>
      "The group hands the third party over to the absolute -- a leader, an idol, an ideology, a deified language."
    Monologic =>
      "The many voices degenerate into a single one: the road of dialogue has reached monologic logic."
    Disciplined =>
      "The group binds itself together along with its members, and the freedom of action is put away."
    Concealed =>
      "The unexhausted are suppressed: what is hidden is no longer hidden but forbidden to ask about."
    Wounded =>
      "The group's wound is opened again and again; the suffering is caused by the group itself and is hard to bring to an end."
    Dispersed => "The group breaks up and its members disperse."
    Returning => "Someone turns back and asks the question again: the cycle reopens."
    Practicing =>
      "Collectively enduring a temporary pain in order to remove the reefs -- discipline, reenacted at group scale."
    Widening => "The frontier widens, and new members and new content are taken in."
    Attuned =>
      "Every pair of members is fully sincere: his sincerity and my own both hold at once."
    Settled =>
      "No conclusion is absolutized any further; one waits for the next moment, and the frontier may open again at any time."
  }
}

///|
/// The English name of a group phase.
pub fn GroupPhase::en_label(self : GroupPhase) -> String {
  match self {
    Gathering => "Gathering"
    Bodied => "Coming to a Body"
    Ordering => "Ordering"
    Diverging => "Diverging"
    Excess => "Excess"
    SelfBound => "Self-bound"
    Impaired => "Impaired"
    Cultivating => "Cultivating"
    Resting => "Resting"
  }
}
