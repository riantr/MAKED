///| Assemble the MAKED application.
///
/// One native process serves the JSON API under `/api/` and the built
/// frontend bundle from `frontend/dist`. The static middleware is added
/// *after* the API routes, so `/api/...` is answered by the router and only
/// unmatched paths fall through to files on disk -- and `history_fallback`
/// makes a deep link like `/about` return `index.html` so the SPA can route
/// it client-side instead of 404ing.

///|
pub fn create_app(db_path : String) -> App raise {
  let db = Database::open(db_path)
  db.seed(seed_pages())
  let home = home_page()
  // The index is a page like any other; store it so it is served from the
  // same table as the rest rather than special-cased in a handler.
  db.seed([home, not_found_page()])
  let app = App::new()
  app.add_middleware(logging_middleware())
  build_api(app, db, db_path)
  app.get("/", _req => Response::json(home.to_json()))
  app.get("/index", _req => Response::json(home.to_json()))
  app
}

///|
/// Log one line per request. Kept deliberately small: the point of the
/// framework's middleware chain is that a cross-cutting concern like this
/// needs no cooperation from any route.
fn logging_middleware() -> Middleware {
  next => req => {
    let response = next(req)
    println("\{req.verb()} \{req.path()} -> \{response.status}")
    response
  }
}

///|
/// Serve the built frontend from `dist`, falling back to `index.html` so the
/// SPA owns its own routes.
pub fn static_files(dist : String) -> @moonback.Middleware {
  @static.new(
    root=dist,
    rewrite_trailing_slash_index=true,
    history_fallback=Some("/index.html"),
  )
}
