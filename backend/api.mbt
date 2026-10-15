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
  // POST /api/loop/step/:slot   → advance one step using the named slot (两字定名)
  // POST /api/loop/reset        → return to Model with empty history
  app.get("/api/loop/status", _req => {
    let state = get_loop_state()
    Response::json(state.to_json())
  })
  app.get("/api/loop/slots", _req => {
    let items = []
    for (english, designation, gloss, source) in all_slots_info() {
      let item : Json = {
        "name": english,
        "designation": designation,
        "gloss": gloss,
        "source": source,
      }
      items.push(item)
    }
    let body : Json = { "slots": [..items] }
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
        "slot": s.designation(),
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
        "slot": slot.designation(),
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
