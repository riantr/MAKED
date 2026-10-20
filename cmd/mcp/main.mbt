///| MAKED as an MCP server: another agent can drive the loop.
///
/// The web panel is for a person, and a person clicks. An agent does not
/// click and does not read a screen: it calls tools. So MAKED answers the
/// same loop as a set of tools -- where am I, what can I do, do it -- and
/// the payloads are the ones in `backend/agent.mbt`: sentences where a
/// sentence helps, ids where an id is needed.
///
/// Two transports, because there are two ways an agent reaches a tool:
/// stdio, for the agent that spawns the server as a subprocess, and
/// Streamable HTTP, for the agent that connects to one already running.
///
/// **Nothing is printed to stdout.** On the stdio transport stdout *is* the
/// protocol, and a line of prose in the middle of a protocol stream is a
/// line the client cannot parse: the transport dies on it, and the reason
/// MAKED had something to say is lost in the noise. Every diagnostic here
/// goes to stderr.

///|
/// The database the tools work on.
///
/// Held in a one-element array because MoonBit has no mutable module-level
/// binding, and the element is mutable in place. The tools work on the
/// same database the web server uses, so a run of steps is written down
/// where a person can look at it afterwards.
///
/// The array starts with **one** element, not zero: the first thing that
/// happens to it is `g_db[0] = Some(db)`, and writing to index 0 of an
/// empty array is an out-of-bounds write, not a push.
let g_db : Array[@maked.Database?] = [None]

///|
/// The database the tools work on, if it is open.
fn database() -> @maked.Database? {
  g_db[0]
}

///|
/// The database the tools work on, or the reason there is not one.
///
/// A tool that cannot reach the database says so. It does not answer with
/// an empty result, because an empty result read as "the loop is at its
/// first position" is a lie about a server that is not running.
fn database_or_error() -> Result[@maked.Database, @mcp_types.MCPError] {
  match database() {
    Some(db) => Ok(db)
    None =>
      Err(@mcp_types.MCPError::InternalError("MAKED's database is not open."))
  }
}

///|
/// The answer to a tool call: the payload, as text and as structured JSON.
///
/// The text is the JSON, so an agent that reads text content can read it
/// and an agent that reads structured content can use it without parsing
/// it first.
fn result_of(payload : Json) -> @tool.ToolResult {
  @tool.ToolResult::structured(payload, content=[
    @mcp_types.ContentBlock::text(payload.stringify()),
  ])
}

///|
/// A string in the arguments, or the empty string.
///
/// An argument that is not there and an argument that is empty are the same
/// thing to the caller -- "no slot" and "no target" are both "leave it to
/// the table" -- so both come back as the empty string.
fn string_of(args : Json, key : String) -> String {
  match args {
    Object(fields) =>
      match fields.get(key) {
        Some(String(text)) => text
        _ => ""
      }
    _ => ""
  }
}

///|
/// A whole number in the arguments, or the fallback.
fn int_of(args : Json, key : String, fallback : Int32) -> Int32 {
  match args {
    Object(fields) =>
      match fields.get(key) {
        Some(Number(n, ..)) => n.to_int()
        Some(String(text)) => @string.parse_int(text) catch { _ => fallback }
        _ => fallback
      }
    _ => fallback
  }
}

///|
/// The schema of a tool that takes no arguments.
fn no_arguments() -> Json {
  { "type": "object", "properties": {}, "required": [] }
}

///|
/// The schema of the step tool.
fn step_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "slot": {
        "type": "string",
        "description": "The drive slot to step with: the model's own id (\"act\") or the designation the panel shows (\"Action\"). Leave it out and the table chooses.",
      },
      "target": {
        "type": "string",
        "description": "One of the successors the table offered and declined to choose between. Only needed when maked_options says the table declined to choose.",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the options tool.
fn options_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "depth": {
        "type": "integer",
        "description": "How many steps ahead to look when listing what could happen next. Default 3.",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the society tool.
fn society_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "trigger": {
        "type": "string",
        "description": "The move to take, by the machine's own name (\"RaiseClaims\"). Leave it out to look without moving.",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the export tool.
fn export_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "session_id": {
        "type": "integer",
        "description": "Which exploration to export. Leave it out for the one in front of us.",
      },
      "format": {
        "type": "string",
        "description": "markdown or json. Default markdown, which is the reading form.",
      },
    },
    "required": [],
  }
}

///|
/// Where the loop stands, and what the last move did.
async fn status_tool(
  _context : @runtime.RequestContext,
  _args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  let db = match database_or_error() {
    Ok(db) => db
    Err(err) => return Err(err)
  }
  let payload = @maked.agent_status(db) catch {
    err =>
      return Err(
        @mcp_types.MCPError::InternalError(
          "the loop could not be read: " + @debug.to_string(err),
        ),
      )
  }
  Ok(result_of(payload))
}

///|
/// What can be done from here, and what cannot.
async fn options_tool(
  _context : @runtime.RequestContext,
  args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  let depth = int_of(args, "depth", 3)
  let bounded = if depth <= 0 || depth > 8 { 3 } else { depth }
  Ok(result_of(@maked.agent_options(bounded)))
}

///|
/// Take a move.
///
/// With no slot the table chooses; with a slot the caller chooses; with a
/// target the caller answers a question the table asked.
async fn step_tool(
  _context : @runtime.RequestContext,
  args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  let db = match database_or_error() {
    Ok(db) => db
    Err(err) => return Err(err)
  }
  let slot = string_of(args, "slot")
  let target = string_of(args, "target")
  if slot == "" {
    let _ = @maked.take_drive_step(db) catch {
      err =>
        return Err(
          @mcp_types.MCPError::InternalError(
            "the step could not be taken: " + @debug.to_string(err),
          ),
        )
    }
  } else {
    let answer = @maked.take_slot_step(db, slot, target) catch {
      err =>
        return Err(
          @mcp_types.MCPError::InternalError(
            "the step could not be taken: " + @debug.to_string(err),
          ),
        )
    }
    match answer {
      @maked.Taken(_) => ()
      @maked.UnknownSlot(name) =>
        return Err(
          @mcp_types.MCPError::InvalidParams(
            "there is no drive slot called \"" +
            name +
            "\". Call maked_options to see the slots there are.",
          ),
        )
      @maked.UnknownTarget(asked, targets) =>
        return Err(
          @mcp_types.MCPError::InvalidParams(
            "there is no successor called \"" +
            asked +
            "\" here. The table offers: " +
            targets.join(", ") +
            ".",
          ),
        )
    }
  }
  let payload = @maked.agent_step_result(db) catch {
    err =>
      return Err(
        @mcp_types.MCPError::InternalError(
          "the step could not be read back: " + @debug.to_string(err),
        ),
      )
  }
  Ok(result_of(payload))
}

///|
/// The machine itself, as data.
async fn model_tool(
  _context : @runtime.RequestContext,
  _args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  Ok(result_of(@maked.agent_model()))
}

///|
/// The collective: where it stands, and what it can do from there.
///
/// With a trigger it moves. The collective has no drive slots, so there is
/// nothing for the machine to choose for it.
async fn society_tool(
  _context : @runtime.RequestContext,
  args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  let trigger = string_of(args, "trigger")
  if trigger == "" {
    Ok(result_of(@maked.agent_society()))
  } else {
    Ok(result_of(@maked.agent_society_step(trigger)))
  }
}

///|
/// The named explorations.
async fn sessions_tool(
  _context : @runtime.RequestContext,
  _args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  let db = match database_or_error() {
    Ok(db) => db
    Err(err) => return Err(err)
  }
  let payload = @maked.agent_sessions(db) catch {
    err =>
      return Err(
        @mcp_types.MCPError::InternalError(
          "the explorations could not be read: " + @debug.to_string(err),
        ),
      )
  }
  Ok(result_of(payload))
}

///|
/// One exploration, as something to take away.
async fn export_tool(
  _context : @runtime.RequestContext,
  args : Json,
) -> Result[@tool.ToolResult, @mcp_types.MCPError] {
  let db = match database_or_error() {
    Ok(db) => db
    Err(err) => return Err(err)
  }
  let asked = int_of(args, "session_id", 0)
  let id = if asked <= 0 {
    @maked.active_session_id()
  } else {
    asked.to_int64()
  }
  let format = string_of(args, "format")
  let wanted = if format == "" { "markdown" } else { format }
  let payload = @maked.agent_export(db, id, wanted) catch {
    err =>
      return Err(
        @mcp_types.MCPError::InternalError(
          "the exploration could not be exported: " + @debug.to_string(err),
        ),
      )
  }
  Ok(result_of(payload))
}

///|
/// A message with a method and no id is a notification.
///
/// JSON-RPC says a notification is never answered. Answering one anyway
/// puts a message on stdout that no client asked for, and a client that
/// reads stdout strictly will treat it as a protocol error -- so the
/// "initialized" handshake some clients send does not come back as a
/// response.
fn is_notification(message : String) -> Bool {
  let json = @json.parse(message) catch { _ => return false }
  match json {
    Object(fields) =>
      match (fields.get("id"), fields.get("method")) {
        (None, Some(_)) => true
        _ => false
      }
    _ => false
  }
}

///|
/// The message, without the byte order marks some clients put in front of it.
///
/// A Windows client that writes stdin through .NET starts its first line
/// with a UTF-8 BOM. A BOM in front of a JSON-RPC message is not JSON, so
/// the first request is answered with a parse error while every later one
/// is answered properly -- which reads like a server that only understands
/// the second question, and it is the client's first question that is lost.
///
/// The mark is a byte-order mark, not content, so it is dropped -- and every
/// mark in front of it is dropped, because how many there are is the
/// client's business and not the server's.
fn strip_bom(text : String) -> String {
  let mut trimmed = text.trim().to_owned()
  while trimmed.has_prefix("\u{FEFF}") {
    trimmed = trimmed[1:].to_owned()
  }
  trimmed
}

///|
/// The answer to one line of input, or nothing at all.
///
/// Nothing for a blank line, and nothing for a notification. A line that is
/// not a message at all is the SDK's business: it answers with a parse
/// error, which is more use to the client than silence.
async fn answer_line(server : @mcp.MCPServer, message : String) -> String? {
  if message.is_empty() {
    return None
  }
  if is_notification(message) {
    return None
  }
  let response = server.handle_request(message) catch {
    e => {
      eprintln("MAKED could not answer a request: \{@debug.to_string(e)}")
      return None
    }
  }
  if response.is_empty() {
    None
  } else {
    Some(response)
  }
}

///|
/// Write one answer and flush it.
///
/// The flush matters: the client is waiting for this answer before it sends
/// the next question, and a buffered answer that has not left the process
/// looks like a server that has stopped answering.
async fn write_line(
  writer : @io.BufferedWriter[@stdio.Output],
  text : String,
) -> Bool {
  writer.write(text) catch {
    e => {
      eprintln("MAKED stopped writing: \{@debug.to_string(e)}")
      return false
    }
  }
  writer.write("\n") catch {
    e => {
      eprintln("MAKED stopped writing: \{@debug.to_string(e)}")
      return false
    }
  }
  writer.flush() catch {
    e => {
      eprintln("MAKED stopped writing: \{@debug.to_string(e)}")
      return false
    }
  }
  true
}

///|
/// Serve the protocol over stdin and stdout.
///
/// MAKED reads the lines itself rather than handing the process to the SDK's
/// stdio transport, because that transport loses the client's first message
/// to a byte order mark and the client's last answers to a closed pipe.
/// The first is described in `strip_bom`; the second is this: when stdin
/// reaches EOF the SDK closes the transport, and the answers still queued
/// behind it are dropped. A client that writes a file of requests and
/// closes the pipe is in a race it does not know it is in.
async fn serve_stdio(server : @mcp.MCPServer) -> Unit {
  let input = @stdio.stdin
  let writer = @io.BufferedWriter::new(@stdio.stdout, size=8192)
  let mut running = true
  while running {
    let line = input.read_until("\n") catch {
      e => {
        eprintln("MAKED stopped reading: \{@debug.to_string(e)}")
        None
      }
    }
    match line {
      None => running = false
      Some(raw) => {
        let message = strip_bom(raw)
        let answer = answer_line(server, message)
        match answer {
          Some(text) => if !write_line(writer, text) { running = false }
          None => ()
        }
      }
    }
  }
}

///|
/// The server, with its tools.
fn build_server() -> @mcp.MCPServer raise @mcp_types.MCPError {
  @mcp.MCPServer::MCPServer("maked", @maked.MAKED_VERSION)
  .with_title("MAKED")
  .with_description(
    "MAKED: the adversarial knowledge loop. Three layers -- the subject (a ring of five domains), the group, and the collective. The tools here read and move the subject loop and the collective.",
  )
  .with_instructions(
    "Start with maked_status to see where the loop stands and what the last move did. Call maked_options to see what the table offers from here -- it lists the slots that can move and the ones that cannot, and says why. Then call maked_step with one of those slots. If the table declined to choose between several successors, pass one of them as the target. Every answer says in words what happened; the ids are there when you want to be exact.",
  )
  .tool(
    "maked_status",
    "Where the loop stands: the domain and position, what the last move did in words, what the run adds up to, and whether it is still finding ground.",
    no_arguments(),
    status_tool,
  )
  .tool(
    "maked_options",
    "What can be done from here and what cannot. The slots that can move, the slots that cannot and why, the successors the table declined to choose between, and what the machine says could happen next.",
    options_schema(),
    options_tool,
  )
  .tool(
    "maked_step",
    "Take a move. With no slot the table chooses; with a slot the caller chooses; with a target the caller answers a question the table asked. Answers with what happened, in words.",
    step_schema(),
    step_tool,
  )
  .tool(
    "maked_model",
    "The machine itself as data: the domains, the positions, the slots, and the rule for every pair of them.",
    no_arguments(),
    model_tool,
  )
  .tool(
    "maked_society",
    "The collective. With no trigger it says where the collective stands and what it can do from there; with a trigger it takes that move.",
    society_schema(),
    society_tool,
  )
  .tool(
    "maked_sessions",
    "The named explorations, and which one is in front of us.",
    no_arguments(),
    sessions_tool,
  )
  .tool(
    "maked_export",
    "One exploration as something to take away: markdown to read, json to process.",
    export_schema(),
    export_tool,
  )
}

///|
/// A port from the environment, or 0 when it is not a port.
fn parse_port(text : String) -> Int32 {
  let port = @string.parse_int(text) catch { _ => 0 }
  if port <= 0 || port > 65535 {
    0
  } else {
    port
  }
}

///|
fn env_or(name : String, fallback : String) -> String {
  match @env.get_env_var(name) {
    Some(value) if value != "" => value
    _ => fallback
  }
}

///|
async fn main {
  // The machine MAKED runs, the table that says what a document means, the
  // words for the collective and the corpus. The rules are in
  // `bootstrap.mbt`, because the web server starts the same way.
  if !@maked.install_from_environment() {
    return
  }
  let db_path = env_or("MAKED_DB", "maked.db")
  let db = @maked.prepare_database(db_path) catch {
    err => {
      eprintln(
        "MAKED could not open the database at \{db_path}: \{@debug.to_string(err)}",
      )
      return
    }
  }
  g_db[0] = Some(db)
  let server = build_server() catch {
    err => {
      eprintln("MAKED could not register its tools: \{@debug.to_string(err)}")
      return
    }
  }
  // Two transports, and the choice is the operator's: an agent that spawns
  // the server speaks to it over stdio, and an agent that connects to one
  // already running speaks to it over HTTP.
  let port = parse_port(env_or("MAKED_MCP_PORT", ""))
  if port > 0 {
    eprintln(
      "MAKED is serving the Model Context Protocol on http://127.0.0.1:\{port}/mcp",
    )
    server.run_http(port~, path="/mcp") catch {
      err => eprintln("MAKED stopped serving: \{@debug.to_string(err)}")
    }
  } else {
    serve_stdio(server)
  }
}
