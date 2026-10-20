///|
/// The discovery document: what an agent is told about MAKED.
///
/// The Model Context Protocol has its own discovery document, and the
/// document at `GET /api/agent` is the same information for an agent that
/// would rather use plain HTTP -- or that has never heard of the
/// protocol. It has to be complete on its own: an agent that reads it and
/// nothing else has to be able to drive the loop.
///
/// Two things could make it wrong without anything failing. It could offer
/// tools the agent's server does not have, and it could name endpoints the
/// server does not serve. The first is checked here, against the same
/// list the server registers from; the second is checked by the
/// integration suite, which asks the running server.

///|
/// The seven tools MAKED offers, by name.
fn the_seven() -> Array[String] {
  [
    "maked_status", "maked_options", "maked_step", "maked_model", "maked_society",
    "maked_sessions", "maked_export",
  ]
}

///|
/// The discovery document says what it is and which version it is.
test "the discovery document says what it is and which version it is" {
  let document = @backend.agent_discovery()
  assert_eq(json_str(document, "format"), "maked.agent.v1")
  assert_eq(json_str(document, "name"), "MAKED")
  assert_eq(json_str(document, "version"), @backend.MAKED_VERSION)
  // A summary an agent can read in one go: a document that says nothing is
  // a document the agent has to guess from.
  assert_true(json_str(document, "summary").length() > 40)
}

///|
/// The discovery document offers the seven tools, each with a description
/// and an argument schema.
///
/// A tool with no description is a name, and a name is not enough for an
/// agent to decide whether to call it.
test "the discovery document offers the seven tools with a description each" {
  let document = @backend.agent_discovery()
  let tools = json_array(document, "tools")
  assert_eq(tools.length(), 7)
  for tool in tools {
    let name = json_str(tool, "name")
    assert_true(name.has_prefix("maked_"))
    assert_true(json_str(tool, "description").length() > 20)
    // The schema is there, and it is an object schema: an agent that
    // passes the wrong arguments deserves an answer that says so.
    let schema = match json_field(tool, "inputSchema") {
      Some(value) => value
      None => fail("the tool " + name + " carries no argument schema")
    }
    assert_eq(json_str(schema, "type"), "object")
  }
}

///|
/// The tools in the discovery document are the tools MAKED has.
///
/// The names are compared as a set, so a tool offered under two names and
/// a tool missing under one are both caught.
test "the tools in the discovery document are the tools MAKED has" {
  let document = @backend.agent_discovery()
  let offered = json_array(document, "tools")
  let wanted = the_seven()
  assert_eq(offered.length(), wanted.length())
  for name in wanted {
    let mut found = false
    for tool in offered {
      if json_str(tool, "name") == name {
        found = true
      }
    }
    if !found {
      fail("the discovery document does not offer the tool " + name)
    }
  }
}

///|
/// No tool is offered twice.
///
/// Two tools with the same name are two tools an agent cannot tell apart,
/// and the second one silently wins.
test "no tool is offered twice" {
  let specs = @backend.agent_tool_specs()
  for spec in specs {
    let mut seen = 0
    for other in specs {
      if other.name == spec.name {
        seen += 1
      }
    }
    if seen != 1 {
      fail("the tool " + spec.name + " is offered more than once")
    }
  }
}

///|
/// The discovery document says which protocol version it speaks, and that
/// there is no handshake.
///
/// An agent that waits for a handshake that will never come reads a
/// silent server as a broken one.
test "the discovery document says which protocol version it speaks" {
  let document = @backend.agent_discovery()
  let protocol = match json_field(document, "protocol") {
    Some(value) => value
    None => fail("the discovery document says nothing about the protocol")
  }
  assert_eq(json_str(protocol, "mcp"), "2026-07-28")
  assert_eq(json_str(protocol, "entry_point"), "server/discover")
  assert_true(json_str(protocol, "note").contains("no handshake"))
}

///|
/// The instructions are the same ones the agent's server sends.
///
/// An agent that speaks the protocol and an agent that only reads the
/// document are told the same thing, or one of them is told something
/// false.
test "the instructions are the same ones the agent's server sends" {
  let document = @backend.agent_discovery()
  assert_eq(json_str(document, "instructions"), @backend.agent_instructions())
  assert_true(json_str(document, "instructions").contains("maked_status"))
  assert_true(json_str(document, "instructions").contains("maked_options"))
  assert_true(json_str(document, "instructions").contains("maked_step"))
}

///|
/// The discovery document lists the plain HTTP endpoints and the files.
///
/// The endpoints are for an agent that does not speak the protocol, and
/// the files are for an agent that wants MAKED to run on its own machine,
/// table or documents.
test "the discovery document lists the endpoints and the files" {
  let document = @backend.agent_discovery()
  let endpoints = json_array(document, "http")
  assert_true(endpoints.length() >= 9)
  for endpoint in endpoints {
    assert_true(json_str(endpoint, "method") != "")
    assert_true(json_str(endpoint, "path").has_prefix("/api/"))
    // Every endpoint says which tool it stands in for, so an agent can
    // read one list and know the other.
    assert_true(json_str(endpoint, "tool").has_prefix("maked_"))
  }
  let files = json_array(document, "files")
  assert_eq(files.length(), 4)
  for file in files {
    assert_true(json_str(file, "variable").has_prefix("MAKED_"))
    assert_true(json_str(file, "format").has_prefix("maked."))
    assert_true(json_str(file, "says") != "")
  }
}
