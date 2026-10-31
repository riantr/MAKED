///| The MAKED API: page content, navigation, workspace entries, and status.
///
/// The page routes are read-only, as they were when the only content was the
/// seeded pages. The workspace routes under `/api/entries` are the first
/// write path in the project: they are how a user puts their own model, data
/// or recorded failure into MAKED instead of only reading about the ring.
///
/// There is no auth. That is a real limitation rather than an oversight, and
/// it is stated here because it is the first thing to change before this is
/// exposed beyond a local process: anyone who can reach the port can read and
/// delete every entry. It is acceptable while the server binds localhost and
/// stores one person's working set, and it stops being acceptable the moment
/// the server is published (see the P0.3 entry-barrier work, which is what
/// makes that reachable).

///|
/// Register the JSON API on `app`.
pub fn build_api(app : App, db : Database, db_path : String) -> Unit {
  app.get("/api/status", req => {
    let pages = db.all_pages()
    let body : Json = {
      "status": "ok",
      "database": db_path,
      "page_count": pages.length(),
      "domains": domains_json(lang_of(req)),
    }
    Response::json(body)
  })
  app.get("/api/pages", req => {
    // The pages speak the language the request asked for, like everything
    // else on this server that has a language to speak. The Chinese of a
    // page is the page's own -- it was written in Chinese, not translated
    // into it -- so a reader who asks for Chinese gets the prose rather than
    // the English one with a Chinese heading over it.
    let lang = lang_of(req)
    let pages = db.all_pages().map(fn(p) { p.to_json(lang) })
    let body : Json = { "pages": pages }
    Response::json(body)
  })
  // GET /api/bootstrap → everything the single-page app needs to start.
  //
  // The pages and the workspace entries come back together, in one request,
  // because a second request at start-up is the shape that used to lose
  // responses: two GETs in flight at once meant the client sometimes never
  // saw either answer, and the screen sat on "Loading..." with nothing in the
  // console to say why. The app therefore asks for this, waits for the
  // answer, and only then asks for the loop status -- a chain of one at a
  // time rather than a pair.
  //
  // The entries are included even though only the workspace route shows them.
  // Keeping the start-up to a single request is worth carrying a list the
  // index page does not display; a user's own working set is small, and the
  // alternative is a third hop, which is where this chain died before.
  //
  // The response is not cacheable. It carries the user's own records, and a
  // cached copy would be a stale list of what the server holds.
  app.get("/api/bootstrap", req => {
    let lang = lang_of(req)
    let pages = db.all_pages().map(fn(p) { p.to_json(lang) })
    let entries = db.all_entries().map(fn(e) { e.to_json() })
    let body : Json = {
      "pages": pages,
      "entries": entries,
      "entry_domains": entry_domains(),
      // The sessions ride along with the first request rather than needing
      // one of their own. The start-up chain is the shape this client is
      // known to survive -- one request out, one answer in, then the loop
      // status -- and a third hop at start-up is exactly where that chain
      // used to die.
      //
      // The whole session state travels: the list, the active one, its path
      // and the branches that are not on the path. A client that had to ask
      // for the timeline separately would be one request further from the
      // answer on every page that shows it.
      "session_state": session_state_json(db, lang),
    }
    Response::json(body).with_header("Cache-Control", "no-store")
  })
  app.get("/api/pages/:slug", req => {
    let lang = lang_of(req)
    match req.param("slug") {
      Some(slug) =>
        match db.page_by_slug(slug) {
          Some(page) => Response::json(page.to_json(lang))
          None => {
            let body : Json = { "error": "not_found", "slug": slug }
            Response::json(body, status=404)
          }
        }
      None => {
        let body : Json = { "error": "missing_slug" }
        Response::json(body, status=400)
      }
    }
  })
  app.get("/api/domains", req => {
    let body : Json = { "domains": domains_json(lang_of(req)) }
    Response::json(body)
  })
  // Workspace: the user's own records, grouped by the domain they belong to.
  //
  // GET    /api/entries      → every entry, oldest first
  // POST   /api/entries      → create one; the body is {domain,title,body}
  // DELETE /api/entries/:id  → remove one
  app.get("/api/entries", _req => {
    let entries = db.all_entries().map(fn(e) { e.to_json() })
    let body : Json = {
      "entries": entries,
      "count": entries.length(),
      // Sent with the list so the client can render the five group headings
      // without hard-coding the ring a second time.
      "domains": entry_domains(),
    }
    // The list changes when a record is written or removed, so a cached copy
    // would be a lie about what the server holds.
    Response::json(body).with_header("Cache-Control", "no-store")
  })
  app.post("/api/entries", req => {
    let payload = req.json().unwrap_or(Json::empty_object())
    match Entry::from_json(payload) {
      Rejected(reason) => {
        let body : Json = { "error": "invalid_entry", "reason": reason }
        Response::json(body, status=400)
      }
      Accepted(domain, title, body_text) => {
        let entry = db.insert_entry(domain, title, body_text)
        Response::json(entry.created_json(), status=201)
      }
    }
  })
  app.delete("/api/entries/:id", req => {
    // -1 means "not a number". Rowids start at 1, so the sentinel cannot
    // collide with a real id, and it keeps the handler flat: matching on the
    // Result here does not typecheck, while `catch` is the form the rest of
    // this file already uses to parse a query parameter.
    let id = match req.param("id") {
      Some(raw) => @string.parse_int(raw) catch { _ => -1 }
      None => -1
    }
    if id < 0 {
      // A missing or non-numeric id can never name a row. Saying so plainly
      // beats a 404 that implies the entry might exist.
      let body : Json = {
        "error": "bad_id",
        "id": match req.param("id") {
          Some(raw) => raw
          None => ""
        },
      }
      Response::json(body, status=400)
    } else if db.delete_entry(id.to_int64()) {
      let body : Json = { "deleted": id }
      Response::json(body)
    } else {
      let body : Json = { "error": "not_found", "id": id }
      Response::json(body, status=404)
    }
  })
  // Session endpoints: the named explorations, and the history inside them.
  //
  // GET    /api/sessions              → every session, newest first
  // POST   /api/sessions              → create one, named, and make it active
  // GET    /api/sessions/:id          → one session with its timeline
  // POST   /api/sessions/:id/activate → make it active and replay it
  // POST   /api/sessions/:id/replay   → rewind to one of its steps
  // POST   /api/sessions/:id/branch   → fork a new session at one of its steps
  // POST   /api/sessions/:id/rename   → give it a different name
  // DELETE /api/sessions/:id          → forget it and its steps
  // GET    /api/sessions/:id/export   → ?format=md|json
  //
  // The session state always carries the *active* session under "session".
  // A route that acts on some other session names its subject as well: the
  // renamed one comes back under "renamed", so the answer is about the
  // session the caller asked about and not about the one that happens to be
  // live.
  app.get("/api/sessions", _req => Response::json(sessions_payload(db)))
  app.post("/api/sessions", req => {
    let payload = req.json().unwrap_or(Json::empty_object())
    match Session::validate_name(json_string(payload, "name")) {
      Rejected(reason) => {
        let body : Json = { "error": "invalid_name", "reason": reason }
        Response::json(body, status=400)
      }
      Accepted(name) => {
        let session = db.insert_session(
          name,
          0L,
          0L,
          "M",
          mode_name(get_loop_mode()),
        )
        set_active_session_id(session.id)
        // A new session is a new walk, not a continuation of the old one: it
        // starts from the first domain with no history. The session it
        // replaced keeps its own steps and can be activated again, so
        // starting a new one never costs the old one.
        set_loop_state(LoopState::new().with_mode(get_loop_mode()))
        Response::json(session_payload(db, lang_of(req)), status=201)
      }
    }
  })
  app.get("/api/sessions/:id", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else {
      match db.session_by_id(id.to_int64()) {
        Some(_) => Response::json(session_payload(db, lang_of(req)))
        None => {
          let body : Json = { "error": "not_found", "id": id }
          Response::json(body, status=404)
        }
      }
    }
  })
  app.post("/api/sessions/:id/activate", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else {
      match activate_session(db, id.to_int64()) {
        Done(_) => Response::json(session_payload(db, lang_of(req)))
        MissingSession => {
          let body : Json = { "error": "not_found", "id": id }
          Response::json(body, status=404)
        }
        MissingStep => {
          let body : Json = { "error": "not_on_path", "id": id }
          Response::json(body, status=400)
        }
        Refused(reason) => {
          let body : Json = { "error": "refused", "reason": reason }
          Response::json(body, status=400)
        }
      }
    }
  })
  app.post("/api/sessions/:id/replay", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else {
      let payload = req.json().unwrap_or(Json::empty_object())
      let step = json_int(payload, "step")
      match rewind_session(db, id.to_int64(), step.to_int64()) {
        Done(_) => Response::json(session_payload(db, lang_of(req)))
        MissingSession => {
          let body : Json = { "error": "not_found", "id": id }
          Response::json(body, status=404)
        }
        MissingStep => {
          // The step is not on this session's current path, so rewinding to
          // it would silently resurrect a branch that was already abandoned.
          let body : Json = { "error": "not_on_path", "step": step }
          Response::json(body, status=400)
        }
        Refused(reason) => {
          let body : Json = { "error": "refused", "reason": reason }
          Response::json(body, status=400)
        }
      }
    }
  })
  app.post("/api/sessions/:id/branch", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else {
      let payload = req.json().unwrap_or(Json::empty_object())
      let step = json_int(payload, "step")
      let named = match Session::validate_name(json_string(payload, "name")) {
        Accepted(value) => Ok(value)
        Rejected(reason) => Err(reason)
      }
      match named {
        Err(reason) => {
          let body : Json = { "error": "invalid_name", "reason": reason }
          Response::json(body, status=400)
        }
        Ok(name) =>
          match branch_session(db, id.to_int64(), step.to_int64(), name) {
            Done(_) =>
              Response::json(session_payload(db, lang_of(req)), status=201)
            MissingSession => {
              let body : Json = { "error": "not_found", "id": id }
              Response::json(body, status=404)
            }
            MissingStep => {
              let body : Json = { "error": "not_on_path", "step": step }
              Response::json(body, status=400)
            }
            Refused(reason) => {
              let body : Json = { "error": "refused", "reason": reason }
              Response::json(body, status=400)
            }
          }
      }
    }
  })
  app.post("/api/sessions/:id/rename", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else {
      let payload = req.json().unwrap_or(Json::empty_object())
      match Session::validate_name(json_string(payload, "name")) {
        Rejected(reason) => {
          let body : Json = { "error": "invalid_name", "reason": reason }
          Response::json(body, status=400)
        }
        Accepted(name) =>
          if db.rename_session(id.to_int64(), name) {
            match db.session_by_id(id.to_int64()) {
              // The renamed session travels under "renamed" because it need
              // not be the active one: the state under "session" is the
              // active session, and a rename of some other session would
              // otherwise answer with a session the caller did not ask
              // about.
              Some(session) =>
                Response::json(
                  session_payload_with(db, "renamed", session, lang_of(req)),
                )
              None => {
                let body : Json = { "error": "not_found", "id": id }
                Response::json(body, status=404)
              }
            }
          } else {
            let body : Json = { "error": "not_found", "id": id }
            Response::json(body, status=404)
          }
      }
    }
  })
  app.delete("/api/sessions/:id", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else if db.delete_session(id.to_int64()) {
      // The live session cannot be a session that no longer exists. If it
      // was the one that was deleted, another takes its place, so the loop
      // is never left pointing at nothing.
      if active_session_id() == id.to_int64() {
        let rest = db.all_sessions()
        if rest.length() == 0 {
          set_active_session_id(0L)
          set_loop_state(LoopState::new())
        } else {
          match activate_session(db, rest[0].id) {
            Done(_) => ()
            MissingSession => set_active_session_id(rest[0].id)
            MissingStep => set_active_session_id(rest[0].id)
            Refused(_) => set_active_session_id(rest[0].id)
          }
        }
      }
      let body : Json = { "deleted": id }
      Response::json(body)
    } else {
      let body : Json = { "error": "not_found", "id": id }
      Response::json(body, status=404)
    }
  })
  app.get("/api/sessions/:id/export", req => {
    let id = session_id_param(req)
    if id < 0 {
      let body : Json = { "error": "bad_id" }
      Response::json(body, status=400)
    } else {
      match db.session_by_id(id.to_int64()) {
        None => {
          let body : Json = { "error": "not_found", "id": id }
          Response::json(body, status=404)
        }
        Some(session) => {
          let lang = lang_of(req)
          match req.query("format") {
            Some("json") => Response::json(export_json(db, session, lang))
            Some("md") | Some("markdown") =>
              Response::text(export_markdown(db, session, lang))
              .with_header("Content-Type", "text/markdown; charset=utf-8")
              .with_header(
                "Content-Disposition",
                "attachment; filename=\"maked-session-\{id}.md\"",
              )
            _ => {
              let body : Json = {
                "error": "unknown_format",
                "format": match req.query("format") {
                  Some(text) => text
                  None => ""
                },
              }
              Response::json(body, status=400)
            }
          }
        }
      }
    }
  })
  // Loop endpoints: the pyroduct-driven state cycle.
  // GET  /api/loop/status       → current domain, position, history
  // GET  /api/loop/slots        → all eight drive slots with designation and gloss
  // POST /api/loop/step         → advance one step using the domain's drive slot
  // POST /api/loop/step/:slot   → advance one step using the named slot
  // POST /api/loop/reset        → return to Model with empty history
  app.get("/api/loop/status", req => {
    let state = get_loop_state()
    Response::json(state.to_json(lang_of(req)))
  })
  app.get("/api/loop/slots", req => {
    // The same array the status response carries under `slots`, from the same
    // helper, so the two endpoints cannot disagree about the vocabulary.
    let body : Json = { "slots": slots_json(lang_of(req)) }
    Response::json(body)
  })
  // GET /api/model
  //
  // The machine itself, as data: the domains, the positions, the slots and
  // the rule for every pair. It is served so that the model can be read,
  // edited and handed back -- the loop is going to run off a model file
  // rather than off a package, and a file nobody can get at is not a file
  // anybody can edit.
  app.get("/api/model", _req => Response::json(current_model().to_json()))
  // GET /api/agent
  //
  // The discovery document: what MAKED is, the seven tools an agent can
  // call, the instructions for calling them, and the plain HTTP endpoints
  // that ask the same questions.
  //
  // It is here for an agent that does not speak the Model Context
  // Protocol, and for one that has never heard of it. The agent's server
  // offers the same tools over the protocol, and the two lists come from
  // one place, so an agent that reads this and an agent that asks the
  // server are told the same thing about the same seven tools.
  app.get("/api/agent", _req => Response::json(agent_discovery()))
  // GET /api/loop/continuations?depth=3
  //
  // What the model itself says could happen next from the current position,
  // via pyroduct's `after_open` -- the table's own answer to "all possible
  // continuations", as distinct from `expand`, which wants the caller to name
  // the slot sequence first. This is the replacement for deciding the ring's
  // next step by meaning: the machine does not choose, and neither does this
  // endpoint -- it returns the candidates and lets a person pick.
  app.get("/api/loop/continuations", req => {
    let model = current_model()
    let lang = lang_of(req)
    let state = get_loop_state()
    let current_pos = state.domain_state(state.current).position
    let depth = match req.query("depth") {
      Some(text) => @string.parse_int(text) catch { _ => 3 }
      None => 3
    }
    let bounded = if depth <= 0 || depth > 8 { 3 } else { depth }
    let items = []
    for (next, steps) in continuations(current_pos, bounded) {
      let item : Json = {
        "position": model.position_label_in(next, lang),
        "position_label": model.position_label_in(next, lang),
        "steps": steps,
      }
      items.push(item)
    }
    let by_slot = []
    for slot in exitable_slots(current_pos) {
      let targets = []
      for (next, steps) in model.continuations_for(current_pos, slot, bounded) {
        let target : Json = {
          "position": model.position_label_in(next, lang),
          "steps": steps,
        }
        targets.push(target)
      }
      let entry : Json = {
        "name": slot,
        "designation": model.slot_designation_in(slot, lang),
        "targets": [..targets],
      }
      by_slot.push(entry)
    }
    let body : Json = {
      "from": model.position_label_in(current_pos, lang),
      "from_label": model.position_label_in(current_pos, lang),
      "depth": bounded,
      "continuations": [..items],
      "by_slot": [..by_slot],
      "note": "The machine does not choose for the subject: this lists the edges the transition table really offers, and the choosing is left to the person.",
    }
    Response::json(body)
  })
  app.post(
    "/api/loop/step",
    // The two states are what the step is recorded from: `before` says where
    // the domain stood and `after` says where it landed, so the recording
    // never has to be told anything the step itself did not produce.
    //
    // The session state travels with the loop status, so that the panel's
    // step count and its summary of the run are the ones the step just
    // produced. Without it they were the ones from start-up, and the count
    // stopped moving after the first click.
    req => Response::json(take_drive_step(db, lang_of(req))),
  )
  app.post("/api/loop/step/:slot", req => {
    match req.param("slot") {
      Some(slot_name) => {
        // A "target" in the body means the reader chose one of the
        // successors the table offered and declined to pick. It is the
        // way out of a position the machine cannot decide for itself.
        //
        // The step itself is in `step.mbt`, because the agent's tools take
        // the same one: two copies of "what a step does" is two things to
        // keep in step with each other.
        let payload = req.json().unwrap_or(Json::empty_object())
        let asked = json_string(payload, "target")
        match take_slot_step(db, slot_name, asked, lang_of(req)) {
          Taken(body) => Response::json(body)
          UnknownSlot(name) => {
            let body : Json = { "error": "unknown_slot", "slot": name }
            Response::json(body, status=400)
          }
          UnknownTarget(target, targets) => {
            // Not a silent failure. The answer names the targets the
            // table really offers, so a reader who asked for the wrong
            // one can see the right one instead of watching the page
            // do nothing.
            let body : Json = {
              "error": "unknown_target",
              "target": target,
              "targets": string_array_json(targets),
            }
            Response::json(body, status=400)
          }
        }
      }
      None => {
        let body : Json = { "error": "missing_slot" }
        Response::json(body, status=400)
      }
    }
  })
  app.post("/api/loop/reset", req => {
    let state = reset_to(starting_domain())
    reset_session_start(db, state)
    Response::json(loop_payload(db, lang_of(req)))
  })
  // POST /api/loop/reset/:domain → reset to start from the specified domain
  app.post("/api/loop/reset/:domain", req => {
    match req.param("domain") {
      Some(domain_name) => {
        let parsed = match domain_from_letter(domain_name) {
          Some(d) => Some(d)
          None => domain_from_english(domain_name)
        }
        match parsed {
          Some(domain) => {
            let state = reset_to(domain)
            reset_session_start(db, state)
            Response::json(loop_payload(db, lang_of(req)))
          }
          None => {
            let body : Json = {
              "error": "unknown_domain",
              "domain": domain_name,
            }
            Response::json(body, status=400)
          }
        }
      }
      None => {
        let body : Json = { "error": "missing_domain" }
        Response::json(body, status=400)
      }
    }
  })
  // Loop mode endpoints: get/set the loop mode (structured/free).
  // GET  /api/loop/mode          → current mode
  // POST /api/loop/mode/:mode    → set mode (structured or free)
  app.get("/api/loop/mode", _req => {
    let mode = get_loop_mode()
    let body : Json = {
      "mode": match mode {
        Structured => "structured"
        Free => "free"
      },
      "designation": mode.designation(),
      "gloss": mode.gloss(),
    }
    Response::json(body)
  })
  app.post("/api/loop/mode/:mode", req => {
    match req.param("mode") {
      Some(raw_mode) => {
        let parsed = match raw_mode {
          "structured" => Some(Structured)
          "free" => Some(Free)
          "Structured" => Some(Structured)
          "Free" => Some(Free)
          _ => None
        }
        match parsed {
          Some(mode) => {
            ignore(set_loop_mode(mode))
            // The mode belongs to the session as well as to the live state:
            // a session replayed tomorrow has to come back in the mode it
            // was explored in.
            let session_id = ensure_session(db)
            db.set_session_mode(session_id, mode_name(mode))
            Response::json(loop_payload(db, lang_of(req)))
          }
          None => {
            let body : Json = { "error": "unknown_mode", "mode": raw_mode }
            Response::json(body, status=400)
          }
        }
      }
      None => {
        let body : Json = { "error": "missing_mode" }
        Response::json(body, status=400)
      }
    }
  })
  // Research endpoints: the corpus, the documents it holds, and the loop
  // driven by them.
  //
  // GET  /api/research/documents → the documents the corpus holds
  // POST /api/research/drive     → drive the Loop with those documents
  // GET  /api/research/config    → the mapping table the reader may edit
  // PUT  /api/research/config    → replace the table, and write it back
  // GET  /api/research/corpus    → the corpus the reader may replace
  // PUT  /api/research/corpus    → replace the corpus, and write it back
  app.get("/api/research/documents", req => {
    let lang = lang_of(req)
    let corpus = current_corpus()
    // The read is told apart from an empty corpus. A corpus that names a
    // folder that is not there is not a corpus that holds nothing, and the
    // panel has to be able to say which one it is looking at.
    let no_documents : Array[Document] = []
    let (documents, read_error, read_reason) = match fetch_corpus(corpus) {
      Ok(found) => (found, "", "")
      Err(reason) => (no_documents, "corpus_unreadable", reason)
    }
    let model = current_model()
    let config = current_research()
    let triggers = documents.map(fn(d) {
      // The table says which slot a document drives and what the rule is
      // called. It is the reader's table, so the slot is read as the
      // model's id and the rest of the server only ever sees the model's
      // vocabulary.
      let (slot, label) = document_to_slot(config, d)
      let item : Json = {
        "document_id": d.id,
        "rule": label,
        "slot": model.slot_designation_in(slot, lang),
        "slot_english": slot,
      }
      item
    })
    let body : Json = {
      "documents": [..documents.map(fn(d) { d.to_json() })],
      "triggers": [..triggers],
      "count": documents.length(),
      "corpus": corpus_json(corpus),
      // The reason the corpus could not be read, and the name of the failure.
      // Empty when the corpus was read: an empty field is a field that says
      // "nothing went wrong", and a client that only looks at one of the two
      // still learns the truth.
      "error": read_error,
      "reason": read_reason,
      // An empty corpus is said out loud. A panel that shows nothing and
      // says nothing is a panel the reader cannot tell apart from a broken
      // one, and "the corpus held nothing" and "the fetch failed" are
      // different facts that look identical when neither is said.
      "notice": if read_error != "" {
        "The corpus (" +
        corpus.describe() +
        ") could not be read: " +
        read_reason +
        "."
      } else if documents.length() == 0 {
        "The corpus (" + corpus.describe() + ") held no documents."
      } else {
        ""
      },
    }
    Response::json(body)
  })
  app.post("/api/research/drive", req => {
    let lang = lang_of(req)
    let corpus = current_corpus()
    // The same distinction as the documents panel: a corpus that could not be
    // read drives nothing, and says so, rather than driving nothing in
    // silence.
    let no_documents : Array[Document] = []
    let (documents, read_error, read_reason) = match fetch_corpus(corpus) {
      Ok(found) => (found, "", "")
      Err(reason) => (no_documents, "corpus_unreadable", reason)
    }
    let model = current_model()
    let config = current_research()
    let results : Array[Json] = []
    let mut driven = 0
    for document in documents {
      let (slot, label) = document_to_slot(config, document)
      // A table may name a slot the running model does not have -- the
      // built-in table is the built-in model's, and a model file has slots
      // of its own. Such a document is not driven, and it is said so: a
      // step that went nowhere while looking like a step is the failure
      // this project exists to remove.
      if slot == "" || model.slot_from_name(slot) is None {
        let skipped : Json = {
          "document_id": document.id,
          "document_title": document.title,
          "rule": label,
          "slot_english": slot,
          "driven": false,
          "reason": if slot == "" {
            "the table leaves documents it does not recognise alone"
          } else {
            "the model has no slot called \"" + slot + "\""
          },
        }
        results.push(skipped)
        continue
      }
      let state_before = get_loop_state()
      let state_after = step_loop_with_slot(slot)
      // A step taken by a document is a step like any other, and it belongs
      // in the timeline: "the model moved because of this document" is
      // exactly the kind of thing a session is for.
      record_step(db, state_before, state_after, "research")
      let result : Json = {
        "document_id": document.id,
        "document_title": document.title,
        "rule": label,
        "slot": model.slot_designation_in(slot, lang),
        "slot_english": slot,
        "driven": true,
        "domain_before": state_before.current.letter(),
        "domain_after": state_after.current.letter(),
        "history_length": state_after.history.length(),
      }
      results.push(result)
      driven += 1
    }
    let final_state = get_loop_state()
    let body : Json = {
      "results": [..results],
      "final_state": final_state.to_json(lang),
      "documents_processed": documents.length(),
      "documents_driven": driven,
      "corpus": corpus_json(corpus),
      // The reason the corpus could not be read. Without it a drive that
      // read nothing looks exactly like a drive over an empty corpus, and
      // the reader is left to guess which one happened.
      "error": read_error,
      "reason": read_reason,
      "notice": if read_error != "" {
        "The corpus (" +
        corpus.describe() +
        ") could not be read: " +
        read_reason +
        "."
      } else {
        ""
      },
    }
    Response::json(body)
  })
  // The mapping table, as data a reader can edit and hand back.
  //
  // GET /api/research/config → the table, the file it came from, and
  // whether it can be written back at all.
  app.get("/api/research/config", _req => {
    let config = current_research()
    let body : Json = {
      "config": config.to_json(),
      "path": config.path,
      // The built-in table has nowhere to be written, and saying so is
      // better than accepting an edit and losing it.
      "writable": config.path != "",
    }
    Response::json(body)
  })
  // PUT /api/research/config → replace the table.
  //
  // The body is the table itself, in the same shape GET hands back, so a
  // client can read the table, change it and put it back without knowing
  // anything about the format. A table that names a slot the model does
  // not have is refused, with the reason, and the table that was running
  // keeps running: half a table fires on the wrong documents.
  app.put("/api/research/config", req => {
    let payload = req.json().unwrap_or(Json::empty_object())
    match
      ResearchConfig::from_json(
        current_model(),
        current_research().path,
        payload,
      ) {
      Accepted(config) => {
        let saved = write_research_file(config) catch { _ => false }
        install_research(config)
        let body : Json = {
          "config": config.to_json(),
          "path": config.path,
          "saved": saved,
          "notice": if saved {
            "The table is running, and it was written back to " +
            config.path +
            "."
          } else if config.path == "" {
            "The table is running. The built-in table is not written anywhere, so it lasts until the server stops."
          } else {
            "The table is running, but it could not be written back to " +
            config.path +
            "."
          },
        }
        Response::json(body)
      }
      Rejected(reason) => {
        let body : Json = { "error": "invalid_config", "reason": reason }
        Response::json(body, status=400)
      }
    }
  })
  // The corpus, as data a reader can replace.
  //
  // GET /api/research/corpus → the corpus, the file it came from, and
  // whether it can be written back at all.
  app.get("/api/research/corpus", _req => {
    let corpus = current_corpus()
    let body : Json = {
      "corpus": corpus.to_json(),
      "path": corpus.path,
      // The built-in corpus has nowhere to be written, and saying so is
      // better than accepting an edit and losing it.
      "writable": corpus.path != "",
      "description": corpus.describe(),
    }
    Response::json(body)
  })
  // PUT /api/research/corpus → replace the corpus.
  //
  // The body is the corpus itself, in the same shape GET hands back, so a
  // client can read it, change it and put it back without knowing anything
  // about the format. A corpus that names a source it cannot read is
  // refused, with the reason, and the corpus that was running keeps
  // running: a corpus that reads nothing is a panel that shows nothing.
  app.put("/api/research/corpus", req => {
    let payload = req.json().unwrap_or(Json::empty_object())
    match CorpusConfig::from_json(current_corpus().path, payload) {
      Accepted(corpus) => {
        let saved = write_corpus_file(corpus) catch { _ => false }
        install_corpus(corpus)
        let body : Json = {
          "corpus": corpus.to_json(),
          "path": corpus.path,
          "saved": saved,
          "description": corpus.describe(),
          "notice": if saved {
            "The corpus is running, and it was written back to " +
            corpus.path +
            "."
          } else if corpus.path == "" {
            "The corpus is running. The built-in corpus is not written anywhere, so it lasts until the server stops."
          } else {
            "The corpus is running, but it could not be written back to " +
            corpus.path +
            "."
          },
        }
        Response::json(body)
      }
      Rejected(reason) => {
        let body : Json = { "error": "invalid_corpus", "reason": reason }
        Response::json(body, status=400)
      }
    }
  })

  // Causal inference endpoint: estimate the causal effect of a document
  // claiming to be new on an impact score, using Double/Debiased Machine
  // Learning, and report the diagnostics that make the estimate arguable.
  //
  // GET /api/research/causal → read the corpus and run causal analysis
  //
  // A refusal is a 200 with a reason in it, not a 400: the request was
  // fine, the corpus was not big enough, and a person is owed the reason
  // rather than a status code they cannot act on.
  app.get("/api/research/causal", _req => {
    let corpus = current_corpus()
    // The same honesty as the documents panel: an empty corpus and a fetch
    // that failed look identical when neither is said out loud. A corpus
    // that could not be read is refused with THAT reason, because the size
    // of a corpus that was never read is not a fact.
    let (documents, read_error, read_reason, causal_result) = match
      fetch_corpus(corpus) {
      Ok(found) => (found, "", "", estimate_causal_effect(found))
      Err(reason) => {
        let no_documents : Array[Document] = []
        (
          no_documents,
          "corpus_unreadable",
          reason,
          CausalOutcome::refused_because(
            "The corpus (" +
            corpus.describe() +
            ") could not be read: " +
            reason,
          ),
        )
      }
    }
    let body : Json = {
      "causal": causal_result.to_json(),
      "documents_analyzed": documents.length(),
      "error": read_error,
      "reason": read_reason,
      "notice": if read_error != "" {
        "The corpus (" +
        corpus.describe() +
        ") could not be read: " +
        read_reason +
        "."
      } else if documents.length() == 0 {
        "The corpus (" + corpus.describe() + ") held no documents."
      } else {
        ""
      },
    }
    Response::json(body)
  })

  // The Society layer: pyroduct's collective machine, the words for it, and
  // where the collective is standing.
  //
  // GET  /api/society       → the machine, the collective's position, the
  //                            moves available from it, and the gaps in the
  //                            vocabulary
  // POST /api/society/step  → take a move; the machine answers with where it
  //                            lands, or with the reason there was no move
  //
  // The machine is pyroduct's and the words are the vocabulary file's, and
  // the two are kept apart on purpose: a position the machine has and the
  // file does not name is a gap, and the gap is said out loud rather than
  // rendered as a blank.
  //
  // Both answers have the same shape. That is the point: a move that is
  // refused still answers with the machine, the collective's position and
  // the moves available from it, plus the reason the move did not happen.
  // A response that carried only a reason on refusal would leave the panel
  // holding two different shapes and no way to tell which one it had.
  app.get("/api/society", req => {
    let vocabulary = current_society_vocabulary()
    let state = get_loop_state()
    Response::json(
      society_payload(
        vocabulary,
        state.society_state,
        SocietyOutcome::none(),
        lang_of(req),
      ),
    )
  })
  app.post("/api/society/step", req => {
    let payload = req.json().unwrap_or(Json::empty_object())
    let trigger = json_string(payload, "trigger")
    let vocabulary = current_society_vocabulary()
    let before = get_loop_state()
    let from = society_position_id(before.society_state)
    let lang = lang_of(req)
    let step = society_step(vocabulary, before.society_state, trigger, lang)
    match step {
      Advanced(_, to) => {
        let landing = society_position_from_id(to)
        match landing {
          Some(state) => {
            set_loop_state(before.with_society_state(state))
            Response::json(
              society_payload(
                vocabulary,
                state,
                { kind: "moved", reason: "", from, },
                lang,
              ),
            )
          }
          // The machine named a landing place that is not one of its
          // positions. That cannot happen with the machine this build
          // knows, and if it ever did, the collective stays where it is
          // and the reader is told why -- rather than the server inventing
          // a position to send it to.
          None =>
            Response::json(
              society_payload(
                vocabulary,
                before.society_state,
                society_outcome_of(vocabulary, step, from, lang),
                lang,
              ),
            )
        }
      }
      Kept(_, _) =>
        Response::json(
          society_payload(
            vocabulary,
            before.society_state,
            society_outcome_of(vocabulary, step, from, lang),
            lang,
          ),
        )
      Undecided(_, _) =>
        Response::json(
          society_payload(
            vocabulary,
            before.society_state,
            society_outcome_of(vocabulary, step, from, lang),
            lang,
          ),
        )
      Refused(_, _) =>
        Response::json(
          society_payload(
            vocabulary,
            before.society_state,
            society_outcome_of(vocabulary, step, from, lang),
            lang,
          ),
        )
    }
  })
}

///|
/// What a move did, in the terms the panel reads.
fn society_outcome_of(
  vocabulary : SocietyVocabulary,
  step : SocietyStep,
  from : String,
  lang : Lang,
) -> SocietyOutcome {
  {
    kind: step.society_step_kind(),
    reason: society_step_reason(vocabulary, step, lang),
    from,
  }
}

///|
/// The Society layer, as the panel reads it.
///
/// One shape for every answer. The outcome travels with it, so a reader who
/// asks where the collective stands and a reader who just moved it are
/// looking at the same body.
pub fn society_payload(
  vocabulary : SocietyVocabulary,
  state : @society.State,
  outcome : SocietyOutcome,
  lang : Lang,
) -> Json {
  let id = society_position_id(state)
  let position = society_word(vocabulary.positions, id)
  let positions : Array[Json] = []
  for p in society_positions(vocabulary, lang) {
    positions.push({
      "id": p.id,
      "label": p.label,
      "gloss": p.gloss,
      "phase": p.phase,
      "phase_label": society_phase_label(vocabulary, p.phase, lang),
    })
  }
  let transitions : Array[Json] = []
  for t in society_transitions() {
    transitions.push({
      "from": t.from,
      "trigger": t.trigger,
      "trigger_label": society_trigger_label(vocabulary, t.trigger, lang),
      "to": t.to,
      "to_label": society_position_label(vocabulary, t.to, lang),
    })
  }
  let moves : Array[Json] = []
  for m in society_moves(state) {
    moves.push({
      "trigger": m.trigger,
      "trigger_label": society_trigger_label(vocabulary, m.trigger, lang),
      "to": m.to,
      "to_label": society_position_label(vocabulary, m.to, lang),
    })
  }
  {
    "state": id,
    "state_label": society_position_label(vocabulary, id, lang),
    "state_gloss": lang.pick(position.gloss, state.gloss()),
    "phase": society_phase_id(state.phase()),
    "positions": positions,
    "transitions": transitions,
    "moves": moves,
    // A gap in the vocabulary is a defect, and a defect the panel shows.
    "gaps": society_vocabulary_gaps(vocabulary),
    "path": vocabulary.path,
    // What the last move did, and why it did not do anything else.
    "kind": outcome.kind,
    "reason": outcome.reason,
    "from": outcome.from,
    "from_label": if outcome.from == "" {
      ""
    } else {
      society_position_label(vocabulary, outcome.from, lang)
    },
  }
}

///|
/// The reason a move did not happen, in words.
pub fn society_step_reason(
  vocabulary : SocietyVocabulary,
  step : SocietyStep,
  lang : Lang,
) -> String {
  match step {
    Advanced(_, _) => ""
    Kept(_, place) => {
      let where_ = society_position_label(vocabulary, place, lang)
      match lang {
        English =>
          "The collective stayed where it was: " +
          where_ +
          " is where that move leads."
        Chinese =>
          "集体停在原地：" +
          where_ +
          " 正是那一步通往的地方。"
      }
    }
    Undecided(_, places) => {
      let names : Array[String] = []
      for place in places {
        names.push(society_position_label(vocabulary, place, lang))
      }
      match lang {
        English =>
          "That move leaves the collective more than one place to be: " +
          names.join(", ") +
          "."
        Chinese =>
          "那一步让集体同时身处不止一处：" +
          names.join("、") +
          "。"
      }
    }
    Refused(_, reason) => reason
  }
}

///|
/// The corpus as the panel sees it: what kind it is, where it reads from,
/// and the file it was configured in.
///
/// The description is written out in words rather than left to the client
/// to assemble, so that the panel says the same thing whether the corpus
/// came from a file or was built in.
fn corpus_json(corpus : CorpusConfig) -> Json {
  {
    "kind": corpus_kind_text(corpus.kind),
    "source": corpus.describe(),
    "path": corpus.path,
    "max_results": corpus.max_results,
  }
}

///|
/// The language a request asks for.
///
/// `?lang=zh` is the whole of the switch, and an absent parameter means
/// English. It is a query parameter rather than a header because it is a
/// choice rather than a negotiation: the client says which language it wants
/// and the server answers in that one, without a second round trip to ask
/// what the server supports.
fn lang_of(req : Request) -> Lang {
  lang_from_query(req.query("lang"))
}

///|
/// The session id in a path parameter, or -1 when it is not a number.
///
/// Rowids start at 1, so the sentinel cannot collide with a real session and
/// it keeps the handler flat: a missing or malformed id can never name a
/// session, and saying so plainly beats a 404 that implies it might exist.
fn session_id_param(req : Request) -> Int32 {
  match req.param("id") {
    Some(raw) => @string.parse_int(raw) catch { _ => -1 }
    None => -1
  }
}

///|
/// The five domains in ring order, for the frontend to draw the ring.///
/// The array is returned as `[..items]` rather than `items`: an
/// `Array[Json]` does not coerce to `Json` on its own, but an array *literal*
/// does, and the spread is the only difference between the two here.
///
/// The names are the machine's own, in the language asked for, and they are
/// the same names the pages carry -- one source, so the ring on the index
/// page and the page behind it cannot call the same domain two different
/// names.
fn domains_json(lang : Lang) -> Json {
  let items = []
  for (slug, stored_title, letter, stored_role) in ring_domains() {
    let (title, role, title_zh, role_zh) = domain_names(
      letter, stored_title, stored_role,
    )
    let item : Json = {
      "slug": slug,
      "title": lang.pick(title, title_zh),
      "letter": letter,
      "role": lang.pick(role, role_zh),
    }
    items.push(item)
  }
  [..items]
}
