///| The research configuration: the table that says what a document means.
///
/// The mapping used to be a function -- a chain of `contains` calls inside
/// `paper_to_trigger`, ending in a default. That is a table written as code,
/// and a table written as code can only be changed by changing the program:
/// the reader who wanted "failure" to mean something else had no way to say
/// so, and the only way to find out what the table said was to read the
/// source of a web application.
///
/// A table is data. It can be read from a file, edited, and handed back,
/// and MAKED runs the table it was given. That is the same move the model
/// made -- the machine became a file -- applied to the part of MAKED that
/// says what reading a document means.
///
/// Four things this file is careful about:
///
///   - **The order is the priority.** The table is read from the top and the
///     first rule that matches wins, so a rule that says "any paper that
///     mentions a benchmark" can sit above a rule that says "any paper that
///     claims to be new". A priority written as an order is a priority the
///     reader can see.
///   - **The slot is the model's.** A rule names a slot by the id the model
///     gives it, not by a name from the table the model came from, so a
///     model file with its own slots gets a mapping that fits it.
///   - **A rule that names a slot the model does not have is refused.** It
///     is a rule about nowhere, and reading it would mean inventing a slot
///     to hold it.
///   - **A table is written back in the syntax it was read in.** A `.yaml`
///     file stays YAML and everything else stays JSON, because a file
///     written in one syntax and read as the other is a file that
///     half-reads -- and that goes for writing as much as for reading.

///|
/// The format a research file says it is written in, so that a file from a
/// later version is refused rather than read as if it were this one.
pub const RESEARCH_FORMAT : String = "maked.research.v1"

///|
/// One rule of the mapping table.
pub(all) struct MappingRule {
  /// The words that make this rule fire. The rule fires when the document
  /// contains any one of them. They are kept in lower case, because the
  /// document is lower-cased before it is matched.
  keywords : Array[String]
  /// The slot the rule drives, by the model's slot id.
  slot : String
  /// What the rule is called, in the reader's words.
  label : String
  /// The reader's own note about the rule. It is data rather than a
  /// comment in the file, so it survives a write-back.
  notes : String
} derive(Eq, Debug)

///|
pub extend MappingRule with Eq::{not_equal, equal}

///|
pub extend MappingRule with Debug::{to_repr}

///|
/// The research configuration MAKED is running.
pub(all) struct ResearchConfig {
  /// The mapping table, in priority order: the first rule that matches wins.
  rules : Array[MappingRule]
  /// The slot for a document that matches no rule. An empty string means
  /// "leave it alone": a document that says nothing the table knows is not
  /// a document the loop should be driven by.
  fallback_slot : String
  /// The name of the fallback, in the reader's words.
  fallback_label : String
  /// Where the configuration was read from. Empty when it is the built-in
  /// one, and that is the difference between a table that can be written
  /// back and one that cannot.
  path : String
} derive(Eq, Debug)

///|
pub extend ResearchConfig with Eq::{not_equal, equal}

///|
pub extend ResearchConfig with Debug::{to_repr}

///|
/// A research configuration, or the reason there is not one.
///
/// The reason is carried rather than printed, because the caller is usually
/// a request from a person who typed something, and a person is owed an
/// answer rather than a line in the server's log.
pub(all) enum ResearchRead {
  Accepted(ResearchConfig)
  Rejected(String)
}

///|
/// The built-in mapping table.
///
/// The table the old hard-coded function produced, written down: the order
/// is the priority the function had, and the words are the ones it looked
/// for. The slot is the model's and the label is the reader's.
///
/// It is a table about papers, and it is the built-in *model's* table: the
/// slots it names are the built-in model's. A model file with its own slots
/// needs its own table, and `MAKED_RESEARCH` is how one is given.
fn builtin_rules() -> Array[MappingRule] {
  [
    {
      keywords: ["state-of-the-art", "outperform", "sota"],
      slot: "feedback",
      label: "A claim of superiority",
      notes: "",
    },
    {
      keywords: ["limitation", "fail", "challenge", "struggle"],
      slot: "feedback",
      label: "A reported failure",
      notes: "",
    },
    {
      keywords: ["novel", "propose", "new method", "introduce"],
      slot: "act",
      label: "A new method",
      notes: "",
    },
    {
      keywords: ["survey", "review", "overview", "tutorial"],
      slot: "hold",
      label: "A survey of the field",
      notes: "",
    },
    {
      keywords: ["benchmark", "dataset", "evaluation"],
      slot: "occasion",
      label: "An evaluation or a dataset",
      notes: "",
    },
  ]
}

///|
/// The configuration MAKED runs when nothing else is installed.
pub fn ResearchConfig::builtin() -> ResearchConfig {
  {
    rules: builtin_rules(),
    fallback_slot: "antecedent",
    fallback_label: "Anything else",
    path: "",
  }
}

///|
/// The slot a piece of text is taken to mean, and the name of the rule that
/// said so.
///
/// The table is read from the top and the first rule that matches wins, so
/// the order of the rules is the priority. A rule matches when the text
/// contains any one of its words. The text is lower-cased once, here,
/// because the table's words are written in lower case and the document is
/// not.
pub fn ResearchConfig::slot_for_text(
  self : ResearchConfig,
  text : String,
) -> (String, String) {
  let lower = text.to_lowercase_ascii()
  for rule in self.rules {
    for word in rule.keywords {
      if lower.contains(word) {
        return (rule.slot, rule.label)
      }
    }
  }
  (self.fallback_slot, self.fallback_label)
}

///|
/// The first slot this table names that the model does not have, if there is
/// one.
///
/// A table that names a slot the model does not have is a rule about
/// nowhere. Reading it would mean inventing a slot to hold it, and driving
/// a document through a slot that is not there is a step that goes nowhere
/// while looking exactly like a step.
pub fn ResearchConfig::first_unfitting_slot(
  self : ResearchConfig,
  model : Model,
) -> String? {
  for rule in self.rules {
    if model.slot_from_name(rule.slot) is None {
      return Some(rule.slot)
    }
  }
  if self.fallback_slot != "" &&
    model.slot_from_name(self.fallback_slot) is None {
    return Some(self.fallback_slot)
  }
  None
}

///|
/// Read a research configuration out of JSON.
///
/// The model is asked about the slots, because a rule that names a slot the
/// model does not have is a rule about nowhere. The path is kept, because a
/// table that came from a file can be written back to it and a table that
/// did not cannot.
///
/// The format is asked for, the same way the model file asks for its own: a
/// file from a later version is refused rather than read as if it were this
/// one.
pub fn ResearchConfig::from_json(
  model : Model,
  path : String,
  json : Json,
) -> ResearchRead {
  let format = json_string(json, "format")
  if format != RESEARCH_FORMAT {
    return Rejected(
      "format must be \"" + RESEARCH_FORMAT + "\"; got \"" + format + "\"",
    )
  }
  let mapping = match json_field(json, "mapping") {
    Some(Array(items)) => items
    _ => return Rejected("mapping must be a list of rules")
  }
  if mapping.length() == 0 {
    return Rejected("mapping must hold at least one rule")
  }
  let rules : Array[MappingRule] = []
  for index in 0..<mapping.length() {
    let item = mapping[index]
    let slot_raw = json_string(item, "slot")
    if slot_raw == "" {
      return Rejected("rule " + index.to_string() + " has no slot")
    }
    let slot = match model.slot_from_name(slot_raw) {
      Some(id) => id
      None =>
        return Rejected(
          "rule " +
          index.to_string() +
          " names the slot \"" +
          slot_raw +
          "\", which this model does not have",
        )
    }
    let keywords : Array[String] = []
    for word in json_strings(item, "keywords") {
      let trimmed = word.trim().to_owned().to_lowercase_ascii()
      if trimmed != "" {
        keywords.push(trimmed)
      }
    }
    if keywords.length() == 0 {
      return Rejected(
        "rule " + index.to_string() + " has no keywords, so it can never fire",
      )
    }
    let mut label = json_string(item, "label")
    if label == "" {
      label = model.slot_designation(slot)
    }
    rules.push({ keywords, slot, label, notes: json_string(item, "notes"), })
  }
  let fallback = match json_field(json, "fallback") {
    Some(Object(fields)) => fields
    _ =>
      return Rejected(
        "fallback must say the slot a document that matches no rule drives",
      )
  }
  let fallback_raw = match fallback.get("slot") {
    Some(String(value)) => value
    _ => return Rejected("fallback must name a slot")
  }
  let fallback_slot = if fallback_raw == "" {
    ""
  } else {
    match model.slot_from_name(fallback_raw) {
      Some(id) => id
      None =>
        return Rejected(
          "fallback names the slot \"" +
          fallback_raw +
          "\", which this model does not have",
        )
    }
  }
  let mut fallback_label = ""
  match fallback.get("label") {
    Some(String(value)) => fallback_label = value
    _ => ()
  }
  if fallback_label == "" {
    fallback_label = if fallback_slot == "" {
      "Nothing the table knows"
    } else {
      model.slot_designation(fallback_slot)
    }
  }
  Accepted({ rules, fallback_slot, fallback_label, path, })
}

///|
/// The configuration as JSON: the form a reader can edit and hand back.
///
/// Every name the table uses is written down, so the file is the table and
/// not a pointer to one.
pub fn ResearchConfig::to_json(self : ResearchConfig) -> Json {
  let rules : Array[Json] = []
  for rule in self.rules {
    rules.push({
      "keywords": rule.keywords,
      "label": rule.label,
      "notes": rule.notes,
      "slot": rule.slot,
    })
  }
  {
    "format": RESEARCH_FORMAT,
    "mapping": rules,
    "fallback": { "label": self.fallback_label, "slot": self.fallback_slot },
  }
}

///|
/// The research configuration MAKED is running.
///
/// Held in a one-element array because MoonBit has no mutable module-level
/// binding, and the element is mutable in place.
let g_research : Array[ResearchConfig] = [ResearchConfig::builtin()]

///|
/// The research configuration MAKED is running.
pub fn current_research() -> ResearchConfig {
  g_research[0]
}

///|
/// Install a research configuration as the one MAKED runs.
///
/// The loop is *not* reset, and it should not be: the table says what a
/// document means, and changing what a document means does not change where
/// the loop is standing. The machine is the model's, and the model is not
/// touched here.
pub fn install_research(config : ResearchConfig) -> Unit {
  g_research[0] = config
}

///|
/// The research file named by `MAKED_RESEARCH`, if there is one.
///
/// The same shape as the model file's switch: unset means the built-in
/// table, set means the table the operator asked for, and an empty value
/// counts as unset because an empty environment variable is a mistake
/// rather than a filename.
pub fn research_path_from_env() -> String? {
  match @env.get_env_var("MAKED_RESEARCH") {
    Some(path) if path != "" => Some(path)
    _ => None
  }
}

///|
/// Read a research configuration from a file.
///
/// None when the file cannot be read or is not a table this version
/// understands, with the reason printed. A table that cannot be read whole
/// is not read at all: half a mapping is a mapping that fires on the wrong
/// documents, and a document driven through the wrong slot is a step in the
/// timeline that nobody can explain afterwards.
pub async fn read_research_file(path : String) -> ResearchConfig? {
  read_research_file_for(current_model(), path)
}

///|
/// Read a research configuration from a file, checked against a named model.
///
/// The model is passed in rather than taken from the machine that happens to
/// be running, because the table and the machine are two different things.
/// A table is checked against the machine it will drive: the start-up reads
/// the machine the operator named and then reads the table against *that*
/// one, so the answer does not depend on what else was installed first, and
/// does not change when two servers start at the same moment.
pub async fn read_research_file_for(
  model : Model,
  path : String,
) -> ResearchConfig? {
  let json = match read_data_text("research", path) {
    Some(json) => json
    None => return None
  }
  match ResearchConfig::from_json(model, path, json) {
    Accepted(config) => Some(config)
    Rejected(reason) => {
      eprintln(
        "error: research file \{path} is not a table this version understands: \{reason}",
      )
      None
    }
  }
}

///|
/// Write a research configuration back to the file it came from.
///
/// False when the table did not come from a file -- the built-in table has
/// nowhere to be written -- or when the file could not be written. The
/// reason is printed either way, because a table that was edited and not
/// saved is a table the reader believes is saved and is not.
///
/// The file is written in the syntax its name asks for, and its comments
/// are not kept: the table is data, and data is written back as data. A
/// reader who wants their notes to survive should put them in a rule's
/// `notes`, which is a field of the table and does survive.
pub async fn write_research_file(config : ResearchConfig) -> Bool {
  if config.path == "" {
    eprintln(
      "note: the built-in table is not written anywhere; it is the table MAKED starts with.",
    )
    return false
  }
  let text = data_text_for(config.path, config.to_json())
  @fs.write_file(config.path, text) catch {
    err => {
      eprintln("error: research file \{config.path} unwritable: \{err}")
      return false
    }
  }
  true
}
