///| Reading a file that may be written in JSON or in YAML.
///
/// The extension decides which, and nothing else does. The two syntaxes
/// overlap -- JSON is a subset of YAML -- so a file read as the wrong one is
/// a file that half-reads, and half a table is worse than no table at all.
/// This is the rule the model file follows and the rule the research file
/// follows, so it lives here rather than in either of them.
///
/// The `kind` is what the file is called in the messages: "model file",
/// "research file". A file that cannot be read should say what it was
/// trying to be, and a message that says "model" about a research file is a
/// message about the wrong thing.

///|
/// Whether a path names a YAML file.
///
/// The extension, and nothing else. A file called `.yml` is YAML and a file
/// called anything else is JSON, and the reason for the rule is the same as
/// the reason for reading the file at all: a file that is read as the wrong
/// syntax is a file that is half-read.
pub fn is_yaml_path(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".yaml") || lower.has_suffix(".yml")
}

///|
/// The JSON a data file says, whatever syntax the file is written in.
///
/// A `.yaml` or `.yml` file is read as YAML, and everything else as JSON.
/// The extension is the whole of the decision, and it is a decision rather
/// than a guess: the two syntaxes overlap -- JSON is a subset of YAML -- so
/// a file that says one thing and is read as the other is a file that
/// half-read, and half a machine is worse than none.
///
/// A YAML file with more than one document in it is refused. A data file is
/// one thing, and a file with two of them in it is a file whose author was
/// not sure which one they meant.
pub fn parse_data_text(kind : String, path : String, text : String) -> Json? {
  if is_yaml_path(path) {
    let documents = @yaml.Yaml::load_from_string(text) catch {
      err => {
        eprintln(
          "error: \{kind} file \{path} is not YAML: \{@debug.to_string(err)}",
        )
        return None
      }
    }
    if documents.length() == 0 {
      eprintln("error: \{kind} file \{path} is empty")
      return None
    }
    if documents.length() > 1 {
      eprintln(
        "error: \{kind} file \{path} holds \{documents.length()} documents; a \{kind} file holds one",
      )
      return None
    }
    Some(documents[0].to_json())
  } else {
    let json = @json.parse(text) catch {
      err => {
        eprintln("error: \{kind} file \{path} is not JSON: \{err}")
        return None
      }
    }
    Some(json)
  }
}

///|
/// Read a data file and give back the JSON it says.
///
/// None when the file cannot be read or cannot be understood, with the
/// reason printed. The reason matters: a file that is not read is a file
/// the operator has to go and look at, and "it did not work" is not
/// something anybody can act on.
pub async fn read_data_text(kind : String, path : String) -> Json? {
  let text = @fs.read_file(path).text() catch {
    err => {
      eprintln("error: \{kind} file \{path} unreadable: \{err}")
      return None
    }
  }
  parse_data_text(kind, path, text)
}

///|
/// The text read as a whole number, if it is one.
///
/// `3` is a whole number and `3.0` is not, and the difference is the
/// difference between a YAML file that says `3` and one that says `3.0` --
/// which is the difference between a file a reader edits and a file a
/// reader distrusts.
fn whole_number(text : String) -> Int64? {
  let number = @string.parse_int64(text) catch { _ => return None }
  Some(number)
}

///|
/// The YAML a piece of JSON is, as a YAML value.
///
/// The other direction of the yaml package's `to_json`, and it is here
/// because a file that can be read has to be writable too: a table edited
/// in the browser is worth nothing if the edit disappears when the server
/// stops. The mapping is the yaml package's own, read in reverse.
///
/// Numbers: a whole number is written as an integer and anything else as a
/// real, so that a value that was read as `3` is written back as `3` and
/// not as `3.0`.
pub fn json_to_yaml(json : Json) -> @yaml.Yaml {
  match json {
    Null => @yaml.Yaml::Null
    True => @yaml.Yaml::Boolean(true)
    False => @yaml.Yaml::Boolean(false)
    Number(value, repr~) => {
      // A whole number is written as an integer and anything else as a
      // real, so that a value that was read as `3` is written back as `3`
      // and not as `3.0`. The text of the number decides where there is
      // one: `3.0` and `3` are the same number, and the text is what the
      // author wrote.
      let text = match repr {
        Some(written) => written
        None => value.to_string()
      }
      match whole_number(text) {
        Some(number) => @yaml.Yaml::Integer(number)
        None => @yaml.Yaml::Real(value, repr=text)
      }
    }
    String(value) => @yaml.Yaml::String(value)
    Array(items) => {
      let out : Array[@yaml.Yaml] = []
      for item in items {
        out.push(json_to_yaml(item))
      }
      @yaml.Yaml::Array(out)
    }
    Object(fields) => {
      let out = Map([], capacity=8)
      for (name, value) in fields {
        out[name] = json_to_yaml(value)
      }
      @yaml.Yaml::Map(out)
    }
  }
}

///|
/// The text a data file should hold, in the syntax its name asks for.
///
/// A `.yaml` or `.yml` file is written as YAML and everything else as JSON,
/// which is the same rule that decides how the file is read. A file written
/// in one syntax and read as the other is a file that half-reads, and a
/// write-back that changed the syntax would do the same thing to a file
/// that was read whole.
pub fn data_text_for(path : String, json : Json) -> String {
  if is_yaml_path(path) {
    @yaml.Yaml::dump(json_to_yaml(json))
  } else {
    // Two spaces of indent, because this file is meant to be read by a
    // person as well as by MAKED, and a table written on one line is a
    // table nobody edits.
    json.stringify(indent=2)
  }
}
