// The MAKED single-page app.
//
// Routing is client-side over the History API: `on_url_changed` maps the
// browser path to a slug and the rendered page follows the model. The backend
// serves `index.html` for every non-API path (its static middleware uses a
// history fallback), so a deep link like /about works on a cold load as well
// as after a client-side navigation.

///|
/// `pub(all)` because rabbita needs `Msg` to name the subscription's message
/// type in the generated `.mbti`.
pub(all) enum Msg {
  Loaded(Result[Json, Error])
  LoopLoaded(Result[Json, Error])
  LoopStepped(Result[Json, Error])
  LoopReset(Result[Json, Error])
  StepClicked
  SlotStepClicked(String)
  /// The reader chose one of the successors the table offered and declined
  /// to pick. The slot's URL slug and the target's name.
  TargetStepClicked(String, String)
  ResetClicked
  ResearchLoaded(Result[Json, Error])
  ResearchDriven(Result[Json, Error])
  /// The mapping table: the reader's own words for what a document means.
  ResearchConfigLoaded(Result[Json, Error])
  ResearchConfigSaved(Result[Json, Error])
  ResearchConfigEditClicked
  ResearchConfigTextChanged(String)
  ResearchConfigSaveClicked
  CausalLoaded(Result[Json, Error])
  /// The Society layer: the collective, read from the server.
  SocietyLoaded(Result[Json, Error])
  /// A move was taken and the machine answered.
  SocietyStepped(Result[Json, Error])
  /// Read the collective: where it stands and what it can do from there.
  SocietyReadClicked
  /// The reader chose a move for the collective. The machine's own name for
  /// the move, not its label: the label is for the reader and can be changed
  /// in the vocabulary file, while the name is what the machine understands.
  SocietyStepClicked(String)
  /// Read the corpus: whatever the server is configured to read, whether
  /// that is arxiv, a feed or the reader's own folder.
  ReadCorpusClicked
  DriveLoopClicked
  EstimateCausalClicked
  UrlChanged(@url.Url)
  /// The reader asked for the other language.
  ///
  /// The whole interface switches: the words the client owns come from its own
  /// table, and the words the machine owns come back from the server in the
  /// language that was asked for. Both halves have to move together, or the
  /// panel ends up saying "环" above a position called Standing.
  LangToggled
  // The workspace: the user's own records.
  EntryCreated(Result[Json, Error])
  EntryDeleted(Result[Json, Error])
  DraftDomainClicked(String)
  DraftTitleChanged(String)
  DraftBodyChanged(String)
  DraftSubmitClicked
  EntryDeleteClicked(Int32)
  // The sessions: named explorations, and the history inside them.
  SessionCreated(Result[Json, Error])
  SessionActivated(Result[Json, Error])
  SessionReplayed(Result[Json, Error])
  SessionBranched(Result[Json, Error])
  SessionRenamed(Result[Json, Error])
  SessionDeleted(Result[Json, Error])
  SessionNameChanged(String)
  SessionRenameChanged(String)
  NewSessionClicked
  OpenSessionClicked(Int32)
  ReplayStepClicked(Int32)
  BranchStepClicked(Int32)
  RenameSessionClicked
  DeleteSessionClicked(Int32)
}

///|
/// The whole client state: every page the backend knows about, plus the slug
/// currently on screen. Content is small and read-only, so it is fetched once
/// and held; a route change is then a lookup rather than another request.
///
/// `Eq` is required by `create_state_with_init`, which uses it to decide
/// whether a re-render is needed; `Page` derives it for the same reason. The
/// `implicit_impl_as_method` warning on that derive is the accepted cost --
/// see `page.mbt`.
pub(all) struct Model {
  pages : Array[Page]
  current : String
  loaded : Bool
  error : String
  loop_status : LoopStatus?
  loop_error : String
  /// The eight drive slots, fetched once and held. This replaces two
  /// hard-coded copies of the vocabulary that used to live in this package.
  slots : Array[Slot]
  /// The documents the corpus holds, and the rule each one matched.
  research_documents : Array[Json]
  research_triggers : Array[Json]
  research_error : String
  /// The corpus the server is reading: its kind, where it reads from, and
  /// the file it was configured in. The reader has to be able to see which
  /// corpus they are looking at, because "no documents" means something
  /// quite different for each one.
  research_corpus : Json?
  /// What the server said about the corpus it read, when it had something
  /// to say -- most often that the corpus held nothing.
  research_notice : String
  /// The mapping table the server is running: the rules, and the text the
  /// reader is editing them in. The table is data, and this is where the
  /// reader gets at it.
  research_config : Json?
  /// The file the table came from; empty when it is the built-in one, and
  /// that is the difference between a table that can be saved and one that
  /// cannot.
  research_config_path : String
  /// The table as text, which is what the reader edits.
  research_config_text : String
  /// What the table panel says after the last action. One of the two is
  /// always empty, and between them they cover every outcome: a save either
  /// lands, is refused with a reason, or fails to reach the server.
  research_config_error : String
  research_config_notice : String
  causal_result : Json?
  causal_error : String
  /// The society machine, as the server describes it: where the collective
  /// stands, the moves from there, and the gaps in the vocabulary.
  society : Json?
  /// What the society panel says after the last action.
  society_error : String
  /// The user's own records, fetched with the pages so that the workspace
  /// needs no second request of its own. See the note in `app`.
  entries : Array[Entry]
  /// The five ring letters, as the backend names them.
  entry_domains : Array[String]
  /// The entry being written: which domain it belongs to, and its text.
  draft_domain : String
  draft_title : String
  draft_body : String
  /// What the workspace says after the last action. One of the two is always
  /// empty, and between them they cover every outcome: a save either lands,
  /// is refused with a reason, or fails to reach the server.
  workspace_error : String
  workspace_notice : String
  /// The sessions, newest first.
  sessions : Array[Session]
  /// The session in front of the user.
  active_session : Session
  /// The steps on the active session's current path, oldest first.
  session_path : Array[SessionStep]
  /// The steps that are recorded but not on the current path: the roads that
  /// were walked and then walked back from.
  session_others : Array[SessionStep]
  /// What the last few steps add up to, in one sentence, written by the
  /// server. Empty when there is nothing to summarise.
  session_summary : String
  /// What the run is worth: whether it is still finding ground, how far it
  /// has ranged, and whether it is doing better than it was at the start.
  ///
  /// Written by the server, like the summary. The measures need the whole
  /// path and the size of the state space, and a client with its own copy
  /// would be measuring something else.
  session_metrics : MetricReport
  /// What the sessions panel says after the last action.
  session_error : String
  session_notice : String
  /// The name being typed for a new session.
  session_name_draft : String
  /// The name being typed for a rename. Empty means "the session's own
  /// name", which is what the box shows until it is typed into.
  session_rename_draft : String
  /// The session a delete is waiting to be confirmed for, or 0.
  ///
  /// A history is worth more than the click that deletes it, so a delete
  /// takes two presses: the first arms it and says so, the second carries
  /// it out. The armed session is named, so a second click somewhere else
  /// does not delete the wrong one.
  session_delete_pending : Int32
  /// The language the interface is speaking.
  ///
  /// It is here rather than in the router because it is a choice about the
  /// whole interface rather than about one page: the loop panel, the corpus
  /// panel, the sessions and the workspace all read it, and the header's
  /// switch reads it to know which way to switch.
  lang : UiLang
} derive(Eq)

///|
/// The state the app starts in.
///
/// Public because `frontend_test.mbt` asserts it: the language the interface
/// opens in is a decision, and a decision that no test can read is a
/// decision that can change without anything noticing.
pub fn initial() -> Model {
  {
    pages: [],
    current: "index",
    loaded: false,
    error: "",
    loop_status: None,
    loop_error: "",
    slots: [],
    research_documents: [],
    research_triggers: [],
    research_error: "",
    research_corpus: None,
    research_notice: "",
    research_config: None,
    research_config_path: "",
    research_config_text: "",
    research_config_error: "",
    research_config_notice: "",
    causal_result: None,
    causal_error: "",
    society: None,
    society_error: "",
    entries: [],
    entry_domains: default_entry_domains(),
    draft_domain: "",
    draft_title: "",
    draft_body: "",
    workspace_error: "",
    workspace_notice: "",
    sessions: [],
    active_session: empty_session(),
    session_path: [],
    session_others: [],
    session_summary: "",
    session_metrics: empty_metric_report(),
    session_error: "",
    session_notice: "",
    session_name_draft: "",
    session_rename_draft: "",
    session_delete_pending: 0,
    // English until the reader asks for the other one. The choice is not
    // remembered across a reload: it is a question the reader asks of the
    // page, and a page that has just been opened has not been asked.
    lang: UiLang::English,
  }
}

///|
fn Model::page(self : Model) -> Page? {
  find_page(self.pages, self.current)
}

///|
/// Map a URL path to a slug: `/about` -> `about`, `/` -> `index`.
///
/// Public only because `frontend_test.mbt` asserts it. MoonBit compiles
/// `_test.mbt` as a blackbox package that can see `pub` items and nothing
/// else, so an internal is untestable until it is exported. Nothing in `cmd/web`
/// calls it.
pub fn slug_of(path : String) -> String {
  let s = if path.has_prefix("/") { path[1:].to_owned() } else { path }
  if s == "" || s == "index" {
    "index"
  } else {
    s
  }
}

///|
/// The request that carries the reader's choice to the server.
///
/// The slot says which edge the table offered, the target says which of that
/// edge's successors the reader wants. The server reads the successor out of
/// one field and refuses a request that does not carry it, so the shape of
/// the request is named in one place: a test can check what goes over the
/// wire without a browser in the loop, and the button and the request cannot
/// drift apart.
///
/// The language travels with it, because the sentence that comes back is
/// written in the language the reader asked for.
///
/// Public for the same reason `update` is public -- the request is the only
/// thing the server ever sees, and a test that cannot read it can only trust
/// that the click arrives.
pub fn target_step_request(
  slot : String,
  target : String,
  lang : UiLang,
) -> (String, Json) {
  ("/api/loop/step/" + slot + lang_query(lang), { "target": target })
}

///|
/// The request that carries the reader's choice of move to the server.
///
/// The move travels by the machine's own name rather than by the label the
/// reader saw: the label is for the reader and can be changed in the
/// vocabulary file, while the name is what the machine understands.
///
/// Public for the same reason `update` is public -- the request is the only
/// thing the server ever sees, and a test that cannot read it can only
/// trust that the click arrives.
pub fn society_step_request(trigger : String) -> (String, Json) {
  ("/api/society/step", { "trigger": trigger })
}

///|
/// `update` takes the emitter as the first parameter. The signature is fixed by
/// `@rabbita.cell`, which passes the emitter so the view can issue commands.
///
/// Public because `frontend_test.mbt` drives it directly: the workspace arms
/// are the ones that decide whether a record is saved, and a test that calls
/// `update` is the only way to prove that a click reaches the right arm
/// without a browser in the loop.
pub fn update(
  model : Model,
  msg : Msg,
  emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  // The words of the interface, in the language it is speaking. Built once
  // per update rather than read field by field, so that the whole handler
  // shares one table.
  let c = chrome(model.lang)
  match msg {
    Loaded(Ok(json)) =>
      (
        // The spread form is used rather than a hand-written list of every
        // field: a list like that is a place for a new field to be forgotten,
        // and forgetting one here is silent -- the panel simply stops
        // updating, with nothing in the console to say why.
        //
        // The session state is folded in by a helper, because there are
        // seven places that take one and a hand-written list at each of them
        // would be seven places for a field to be forgotten.
        {
          ..apply_session_state(model, decode_bootstrap_session_state(json)),
          pages: decode_pages(json),
          entries: decode_entries(json),
          entry_domains: decode_entry_domains(json),
          loaded: true,
          error: "",
        },
        // Requests are issued one after another, never with @cmd.batch.
        // Batching two GETs in `init` made every later click-initiated POST
        // reach the server but never deliver its response: the request
        // executed, the view stayed frozen on stale state, and no error was
        // ever shown. Each request below is therefore issued from the handler
        // for the previous one, which has already been answered.
        //
        // Exactly one chained hop, and no more. The loop status carries the
        // eight-slot vocabulary in its own body, so the panel needs a single
        // response. This used to be a three-hop chain -- pages, then
        // `/api/loop/slots`, then `/api/loop/status` -- and it stalled
        // intermittently after the second hop: the request was answered 200 by
        // the server, but the reply never reached `update`, so the panel sat on
        // "Loading loop status..." with no error anywhere. Do not split these
        // into more sequential requests to "tidy up" the flow.
        //
        // The workspace entries ride along in the first response for the same
        // reason. Fetching them with a request of their own would have been a
        // third hop, and the third hop is where this chain used to die.
        @http.get("/api/loop/status" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { LoopLoaded(result) }),
        ),
      )
    Loaded(Err(_)) =>
      (
        { ..model, loaded: true, error: c.status.server_unreachable, },
        @cmd.none,
      )
    LoopLoaded(Ok(json)) =>
      (
        {
          ..model,
          loop_status: Some(decode_loop_status(json)),
          // Same payload: the status response carries the vocabulary, so a
          // missing `slots` field simply leaves the panel without slot
          // buttons rather than failing the whole update.
          slots: decode_slots(json),
          loop_error: "",
        },
        @cmd.none,
      )
    LoopLoaded(Err(_)) =>
      ({ ..model, loop_error: c.status.loop_unavailable, }, @cmd.none)
    LoopStepped(Ok(json)) =>
      (
        {
          // The session state comes with the step, so the panel's step count
          // and its summary of the run are the ones this step produced. They
          // used to be the ones from start-up, and the count stopped moving
          // after the first click.
          ..apply_session_state_if_present(model, session_state_of(json)),
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
        },
        @cmd.none,
      )
    LoopStepped(Err(_)) =>
      ({ ..model, loop_error: c.status.step_failed, }, @cmd.none)
    LoopReset(Ok(json)) =>
      (
        {
          ..apply_session_state_if_present(model, session_state_of(json)),
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
        },
        @cmd.none,
      )
    LoopReset(Err(_)) =>
      ({ ..model, loop_error: c.status.reset_failed, }, @cmd.none)
    StepClicked =>
      (
        model,
        @http.post("/api/loop/step" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { LoopStepped(result) }),
        ),
      )
    // The message carries the slot's URL slug, which the backend supplied with
    // the slot itself. This used to carry the display name and be mapped to a
    // slug by a second hand-written table in this file, which had to be kept in
    // step with the one in `views.mbt` by hand.
    SlotStepClicked(name) =>
      (
        model,
        @http.post("/api/loop/step/\{name}" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { LoopStepped(result) }),
        ),
      )
    // The reader picked one of the successors the table offered and would not
    // choose between. The slot says which edge the table offered, the target
    // says which of its successors the reader wants.
    TargetStepClicked(name, target) => {
      let (path, body) = target_step_request(name, target, model.lang)
      (
        model,
        @http.post(path)
        .with_json(body)
        .expect_json(emit.map(fn(result) { LoopStepped(result) })),
      )
    }
    ResetClicked =>
      (
        model,
        @http.post("/api/loop/reset" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { LoopReset(result) }),
        ),
      )
    ResearchLoaded(Ok(json)) =>
      (
        {
          ..model,
          research_documents: decode_research_documents(json),
          research_triggers: decode_research_triggers(json),
          research_corpus: decode_research_corpus(json),
          research_notice: get_string(json, "notice", ""),
          research_error: "",
        },
        @cmd.none,
      )
    ResearchLoaded(Err(_)) =>
      ({ ..model, research_error: c.status.research_unavailable, }, @cmd.none)
    ResearchDriven(Ok(json)) =>
      (
        {
          ..model,
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
          research_documents: [],
          research_triggers: [],
          research_error: "",
        },
        @cmd.none,
      )
    ResearchDriven(Err(_)) =>
      ({ ..model, loop_error: c.status.research_drive_failed, }, @cmd.none)
    // The mapping table.
    ResearchConfigLoaded(Ok(json)) =>
      (
        {
          ..model,
          research_config: decode_research_config(json),
          research_config_path: get_string(json, "path", ""),
          research_config_text: config_text_of(json),
          research_config_error: "",
          research_config_notice: "",
        },
        @cmd.none,
      )
    ResearchConfigLoaded(Err(_)) =>
      (
        { ..model, research_config_error: c.research.table_unavailable, },
        @cmd.none,
      )
    ResearchConfigSaved(Ok(json)) =>
      // The server refuses a table that names a slot the model does not
      // have, and the reason is the whole of the answer: a table that is
      // simply wrong is not something a reader can act on.
      match field(json, "error") {
        Some(String(_)) => {
          let mut reason = ""
          match field(json, "reason") {
            Some(String(text)) => reason = text
            _ => ()
          }
          (
            {
              ..model,
              research_config_error: if reason == "" {
                c.research.table_refused
              } else {
                reason
              },
              research_config_notice: "",
            },
            @cmd.none,
          )
        }
        _ =>
          (
            {
              ..model,
              research_config: decode_research_config(json),
              research_config_path: get_string(
                json,
                "path",
                model.research_config_path,
              ),
              research_config_text: config_text_of(json),
              research_config_error: "",
              research_config_notice: get_string(
                json,
                "notice",
                c.research.table_running,
              ),
            },
            @cmd.none,
          )
      }
    ResearchConfigSaved(Err(_)) =>
      (
        { ..model, research_config_error: c.research.table_not_saved, },
        @cmd.none,
      )
    ResearchConfigEditClicked =>
      (
        model,
        @http.get("/api/research/config").expect_json(
          emit.map(fn(result) { ResearchConfigLoaded(result) }),
        ),
      )
    ResearchConfigTextChanged(text) =>
      ({ ..model, research_config_text: text, }, @cmd.none)
    ResearchConfigSaveClicked => {
      // The text is parsed here rather than sent as text, so that a table
      // that is not JSON at all is refused straight away instead of
      // travelling to the server and being refused there. The server
      // refuses a table that names a slot the model does not have, and
      // says why; this only catches the text that is not a table at all.
      let parsed = @json.parse(model.research_config_text) catch {
        err =>
          return (
            {
              ..model,
              research_config_error: not_json(c, err.to_string()),
              research_config_notice: "",
            },
            @cmd.none,
          )
      }
      (
        {
          ..model,
          research_config_error: "",
          research_config_notice: c.research.saving,
        },
        @http.put("/api/research/config")
        .with_json(parsed)
        .expect_json(emit.map(fn(result) { ResearchConfigSaved(result) })),
      )
    }
    ReadCorpusClicked =>
      (
        model,
        @http.get("/api/research/documents" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { ResearchLoaded(result) }),
        ),
      )
    DriveLoopClicked =>
      (
        model,
        @http.post("/api/research/drive" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { ResearchDriven(result) }),
        ),
      )
    CausalLoaded(Ok(json)) =>
      (
        {
          ..model,
          causal_result: decode_causal_result(json),
          causal_error: "",
        },
        @cmd.none,
      )
    CausalLoaded(Err(_)) =>
      ({ ..model, causal_error: c.status.causal_unavailable, }, @cmd.none)
    EstimateCausalClicked =>
      (
        model,
        @http.get("/api/research/causal").expect_json(
          emit.map(fn(result) { CausalLoaded(result) }),
        ),
      )
    // The collective.
    //
    // The society panel is not chained onto the start-up requests on
    // purpose. The loop status already carries the collective's position,
    // and the machine itself is only wanted when a reader asks for it --
    // so the panel asks for it rather than the page paying for it on every
    // load. See the note on the chained requests above: that chain is one
    // hop, and this one is not part of it.
    SocietyReadClicked =>
      (
        model,
        @http.get("/api/society").expect_json(
          emit.map(fn(result) { SocietyLoaded(result) }),
        ),
      )
    SocietyLoaded(Ok(json)) =>
      ({ ..model, society: Some(json), society_error: "", }, @cmd.none)
    SocietyLoaded(Err(_)) =>
      ({ ..model, society_error: c.status.society_unavailable, }, @cmd.none)
    // A move for the collective.
    //
    // The body carries the machine's own name for the move. The panel shows
    // the reader a label, but the label can be changed in the vocabulary
    // file -- so the name is what travels, and the server looks the move up
    // by the name the machine gave it.
    SocietyStepClicked(trigger) => {
      let (path, body) = society_step_request(trigger)
      (
        model,
        @http.post(path)
        .with_json(body)
        .expect_json(emit.map(fn(result) { SocietyStepped(result) })),
      )
    }
    // The answer to a move has the same shape as the answer to "where does
    // the collective stand": the machine, the position and the moves from
    // it. A refusal is in the same body as the reason, so the panel keeps
    // showing where the collective is rather than going blank because a
    // move did not land.
    SocietyStepped(Ok(json)) =>
      ({ ..model, society: Some(json), society_error: "", }, @cmd.none)
    SocietyStepped(Err(_)) =>
      ({ ..model, society_error: c.status.move_unreached, }, @cmd.none)
    UrlChanged(url) => ({ ..model, current: slug_of(url.path), }, @cmd.none)
    // The reader asked for the other language.
    //
    // Two things have to move together, and only one of them is the words
    // this client owns. The other is the words the machine owns: the
    // positions, the slots, the narrations and the summary are written by
    // the server, in the language the request asked for. So the switch asks
    // for the bootstrap again, in the new language, and the chain that
    // already exists -- bootstrap, then the loop status -- carries the rest
    // of it.
    //
    // The panels the reader has not opened are not re-asked for. They were
    // not open before the switch and they are not open after it, and the
    // request is the reader's to make.
    LangToggled => {
      let lang = model.lang.other()
      (
        { ..model, lang, },
        @http.get("/api/bootstrap" + lang_query(lang)).expect_json(
          emit.map(fn(result) { Loaded(result) }),
        ),
      )
    }
    // The workspace.
    //
    // Every branch of this group says what happened. A click that produces no
    // visible change anywhere is the failure this project exists to remove,
    // so there is no branch here that returns without a word: a save either
    // lands, is refused with a reason, or fails to reach the server, and each
    // of those three says so in the panel.
    DraftDomainClicked(letter) =>
      (
        {
          ..model,
          draft_domain: letter,
          workspace_error: "",
          workspace_notice: "",
        },
        @cmd.none,
      )
    DraftTitleChanged(text) => ({ ..model, draft_title: text, }, @cmd.none)
    DraftBodyChanged(text) => ({ ..model, draft_body: text, }, @cmd.none)
    DraftSubmitClicked => {
      // The same rules the server applies, checked here so that the common
      // mistakes produce a sentence straight away instead of a round trip
      // that comes back as a refusal.
      let problem = draft_problem(
        model.entry_domains,
        model.draft_domain,
        model.draft_title,
        c,
      )
      if problem != "" {
        (
          { ..model, workspace_error: problem, workspace_notice: "", },
          @cmd.none,
        )
      } else {
        let payload : Json = {
          "domain": model.draft_domain,
          "title": model.draft_title,
          "body": model.draft_body,
        }
        (
          {
            ..model,
            workspace_error: "",
            workspace_notice: c.workspace.saving,
          },
          @http.post("/api/entries")
          .with_json(payload)
          .expect_json(emit.map(fn(result) { EntryCreated(result) })),
        )
      }
    }
    EntryCreated(Ok(json)) =>
      match decode_created_entry(json) {
        Some(entry) =>
          (
            {
              ..model,
              entries: [entry, ..model.entries],
              draft_title: "",
              draft_body: "",
              workspace_error: "",
              workspace_notice: saved_entry(c, entry.title, entry.domain),
            },
            @cmd.none,
          )
        None => {
          // The server answered, and what it answered was a refusal rather
          // than an entry. The status code never reaches the client, so the
          // body is the only place the reason can come from.
          let reason = decode_error_reason(json)
          (
            {
              ..model,
              workspace_notice: "",
              workspace_error: if reason == "" {
                c.workspace.refused
              } else {
                reason
              },
            },
            @cmd.none,
          )
        }
      }
    EntryCreated(Err(_)) =>
      (
        {
          ..model,
          workspace_notice: "",
          workspace_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    EntryDeleteClicked(id) =>
      (
        {
          ..model,
          workspace_error: "",
          workspace_notice: c.workspace.deleting,
        },
        @http.delete("/api/entries/\{id}").expect_json(
          emit.map(fn(result) { EntryDeleted(result) }),
        ),
      )
    EntryDeleted(Ok(json)) => {
      // The server answers `{"deleted": id}` when it removed the row, and an
      // error object when it did not. A missing `deleted` is the failure case,
      // not a delete of record -1.
      let deleted = get_int(json, "deleted", -1)
      if deleted < 0 {
        let reason = decode_error_reason(json)
        (
          {
            ..model,
            workspace_notice: "",
            workspace_error: if reason == "" {
              "the server refused the delete"
            } else {
              reason
            },
          },
          @cmd.none,
        )
      } else {
        let remaining = model.entries.filter(fn(entry) { entry.id != deleted })
        (
          {
            ..model,
            entries: remaining,
            workspace_error: "",
            workspace_notice: c.workspace.removed,
          },
          @cmd.none,
        )
      }
    }
    EntryDeleted(Err(_)) =>
      (
        {
          ..model,
          workspace_notice: "",
          workspace_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    // The sessions.
    //
    // Every arm of this group says what happened, in the same place, every
    // time -- the rule the workspace follows and the reason it exists. A
    // click that produces no visible change anywhere is the failure this
    // project exists to remove, so there is no branch here that returns
    // without a word: the action either lands, is refused with a reason, or
    // fails to reach the server, and each of those three says so.
    //
    // The responses all carry the same session state, so the panel is
    // rebuilt from one shape no matter which action produced it.
    SessionCreated(Ok(json)) =>
      if session_refused(json) {
        (
          {
            ..model,
            session_notice: "",
            session_error: session_refusal_reason(json),
          },
          @cmd.none,
        )
      } else {
        (
          {
            ..apply_session_state(model, decode_session_state(json)),
            session_error: "",
            session_notice: c.sessions.started,
            session_name_draft: "",
          },
          @cmd.none,
        )
      }
    SessionCreated(Err(_)) =>
      (
        {
          ..model,
          session_notice: "",
          session_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    SessionActivated(Ok(json)) =>
      if session_refused(json) {
        (
          {
            ..model,
            session_notice: "",
            session_error: session_refusal_reason(json),
          },
          @cmd.none,
        )
      } else {
        (
          {
            ..apply_session_state(model, decode_session_state(json)),
            session_error: "",
            session_notice: c.sessions.opened,
          },
          @cmd.none,
        )
      }
    SessionActivated(Err(_)) =>
      (
        {
          ..model,
          session_notice: "",
          session_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    SessionReplayed(Ok(json)) =>
      if session_refused(json) {
        (
          {
            ..model,
            session_notice: "",
            session_error: session_refusal_reason(json),
          },
          @cmd.none,
        )
      } else {
        (
          {
            ..apply_session_state(model, decode_session_state(json)),
            session_error: "",
            session_notice: c.sessions.went_back,
          },
          @cmd.none,
        )
      }
    SessionReplayed(Err(_)) =>
      (
        {
          ..model,
          session_notice: "",
          session_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    SessionBranched(Ok(json)) =>
      if session_refused(json) {
        (
          {
            ..model,
            session_notice: "",
            session_error: session_refusal_reason(json),
          },
          @cmd.none,
        )
      } else {
        (
          {
            ..apply_session_state(model, decode_session_state(json)),
            session_error: "",
            session_notice: c.sessions.forked,
          },
          @cmd.none,
        )
      }
    SessionBranched(Err(_)) =>
      (
        {
          ..model,
          session_notice: "",
          session_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    SessionRenamed(Ok(json)) =>
      if session_refused(json) {
        (
          {
            ..model,
            session_notice: "",
            session_error: session_refusal_reason(json),
          },
          @cmd.none,
        )
      } else {
        (
          {
            ..apply_session_state(model, decode_session_state(json)),
            session_error: "",
            session_notice: c.sessions.renamed,
          },
          @cmd.none,
        )
      }
    SessionRenamed(Err(_)) =>
      (
        {
          ..model,
          session_notice: "",
          session_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    SessionDeleted(Ok(json)) =>
      if session_refused(json) {
        (
          {
            ..model,
            session_notice: "",
            session_error: session_refusal_reason(json),
          },
          @cmd.none,
        )
      } else {
        (
          {
            ..apply_session_state(model, decode_session_state(json)),
            session_error: "",
            session_notice: c.sessions.forgot,
          },
          @cmd.none,
        )
      }
    SessionDeleted(Err(_)) =>
      (
        {
          ..model,
          session_notice: "",
          session_error: c.status.server_unreachable,
        },
        @cmd.none,
      )
    SessionNameChanged(text) =>
      ({ ..model, session_name_draft: text, }, @cmd.none)
    SessionRenameChanged(text) =>
      ({ ..model, session_rename_draft: text, }, @cmd.none)
    NewSessionClicked => {
      // The same check the server applies, made here so that the common
      // mistake produces a sentence straight away instead of a round trip.
      let name = model.session_name_draft.trim().to_owned()
      if name == "" {
        (
          { ..model, session_notice: "", session_error: c.sessions.give_name, },
          @cmd.none,
        )
      } else {
        let payload : Json = { "name": name }
        (
          { ..model, session_notice: c.sessions.starting, session_error: "", },
          @http.post("/api/sessions" + lang_query(model.lang))
          .with_json(payload)
          .expect_json(emit.map(fn(result) { SessionCreated(result) })),
        )
      }
    }
    OpenSessionClicked(id) =>
      (
        { ..model, session_notice: c.sessions.opening, session_error: "", },
        @http.post("/api/sessions/\{id}/activate" + lang_query(model.lang)).expect_json(
          emit.map(fn(result) { SessionActivated(result) }),
        ),
      )
    ReplayStepClicked(id) => {
      let payload : Json = { "step": id }
      (
        { ..model, session_notice: c.sessions.going_back, session_error: "", },
        @http.post(
          "/api/sessions/\{model.active_session.id}/replay" +
          lang_query(model.lang),
        )
        .with_json(payload)
        .expect_json(emit.map(fn(result) { SessionReplayed(result) })),
      )
    }
    BranchStepClicked(id) => {
      let payload : Json = {
        "step": id,
        "name": branch_name(model.active_session.name, c),
      }
      (
        { ..model, session_notice: c.sessions.forking, session_error: "", },
        @http.post(
          "/api/sessions/\{model.active_session.id}/branch" +
          lang_query(model.lang),
        )
        .with_json(payload)
        .expect_json(emit.map(fn(result) { SessionBranched(result) })),
      )
    }
    RenameSessionClicked => {
      let name = rename_text(model).trim().to_owned()
      if name == "" {
        (
          { ..model, session_notice: "", session_error: c.sessions.give_name, },
          @cmd.none,
        )
      } else {
        let payload : Json = { "name": name }
        (
          { ..model, session_notice: c.sessions.renaming, session_error: "", },
          @http.post(
            "/api/sessions/\{model.active_session.id}/rename" +
            lang_query(model.lang),
          )
          .with_json(payload)
          .expect_json(emit.map(fn(result) { SessionRenamed(result) })),
        )
      }
    }
    DeleteSessionClicked(id) =>
      if model.session_delete_pending == id {
        (
          {
            ..model,
            session_notice: c.sessions.deleting,
            session_error: "",
            session_delete_pending: 0,
          },
          @http.delete("/api/sessions/\{id}").expect_json(
            emit.map(fn(result) { SessionDeleted(result) }),
          ),
        )
      } else {
        (
          {
            ..model,
            session_notice: c.sessions.confirm_delete,
            session_error: "",
            session_delete_pending: id,
          },
          @cmd.none,
        )
      }
  }
}

///|
/// Fold a session state into the model.
///
/// Done here rather than at each call site because there are seven places
/// that take one, and a hand-written list at each of them would be seven
/// places for a field to be forgotten. Forgetting one is silent: the panel
/// would stop showing something, and nothing would say why.
fn apply_session_state(model : Model, state : SessionState) -> Model {
  {
    ..model,
    sessions: state.sessions,
    active_session: state.session,
    session_path: state.path,
    session_others: state.other_steps,
    session_summary: state.summary,
    session_metrics: state.metrics,
    // The live status travels with a session action, because the action
    // changed the live state. A response without one -- the bootstrap --
    // leaves the panel as it was rather than blanking it.
    loop_status: match state.loop_status {
      Some(status) => Some(status)
      None => model.loop_status
    },
    // The list has changed, so an armed delete is no longer pointing at
    // anything the user can see.
    session_delete_pending: 0,
  }
}

///|
/// Fold a session state into the model, when the response carried one.
///
/// A step response is the loop status with the session state folded in. A
/// response without one leaves the model exactly as it was: the sessions a
/// person has are not something a missing field should be able to erase.
fn apply_session_state_if_present(
  model : Model,
  state : SessionState?,
) -> Model {
  match state {
    Some(value) => apply_session_state(model, value)
    None => model
  }
}

///|
/// `on_url_changed` and `expect_json` each take an emitter for *their own*
/// message type. `Emit::map` is the intended lift: it retypes an emitter so
/// that a foreign message is wrapped in one of ours before it is dispatched.
/// Without it there is no way to feed a `Url` into an `Emit[Msg]`.
fn subscriptions(_model : Model, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.on_url_changed(emit.map(fn(url) { UrlChanged(url) }))
}

///|
fn view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let nav_pages = navigation(model.pages)
  let c = chrome(model.lang)
  let content = if !model.loaded {
    loading_view(c)
  } else if model.error != "" {
    error_view(c, model.error)
  } else {
    match model.page() {
      Some(page) => page_view(page, model.lang)
      None => not_found_view(c, model.current)
    }
  }
  let body = if model.current == "index" {
    let hero = @html.div(class="maked-hero", [logo(240), content])
    let loop_panel = loop_view(emit, model)
    let society_panel = society_view(emit, model)
    let research_panel = research_view(emit, model)
    let causal_panel = causal_view(emit, model)
    @html.div([
      hero,
      loop_panel,
      society_panel,
      research_panel,
      causal_panel,
      domain_cards(nav_pages, model.lang),
    ])
  } else if model.current == "workspace" && model.loaded {
    // The workspace is a client-side route rather than a seeded page: what it
    // shows is the user's own records, not a row in the `pages` table. The
    // backend serves the same `index.html` for it, so a cold load of
    // /workspace lands here too.
    //
    // It is rendered only once the data has arrived. Rendering it before that
    // would put the form on the screen with placeholder values, and the first
    // update would then have to *patch* those controls rather than insert
    // them -- and a patched control is a different thing from an inserted one.
    workspace_view(emit, model)
  } else if model.current == "workspace" {
    loading_view(c)
  } else if model.current == "sessions" && model.loaded {
    // The sessions, for the same reason as the workspace: a client-side
    // route over data the backend holds, not a row in the `pages` table.
    sessions_view(emit, model)
  } else if model.current == "sessions" {
    loading_view(c)
  } else {
    content
  }
  @html.div([
    header(emit, model.current, nav_pages, model.lang),
    @html.div(class="maked-main", [body]),
    @html.footer(
      class="maked-footer",
      "MAKED · MoonBit · rabbita + moonback + sqlite3",
    ),
  ])
}

///|
/// The root component. Public because `cmd/web` mounts it.
///
/// Uses `create_state_with_init` inside a builder so the view receives the
/// emitter and can issue commands (step/reset POST requests) from button
/// clicks. The initial data fetch is returned from `init`, which is the only
/// place the runtime will actually dispatch it.
///
/// The batch must be the `Cmd` half of `init`'s return value. `@rabbita.new`
/// takes a builder returning `Val[Html]` only, so a command issued in the
/// builder body has nowhere to go: `create_state` synthesises an init of
/// `_ => (model, none)`, and discarding the batch leaves both requests
/// undispatched -- the app renders its shell and then waits forever on
/// "Loading...", with every request returning a healthy 200.
pub fn app() -> @rabbita.App {
  @rabbita.new(fn() {
    let (model, emit) = @rabbita.create_state_with_init(
      init=fn(emit) {
        (
          initial(),
          // `/api/bootstrap` rather than `/api/pages`: the pages and the
          // workspace entries arrive together, so the workspace costs no
          // request of its own. One request out, one answer in, then the loop
          // status -- the chain stays two hops, which is the shape this
          // client is known to survive.
          @http.get("/api/bootstrap").expect_json(
            emit.map(fn(result) { Loaded(result) }),
          ),
        )
      },
      update~,
      subscriptions~,
    )
    model.map(fn(m) { view(emit, m) })
  })
}

///|
fn decode_research_documents(json : Json) -> Array[Json] {
  match field(json, "documents") {
    Some(Array(items)) => items
    _ => []
  }
}

///|
/// The corpus out of the server's answer.
///
/// The panel shows which corpus it is looking at, because the same empty
/// panel means "arxiv had nothing new" for one reader and "your folder has
/// no notes in it" for another.
fn decode_research_corpus(json : Json) -> Json? {
  match field(json, "corpus") {
    Some(obj) => Some(obj)
    _ => None
  }
}

///|
fn decode_research_triggers(json : Json) -> Array[Json] {
  match field(json, "triggers") {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn decode_causal_result(json : Json) -> Json? {
  match field(json, "causal") {
    Some(obj) => Some(obj)
    _ => None
  }
}

///|
/// The mapping table out of the server's answer.
fn decode_research_config(json : Json) -> Json? {
  match field(json, "config") {
    Some(obj) => Some(obj)
    _ => None
  }
}

///|
/// The mapping table as text, which is what the reader edits.
///
/// Two spaces of indent, because a table written on one line is a table
/// nobody edits. The text is the table the server is running, so the
/// reader starts from what is in force rather than from a blank box.
fn config_text_of(json : Json) -> String {
  match decode_research_config(json) {
    Some(config) => config.stringify(indent=2)
    None => ""
  }
}
