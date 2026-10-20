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
/// what was read. The reading is tested here, against files named
/// outright, and the binding from the environment to the files that are
/// installed is tested where it can be seen from outside the process: the
/// integration suite starts a server with the variables set and asks it
/// what it is running.

///|
/// The plan that names the four files MAKED ships with.
fn shipped_plan() -> @backend.StartupPlan {
  @backend.StartupPlan::new(
    Some("models/product-iteration.json"),
    Some("research/product-iteration.yaml"),
    Some("research/society.yaml"),
    Some("research/corpus-arxiv.yaml"),
  )
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
  let files = @backend.read_startup_files(shipped_plan())
  assert_eq(files.model_path, Some("models/product-iteration.json"))
  assert_eq(files.research_path, Some("research/product-iteration.yaml"))
  assert_eq(files.society_path, Some("research/society.yaml"))
  assert_eq(files.corpus_path, Some("research/corpus-arxiv.yaml"))
  assert_eq(files.refused_path, None)
  // And what came out of them is what those files say.
  match files.model {
    Some(model) => assert_eq(model.name, "Product iteration")
    None => fail("the machine the plan names was not read")
  }
  match files.research {
    Some(table) => assert_eq(table.path, "research/product-iteration.yaml")
    None => fail("the table the plan names was not read")
  }
  match files.society {
    Some(words) => assert_eq(words.path, "research/society.yaml")
    None => fail("the vocabulary the plan names was not read")
  }
  match files.corpus {
    Some(corpus) => assert_eq(corpus.path, "research/corpus-arxiv.yaml")
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
  let files = @backend.read_startup_files(shipped_plan())
  assert_eq(files.refused_path, None)
  match files.research {
    Some(table) => assert_eq(table.rules.length(), 4)
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
  let plan = @backend.StartupPlan::new(
    None,
    Some("research/product-iteration.yaml"),
    None,
    None,
  )
  let files = @backend.read_startup_files(plan)
  assert_eq(files.refused_kind, Some("research"))
  assert_eq(files.refused_path, Some("research/product-iteration.yaml"))
}

///|
/// A machine that cannot be read is refused.
async test "a machine that cannot be read is refused" {
  let path = "test_bootstrap_broken_model.json"
  @fs.write_file(path, "this is not a machine") catch {
    err => fail("the broken machine was not written: " + @debug.to_string(err))
  }
  let plan = @backend.StartupPlan::new(Some(path), None, None, None)
  let files = @backend.read_startup_files(plan)
  @fs.remove(path) catch {
    _ => ()
  }
  assert_eq(files.refused_kind, Some("model"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// A table that cannot be read is refused.
async test "a table that cannot be read is refused" {
  let path = "test_bootstrap_broken_table.yaml"
  @fs.write_file(path, "[unclosed") catch {
    err => fail("the broken table was not written: " + @debug.to_string(err))
  }
  let plan = @backend.StartupPlan::new(None, Some(path), None, None)
  let files = @backend.read_startup_files(plan)
  @fs.remove(path) catch {
    _ => ()
  }
  assert_eq(files.refused_kind, Some("research"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// A vocabulary that cannot be read is refused.
async test "a vocabulary that cannot be read is refused" {
  let path = "test_bootstrap_broken_society.yaml"
  @fs.write_file(path, "[unclosed") catch {
    err =>
      fail("the broken vocabulary was not written: " + @debug.to_string(err))
  }
  let plan = @backend.StartupPlan::new(None, None, Some(path), None)
  let files = @backend.read_startup_files(plan)
  @fs.remove(path) catch {
    _ => ()
  }
  assert_eq(files.refused_kind, Some("society"))
  assert_eq(files.refused_path, Some(path))
}

///|
/// A corpus that cannot be read is refused.
async test "a corpus that cannot be read is refused" {
  let path = "test_bootstrap_broken_corpus.yaml"
  @fs.write_file(path, "[unclosed") catch {
    err => fail("the broken corpus was not written: " + @debug.to_string(err))
  }
  let plan = @backend.StartupPlan::new(None, None, None, Some(path))
  let files = @backend.read_startup_files(plan)
  @fs.remove(path) catch {
    _ => ()
  }
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
  let plan = @backend.StartupPlan::new(
    Some("models/product-iteration.json"),
    None,
    None,
    None,
  )
  let files = @backend.read_startup_files(plan)
  assert_eq(files.unfit_slot, Some("feedback"))
}
