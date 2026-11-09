///| Tests for changing the machine while the server runs.
///
/// The machine was the one thing a reader could not change without stopping
/// the server: `MAKED_MODEL` was read once, at start-up, and the only way to
/// run on another machine was to start another server.
///
/// These tests are about the two things that make the change safe:
///
///  - **A file that cannot be read is refused, and nothing changes.** Half a
///    machine is worse than the one that was there.
///  - **A session keeps the machine it was run on.** The steps belong to that
///    machine, and a session read through another one would re-derive
///    positions the reader never stood at.
///
/// The machine is a global, so every test here puts the built-in one back
/// before it ends. A test that left a toy machine installed would be testing
/// whatever the next test happened to run on.
///

///|
fn switch_db_path(name : String) -> String {
  "test_switch_" + name + ".db"
}

///|
async fn open_switch_db(name : String) -> @backend.Database {
  let path = switch_db_path(name)
  drop_db(path)
  @backend.Database::open(path)
}

///|
/// A machine of the test's own, in words that are not the built-in machine's.
///
/// It is written out here rather than borrowed from `model_test.mbt`, because
/// a test that shares its fixture with the code it checks proves nothing: if
/// the shape of a machine file were wrong, both sides would be wrong in the
/// same way and the comparison would pass.
fn toy_machine_json() -> Json {
  {
    "format": "maked.model.v1",
    "name": "Toy machine",
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
        "id": "talked",
        "label": "Talked about",
        "gloss": "Someone has heard it.",
        "domain": "idea",
      },
    ],
    "slots": [
      { "id": "ask", "designation": "Ask", "gloss": "Talk to a customer." },
    ],
    "rules": [
      {
        "from": "raw",
        "slot": "ask",
        "outcome": {
          "kind": "moved",
          "edge": "A customer said no",
          "to": "talked",
        },
      },
      {
        "from": "talked",
        "slot": "ask",
        "outcome": {
          "kind": "held",
          "edge": "A customer said no",
          "to": "talked",
        },
      },
    ],
    "continuations": [],
  }
}

///|
/// Write the toy machine to a file, and say where it is.
async fn write_toy_model(path : String) -> Unit {
  @fs.write_file(path, @backend.data_text_for(path, toy_machine_json())) catch {
    err => fail("the machine was not written: " + @debug.to_string(err))
  }
}

///|
/// Take the toy machine away again.
async fn remove_toy_model(path : String) -> Unit {
  @fs.remove(path) catch {
    _ => ()
  }
}

///|
/// Put the built-in machine back, so that the next test runs on it.
fn restore_built_in() -> Unit {
  @backend.install_model(@backend.Model::pyroduct(), "")
}

///|
/// The machines in a folder are listed, in path order, and only the ones a
/// machine file can be.
///
/// A folder holds more than machines -- notes, tables, corpora -- and the
/// reader asked for the machines.
async test "the machines in a folder are listed, in path order" {
  let dir = "test_model_dir"
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    err => fail("the folder was not made: " + @debug.to_string(err))
  }
  let first = dir + "/a_machine.json"
  let second = dir + "/b_machine.yaml"
  let other = dir + "/notes.txt"
  write_toy_model(first)
  write_toy_model(second)
  @fs.write_file(other, "a note, not a machine") catch {
    err => fail("the note was not written: " + @debug.to_string(err))
  }
  let files = @backend.model_files_in(dir)
  remove_toy_model(first)
  remove_toy_model(second)
  @fs.remove(other) catch {
    _ => ()
  }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  assert_eq(files.length(), 2)
  assert_true(files[0].has_suffix("a_machine.json"))
  assert_true(files[1].has_suffix("b_machine.yaml"))
}

///|
/// The reader changes the machine while the server runs.
///
/// The machine in force is the new one, the file it came from is remembered,
/// and a new exploration is opened on it -- because the exploration that was
/// running belongs to the machine it was taken on.
async test "the machine can be changed while the server runs" {
  let db = open_switch_db("change")
  let path = "test_switch_machine.json"
  write_toy_model(path)
  let response = @backend.switch_model(db, path, @backend.Lang::english())
  let running = @backend.current_model()
  let running_path = @backend.current_model_path()
  restore_built_in()
  remove_toy_model(path)
  assert_eq(response.status, 200)
  assert_eq(running.name, "Toy machine")
  assert_eq(running_path, path)
  db.close()
}

///|
/// The machine in force is the one that was asked for.
///
/// The answer carries the machine as data, so a client can put the reader's
/// own words back on the screen rather than guessing what was installed.
async test "the answer carries the machine that is now running" {
  let db = open_switch_db("answer")
  let path = "test_switch_answer.json"
  write_toy_model(path)
  let response = @backend.switch_model(db, path, @backend.Lang::english())
  restore_built_in()
  remove_toy_model(path)
  assert_eq(response.status, 200)
  let body = match response.body {
    Json(json) => json
    _ => fail("the answer should be JSON")
  }
  let machine = match json_field(body, "model") {
    Some(json) => json
    None => fail("the answer should carry the machine")
  }
  assert_eq(json_str(machine, "name"), "Toy machine")
  assert_eq(json_str(body, "path"), path)
  db.close()
}

///|
/// A file that is not a machine is refused, and the machine in force keeps
/// running.
///
/// Half a machine is worse than the one that was there, so the refusal
/// changes nothing at all.
async test "a file that is not a machine is refused and nothing changes" {
  let db = open_switch_db("refuse")
  let path = "test_switch_broken.json"
  @fs.write_file(path, "this is not a machine") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  let before = @backend.current_model().name
  let response = @backend.switch_model(db, path, @backend.Lang::english())
  let after = @backend.current_model().name
  @fs.remove(path) catch {
    _ => ()
  }
  assert_eq(response.status, 400)
  assert_eq(after, before)
  db.close()
}

///|
/// A session keeps the machine it was run on.
///
/// The steps are that machine's, and a session that forgot the machine would
/// be a session whose history belonged to nobody.
async test "a session keeps the machine it was run on" {
  let db = open_switch_db("keeps")
  ignore(@backend.reset_loop())
  let session = fresh_session(db, "On the built-in machine")
  let built_in = @backend.current_model().name
  let path = "test_switch_keeps.json"
  write_toy_model(path)
  ignore(@backend.switch_model(db, path, @backend.Lang::english()))
  let stored = match db.session_by_id(session.id) {
    Some(s) => s
    None => fail("the session is not in the table any more")
  }
  let read_back = @backend.model_of_session(stored)
  restore_built_in()
  remove_toy_model(path)
  assert_eq(read_back.name, built_in)
  // And the session says which machine it was run on, because a reader with
  // two machines and two explorations has to be able to tell them apart.
  let json = stored.to_json()
  assert_eq(json_str(json, "model"), built_in)
  db.close()
}

///|
/// A session of another machine is not adopted.
///
/// The steps recorded into a session are that session's machine's steps, and
/// a session of another machine would collect steps that do not belong to it.
async test "a session of another machine is not adopted" {
  let db = open_switch_db("adopt")
  ignore(@backend.reset_loop())
  let session = fresh_session(db, "On the built-in machine")
  let path = "test_switch_adopt.json"
  write_toy_model(path)
  ignore(@backend.switch_model(db, path, @backend.Lang::english()))
  let chosen = @backend.ensure_session(db)
  let stored = match db.session_by_id(chosen) {
    Some(s) => s
    None => fail("the session is not in the table any more")
  }
  restore_built_in()
  remove_toy_model(path)
  assert_true(chosen != session.id)
  assert_eq(@backend.model_of_session(stored).name, "Toy machine")
  db.close()
}

///|
/// An exploration taken on one machine still reads through that machine.
///
/// The export is the reader's own copy of the run, and a run read through
/// another machine would show positions the reader never stood at.
async test "an exploration taken on one machine still reads through that machine" {
  let db = open_switch_db("reads")
  ignore(@backend.reset_loop())
  let session = fresh_session(db, "On the built-in machine")
  let state = take_steps(db, 1)
  assert_true(state.history.length() > 0)
  // The export as it reads while that machine is the one in force.
  let before = @backend.export_markdown(db, session, @backend.Lang::english())
  let path = "test_switch_reads.json"
  write_toy_model(path)
  ignore(@backend.switch_model(db, path, @backend.Lang::english()))
  // And the export as it reads afterwards, when the machine in force is
  // another one.
  let after = @backend.export_markdown(db, session, @backend.Lang::english())
  restore_built_in()
  remove_toy_model(path)
  // The same document: the run is described in the machine it was taken on,
  // and the machine in force does not change what the reader did.
  assert_eq(after, before)
  // And it is not the toy machine's words.
  assert_false(after.contains("Raw idea"))
  db.close()
}

///|
/// Opening an exploration brings its machine back with it.
///
/// The steps are re-derived against the machine they were taken on, and a
/// step taken afterwards has to be taken on the machine the steps before it
/// were -- so the machine comes back with the session.
async test "opening an exploration brings its machine back" {
  let db = open_switch_db("opens")
  ignore(@backend.reset_loop())
  let session = fresh_session(db, "On the built-in machine")
  let path = "test_switch_opens.json"
  write_toy_model(path)
  ignore(@backend.switch_model(db, path, @backend.Lang::english()))
  // The machine in force is now the toy one, and the old session is on the
  // built-in one.
  assert_eq(@backend.current_model().name, "Toy machine")
  let outcome = @backend.activate_session(db, session.id)
  let running = @backend.current_model().name
  restore_built_in()
  remove_toy_model(path)
  assert_true(outcome is @backend.Done(_))
  assert_true(running != "Toy machine")
  db.close()
}
