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
async fn main {
  // The machine MAKED runs. `MAKED_MODEL` names a model file, and a file
  // that cannot be read whole is refused rather than half-read: a server
  // running a machine nobody can see would answer every request
  // confidently and wrongly, which is the worst thing a server can do.
  let model_path = @maked.model_path_from_env()
  let model_name = match model_path {
    Some(path) =>
      match @maked.read_model_file(path) {
        Some(model) => {
          @maked.install_model(model)
          model.name
        }
        None => {
          println("")
          println("MAKED will not start with a model it could not read.")
          println("  unset MAKED_MODEL to run the built-in model instead")
          return
        }
      }
    None => @maked.current_model().name
  }
  let port = parse_port(env_or("MAKED_PORT", "8080"))
  let host = env_or("MAKED_HOST", "127.0.0.1")
  let db_path = env_or("MAKED_DB", "maked.db")
  let dist = env_or("MAKED_DIST", "frontend/dist")
  if !@fs.exists(dist) {
    println("warning: \{dist} not found; only the API will be served.")
    println("  build it with: moon build --release --target js cmd/web")
  }
  // Say so when the port is not the default: the usual reason someone is staring
  // at a working server that will not answer on localhost:8080 is that this
  // process is somewhere else.
  if port != 8080 {
    println(
      "WARNING: MAKED_PORT is set, so MAKED listens on \{port} instead of 8080.",
    )
    println("  unset MAKED_PORT to go back to the default port")
  }
  // The host matters as much as the port, and in the opposite direction: the
  // default is localhost, so a server that is meant to be reached from
  // outside -- in a container, behind a proxy, on a shared machine -- has to
  // be told so. A published container port cannot reach a server that is
  // listening on 127.0.0.1 inside it, and the symptom is a connection reset
  // with nothing in the logs.
  if host != "127.0.0.1" {
    println(
      "WARNING: MAKED_HOST is \{host}, so MAKED is reachable from other machines.",
    )
    println(
      "  there is no authentication; do not expose it to a network you do not control",
    )
  }
  let app = @maked.create_app(db_path)
  let routes = app.to_module()
  // Order is outermost-first: statics serves a real file, then spa_fallback
  // answers the remaining browser navigations, then the router. Registering
  // spa_fallback last puts it closest to the router, which is what lets it
  // tell an SPA route from an API 404 -- an `/api/` path never reaches it.
  let statics = @maked.static_files(dist)
  let spa = @maked.spa_fallback(dist)
  let root = @moonback.Module(ctx => {
    ctx.use_(routes)
    ctx.add_middleware(statics)
    ctx.add_middleware(spa)
  })
  let server = @moonback.App(root)
  // A failed bind is the one startup error a user cannot self-diagnose from the
  // message alone, so replace it with the two facts that actually decide it:
  // which port, and how to find what is holding it.
  let listener = @moonback.listen(host~, port~) catch {
    _ => {
      println("WARNING: MAKED cannot bind port \{port}.")
      println("")
      println(
        "  Something else already holds that port. On Windows that is often a",
      )
      println(
        "  SYSTEM service rather than a leftover dev server, which is why the",
      )
      println(
        "  OS reports 'access permissions' and not 'address already in use' --",
      )
      println("  so the error text points away from the real cause.")
      println("")
      println("  Find the owner:")
      println(
        "    Get-NetTCPConnection -LocalPort \{port} | Select-Object OwningProcess",
      )
      println("    tasklist /svc /fi \"PID eq <that pid>\"")
      println("")
      println("  Or serve on a different port:")
      println("    $env:MAKED_PORT = '\{port + 1}'")
      return
    }
  }
  println("MAKED listening on http://\{host}:\{port}")
  println("  api:  http://127.0.0.1:\{port}/api/pages")
  println("  data: \{db_path}")
  println("  machine: \{model_name}")
  server.serve(listener)
}
