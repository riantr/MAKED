///| App whitebox tests.
///
/// Whitebox tests can access `pub(all)` items like the `routes` and `middlewares`
/// arrays. These tests verify that route registration works correctly and that
/// the middleware chain is built in the right order.

///|
/// App::new creates an empty app.
test "App::new creates empty routes and middlewares" {
  let app = App::new()
  assert_eq(app.routes.length(), 0)
  assert_eq(app.middlewares.length(), 0)
}

///|
/// App::get registers a GET route.
test "App::get registers a GET route" {
  let app = App::new()
  app.get("/test", _req => Response::text("ok"))
  assert_eq(app.routes.length(), 1)
  assert_eq(app.routes[0].path, "/test")
  assert_true(app.routes[0].verb is @http.Get)
}

///|
/// App::post registers a POST route.
test "App::post registers a POST route" {
  let app = App::new()
  app.post("/submit", _req => Response::text("done"))
  assert_eq(app.routes.length(), 1)
  assert_eq(app.routes[0].path, "/submit")
  assert_true(app.routes[0].verb is @http.Post)
}

///|
/// Multiple routes can be registered.
test "App registers multiple routes in order" {
  let app = App::new()
  app.get("/first", _req => Response::text("1"))
  app.post("/second", _req => Response::text("2"))
  app.get("/third", _req => Response::text("3"))
  assert_eq(app.routes.length(), 3)
  assert_eq(app.routes[0].path, "/first")
  assert_eq(app.routes[1].path, "/second")
  assert_eq(app.routes[2].path, "/third")
}

///|
/// App::add_middleware adds to the middleware chain.
test "App::add_middleware appends middleware" {
  let app = App::new()
  app.add_middleware(next => req => next(req))
  app.add_middleware(next => req => next(req))
  assert_eq(app.middlewares.length(), 2)
}

///|
/// Route struct has the expected fields.
test "Route struct fields are accessible" {
  let route : Route = {
    verb: @http.Get,
    path: "/api/test",
    handler: _req => Response::text("test"),
  }
  assert_eq(route.path, "/api/test")
  assert_true(route.verb is @http.Get)
}
