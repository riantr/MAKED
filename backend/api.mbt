///| The MAKED API: page content, navigation, workspace entries, and status.
///
/// The page routes are read-only, as they were when the only content was the
/// nine seeded pages. The workspace routes under `/api/entries` are the first
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
  app.get("/api/status", _req => {
    let pages = db.all_pages()
    let body : Json = {
      "status": "ok",
      "database": db_path,
      "page_count": pages.length(),
      "domains": domains_json(),
    }
    Response::json(body)
  })
  app.get("/api/pages", _req => {
    let pages = db.all_pages().map(fn(p) { p.to_json() })
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
  app.get("/api/bootstrap", _req => {
    let pages = db.all_pages().map(fn(p) { p.to_json() })
    let entries = db.all_entries().map(fn(e) { e.to_json() })
    let body : Json = {
      "pages": pages,
      "entries": entries,
      "entry_domains": entry_domains(),
    }
    Response::json(body).with_header("Cache-Control", "no-store")
  })
  app.get("/api/pages/:slug", req => {
    match req.param("slug") {
      Some(slug) =>
        match db.page_by_slug(slug) {
          Some(page) => Response::json(page.to_json())
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
  app.get("/api/domains", _req => {
    let body : Json = { "domains": domains_json() }
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
  // Loop endpoints: the pyroduct-driven state cycle.
  // GET  /api/loop/status       → current domain, position, history
  // GET  /api/loop/slots        → all eight drive slots with designation and gloss
  // POST /api/loop/step         → advance one step using the domain's drive slot
  // POST /api/loop/step/:slot   → advance one step using the named slot
  // POST /api/loop/reset        → return to Model with empty history
  app.get("/api/loop/status", _req => {
    let state = get_loop_state()
    Response::json(state.to_json())
  })
  app.get("/api/loop/slots", _req => {
    // The same array the status response carries under `slots`, from the same
    // helper, so the two endpoints cannot disagree about the vocabulary.
    let body : Json = { "slots": slots_json() }
    Response::json(body)
  })
  // GET /api/loop/continuations?depth=3
  //
  // What the model itself says could happen next from the current position,
  // via pyroduct's `after_open` -- the table's own answer to "all possible
  // continuations", as distinct from `expand`, which wants the caller to name
  // the slot sequence first. This is the replacement for deciding the ring's
  // next step by meaning: the machine does not choose, and neither does this
  // endpoint -- it returns the candidates and lets a person pick.
  app.get("/api/loop/continuations", req => {
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
        "position": next.en_label(),
        "position_label": next.en_label(),
        "steps": steps,
      }
      items.push(item)
    }
    let by_slot = []
    for slot in exitable_slots(current_pos) {
      let targets = []
      for (next, steps) in @sm.after_open(current_pos, slot, bounded) {
        let target : Json = { "position": next.en_label(), "steps": steps }
        targets.push(target)
      }
      let entry : Json = {
        "name": slot_english_name(slot),
        "designation": slot.en_designation(),
        "targets": [..targets],
      }
      by_slot.push(entry)
    }
    let body : Json = {
      "from": current_pos.en_label(),
      "from_label": current_pos.en_label(),
      "depth": bounded,
      "continuations": [..items],
      "by_slot": [..by_slot],
      "note": "The machine does not choose for the subject: this lists the edges the transition table really offers, and the choosing is left to the person.",
    }
    Response::json(body)
  })
  app.post("/api/loop/step", _req => {
    let state = step_loop()
    Response::json(state.to_json())
  })
  app.post("/api/loop/step/:slot", req => {
    match req.param("slot") {
      Some(slot_name) => {
        let parsed = match slot_from_english(slot_name) {
          Some(s) => Some(s)
          None => slot_from_designation(slot_name)
        }
        match parsed {
          Some(slot) => {
            let state = step_loop_with_slot(slot)
            Response::json(state.to_json())
          }
          None => {
            let body : Json = { "error": "unknown_slot", "slot": slot_name }
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
  app.post("/api/loop/reset", _req => {
    let state = reset_loop()
    Response::json(state.to_json())
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
            Response::json(state.to_json())
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
      Some(mode_name) => {
        let parsed = match mode_name {
          "structured" => Some(Structured)
          "free" => Some(Free)
          "Structured" => Some(Structured)
          "Free" => Some(Free)
          _ => None
        }
        match parsed {
          Some(mode) => {
            let state = set_loop_mode(mode)
            Response::json(state.to_json())
          }
          None => {
            let body : Json = { "error": "unknown_mode", "mode": mode_name }
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
  // Research endpoints: arxiv-driven SNN research cycle.
  // GET  /api/research/papers  → fetch recent SNN papers from arxiv
  // POST /api/research/drive   → fetch papers and drive the Loop with them
  app.get("/api/research/papers", _req => {
    let papers = fetch_snn_papers(10) catch { _ => [] }
    let papers_json = papers.map(fn(p) { p.to_json() })
    let triggers = papers.map(fn(p) {
      let t = paper_to_trigger(p)
      let s = trigger_to_slot(t)
      let item : Json = {
        "paper_id": p.id,
        "trigger": @debug.to_string(t),
        "slot": s.en_designation(),
        "slot_english": slot_english_name(s),
      }
      item
    })
    let body : Json = {
      "papers": [..papers_json],
      "triggers": [..triggers],
      "count": papers.length(),
    }
    Response::json(body)
  })
  app.post("/api/research/drive", _req => {
    let papers = fetch_snn_papers(5) catch { _ => [] }
    let results : Array[Json] = []
    for paper in papers {
      let trigger = paper_to_trigger(paper)
      let slot = trigger_to_slot(trigger)
      let state_before = get_loop_state()
      let state_after = step_loop_with_slot(slot)
      let result : Json = {
        "paper_id": paper.id,
        "paper_title": paper.title,
        "trigger": @debug.to_string(trigger),
        "slot": slot.en_designation(),
        "slot_english": slot_english_name(slot),
        "domain_before": state_before.current.letter(),
        "domain_after": state_after.current.letter(),
        "history_length": state_after.history.length(),
      }
      results.push(result)
    }
    let final_state = get_loop_state()
    let body : Json = {
      "results": [..results],
      "final_state": final_state.to_json(),
      "papers_processed": papers.length(),
    }
    Response::json(body)
  })
  // Causal inference endpoint: estimate the causal effect of paper "novelty"
  // on a synthetic impact score using Double/Debiased Machine Learning.
  // GET /api/research/causal → fetch papers and run causal analysis
  app.get("/api/research/causal", _req => {
    let papers = fetch_snn_papers(20) catch { _ => [] }
    let causal_result = estimate_causal_effect(papers)
    let body : Json = {
      "causal": causal_result.to_json(),
      "papers_analyzed": papers.length(),
    }
    Response::json(body)
  })
}

///|
/// The five domains in ring order, for the frontend to draw the ring.
///
/// The array is returned as `[..items]` rather than `items`: an
/// `Array[Json]` does not coerce to `Json` on its own, but an array *literal*
/// does, and the spread is the only difference between the two here.
fn domains_json() -> Json {
  let items = []
  for (slug, title, letter, role) in ring_domains() {
    let item : Json = {
      "slug": slug,
      "title": title,
      "letter": letter,
      "role": role,
    }
    items.push(item)
  }
  [..items]
}
