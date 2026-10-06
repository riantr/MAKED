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

///| A handler takes the request and produces a response.
pub type Handler = async (Request) -> Response

///|
/// Middleware is a *factory*: it receives the next link and returns the
/// wrapped link. `Middleware = (Next -> Next)`, so calling one with a single
/// argument yields the next link, which is what a route handler then invokes.
pub type Middleware = (async (Request) -> Response) ->
  async (Request) -> Response

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
  { routes: [], middlewares: [] }
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
  self.routes.push({ verb, path, handler })
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
  (req, res) => { (dispatch)(Request(req)).send(res) }
}

///|
/// Turn the declared routes and middleware into a moonback `Module`.
///
/// A catch-all GET route is registered last so unmatched paths produce the
/// same JSON 404 shape as everything else, instead of moonback's empty
/// default 404. The trie tries static and `:param` children before `*rest`,
/// so registering it does not shadow real routes.
pub fn App::to_module(self : App) -> @moonback.Module raise {
  let routes = self.routes
  let app = self
  @moonback.Module(ctx => {
    // A conflicting path is a programming error in the route table, so the
    // error propagates out of module initialisation rather than being logged
    // and ignored.
    //
    // `try ... catch { err => raise err }` is used rather than `?` because
    // `?` is an expression form and this is a statement inside a `for` body.
    // The re-raise looks redundant, and the compiler does warn that it could
    // be `errdefer` -- but the warning is about the cleanup idiom, and here
    // the point is simply to let the error escape unchanged.
    for route in routes {
      let handler = app.adapt(route.handler)
      try ctx.add_route(route.verb, route.path, handler) catch {
        err => raise err
      }
    }
    ctx.get(
      "/*rest",
      (req, res) => {
        let body : Json = { "error": "not_found", "path": req.path.to_owned() }
        res.send_json(body, status=404)
      },
    )
  })
}
