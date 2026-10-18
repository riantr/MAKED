///| The MAKED API: page content, navigation, and server status.
///
/// Every route is read-only. The original django CMS deployment had an admin,
/// Celery and a flat-page editor; this scope is the nine public pages, so
/// there is no write path and no auth to get wrong.

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
