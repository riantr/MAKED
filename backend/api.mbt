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
