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
  match @backend.ResearchConfig::from_json(model, "", one_rule_table("ship")) {
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
  match @backend.ResearchConfig::from_json(model, "", json) {
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
  match @backend.ResearchConfig::from_json(model, "", json) {
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
  match @backend.ResearchConfig::from_json(model, "", json) {
    @backend.Rejected(reason) => assert_true(reason.contains("format"))
    @backend.Accepted(_) => fail("a table in another format was accepted")
  }
}

///|
/// The same table, in the two syntaxes, is the same table.
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
    @backend.ResearchConfig::from_json(model, "table.yaml", json) {
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
    @backend.ResearchConfig::from_json(model, "", one_rule_table("act")) {
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
    @backend.ResearchConfig::from_json(model, "", one_rule_table("hold")) {
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
  let config = match @backend.ResearchConfig::from_json(model, "", json) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the table was refused: " + reason)
  }
  let (slot, _) = config.slot_for_text("Something the table has never seen")
  assert_eq(slot, "")
}
