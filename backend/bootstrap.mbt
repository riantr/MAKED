///| Starting MAKED: the machine, the table, the words and the corpus.
///
/// The web server and the agent's server start the same way, and the rules
/// are the same rules: a file that cannot be read whole is refused rather
/// than half-read. A machine that half-reads answers every request
/// confidently and wrongly, which is the worst thing a server can do, and a
/// table that half-reads fires on the wrong documents.
///
/// So the start-up lives here and both callers are thin. A second copy of
/// "which files does MAKED run" is a second thing to keep in step with the
/// first, and the one that drifts is the one nobody is looking at.
///
/// Everything said here goes to **stderr**, not stdout. The agent's server
/// speaks the Model Context Protocol over stdout, and a line of prose in
/// the middle of a protocol stream is a line the client cannot parse: the
/// transport dies on it, and the reason MAKED refused to start is lost in
/// the noise. Diagnostics belong on stderr anyway, and stdout in this
/// project now means exactly one thing -- the protocol, in the process
/// where there is a protocol.

///|
/// The four files the start-up runs on.
///
/// A plan is a value rather than an effect, so the question "which files
/// would this environment name" has an answer that does not require
/// changing what MAKED is running. That is what makes the start-up
/// checkable: the files can be read, and refused, before anything about
/// MAKED has changed.
pub struct StartupPlan {
  model_path : String?
  research_path : String?
  society_path : String?
  corpus_path : String?
}

///|
/// A plan that names four files.
pub fn StartupPlan::new(
  model_path : String?,
  research_path : String?,
  society_path : String?,
  corpus_path : String?,
) -> StartupPlan {
  { model_path, research_path, society_path, corpus_path, }
}

///|
/// A plan that names nothing: the built-in machine, the built-in table,
/// the built-in vocabulary and the built-in corpus.
pub fn StartupPlan::empty() -> StartupPlan {
  StartupPlan::new(None, None, None, None)
}

///|
/// The files the start-up read, and what came out of them.
///
/// Reading and installing are two separate steps on purpose. A start-up
/// that read and installed in one breath could not say what it had read
/// without having already changed what MAKED was running, and a test of
/// "does the environment name the file that is read" would then be a test
/// of the order things happened to run in.
pub(all) struct StartupFiles {
  model : Model?
  research : ResearchConfig?
  society : SocietyVocabulary?
  corpus : CorpusConfig?
  model_path : String?
  research_path : String?
  society_path : String?
  corpus_path : String?
  /// Which kind of file could not be read: "model", "research", "society"
  /// or "corpus".
  refused_kind : String?
  /// The path of the file that could not be read.
  refused_path : String?
  /// The slot the built-in table names and the named machine does not have.
  unfit_slot : String?
}

///|
/// The files the environment names.
///
/// The environment is read here and nowhere else, so that the rest of the
/// start-up can be given its files directly.
pub fn startup_plan_from_env() -> StartupPlan {
  {
    model_path: model_path_from_env(),
    research_path: research_path_from_env(),
    society_path: society_path_from_env(),
    corpus_path: corpus_path_from_env(),
  }
}

///|
/// A file that could not be read, and nothing else.
///
/// The start-up stops at the first file it cannot read. A machine that
/// half-reads answers every request confidently and wrongly, and that is
/// the worst thing a server can do, so the files that were read before the
/// bad one are dropped rather than kept.
fn refusing(kind : String, path : String) -> StartupFiles {
  {
    model: None,
    research: None,
    society: None,
    corpus: None,
    model_path: None,
    research_path: None,
    society_path: None,
    corpus_path: None,
    refused_kind: Some(kind),
    refused_path: Some(path),
    unfit_slot: None,
  }
}

///|
/// Read the files the plan names, and say which ones were read.
///
/// The machine is read first, because the table names slots and the machine
/// is what has the slots. The table is checked against the machine the
/// *plan* names, not against the machine that happens to be running, so
/// the same plan always gives the same answer.
///
/// Nothing is installed here. Reading is separate from installing so the
/// files can be checked before anything about MAKED changes.
pub async fn read_startup_files(plan : StartupPlan) -> StartupFiles {
  let model = match plan.model_path {
    Some(path) =>
      match read_model_file(path) {
        Some(read_machine) => Some(read_machine)
        None => return refusing("model", path)
      }
    None => None
  }
  // The machine the table is checked against: the one the plan names, or
  // the built-in one when the plan names none.
  let machine = match model {
    Some(read_machine) => read_machine
    None => Model::pyroduct()
  }
  // The table that says what a document means.
  let research = match plan.research_path {
    Some(path) =>
      match read_research_file_for(machine, path) {
        Some(read_table) => Some(read_table)
        None => return refusing("research", path)
      }
    None => None
  }
  // The words for the Society layer. The society machine is pyroduct's, and
  // a vocabulary that half-reads leaves the collective's positions unnamed
  // -- a panel that shows a collective and cannot say where it is.
  let society = match plan.society_path {
    Some(path) =>
      match read_society_file(path) {
        Some(read_words) => Some(read_words)
        None => return refusing("society", path)
      }
    None => None
  }
  // The corpus the documents come from. A server that quietly fell back to
  // arxiv would show the reader a panel full of papers while their own
  // documents went unread, and a panel full of the wrong documents is a lie
  // told with a straight face.
  let corpus = match plan.corpus_path {
    Some(path) =>
      match read_corpus_file(path) {
        Some(read_corpus) => Some(read_corpus)
        None => return refusing("corpus", path)
      }
    None => None
  }
  // The built-in table is the built-in machine's: it names slots like
  // "feedback" and "act". A model file has slots of its own, and a table
  // that names a slot the running model does not have is a rule about
  // nowhere. Saying so at start-up is better than letting every document
  // be skipped in silence.
  let unfit = match research {
    Some(_) => None
    None =>
      match ResearchConfig::builtin().first_unfitting_slot(machine) {
        Some(slot) => Some(slot)
        None => None
      }
  }
  {
    model,
    research,
    society,
    corpus,
    model_path: plan.model_path,
    research_path: plan.research_path,
    society_path: plan.society_path,
    corpus_path: plan.corpus_path,
    refused_kind: None,
    refused_path: None,
    unfit_slot: unfit,
  }
}

///|
/// Install the files that were read.
///
/// This is the one step that changes what MAKED is running. The machine is
/// installed first, because the table is checked against it.
pub fn install_startup(files : StartupFiles) -> Bool {
  match files.model {
    Some(read_machine) => install_model(read_machine)
    None => ()
  }
  match files.research {
    Some(read_table) => install_research(read_table)
    None => ()
  }
  match files.society {
    Some(read_words) => install_society_vocabulary(read_words)
    None => ()
  }
  match files.corpus {
    Some(read_corpus) => install_corpus(read_corpus)
    None => ()
  }
  true
}

///|
/// What a file of this kind is called, when it could not be read.
fn refused_noun(kind : String?) -> String {
  match kind {
    Some("model") => "a model"
    Some("research") => "a mapping table"
    Some("society") => "a society vocabulary"
    Some("corpus") => "a corpus"
    _ => "a file"
  }
}

///|
/// How to go back to the built-in one, when a file could not be read.
fn refused_advice(kind : String?) -> String {
  match kind {
    Some("model") => "unset MAKED_MODEL to run the built-in model instead"
    Some("research") => "unset MAKED_RESEARCH to run the built-in table instead"
    Some("society") =>
      "unset MAKED_SOCIETY to run the built-in vocabulary instead"
    Some("corpus") => "unset MAKED_CORPUS to run the built-in corpus instead"
    _ => "unset the variable that names it to run the built-in one instead"
  }
}

///|
/// Install the machine MAKED runs, from the environment.
///
/// The files are read first and installed second: a file that cannot be
/// read is refused before anything about MAKED has changed.
///
/// False when the start-up failed, with the reason printed. The caller
/// stops: MAKED does not carry on with half a machine.
pub async fn install_from_environment() -> Bool {
  let plan = startup_plan_from_env()
  let files = read_startup_files(plan)
  match files.refused_path {
    Some(path) => {
      eprintln("")
      eprintln(
        "MAKED will not start with " +
        refused_noun(files.refused_kind) +
        " it could not read.",
      )
      eprintln("  " + refused_advice(files.refused_kind))
      eprintln("  the file was: " + path)
      return false
    }
    None => ()
  }
  match files.unfit_slot {
    Some(slot) => {
      eprintln("")
      eprintln(
        "WARNING: the built-in mapping table names the slot \"" +
        slot +
        "\", which this model does not have.",
      )
      eprintln(
        "  the research panel will not drive the loop until MAKED_RESEARCH names a table for this model",
      )
    }
    None => ()
  }
  install_startup(files)
}

///|
/// Open the database and put the last session back in front of the user.
///
/// The web server needs the pages seeded and the session restored; the
/// agent's server needs the session, because a run of steps that is not
/// written down is a run nobody can look at afterwards.
pub fn prepare_database(db_path : String) -> Database raise {
  let db = Database::open(db_path)
  db.seed(seed_pages())
  let home = home_page()
  // The index is a page like any other; store it so it is served from the
  // same table as the rest rather than special-cased in a handler.
  db.seed([home, not_found_page()])
  restore_session(db)
  db
}
