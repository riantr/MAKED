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
#derive(Eq, Debug)
pub(all) struct MappingRule {
  /// The words that make this rule fire. The rule fires when the document
  /// contains any one of them. They are kept in lower case, because the
  /// document is lower-cased before it is matched.
  keywords : Array[String]
  /// The words that make this rule fire, in Chinese.
  ///
  /// They are matched whatever the reader asked for: a table whose words are
  /// all English reads nothing at all when the documents are Chinese, and the
  /// corpus is the operator's choice, not the table's. A rule with no Chinese
  /// words still fires on the English ones.
  keywords_zh : Array[String]
  /// The slot the rule drives, by the model's slot id.
  slot : String
  /// What the rule is called, in the reader's words.
  label : String
  /// The same name, in Chinese. The reader is the one who reads it, so the
  /// reader's language chooses which of the two names is shown -- and the
  /// other one is still there, in the file, for the other reader.
  label_zh : String
  /// The reader's own note about the rule. It is data rather than a
  /// comment in the file, so it survives a write-back.
  notes : String
  /// The same note, in Chinese.
  notes_zh : String
}

///|
pub extend MappingRule with Eq::{not_equal, equal}

///|
pub extend MappingRule with Debug::{to_repr}

///|
/// The research configuration MAKED is running.
#derive(Eq, Debug)
pub(all) struct ResearchConfig {
  /// The mapping table, in priority order: the first rule that matches wins.
  rules : Array[MappingRule]
  /// The slot for a document that matches no rule. An empty string means
  /// "leave it alone": a document that says nothing the table knows is not
  /// a document the loop should be driven by.
  fallback_slot : String
  /// The name of the fallback, in the reader's words.
  fallback_label : String
  /// The same name, in Chinese.
  fallback_label_zh : String
  /// Where the configuration was read from. Empty when it is the built-in
  /// one, and that is the difference between a table that can be written
  /// back and one that cannot.
  path : String
}

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
      keywords_zh: ["最先进", "优于", "超过"],
      slot: "feedback",
      label: "A claim of superiority",
      label_zh: "一种领先的说法",
      notes: "",
      notes_zh: "",
    },
    {
      keywords: ["limitation", "fail", "challenge", "struggle"],
      keywords_zh: ["局限", "失败", "挑战"],
      slot: "feedback",
      label: "A reported failure",
      label_zh: "一次被报告的失败",
      notes: "",
      notes_zh: "",
    },
    {
      keywords: ["novel", "propose", "new method", "introduce"],
      keywords_zh: ["提出", "新方法", "介绍"],
      slot: "act",
      label: "A new method",
      label_zh: "一种新方法",
      notes: "",
      notes_zh: "",
    },
    {
      keywords: ["survey", "review", "overview", "tutorial"],
      keywords_zh: ["综述", "回顾", "概览"],
      slot: "hold",
      label: "A survey of the field",
      label_zh: "对这个领域的一次综述",
      notes: "",
      notes_zh: "",
    },
    {
      keywords: ["benchmark", "dataset", "evaluation"],
      keywords_zh: ["基准", "数据集", "评估"],
      slot: "occasion",
      label: "An evaluation or a dataset",
      label_zh: "一次评测或一个数据集",
      notes: "",
      notes_zh: "",
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
    fallback_label_zh: "其他",
    path: "",
  }
}

///|
/// Whether this rule fires on a piece of text.
///
/// The English words are matched against the lower-cased text and the Chinese
/// words against the text as it is: Chinese has no case, so lower-casing it
/// would change nothing at all.
pub fn MappingRule::matches(
  self : MappingRule,
  lower : String,
  text : String,
) -> Bool {
  for word in self.keywords {
    if lower.contains(word) {
      return true
    }
  }
  for word in self.keywords_zh {
    if text.contains(word) {
      return true
    }
  }
  false
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
  self.slot_for_text_in(text, Lang::english())
}

///|
/// The same, with the rule named in the language asked for.
///
/// The words the rule matches are the same in both languages, because the
/// corpus is the operator's choice and it may hold either: a table that only
/// matched the reader's language would read half of it. What the language
/// chooses is the NAME of the rule -- the reader's own words for it -- which
/// is the one thing the reader has to read.
pub fn ResearchConfig::slot_for_text_in(
  self : ResearchConfig,
  text : String,
  lang : Lang,
) -> (String, String) {
  let lower = text.to_lowercase_ascii()
  for rule in self.rules {
    if rule.matches(lower, text) {
      return (rule.slot, lang.pick(rule.label, rule.label_zh))
    }
  }
  (self.fallback_slot, lang.pick(self.fallback_label, self.fallback_label_zh))
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
///
/// The reason a table was refused is a sentence the reader reads -- it says
/// which rule is wrong and why -- so it is written in the language asked for.
/// A table is edited by hand, and the person editing it is the one who has to
/// read what went wrong.
pub fn ResearchConfig::from_json(
  model : Model,
  path : String,
  json : Json,
  lang : Lang,
) -> ResearchRead {
  let format = json_string(json, "format")
  if format != RESEARCH_FORMAT {
    return Rejected(
      match lang {
        English =>
          "format must be \"" + RESEARCH_FORMAT + "\"; got \"" + format + "\""
        Chinese =>
          "格式必须是「" +
          RESEARCH_FORMAT +
          "」；收到的是「" +
          format +
          "」。"
      },
    )
  }
  let mapping = match json_field(json, "mapping") {
    Some(Array(items)) => items
    _ =>
      return Rejected(
        match lang {
          English => "mapping must be a list of rules"
          Chinese => "映射必须是一张规则表。"
        },
      )
  }
  if mapping.length() == 0 {
    return Rejected(
      match lang {
        English => "mapping must hold at least one rule"
        Chinese => "映射里至少要有一条规则。"
      },
    )
  }
  let rules : Array[MappingRule] = []
  for index in 0..<mapping.length() {
    let item = mapping[index]
    let slot_raw = json_string(item, "slot")
    if slot_raw == "" {
      return Rejected(
        match lang {
          English => "rule " + index.to_string() + " has no slot"
          Chinese => "第 " + index.to_string() + " 条规则没有写槽。"
        },
      )
    }
    let slot = match model.slot_from_name(slot_raw) {
      Some(id) => id
      None =>
        return Rejected(
          match lang {
            English =>
              "rule " +
              index.to_string() +
              " names the slot \"" +
              slot_raw +
              "\", which this model does not have"
            Chinese =>
              "第 " +
              index.to_string() +
              " 条规则写的是槽「" +
              slot_raw +
              "」，而这台机器没有这个槽。"
          },
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
        match lang {
          English =>
            "rule " +
            index.to_string() +
            " has no keywords, so it can never fire"
          Chinese =>
            "第 " +
            index.to_string() +
            " 条规则没有关键词，因此永远不会触发。"
        },
      )
    }
    let mut label = json_string(item, "label")
    if label == "" {
      label = model.slot_designation(slot)
    }
    // The Chinese words are matched whatever the reader asked for, so a table
    // with none of them is still a table: it simply reads nothing when the
    // documents are Chinese.
    let keywords_zh : Array[String] = []
    for word in json_strings(item, "keywords_zh") {
      let trimmed = word.trim().to_owned()
      if trimmed != "" {
        keywords_zh.push(trimmed)
      }
    }
    // A rule with no Chinese name is shown in English, exactly as a name of
    // the machine's is: a table written only in English still runs, it just
    // answers in English.  The name of the slot it drives is not the name of
    // the rule, so borrowing it would be a different name pretending to be
    // this one.
    let label_zh = json_string(item, "label_zh")
    rules.push({
      keywords,
      keywords_zh,
      slot,
      label,
      label_zh,
      notes: json_string(item, "notes"),
      notes_zh: json_string(item, "notes_zh"),
    })
  }
  let fallback = match json_field(json, "fallback") {
    Some(Object(fields)) => fields
    _ =>
      return Rejected(
        match lang {
          English =>
            "fallback must say the slot a document that matches no rule drives"
          Chinese =>
            "兜底规则必须写明：一条没有命中任何规则的文档该推动哪个槽。"
        },
      )
  }
  let fallback_raw = match fallback.get("slot") {
    Some(String(value)) => value
    _ =>
      return Rejected(
        match lang {
          English => "fallback must name a slot"
          Chinese => "兜底规则必须写出一个槽。"
        },
      )
  }
  let fallback_slot = if fallback_raw == "" {
    ""
  } else {
    match model.slot_from_name(fallback_raw) {
      Some(id) => id
      None =>
        return Rejected(
          match lang {
            English =>
              "fallback names the slot \"" +
              fallback_raw +
              "\", which this model does not have"
            Chinese =>
              "兜底规则写的是槽「" +
              fallback_raw +
              "」，而这台机器没有这个槽。"
          },
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
  let mut fallback_label_zh = ""
  match fallback.get("label_zh") {
    Some(String(value)) => fallback_label_zh = value
    _ => ()
  }
  Accepted({ rules, fallback_slot, fallback_label, fallback_label_zh, path, })
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
      "keywords_zh": rule.keywords_zh,
      "label": rule.label,
      "label_zh": rule.label_zh,
      "notes": rule.notes,
      "notes_zh": rule.notes_zh,
      "slot": rule.slot,
    })
  }
  {
    "format": RESEARCH_FORMAT,
    "mapping": rules,
    "fallback": {
      "label": self.fallback_label,
      "label_zh": self.fallback_label_zh,
      "slot": self.fallback_slot,
    },
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
  match ResearchConfig::from_json(model, path, json, Lang::english()) {
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
