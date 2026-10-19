///| The application object: a route table plus an ordered middleware chain.
///
/// This is the Flask-shaped part of the project. It does not reimplement
/// routing: moonback's trie already resolves static, `:param` and `*rest`
/// segments with backtracking, and a second router here would only be a worse
/// one. Instead `App` collects routes in declaration order and registers each
/// with moonback, adapting between two shapes:
///
///   - handlers here are `async (Request) -> Response`
///   - moonback handlers are `async (Request, Responder) -> Unit`
///
/// The adapter is the only place that knows about `Responder`'s rule that it
/// is only valid for the duration of one request.

///|
/// A handler takes the request and produces a response.
pub type Handler = async (Request) -> Response

///|
/// Middleware is a *factory*: it receives the next link and returns the
/// wrapped link. `Middleware = (Next -> Next)`, so calling one with a single
/// argument yields the next link, which is what a route handler then invokes.
pub type Middleware = (async (Request) -> Response) -> async (Request) -> Response

///|
pub(all) struct Route {
  verb : @http.RequestMethod
  path : String
  handler : Handler
}

///|
pub struct App {
  routes : Array[Route]
  middlewares : Array[Middleware]
}

///|
pub fn App::new() -> App {
  { routes: [], middlewares: [], }
}

///|
/// Register a handler. `path` may contain `:name` segments and a trailing
/// `*rest`; both are resolved by moonback's router and read back through
/// `Request::param`.
pub fn App::route(
  self : App,
  verb : @http.RequestMethod,
  path : String,
  handler : Handler,
) -> Unit {
  self.routes.push({ verb, path, handler, })
}

///|
pub fn App::get(self : App, path : String, handler : Handler) -> Unit {
  self.route(@http.Get, path, handler)
}

///|
pub fn App::post(self : App, path : String, handler : Handler) -> Unit {
  self.route(@http.Post, path, handler)
}

///|
pub fn App::delete(self : App, path : String, handler : Handler) -> Unit {
  self.route(@http.Delete, path, handler)
}

///|
/// Middleware wraps every route. Middleware runs in registration order, so the
/// first one registered is the outermost.
pub fn App::add_middleware(self : App, middleware : Middleware) -> Unit {
  self.middlewares.push(middleware)
}

///|
/// Compose the middleware chain around `inner`, so that the first-registered
/// middleware ends up outermost.
fn wrap(
  middlewares : Array[Middleware],
  inner : async (Request) -> Response,
) -> async (Request) -> Response {
  let mut current = inner
  let mut i = middlewares.length()
  while i > 0 {
    i -= 1
    current = middlewares[i](current)
  }
  current
}

///|
/// Build the moonback handler for one route: wrap it in the middleware chain,
/// run it, and write the returned `Response` to the socket.
fn App::adapt(self : App, handler : Handler) -> @moonback.Handler {
  let dispatch = wrap(self.middlewares, handler)
  (req, res) => dispatch(Request(req)).send(res)
}

///|
/// Turn the declared routes and middleware into a moonback `Module`.
///
/// A catch-all GET route is registered last so unmatched paths produce the
/// same JSON 404 shape as everything else, instead of moonback's empty
/// default 404. The trie tries static and `:param` children before `*rest`,
/// so registering it does not shadow real routes.
pub fn App::to_module(self : App) -> @moonback.Module {
  let routes = self.routes
  let app = self
  @moonback.Module(ctx => {
    // A conflicting path is a programming error in the route table, so it must
    // stop start-up rather than be logged and ignored.
    //
    // `fail`, not `raise`: the `Module` closure is typed
    // `async (ModuleContext) -> Unit` with no error type, so a `raise` inside
    // it goes nowhere. That was not obvious -- an earlier version re-raised in
    // a `try/catch` and compiled without complaint, but a probe registering
    // the same path twice showed `to_module` returning normally and the
    // duplicate route being dropped in silence. The compiler's
    // `unused_error_type` warning on this function was the accurate report.
    for route in routes {
      let handler = app.adapt(route.handler)
      ctx.add_route(route.verb, route.path, handler) catch {
        // `RouterError` has one variant and implements neither `Show` nor
        // `Debug`, so the verb and path from our own table carry the message.
        RouteConflict(_) =>
          fail(
            "route conflict on \{@debug.to_string(route.verb)} \{route.path}",
          )
      }
    }
    ctx.get("/*rest", (req, res) => {
      let body : Json = { "error": "not_found", "path": req.path.to_owned() }
      res.send_json(body, status=404)
    })
  })
}
