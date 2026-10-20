///|
/// The start-up, tested without touching the environment or the machine.
///
/// The start-up used to be tested by setting environment variables and
/// calling `install_from_environment`. That made the test depend on the
/// order things ran in: the environment is process-wide, and the test
/// driver runs these tests side by side, so one test's `MAKED_MODEL` was
/// another test's model. A test that says what the start-up does cannot
/// be one whose answer depends on its neighbours.
///
/// So the start-up is split in two. `read_startup_files` is given a plan
/// -- four paths, or nothing -- and reads them. `install_startup` installs
/// what was read. The reading is tested here, against files written for
/// this test, and the binding from the environment to the file that is
/// installed is tested where it can be seen from outside the process: the
/// integration suite starts a server with the variables set and asks it
/// what it is running.
///
/// The files here are written by the test rather than read from the
/// repository. A test that reads a file outside its own package is a test
/// that can fail for a reason that has nothing to do with the code: the
/// published package is not the working tree, and a data directory that
/// the repository has and the package does not turns a green test red in
/// the one place nobody is looking.

///|
/// A machine, in the machine's own format.
///
/// One domain, two positions, one slot and one rule -- the smallest thing
/// that is still a machine, and every part of it is checked against the
/// format the parser expects.
fn fixture_machine() -> Json {
  {
    "format": "maked.model.v1",
    "name": "Test machine",
    "domains": [
      {
        "id": "idea",
        "letter": "I",
        "title": "Idea",
        "role": "the idea",
        "anchor": "raw",
      },
    ],
    "positions": [
      {
        "id": "raw",
        "label": "Raw idea",
        "gloss": "Nobody has built it yet.",
        "domain": "idea",
      },
      {
        "id": "asked",
        "label": "A question asked",
        "gloss": "Somebody was asked.",
        "domain": "idea",
      },
    ],
    "slots": [
      {
        "id": "ask",
        "designation": "Ask",
        "gloss": "Talk to somebody who would use it.",
      },
    ],
    "rules": [
      {
        "from": "raw",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said no",
          "to": "asked",
        },
      },
    ],
  }
}

///|
/// A mapping table for that machine.
///
/// The slot it names is the machine's own, so the table fits it. A table
/// that named a slot the built-in machine does not have would be refused,
/// which is the next test.
fn fixture_table() -> Json {
  {
    "format": "maked.research.v1",
    "mapping": [
      {
        "keywords": ["question", "why"],
        "label": "A question worth asking",
        "slot": "ask",
        "notes": "",
      },
    ],
    "fallback": { "label": "Anything else", "slot": "ask" },
  }
}

///|
/// A society vocabulary naming one position the machine has.
///
/// A name the machine does not have is refused; a position the machine has
/// and the file does not name is a gap, and gaps are allowed. So one
/// position is a valid vocabulary.
fn fixture_society() -> Json {
  {
    "format": "maked.society.v1",
    "positions": [
      {
        "id": "World",
        "label": "Lifeworld",
        "gloss": "The prior place where speakers and listeners meet.",
      },
    ],
    "phases": [],
    "triggers": [],
  }
}

///|
/// A corpus that asks a public index for something.
fn fixture_corpus() -> Json {
  {
    "format": "maked.corpus.v1",
    "source": {
      "kind": "arxiv",
      "query": "(all:test)",
      "url": "",
      "path": "",
      "max_results": 5,
    },
  }
}

///|
/// Write a file for this test, and say that it was written.
///
/// The text is written by MAKED's own writer, in the syntax the file's
/// name asks for, so the fixture is read back exactly the way a file the
/// reader wrote would be.
async fn write_fixture(path : String, json : Json) -> Unit {
  @fs.write_file(path, @backend.data_text_for(path, json)) catch {
    err =>
      fail("the fixture " + path + " was not written: " + @debug.to_string(err))
  }
}

///|
/// Write a file for this test that is not in any format at all.
///
/// The broken fixtures are text rather than data: that is the point of
/// them, and a file that is valid JSON but the wrong shape is a different
/// mistake, tested elsewhere.
async fn write_text(path : String, text : String) -> Unit {
  @fs.write_file(path, text) catch {
    err =>
      fail(
        "the broken fixture " +
        path +
        " was not written: " +
        @debug.to_string(err),
      )
  }
}

///|
/// The four files of a plan that names everything, written for this test.
///
/// The tag is in the names because the test driver runs these tests side by
/// side: two tests sharing four file names means one of them takes the
/// files away while the other is still reading them, and the failure reads
/// as "the file was not there" rather than as "the tests are sharing".
async fn write_good_fixtures(tag : String) -> (String, String, String, String) {
  let machine = "test_bootstrap_" + tag + "_machine.json"
  let table = "test_bootstrap_" + tag + "_table.yaml"
  let society = "test_bootstrap_" + tag + "_society.yaml"
  let corpus = "test_bootstrap_" + tag + "_corpus.yaml"
  write_fixture(machine, fixture_machine())
  write_fixture(table, fixture_table())
  write_fixture(society, fixture_society())
  write_fixture(corpus, fixture_corpus())
  (machine, table, society, corpus)
}

///|
/// Take the fixtures away again.
async fn remove_fixtures(paths : Array[String]) -> Unit {
  for path in paths {
    @fs.remove(path) catch {
      _ => ()
    }
  }
}

///|
/// The plan that names the four files.
fn plan_of(
  machine : String?,
  table : String?,
  society : String?,
  corpus : String?,
) -> @backend.StartupPlan {
  @backend.StartupPlan::new(machine, table, society, corpus)
}

///|
/// A plan that names nothing.
fn empty_plan() -> @backend.StartupPlan {
  @backend.StartupPlan::empty()
}

///|
/// The files the plan names are the files that are read.
///
/// The machine, the table that says what a document means, the words for
/// the collective and the corpus are four separate files, and a start-up
/// that quietly ran on the built-in ones while the operator asked for
/// their own would answer every question about a machine nobody is
/// running.
async test "the files the plan names are the files that are read" {
  let (machine, table, society, corpus) = write_good_fixtures("read")
  let files = @backend.read_startup_files(
    plan_of(Some(machine), Some(table), Some(society), Some(corpus)),
  )
  remove_fixtures([machine, table, society, corpus])
  assert_eq(files.model_path, Some(machine))
  assert_eq(files.research_path, Some(table))
  assert_eq(files.society_path, Some(society))
  assert_eq(files.corpus_path, Some(corpus))
  assert_eq(files.refused_path, None)
  // And what came out of them is what those files say.
  match files.model {
    Some(read) => assert_eq(read.name, "Test machine")
    None => fail("the machine the plan names was not read")
  }
  match files.research {
    Some(read) => assert_eq(read.path, table)
    None => fail("the table the plan names was not read")
  }
  match files.society {
    Some(read) => assert_eq(read.path, society)
    None => fail("the vocabulary the plan names was not read")
  }
  match files.corpus {
    Some(read) => assert_eq(read.path, corpus)
    None => fail("the corpus the plan names was not read")
  }
}

///|
/// The table is checked against the machine the plan names.
///
/// The table names slots, and the machine is what has the slots. A table
/// that names a slot the machine does not have is a rule about nowhere, so
/// the check is made against the machine that will actually run -- and not
/// against whichever machine happened to be installed when the check was
/// made, which is a different thing whenever two servers start together.
async test "the table is checked against the machine the plan names" {
  let (machine, table, society, corpus) = write_good_fixtures("fit")
  let files = @backend.read_startup_files(
    plan_of(Some(machine), Some(table), Some(society), Some(corpus)),
  )
  remove_fixtures([machine, table, society, corpus])
  assert_eq(files.refused_path, None)
  match files.research {
    Some(read) => assert_eq(read.rules.length(), 1)
    None => fail("the table was refused against the machine it fits")
  }
}

///|
/// A table that does not fit the machine is refused.
///
/// The same table, read without the machine it belongs to. The built-in
/// machine's slots have other names, so every rule in the table is a rule
/// about nowhere, and the start-up says so rather than reading a table
/// that cannot fire.
async test "a table that does not fit the machine is refused" {
  let (machine, table, society, corpus) = write_good_fixtures("nofit")
  let files = @backend.read_startup_files(
    plan_of(None, Some(table), None, None),
  )
  remove_fixtures([machine, table, society, corpus])
  assert_eq(files.refused_kind, Some("research"))
  assert_eq(files.refused_path, Some(table))
}

///|
/// A machine that cannot be read is refused.
async test "a machine that cannot be read is refused" {
  let path = "test_bootstrap_broken_model.json"
  write_text(path, "this is not a machine")
  let files = @backend.read_startup_files(plan_of(Some(path), None, None, None))
  remove_fixtures([path])
  assert_eq(files.refused_kind, Some("model"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// A table that cannot be read is refused.
async test "a table that cannot be read is refused" {
  let path = "test_bootstrap_broken_table.yaml"
  write_text(path, "[unclosed")
  let files = @backend.read_startup_files(plan_of(None, Some(path), None, None))
  remove_fixtures([path])
  assert_eq(files.refused_kind, Some("research"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// A vocabulary that cannot be read is refused.
async test "a vocabulary that cannot be read is refused" {
  let path = "test_bootstrap_broken_society.yaml"
  write_text(path, "[unclosed")
  let files = @backend.read_startup_files(plan_of(None, None, Some(path), None))
  remove_fixtures([path])
  assert_eq(files.refused_kind, Some("society"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// A corpus that cannot be read is refused.
async test "a corpus that cannot be read is refused" {
  let path = "test_bootstrap_broken_corpus.yaml"
  write_text(path, "[unclosed")
  let files = @backend.read_startup_files(plan_of(None, None, None, Some(path)))
  remove_fixtures([path])
  assert_eq(files.refused_kind, Some("corpus"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// Nothing named means nothing read.
///
/// A start-up with no files named runs on the built-in machine and the
/// built-in table, and the built-in table fits the built-in machine, so
/// there is nothing to say.
async test "nothing named means nothing read" {
  let files = @backend.read_startup_files(empty_plan())
  assert_eq(files.model_path, None)
  assert_eq(files.research_path, None)
  assert_eq(files.society_path, None)
  assert_eq(files.corpus_path, None)
  assert_eq(files.refused_path, None)
  assert_eq(files.unfit_slot, None)
}

///|
/// The built-in table says so when it does not fit the machine.
///
/// The built-in table is the built-in machine's: it names slots like
/// "feedback" and "act". A machine of one's own has slots of its own, and
/// the reader is told rather than left to wonder why every document is
/// skipped in silence.
async test "the built-in table says so when it does not fit the machine" {
  let (machine, table, society, corpus) = write_good_fixtures("unfit")
  let files = @backend.read_startup_files(
    plan_of(Some(machine), None, None, None),
  )
  remove_fixtures([machine, table, society, corpus])
  assert_eq(files.unfit_slot, Some("feedback"))
}
