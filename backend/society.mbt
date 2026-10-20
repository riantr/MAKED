///| The Society layer: the collective, and the words for it.
///
/// MAKED has three layers and had two. The subject layer is the ring of five
/// domains, and the group layer is the state that emerges when the domains
/// are read together. The society layer is the third: the collective as a
/// communicative whole -- a lifeworld or a system, a claim or a consensus,
/// and the moves that take it from one to another.
///
/// The machine is pyroduct's. Its thirteen positions, eight phases and
/// twenty-eight transitions are the authority, and MAKED does not restate
/// them: it asks pyroduct what they are and serves the answer. What MAKED
/// adds is the English, because pyroduct keeps the society machine's own
/// wording in Chinese -- the way it keeps the subject machine's -- and
/// MAKED is an English surface.
///
/// That English is a file (`research/society.yaml`), not code, for the same
/// reason the mapping table and the corpus are files: a word the reader
/// wants to change should not need a release to change. The file's ids are
/// pyroduct's own names, so the two cannot drift apart silently: a position
/// pyroduct defines and the file does not name is a gap the panel says out
/// loud, and a name in the file that pyroduct does not define is a name
/// about nowhere, which is refused.
///
/// The collective is stepped with a trigger rather than a slot. The subject
/// machine has eight drive slots and 228 combinations that are blocked; the
/// society machine has no slots at all, so the reader picks the move and the
/// machine answers with where it lands or with the reason it does not.

///|
/// The format a society vocabulary file says it is written in, so that a
/// file from a later version is refused rather than read as if it were this
/// one.
pub const SOCIETY_FORMAT : String = "maked.society.v1"

///|
/// One word: a label, and for the positions a sentence about it.
pub(all) struct SocietyWord {
  /// The name as the reader should see it.
  label : String
  /// A sentence saying what it means.
  gloss : String
} derive(Eq)

///|
pub extend SocietyWord with Eq::{not_equal, equal}

///|
/// The vocabulary of the society machine.
///
/// Three sets of words, keyed by pyroduct's own names. A word that is not
/// there is not a blank in the panel -- it is a gap the panel reports.
pub(all) struct SocietyVocabulary {
  /// The words for the positions.
  positions : Map[String, SocietyWord]
  /// The words for the phases.
  phases : Map[String, SocietyWord]
  /// The words for the triggers.
  triggers : Map[String, SocietyWord]
  /// Where the vocabulary was read from. Empty when it is the built-in one,
  /// and that is the difference between a vocabulary that can be written
  /// back and one that cannot.
  path : String
} derive(Eq)

///|
pub extend SocietyVocabulary with Eq::{not_equal, equal}

///|
/// One position of the society machine.
pub(all) struct SocietyPosition {
  /// pyroduct's name for the position.
  id : String
  /// The name as the reader should see it.
  label : String
  /// A sentence saying what the position means.
  gloss : String
  /// The phase the position belongs to, by pyroduct's name.
  phase : String
} derive(Eq)

///|
pub extend SocietyPosition with Eq::{not_equal, equal}

///|
/// One transition of the society machine.
pub(all) struct SocietyTransition {
  /// Where the move starts, by pyroduct's name.
  from : String
  /// The move itself, by pyroduct's name.
  trigger : String
  /// Where the move lands, by pyroduct's name.
  to : String
} derive(Eq)

///|
pub extend SocietyTransition with Eq::{not_equal, equal}

///|
/// What a move did.
///
/// The four cases are pyroduct's own, and they are the same four the
/// subject machine answers with: the move went somewhere, the move came
/// back where it started, the move left more than one possibility open, or
/// there was no move at all.
pub(all) enum SocietyStep {
  /// The collective went somewhere.
  Advanced(String, String)
  /// The collective came back where it started.
  Kept(String, String)
  /// The machine left more than one place to go.
  Undecided(String, Array[String])
  /// There was no such move.
  Refused(String, String)
}

///|
/// What the last move did.
///
/// This is carried with every answer about the collective, including the
/// answer to "where does it stand right now?", where it is empty. The
/// reason it exists is that a response that means one thing when a move
/// lands and another thing when it does not is a response the client has to
/// interpret before it can show anything: the panel would have to keep two
/// shapes in mind and decide which one it was handed. One shape is the
/// whole of the difference between a panel that always knows where the
/// collective stands and a panel that goes blank when a move is refused.
pub(all) struct SocietyOutcome {
  /// What the move did, in the vocabulary MAKED uses everywhere: "moved",
  /// "held", "open" or "block". Empty when no move has been taken.
  kind : String
  /// Why the collective did not go where the reader asked it to go, in
  /// words. Empty when the move landed.
  reason : String
  /// Where the collective stood before the move. Empty when no move has been
  /// taken.
  ///
  /// A move that lands is reported as a move from one place to another.
  /// Without the place it came from, "the collective is now at a validity
  /// claim" is a fact with no history in it, and a reader watching the
  /// collective move has no way to tell a first step from a return.
  from : String
} derive(Eq)

///|
pub extend SocietyOutcome with Eq::{not_equal, equal}

///|
/// The outcome of a collective that has not been moved yet.
pub fn SocietyOutcome::none() -> SocietyOutcome {
  { kind: "", reason: "", from: "", }
}

///|
/// The vocabulary MAKED runs when nothing else is installed.
///
/// The built-in words are the ones the shipped file carries, so the panel
/// reads the same with or without the file.
pub fn SocietyVocabulary::builtin() -> SocietyVocabulary {
  {
    positions: Map([
      (
        "World",
        {
          label: "Lifeworld",
          gloss: "The prior place where speakers and listeners meet, organised by language.",
        },
      ),
      (
        "Suprasubjective",
        {
          label: "Suprasubjectivity",
          gloss: "Understanding and language are events that happen to us rather than acts we perform.",
        },
      ),
      (
        "Intersubjective",
        {
          label: "Intersubjectivity",
          gloss: "Intersubjectivity is established through language.",
        },
      ),
      (
        "Claim",
        {
          label: "Validity claim",
          gloss: "What one actor says, in words meant to be taken up by others.",
        },
      ),
      (
        "Discourse",
        { label: "Discourse", gloss: "The conversation that filters claims.", },
      ),
      (
        "Justification",
        {
          label: "Justification",
          gloss: "A claim is true when the speech act that asserts it has been justified.",
        },
      ),
      (
        "Consensus",
        {
          label: "Consensus",
          gloss: "An understanding that has been justified and taken up by the community.",
        },
      ),
      (
        "Norm",
        {
          label: "Norm",
          gloss: "Practical discourse sets rules that bind the participants.",
        },
      ),
      (
        "Gap",
        {
          label: "Gap",
          gloss: "A third party has to weigh the possible criticism against the judgement.",
        },
      ),
      (
        "System",
        { label: "System", gloss: "Money and power as intermediaries.", },
      ),
      (
        "Colony",
        {
          label: "Colonisation",
          gloss: "Instrumental reason lets the system's appetite grow, and it reaches into the lifeworld.",
        },
      ),
      (
        "Distortion",
        {
          label: "Distorted communication",
          gloss: "Communication that the system has twisted.",
        },
      ),
      (
        "Reconstruction",
        {
          label: "Reconstruction",
          gloss: "Putting the distorted sphere of communication back together.",
        },
      ),
    ]),
    phases: Map([
      ("Life", { label: "Life", gloss: "", }),
      ("Language", { label: "Language", gloss: "", }),
      ("Discourse", { label: "Discourse", gloss: "", }),
      ("Rule", { label: "Rule", gloss: "", }),
      ("Aporia", { label: "Aporia", gloss: "", }),
      ("Instrument", { label: "Instrument", gloss: "", }),
      ("Domination", { label: "Domination", gloss: "", }),
      ("Rebuild", { label: "Rebuild", gloss: "", }),
    ]),
    triggers: Map([
      ("SpeakLanguage", { label: "Language speaks", gloss: "", }),
      ("BuildIntersubjective", { label: "Build intersubjectivity", gloss: "", }),
      ("RaiseClaims", { label: "Raise a validity claim", gloss: "", }),
      ("EnterDiscourse", { label: "Enter discourse", gloss: "", }),
      ("Filter", { label: "Filter through discourse", gloss: "", }),
      ("Justify", { label: "Justify", gloss: "", }),
      ("Subsume", { label: "Subsume", gloss: "", }),
      ("Store", { label: "Store", gloss: "", }),
      ("EnactNorm", { label: "Enact a norm", gloss: "", }),
      ("LabelPast", { label: "Label the past", gloss: "", }),
      ("DemandThird", { label: "Demand a third party", gloss: "", }),
      ("Serve", { label: "Serve the lifeworld", gloss: "", }),
      ("Expand", { label: "Expand", gloss: "", }),
      ("Colonize", { label: "Colonise the lifeworld", gloss: "", }),
      ("Distort", { label: "Distort communication", gloss: "", }),
      ("Hinder", { label: "Hinder consensus", gloss: "", }),
      ("Reconstruct", { label: "Reconstruct", gloss: "", }),
      ("Circulate", { label: "Circulate", gloss: "", }),
    ]),
    path: "",
  }
}

///|
/// The word for a position, or the fallback.
///
/// The fallback is the position's own name with no gloss: a position the
/// vocabulary does not name is still a position, and showing its name is
/// better than showing nothing. The gap is reported separately.
fn society_word(words : Map[String, SocietyWord], id : String) -> SocietyWord {
  match words.get(id) {
    Some(word) => word
    None => { label: id, gloss: "", }
  }
}

///|
/// pyroduct's name for a society position.
///
/// The match is exhaustive on purpose: if pyroduct adds a position, this
/// stops compiling rather than quietly calling the new position one of the
/// old ones.
pub fn society_position_id(state : @society.State) -> String {
  match state {
    @society.World => "World"
    @society.Suprasubjective => "Suprasubjective"
    @society.Intersubjective => "Intersubjective"
    @society.Claim => "Claim"
    @society.Discourse => "Discourse"
    @society.Justification => "Justification"
    @society.Consensus => "Consensus"
    @society.Norm => "Norm"
    @society.Gap => "Gap"
    @society.System => "System"
    @society.Colony => "Colony"
    @society.Distortion => "Distortion"
    @society.Reconstruction => "Reconstruction"
  }
}

///|
/// The society position with that name, if there is one.
///
/// `None` means the name is about nowhere: no position in the machine
/// carries it.
pub fn society_position_from_id(id : String) -> @society.State? {
  match id {
    "World" => Some(@society.World)
    "Suprasubjective" => Some(@society.Suprasubjective)
    "Intersubjective" => Some(@society.Intersubjective)
    "Claim" => Some(@society.Claim)
    "Discourse" => Some(@society.Discourse)
    "Justification" => Some(@society.Justification)
    "Consensus" => Some(@society.Consensus)
    "Norm" => Some(@society.Norm)
    "Gap" => Some(@society.Gap)
    "System" => Some(@society.System)
    "Colony" => Some(@society.Colony)
    "Distortion" => Some(@society.Distortion)
    "Reconstruction" => Some(@society.Reconstruction)
    _ => None
  }
}

///|
/// pyroduct's name for a society trigger.
///
/// Exhaustive for the same reason the position's is: a new trigger in the
/// authority has to be given a name here, or the code says so.
pub fn society_trigger_id(trigger : @society.Trigger) -> String {
  match trigger {
    @society.SpeakLanguage => "SpeakLanguage"
    @society.BuildIntersubjective => "BuildIntersubjective"
    @society.RaiseClaims => "RaiseClaims"
    @society.EnterDiscourse => "EnterDiscourse"
    @society.Filter => "Filter"
    @society.Justify => "Justify"
    @society.Subsume => "Subsume"
    @society.Store => "Store"
    @society.EnactNorm => "EnactNorm"
    @society.LabelPast => "LabelPast"
    @society.DemandThird => "DemandThird"
    @society.Serve => "Serve"
    @society.Expand => "Expand"
    @society.Colonize => "Colonize"
    @society.Distort => "Distort"
    @society.Hinder => "Hinder"
    @society.Reconstruct => "Reconstruct"
    @society.Circulate => "Circulate"
  }
}

///|
/// The society trigger with that name, if there is one.
pub fn society_trigger_from_id(id : String) -> @society.Trigger? {
  match id {
    "SpeakLanguage" => Some(@society.SpeakLanguage)
    "BuildIntersubjective" => Some(@society.BuildIntersubjective)
    "RaiseClaims" => Some(@society.RaiseClaims)
    "EnterDiscourse" => Some(@society.EnterDiscourse)
    "Filter" => Some(@society.Filter)
    "Justify" => Some(@society.Justify)
    "Subsume" => Some(@society.Subsume)
    "Store" => Some(@society.Store)
    "EnactNorm" => Some(@society.EnactNorm)
    "LabelPast" => Some(@society.LabelPast)
    "DemandThird" => Some(@society.DemandThird)
    "Serve" => Some(@society.Serve)
    "Expand" => Some(@society.Expand)
    "Colonize" => Some(@society.Colonize)
    "Distort" => Some(@society.Distort)
    "Hinder" => Some(@society.Hinder)
    "Reconstruct" => Some(@society.Reconstruct)
    "Circulate" => Some(@society.Circulate)
    _ => None
  }
}

///|
/// pyroduct's name for a phase of the society machine.
pub fn society_phase_id(phase : @society.Phase) -> String {
  match phase {
    @society.Life => "Life"
    @society.Language => "Language"
    @society.Discourse => "Discourse"
    @society.Rule => "Rule"
    @society.Aporia => "Aporia"
    @society.Instrument => "Instrument"
    @society.Domination => "Domination"
    @society.Rebuild => "Rebuild"
  }
}

///|
/// The positions of the society machine, with the vocabulary's words.
///
/// The order is pyroduct's, so the panel reads the machine in the order the
/// authority writes it down.
pub fn society_positions(
  vocabulary : SocietyVocabulary,
) -> Array[SocietyPosition] {
  let out : Array[SocietyPosition] = []
  for state in @society.all_states() {
    let id = society_position_id(state)
    let word = society_word(vocabulary.positions, id)
    out.push({
      id,
      label: word.label,
      gloss: word.gloss,
      phase: society_phase_id(state.phase()),
    })
  }
  out
}

///|
/// The transitions of the society machine.
pub fn society_transitions() -> Array[SocietyTransition] {
  let out : Array[SocietyTransition] = []
  for transition in @society.transitions() {
    out.push({
      from: society_position_id(transition.from),
      trigger: society_trigger_id(transition.trigger),
      to: society_position_id(transition.to),
    })
  }
  out
}

///|
/// The moves available from a position.
///
/// This is the society machine's answer to "what can the collective do
/// next?", read straight out of the transition table.
pub fn society_moves(state : @society.State) -> Array[SocietyTransition] {
  let out : Array[SocietyTransition] = []
  for transition in @society.transitions() {
    if transition.from == state {
      out.push({
        from: society_position_id(transition.from),
        trigger: society_trigger_id(transition.trigger),
        to: society_position_id(transition.to),
      })
    }
  }
  out
}

///|
/// The gaps in the vocabulary: the names the machine has and the file does
/// not.
///
/// A gap is a defect the panel shows rather than hides. The alternative is
/// a position that renders as a blank, and a blank in a list of positions
/// reads as "the machine has an unnamed state" rather than "the file is
/// behind the machine".
pub fn society_vocabulary_gaps(vocabulary : SocietyVocabulary) -> Array[String] {
  let gaps : Array[String] = []
  for state in @society.all_states() {
    let id = society_position_id(state)
    if vocabulary.positions.get(id) is None {
      gaps.push("position " + id)
    }
  }
  for phase in @society.all_phases() {
    let id = society_phase_id(phase)
    if vocabulary.phases.get(id) is None {
      gaps.push("phase " + id)
    }
  }
  for transition in @society.transitions() {
    let id = society_trigger_id(transition.trigger)
    if vocabulary.triggers.get(id) is None {
      gaps.push("trigger " + id)
    }
  }
  gaps
}

///|
/// Step the collective.
///
/// The machine decides: the reader names a move and pyroduct answers with
/// where it lands, with where it comes back to, with the possibilities it
/// leaves open, or with the reason there was no move at all.
///
/// A move that is not in the machine is refused with a reason rather than
/// ignored, because a refused move that says nothing looks exactly like a
/// move that did nothing.
pub fn society_step(
  vocabulary : SocietyVocabulary,
  state : @society.State,
  trigger_id : String,
) -> SocietyStep {
  let trigger = match society_trigger_from_id(trigger_id) {
    Some(t) => t
    None =>
      return Refused(
        trigger_id,
        "There is no move called \"" + trigger_id + "\" in the society machine.",
      )
  }
  let outcome = @society.step(state, trigger)
  match outcome {
    @society.Moved(t, to) =>
      Advanced(society_trigger_id(t), society_position_id(to))
    @society.Held(t, s) => Kept(society_trigger_id(t), society_position_id(s))
    @society.Open(t, states) => {
      let names : Array[String] = []
      for s in states {
        names.push(society_position_id(s))
      }
      Undecided(society_trigger_id(t), names)
    }
    @society.Block(reason) =>
      Refused(
        society_trigger_id(trigger),
        society_reason(vocabulary, state, trigger_id, reason),
      )
  }
}

///|
/// The outcome kind, in the vocabulary the whole of MAKED uses.
///
/// The society machine and the subject machine answer with the same four
/// shapes -- a move, a hold, an opening, a block -- so the kind is written
/// the same way here, and the frontend reads one vocabulary for both.
pub fn SocietyStep::society_step_kind(self : SocietyStep) -> String {
  match self {
    Advanced(_, _) => "moved"
    Kept(_, _) => "held"
    Undecided(_, _) => "open"
    Refused(_, _) => "block"
  }
}

///|
/// A society vocabulary, or the reason there is not one.
///
/// The reason is carried rather than printed, because the caller is usually
/// a request from a person who typed something, and a person is owed an
/// answer rather than a line in the server's log.
pub(all) enum SocietyRead {
  Accepted(SocietyVocabulary)
  Rejected(String)
}

///|
/// Read a society vocabulary out of a JSON document.
///
/// The format is asked for, the same way the model file and the mapping
/// table ask for theirs: a file from a later version is refused rather
/// than read as if it were this one.
///
/// A word whose id is not one the machine knows is refused. It is a word
/// about nowhere, and a vocabulary that names a position the machine does
/// not have is a vocabulary that is quietly out of step with it -- which is
/// the one thing a vocabulary must never be.
pub fn SocietyVocabulary::from_json(path : String, json : Json) -> SocietyRead {
  let format = json_string(json, "format")
  if format != SOCIETY_FORMAT {
    return Rejected(
      "format must be \"" + SOCIETY_FORMAT + "\"; got \"" + format + "\"",
    )
  }
  let positions = read_words(json, "positions", true)
  let phases = read_words(json, "phases", false)
  let triggers = read_words(json, "triggers", false)
  match (positions, phases, triggers) {
    (Err(a), _, _) => Rejected(a)
    (_, Err(b), _) => Rejected(b)
    (_, _, Err(c)) => Rejected(c)
    (Ok(p), Ok(ph), Ok(t)) => {
      let vocabulary = { positions: p, phases: ph, triggers: t, path, }
      // A word about nowhere is refused here rather than ignored: a
      // vocabulary with a name the machine does not have is a vocabulary
      // that has drifted, and the drift is the whole thing this file
      // exists to prevent.
      let stray = first_stray(vocabulary)
      match stray {
        Some(reason) => Rejected(reason)
        None => Accepted(vocabulary)
      }
    }
  }
}

///|
/// The first name in a vocabulary that the machine does not have.
fn first_stray(vocabulary : SocietyVocabulary) -> String? {
  for (id, _) in vocabulary.positions {
    if society_position_from_id(id) is None {
      return Some("the position \"" + id + "\" is not one the machine has")
    }
  }
  for (id, _) in vocabulary.phases {
    if society_phase_from_id(id) is None {
      return Some("the phase \"" + id + "\" is not one the machine has")
    }
  }
  for (id, _) in vocabulary.triggers {
    if society_trigger_from_id(id) is None {
      return Some("the trigger \"" + id + "\" is not one the machine has")
    }
  }
  None
}

///|
/// pyroduct's name for a phase of the society machine, as a position the
/// machine can be asked about.
pub fn society_phase_from_id(id : String) -> @society.Phase? {
  match id {
    "Life" => Some(@society.Life)
    "Language" => Some(@society.Language)
    "Discourse" => Some(@society.Discourse)
    "Rule" => Some(@society.Rule)
    "Aporia" => Some(@society.Aporia)
    "Instrument" => Some(@society.Instrument)
    "Domination" => Some(@society.Domination)
    "Rebuild" => Some(@society.Rebuild)
    _ => None
  }
}

///|
/// Read one set of words out of a JSON document.
fn read_words(
  json : Json,
  key : String,
  glossed : Bool,
) -> Result[Map[String, SocietyWord], String] {
  let items = match json_field(json, key) {
    Some(Array(list)) => list
    _ => return Err(key + " must be a list of words")
  }
  let words = Map([])
  for item in items {
    let id = json_string(item, "id")
    if id == "" {
      return Err("a " + key + " entry has no id")
    }
    let label = json_string(item, "label")
    if label == "" {
      return Err("the " + key + " entry \"" + id + "\" has no label")
    }
    let gloss = if glossed { json_string(item, "gloss") } else { "" }
    words[id] = { label, gloss, }
  }
  Ok(words)
}

///|
/// The society vocabulary MAKED is running.
///
/// Held in a one-element array because MoonBit has no mutable module-level
/// binding, and the element is mutable in place.
let g_society_vocabulary : Array[SocietyVocabulary] = [
  SocietyVocabulary::builtin(),
]

///|
/// The society vocabulary MAKED is running.
pub fn current_society_vocabulary() -> SocietyVocabulary {
  g_society_vocabulary[0]
}

///|
/// Install a society vocabulary as the one MAKED runs.
pub fn install_society_vocabulary(vocabulary : SocietyVocabulary) -> Unit {
  g_society_vocabulary[0] = vocabulary
}

///|
/// The society file named by `MAKED_SOCIETY`, if there is one.
///
/// The same shape as the model file's switch: unset means the built-in
/// vocabulary, set means the vocabulary the operator asked for, and an empty
/// value counts as unset because an empty environment variable is a
/// mistake rather than a filename.
pub fn society_path_from_env() -> String? {
  match @env.get_env_var("MAKED_SOCIETY") {
    Some(path) if path != "" => Some(path)
    _ => None
  }
}

///|
/// Read a society vocabulary from a file.
///
/// None when the file cannot be read or is not a vocabulary this version
/// understands, with the reason printed. A vocabulary that cannot be read
/// whole is not read at all: half the words for the machine is a panel that
/// names some of the collective's positions and leaves the rest blank,
/// which is the state the file exists to prevent.
pub async fn read_society_file(path : String) -> SocietyVocabulary? {
  let json = match read_data_text("society", path) {
    Some(json) => json
    None => return None
  }
  match SocietyVocabulary::from_json(path, json) {
    Accepted(vocabulary) => Some(vocabulary)
    Rejected(reason) => {
      println(
        "error: society file \{path} is not a vocabulary this version understands: \{reason}",
      )
      None
    }
  }
}

///|
/// Write a society vocabulary back to the file it came from.
///
/// False when the vocabulary did not come from a file -- the built-in one
/// has nowhere to be written -- or when the file could not be written. The
/// reason is printed either way, because a vocabulary that was edited and
/// not saved is a vocabulary the reader believes is saved and is not.
pub async fn write_society_file(vocabulary : SocietyVocabulary) -> Bool {
  if vocabulary.path == "" {
    println(
      "note: the built-in vocabulary is not written anywhere; it is the one MAKED starts with.",
    )
    return false
  }
  let text = data_text_for(vocabulary.path, vocabulary.to_json())
  @fs.write_file(vocabulary.path, text) catch {
    err => {
      println("error: society file \{vocabulary.path} unwritable: \{err}")
      return false
    }
  }
  true
}

///|
/// The vocabulary as JSON: the form a reader can edit and hand back.
///
/// Every word is written down, so the file is the vocabulary and not a
/// pointer to one.
pub fn SocietyVocabulary::to_json(self : SocietyVocabulary) -> Json {
  {
    "format": SOCIETY_FORMAT,
    "positions": words_to_json(self.positions),
    "phases": words_to_json(self.phases),
    "triggers": words_to_json(self.triggers),
  }
}

///|
/// One set of words, as a list of entries.
fn words_to_json(words : Map[String, SocietyWord]) -> Array[Json] {
  let out : Array[Json] = []
  for (id, word) in words {
    out.push({ "id": id, "label": word.label, "gloss": word.gloss })
  }
  out
}

///|
/// The name of a society position, as the reader should see it.
pub fn society_position_label(
  vocabulary : SocietyVocabulary,
  id : String,
) -> String {
  society_word(vocabulary.positions, id).label
}

///|
/// The name of a society trigger, as the reader should see it.
pub fn society_trigger_label(
  vocabulary : SocietyVocabulary,
  id : String,
) -> String {
  society_word(vocabulary.triggers, id).label
}

///|
/// The name of a society phase, as the reader should see it.
pub fn society_phase_label(
  vocabulary : SocietyVocabulary,
  id : String,
) -> String {
  society_word(vocabulary.phases, id).label
}

///|
/// The reason a move was refused, in the vocabulary's words.
///
/// pyroduct's own reason names the position and the move in its own
/// wording, which is Chinese. The reason is rebuilt here from the words
/// MAKED has, because the reader has to be able to read it.
fn society_reason(
  vocabulary : SocietyVocabulary,
  state : @society.State,
  trigger_id : String,
  _reason : String,
) -> String {
  let position = society_word(vocabulary.positions, society_position_id(state))
  let trigger = society_word(vocabulary.triggers, trigger_id)
  "From " + position.label + " there is no \"" + trigger.label + "\" to take."
}
