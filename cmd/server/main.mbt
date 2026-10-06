///| MAKED server entry point.
///
/// Serves the JSON API and the built rabbita frontend from one process, so
/// there is no second web server and no CORS to configure.

///|
fn env_or(name : String, fallback : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if value != "" => value
    _ => fallback
  }
}

///|
fn parse_port(text : String) -> UInt16 {
  let port = @string.parse_int(text) catch { _ => 8080 }
  if port <= 0 || port > 65535 {
    8080
  } else {
    port.to_uint16()
  }
}

///|
async fn main raise {
  let port = parse_port(env_or("MAKED_PORT", "8080"))
  let db_path = env_or("MAKED_DB", "maked.db")
  let dist = env_or("MAKED_DIST", "frontend/dist")
  if !@fs.exists(dist) {
    println("warning: \{dist} not found; only the API will be served.")
    println("  build it with: moon build --release --target js cmd/web")
  }
  let app = @maked.create_app(db_path)
  let routes = app.to_module()
  // Static files are registered after the API so `/api/...` never reaches the
  // filesystem, and the SPA history fallback handles every other deep link.
  let statics = @maked.static_files(dist)
  let root = @moonback.Module(ctx => {
    ctx.use_(routes)
    ctx.add_middleware(statics)
  })
  let server = @moonback.App(root)
  let listener = @moonback.listen(port=port)
  println("MAKED listening on http://127.0.0.1:\{port}")
  println("  api:  http://127.0.0.1:\{port}/api/pages")
  println("  data: \{db_path}")
  server.serve(listener)
}
