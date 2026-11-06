///| Research configuration tests.
///
/// The mapping table is data: it is read from a file, edited, and written
/// back. Three things can go wrong with that, and each is pinned here:
///
///   1. A table that names a slot the running model does not have is a rule
///      about nowhere, and it is refused rather than half-read.
///   2. A table written in one syntax and read as the other is a table that
///      half-reads, and the write-back keeps the syntax the file's name
///      asks for.
///   3. A table that was edited and is not the one that runs is a table the
///      reader believes is in force and is not.
///
/// MoonBit compiles a `_test.mbt` file as a *blackbox* package: it sees only
/// `pub` items and wants cross-file names qualified as `@backend.<name>`.

///|
/// A table with one rule, as JSON.
///
/// The rule's slot is a parameter, because "a rule that names a slot the
/// model does not have" is one of the things being tested.
fn one_rule_table(slot : String) -> Json {
  {
    "format": "maked.research.v1",
    "mapping": [
      { "keywords": ["reproduce"], "label": "A reproduction", "slot": slot },
    ],
    "fallback": { "label": "Anything else", "slot": "act" },
  }
}

///|
/// The built-in model, which is the model the built-in table belongs to.
fn built_in_model() -> @backend.Model {
  @backend.Model::pyroduct()
}

///|
/// A table that names a slot the model does not have is refused.
test "a table that names a slot the model does not have is refused" {
  let model = built_in_model()
  match
    @backend.ResearchConfig::from_json(
      model,
      "",
      one_rule_table("ship"),
      @backend.Lang::english(),
    ) {
    @backend.Rejected(reason) => assert_true(reason.contains("ship"))
    @backend.Accepted(_) =>
      fail("a table that names a slot the model does not have was accepted")
  }
}

///|
/// A rule with no keywords can never fire, and is refused.
test "a rule with no keywords is refused" {
  let model = built_in_model()
  // An explicitly empty list, which is what a reader gets when they type
  // the field and leave it empty.
  let no_keywords : Array[Json] = []
  let json : Json = {
    "format": "maked.research.v1",
    "mapping": [{ "keywords": no_keywords, "label": "Nothing", "slot": "act" }],
    "fallback": { "label": "Anything else", "slot": "act" },
  }
  match
    @backend.ResearchConfig::from_json(
      model,
      "",
      json,
      @backend.Lang::english(),
    ) {
    @backend.Rejected(reason) => assert_true(reason.contains("keywords"))
    @backend.Accepted(_) => fail("a rule with no keywords was accepted")
  }
}

///|
/// A table with no rules at all is refused: it says nothing, and saying
/// nothing is not a table.
test "a table with no rules is refused" {
  let model = built_in_model()
  let json : Json = {
    "format": "maked.research.v1",
    "mapping": [],
    "fallback": { "label": "Anything else", "slot": "act" },
  }
  match
    @backend.ResearchConfig::from_json(
      model,
      "",
      json,
      @backend.Lang::english(),
    ) {
    @backend.Rejected(reason) =>
      assert_true(reason.contains("at least one rule"))
    @backend.Accepted(_) => fail("a table with no rules was accepted")
  }
}

///|
/// A table in another format is refused rather than read as if it were this
/// one.
test "a table in another format is refused" {
  let model = built_in_model()
  let json : Json = {
    "format": "maked.research.v2",
    "mapping": [
      { "keywords": ["reproduce"], "label": "A reproduction", "slot": "act" },
    ],
    "fallback": { "label": "Anything else", "slot": "act" },
  }
  match
    @backend.ResearchConfig::from_json(
      model,
      "",
      json,
      @backend.Lang::english(),
    ) {
    @backend.Rejected(reason) => assert_true(reason.contains("format"))
    @backend.Accepted(_) => fail("a table in another format was accepted")
  }
}

///|
/// A refusal is a sentence the reader reads, and the reader asked for a
/// language.
///
/// A table is edited by hand, and the person editing it is the one who has to
/// read what went wrong -- which rule is wrong, which field is missing, and
/// why it matters. So the reason is written in the language asked for.
///
/// The English is the English it was: the language is a dimension beside the
/// wording, not a replacement of it.
test "a refusal of a table is in the language that was asked for" {
  let model = built_in_model()
  let no_rules : Json = {
    "format": "maked.research.v1",
    "mapping": [],
    "fallback": { "label": "Anything else", "slot": "act" },
  }
  let english = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      no_rules,
      @backend.Lang::english(),
    ) {
    @backend.Rejected(reason) => reason
    @backend.Accepted(_) => fail("a table with no rules was accepted")
  }
  let chinese = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      no_rules,
      @backend.Lang::chinese(),
    ) {
    @backend.Rejected(reason) => reason
    @backend.Accepted(_) => fail("a table with no rules was accepted")
  }
  assert_true(english.contains("at least one rule"))
  assert_true(chinese.contains("至少"))
  assert_true(chinese != english)
  // The Chinese sentence ends the way a Chinese sentence ends.
  assert_true(chinese.has_suffix("。"))

  // The rule that names a slot the model does not have says WHICH rule and
  // WHICH slot -- in both languages.
  let english_slot = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      one_rule_table("ship"),
      @backend.Lang::english(),
    ) {
    @backend.Rejected(reason) => reason
    @backend.Accepted(_) => fail("a table naming a slot was accepted")
  }
  let chinese_slot = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      one_rule_table("ship"),
      @backend.Lang::chinese(),
    ) {
    @backend.Rejected(reason) => reason
    @backend.Accepted(_) => fail("a table naming a slot was accepted")
  }
  assert_true(english_slot.contains("ship"))
  assert_true(chinese_slot.contains("ship"))
  assert_true(chinese_slot.contains("没有这个槽"))
  assert_true(chinese_slot != english_slot)
}

///|
/// The same table in the two syntaxes, is the same table.
///
/// The file's name decides how it is read, and a table written as YAML and
/// read as JSON is a table that half-reads -- so the two must agree.
test "the same table in the two syntaxes is the same table" {
  let model = built_in_model()
  let from_json = match
    @backend.ResearchConfig::from_json(
      model,
      "table.json",
      one_rule_table("act"),
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the JSON table was refused: " + reason)
  }
  let text = @backend.data_text_for("table.yaml", from_json.to_json())
  let json = match @backend.parse_data_text("research", "table.yaml", text) {
    Some(json) => json
    None => fail("the YAML table was not read")
  }
  let from_yaml = match
    @backend.ResearchConfig::from_json(
      model,
      "table.yaml",
      json,
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the YAML table was refused: " + reason)
  }
  assert_eq(from_yaml.to_json(), from_json.to_json())
}

///|
/// A table written back is the table that was read.
///
/// The point of writing it back is that the edit survives the server
/// stopping, and an edit that is read back as a different table has not
/// survived anything.
async test "a table written back is the table that was read" {
  let model = built_in_model()
  let original = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      one_rule_table("act"),
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the table was refused: " + reason)
  }
  let path = "test_research_table.yaml"
  let text = @backend.data_text_for(path, original.to_json())
  @fs.write_file(path, text) catch {
    err => fail("the table was not written: " + @debug.to_string(err))
  }
  let read_back = match @backend.read_research_file(path) {
    Some(config) => config
    None => fail("the table that was written was not read back")
  }
  assert_eq(read_back.to_json(), original.to_json())
  // The file's name is remembered, because that is what makes the table
  // writable back.
  assert_eq(read_back.path, path)
  @fs.remove(path) catch {
    _ => ()
  }
}

///|
/// The built-in table belongs to the built-in model.
///
/// A model file has slots of its own, and the built-in table names slots
/// like "feedback" and "act". Saying so is better than letting every
/// document be skipped in silence.
test "the built-in table does not fit a model with other slots" {
  let model = model_or_fail(toy_model())
  let slot = @backend.ResearchConfig::builtin().first_unfitting_slot(model)
  // The *first* slot that does not fit, not just any of them: a check that
  // only asks whether the table fits somewhere would still pass when the
  // table answers with a different slot than it should.
  assert_eq(slot, Some("feedback"))
}

///|
/// A table is written back in the syntax its file's name asks for.
///
/// JSON is a subset of YAML, so a YAML file written as JSON still reads
/// back as the very same table -- which is exactly why the syntax has to
/// be checked rather than inferred from what reads. A reader who opens a
/// .yaml file and finds braces in it has been handed a file in a language
/// they did not ask for.
test "a table is written back in the syntax its file's name asks for" {
  let config = @backend.ResearchConfig::builtin()
  let yaml_text = @backend.data_text_for("table.yaml", config.to_json())
  let json_text = @backend.data_text_for("table.json", config.to_json())
  // The YAML form writes the key as a word; the JSON form writes it in
  // quotes.
  assert_true(yaml_text.contains("format:"))
  assert_true(!yaml_text.contains("\"format\""))
  assert_true(json_text.contains("\"format\""))
}

///|
/// The built-in table does fit the built-in model.
test "the built-in table fits the built-in model" {
  let model = built_in_model()
  assert_true(
    @backend.ResearchConfig::builtin().first_unfitting_slot(model) is None,
  )
}

///|
/// A keyword is matched whatever its case.
///
/// The document is not written by MAKED and does not know what case the
/// table's words are in, and a table that only matched one case would be a
/// table that silently reads half the documents.
test "a keyword is matched whatever its case" {
  let config = @backend.ResearchConfig::builtin()
  let (slot, _) = config.slot_for_text("A NOVEL METHOD for the task")
  assert_eq(slot, "act")
}

///|
/// The table that runs is the table that was installed.
///
/// A server that read a file and then ran the built-in table anyway would
/// answer every request confidently and about the wrong table.
test "the table that runs is the table that was installed" {
  let model = built_in_model()
  let table = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      one_rule_table("hold"),
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the table was refused: " + reason)
  }
  @backend.install_research(table)
  assert_eq(@backend.current_research().to_json(), table.to_json())
  // Put the built-in table back, so that a test which reads the installed
  // table is not reading this one.
  @backend.install_research(@backend.ResearchConfig::builtin())
}

///|
/// A table with no fallback slot leaves the documents it does not know
/// alone.
///
/// "Leave it alone" is a decision, and it has to be one the reader made
/// rather than one the code made by accident.
test "a table with no fallback leaves unknown documents alone" {
  let model = built_in_model()
  let json : Json = {
    "format": "maked.research.v1",
    "mapping": [
      { "keywords": ["reproduce"], "label": "A reproduction", "slot": "act" },
    ],
    "fallback": { "label": "Nothing the table knows", "slot": "" },
  }
  let config = match
    @backend.ResearchConfig::from_json(
      model,
      "",
      json,
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the table was refused: " + reason)
  }
  let (slot, _) = config.slot_for_text("Something the table has never seen")
  assert_eq(slot, "")
}

///|
/// The machine that ships with the repository, read from its file.
async fn shipped_iteration_model() -> @backend.Model {
  let path = "models/product-iteration.json"
  let text = @fs.read_file(path).text() catch {
    err =>
      fail("the shipped machine could not be read: " + @debug.to_string(err))
  }
  let json = match @backend.parse_model_text(path, text) {
    Some(parsed) => parsed
    None => fail("the shipped machine was not read at all: " + path)
  }
  match @backend.Model::from_json(json) {
    Some(model) => model
    None => fail("the shipped machine was refused: " + path)
  }
}

///|
/// The mapping table that ships with the repository, read from its file.
async fn shipped_iteration_table() -> @backend.ResearchConfig {
  let path = "research/product-iteration.yaml"
  let text = @fs.read_file(path).text() catch {
    err => fail("the shipped table could not be read: " + @debug.to_string(err))
  }
  let json = match @backend.parse_data_text("research", path, text) {
    Some(parsed) => parsed
    None => fail("the shipped table was not read at all: " + path)
  }
  match
    @backend.ResearchConfig::from_json(
      shipped_iteration_model(),
      path,
      json,
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) =>
      fail("the shipped table was refused: " + reason)
  }
}

///|
/// A document with the given words in it.
fn note_with(title : String, summary : String) -> @backend.Document {
  {
    id: "1",
    title,
    summary,
    authors: [],
    categories: [],
    published: "2024-01-01",
    link: "",
  }
}

///|
/// The shipped table reads a document written in Chinese.
///
/// The table's words used to be English only, so a Chinese document matched
/// no rule at all and the corpus was read by nothing. The table is the
/// reader's own, and the reader's documents are in the reader's language.
async test "the shipped table reads a document written in Chinese" {
  let table = shipped_iteration_table()
  let (slot, label) = @backend.document_to_slot_in(
    table,
    note_with("这一版的实现", "我们先做了原型，再谈别的。"),
    @backend.Lang::chinese(),
  )
  assert_eq(slot, "build")
  assert_eq(label, "正在做出来的东西")
}

///|
/// The rule is named in the reader's language.
///
/// The same document, read by two readers: the slot it drives is the
/// machine's and is the same either way, and the name of the rule is the
/// reader's own words and is not.
async test "the rule that fired is named in the reader's language" {
  let table = shipped_iteration_table()
  let document = note_with(
    "这一版的实现", "我们先做了原型，再谈别的。",
  )
  let (english_slot, english_label) = @backend.document_to_slot_in(
    table,
    document,
    @backend.Lang::english(),
  )
  let (chinese_slot, chinese_label) = @backend.document_to_slot_in(
    table,
    document,
    @backend.Lang::chinese(),
  )
  assert_eq(english_slot, chinese_slot)
  assert_eq(english_slot, "build")
  assert_eq(english_label, "A thing being built")
  assert_eq(chinese_label, "正在做出来的东西")
}

///|
/// A Chinese reader still reads a document written in English.
///
/// The corpus is the operator's choice and it may hold either language, so
/// the words a rule matches are not the reader's language: what the
/// language chooses is the name of the rule, and nothing else.
async test "a Chinese reader still reads a document written in English" {
  let table = shipped_iteration_table()
  let (slot, label) = @backend.document_to_slot_in(
    table,
    note_with("The implementation", "We built the prototype first."),
    @backend.Lang::chinese(),
  )
  assert_eq(slot, "build")
  assert_eq(label, "正在做出来的东西")
}

///|
/// The shipped table names every rule in both languages.
///
/// A rule with no Chinese name is a rule a Chinese reader cannot read, and
/// a rule with no Chinese words is a rule that cannot fire on a Chinese
/// document: both are gaps in the table that ships, and both are named here
/// so that a gap says which rule it is.
async test "the shipped table names every rule in both languages" {
  let table = shipped_iteration_table()
  for rule in table.rules {
    assert_true(rule.label_zh != "")
    assert_true(rule.notes_zh != "")
    assert_true(rule.keywords_zh.length() > 0)
  }
  assert_true(table.fallback_label_zh != "")
}

///|
/// The Chinese names of the table survive a trip through JSON.
///
/// A table is written back when the reader edits it in the browser, and a
/// write-back that dropped the Chinese would quietly take the table back to
/// one language.
async test "the Chinese names of the table survive a trip through JSON" {
  let table = shipped_iteration_table()
  let json = table.to_json()
  let read_back = match
    @backend.ResearchConfig::from_json(
      shipped_iteration_model(),
      "research/product-iteration.yaml",
      json,
      @backend.Lang::english(),
    ) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the table was refused: " + reason)
  }
  assert_eq(read_back.to_json(), table.to_json())
  for i in 0..<table.rules.length() {
    assert_eq(read_back.rules[i].label_zh, table.rules[i].label_zh)
    assert_eq(read_back.rules[i].keywords_zh, table.rules[i].keywords_zh)
  }
}
