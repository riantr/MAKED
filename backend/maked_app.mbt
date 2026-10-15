///| Assemble the MAKED application.
///
/// One native process serves the JSON API under `/api/` and the built
/// frontend bundle from `frontend/dist`. The static middleware is added
/// *after* the API routes, so `/api/...` is answered by the router and only
/// unmatched paths fall through to files on disk; `spa_fallback` then hands
/// the remaining navigations to `index.html` so the SPA can route them
/// client-side instead of 404ing.

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
  // There is deliberately no route for `/` or `/index`. Those paths are owned
  // by the static layer -- `rewrite_trailing_slash_index` resolves `/` to
  // `dist/index.html` -- so an SPA-shell route registered here would never run.
  // An earlier version had `app.get("/", ...)` returning the home page as
  // JSON and it was dead code that read like a live endpoint. The home page is
  // still in the `pages` table; the SPA reads it out of `GET /api/pages` like
  // every other page.
  app
}

///|
/// Log one line per request. Kept deliberately small: the point of the
/// framework's middleware chain is that a cross-cutting concern like this
/// needs no cooperation from any route.
fn logging_middleware() -> Middleware {
  next => {
    req => {
      let response = next(req)
      println("\{req.verb()} \{req.path()} -> \{response.status}")
      response
    }
  }
}

///|
/// Serve the built frontend from `dist`.
///
/// `history_fallback` is deliberately *not* used. moonback's implementation
/// runs the downstream handler and rewrites **any** 404 into `index.html`
/// (`unstable_static/static.mbt`, the `HistoryFallback` suberror). That cannot
/// tell a browser deep link apart from a legitimate API 404, so
/// `/api/pages/nope` came back as `200 text/html` and the frontend's
/// `decode_pages` silently fell back to an empty list. `spa_fallback` below
/// makes that distinction instead.
pub fn static_files(dist : String) -> @moonback.Middleware {
  @static.new(root=dist, rewrite_trailing_slash_index=true)
}

///|
/// Answer an unmatched browser navigation with `index.html`.
///
/// Registered *after* `static_files` so it sits closer to the router: a real
/// file is served before this runs at all, and an `/api/` path falls straight
/// through so its 404 stays a 404.
pub fn spa_fallback(dist : String) -> @moonback.Middleware {
  let index_path = dist + "/index.html"
  @moonback.Middleware(next => {
    (req, res) => {
      guard wants_spa_shell(req) else {
        next(req, res)
        return
      }
      let data = @fs.read_file(index_path) catch {
        err => {
          // No bundle built yet. Let the router answer rather than invent a
          // blank page; the server already warns about this at start-up.
          println("warning: \{index_path} unreadable: \{err}")
          next(req, res)
          return
        }
      }
      res
      .respond(status=200, headers=[
        ("content-type", "text/html; charset=utf-8"),
      ])
      .write(data)
    }
  })
}

///|
/// Whether this request is an SPA route rather than an asset or an API call.
fn wants_spa_shell(req : @moonback.Request) -> Bool {
  guard req.meth is Get || req.meth is Head else { return false }
  let path = strip_query_and_fragment(req.path)
  guard path != "/api" && !path.has_prefix("/api/") else { return false }
  // A last segment containing a dot names an asset. A missing stylesheet or
  // script should 404, not quietly come back as HTML that the browser will
  // try to execute.
  let last_segment = match path.rev_find("/") {
    Some(index) => path[index + 1:]
    None => path
  }
  !last_segment.contains_char('.')
}

///|
fn strip_query_and_fragment(path : StringView) -> String {
  let mut end = path.length()
  if path.find("?") is Some(index) && index < end {
    end = index
  }
  if path.find("#") is Some(index) && index < end {
    end = index
  }
  path[0:end].to_owned()
}
