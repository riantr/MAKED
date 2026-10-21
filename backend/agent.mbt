///| The agent's view of the loop: what happened, and what it means.
///
/// A person reads the loop panel. An agent reads this. The difference is
/// what each of them needs first: a person wants the position and a button
/// to press, and an agent wants to know what the last move did in words it
/// can reason about, and what it may do next.
///
/// The raw loop status is not that. It is a map of ids -- "M", "Action",
/// "Undecided" -- and an agent that has to reconstruct the meaning from the
/// ids is an agent that guesses. So the sentences are written here, on the
/// server, where the model and the history both are, and the ids travel
/// beside the sentences for the agent that wants to be exact.
///
/// Nothing here is a second source of truth: every sentence is built from
/// the same model, the same transition table and the same recorded steps the
/// panel is built from.

///|
/// A list of strings, as a JSON array of strings.
///
/// The backend's other string lists are arrays of one-element arrays, which
/// is the shape the browser's decoder expects. An agent reads JSON, not the
/// browser, and an array of one-element arrays is a shape it has to know
/// about before it can read the list at all.
fn agent_strings(names : Array[String]) -> Json {
  let items : Array[Json] = []
  for name in names {
    items.push(Json::string(name))
  }
  Json::array(items)
}

///|
/// The steps on the active session's current path, oldest first.
///
/// The path is the run of steps that leads to where the loop stands now, as
/// opposed to the steps that were walked and then walked back from.
fn active_path(db : Database) -> Array[SessionStep] raise {
  let session = match db.session_by_id(active_session_id()) {
    Some(s) => s
    None => return []
  }
  chain_to_step(db.steps_of_session(session.id), session.head_step_id)
}

///|
/// The last step of the active path, if there is one.
fn last_step(path : Array[SessionStep]) -> SessionStep? {
  if path.length() == 0 {
    return None
  }
  Some(path[path.length() - 1])
}

///|
/// Where the loop stands: the domain, the position, the mode, the group and
/// the collective.
///
/// The ids travel beside the words, because an agent that wants to be exact
/// needs the model's own names and not only the ones the reader sees.
pub fn agent_where(lang : Lang) -> Json {
  let state = get_loop_state()
  let model = state.model
  let domain = state.current
  let position = state.domain_state(domain).position
  let vocabulary = current_society_vocabulary()
  let society_id = society_position_id(state.society_state)
  {
    "domain": domain.letter(),
    "domain_name": domain.title_in(lang),
    "the_domain_in_words": role_of_in(model, domain.letter(), lang),
    "position": position,
    "position_label": model.position_label_in(position, lang),
    "position_gloss": model.position_gloss_in(position, lang),
    "mode": state.mode.designation_in(lang),
    "the_group": group_state_in(state.group_state.en_designation(), lang),
    "the_group_gloss": group_gloss_in(state.group_state.en_gloss(), lang),
    "the_collective": society_position_label(vocabulary, society_id, lang),
    "the_collective_position": society_id,
  }
}

///|
/// The state of the loop, as an agent should read it.
pub fn agent_status(db : Database, lang : Lang) -> Json raise {
  let model = current_model()
  let path = active_path(db)
  let last_move = match last_step(path) {
    Some(step) => step_sentence(facts_of(model, step), lang)
    None =>
      match lang {
        English =>
          "No step has been taken yet. The loop is standing where it starts."
        Chinese =>
          "还没有走过任何一步。循环停在它出发的地方。"
      }
  }
  {
    "where": agent_where(lang),
    "the_last_move": last_move,
    "the_run_so_far": summary_of(path, lang),
    "steps_taken": path.length(),
    "the_measures": measure(path, lang).to_json(),
    "note": match lang {
      English =>
        "Call maked_options to see what the table offers from here, and maked_step to take one of them."
      Chinese =>
        "调用 maked_options 看这里表格提供了什么，再用 maked_step 走其中一步。"
    },
  }
}

///|
/// What can be done from here, and what cannot.
///
/// The two lists are the same length as the model's slot vocabulary, and
/// together they are all of it. A slot that cannot move says why, because a
/// slot that is merely absent reads as a slot nobody has heard of.
pub fn agent_options(depth : Int32, lang : Lang) -> Json {
  let state = get_loop_state()
  let model = state.model
  let position = state.domain_state(state.current).position
  let can_move : Array[Json] = []
  let cannot_move : Array[Json] = []
  let declined : Array[Json] = []
  for (name, designation, gloss) in all_slots_info(lang) {
    let transition = model.step(position, name)
    let kind = transition.kind()
    if kind == "block" {
      cannot_move.push({
        "slot": name,
        "slot_name": designation,
        "what_the_slot_is": gloss,
        "why": match lang {
          English =>
            "There is no \"" +
            designation +
            "\" out of " +
            model.position_label_in(position, lang) +
            "."
          Chinese =>
            "从" +
            model.position_label_in(position, lang) +
            "出发，没有可以走的“" +
            designation +
            "”。"
        },
      })
    } else {
      let lands : Array[String] = []
      match transition {
        Moved(_, to) => lands.push(model.position_label_in(to, lang))
        Held(_, to) => lands.push(model.position_label_in(to, lang))
        Same(_, to) => lands.push(model.position_label_in(to, lang))
        Open(candidates) =>
          for candidate in candidates {
            lands.push(model.position_label_in(candidate.to, lang))
          }
        Block(_) => ()
      }
      can_move.push({
        "slot": name,
        "slot_name": designation,
        "what_the_slot_is": gloss,
        "outcome": model.outcome_label_in(kind, lang),
        "outcome_kind": kind,
        "lands_at": agent_strings(lands),
      })
      if kind == "open" {
        declined.push({
          "slot": name,
          "slot_name": designation,
          "the_candidates": agent_strings(lands),
          "note": match lang {
            English =>
              "The table offers several successors here and will not choose between them. Pass one of them to maked_step as the target."
            Chinese =>
              "这里的表格给出了好几个后继，不肯在其中挑选。把其中一个作为 target 传给 maked_step。"
          },
        })
      }
    }
  }
  let ahead : Array[Json] = []
  for (next, steps) in continuations(position, depth) {
    ahead.push({
      "position": next,
      "position_label": model.position_label_in(next, lang),
      "steps_away": steps,
    })
  }
  {
    "can_move": can_move,
    "cannot_move": cannot_move,
    "the_table_declined_to_choose": declined,
    "the_machine_says_could_happen_next": ahead,
    "note": match lang {
      English =>
        "The machine does not choose for you. Take one of the moves that can_move names, with maked_step."
      Chinese =>
        "机器不替你选择。用 maked_step 走 can_move 中列出的某一步。"
    },
  }
}

///|
/// What a step did, in words.
///
/// The step itself is taken in `step.mbt`; this says what it came to.
pub fn agent_step_result(db : Database, lang : Lang) -> Json raise {
  let model = current_model()
  let path = active_path(db)
  let what_happened = match last_step(path) {
    Some(step) => step_sentence(facts_of(model, step), lang)
    None =>
      match lang {
        English => "The step did not land anywhere the history can describe."
        Chinese =>
          "这一步没有落在历史能够描述的任何一个地方。"
      }
  }
  {
    "what_happened": what_happened,
    "where_now": agent_where(lang),
    "the_run_so_far": summary_of(path, lang),
    "steps_taken": path.length(),
    "the_measures": measure(path, lang).to_json(),
  }
}

///|
/// The machine itself, as data: the domains, the positions, the slots and
/// the rule for every pair of them.
pub fn agent_model() -> Json {
  current_model().to_json()
}

///|
/// The collective, as the agent sees it.
pub fn agent_society(lang : Lang) -> Json {
  let vocabulary = current_society_vocabulary()
  let state = get_loop_state()
  let id = society_position_id(state.society_state)
  let moves : Array[Json] = []
  for edge in society_moves(state.society_state) {
    moves.push({
      "trigger": edge.trigger,
      "the_move": society_trigger_label(vocabulary, edge.trigger, lang),
      "lands_at": society_position_label(vocabulary, edge.to, lang),
    })
  }
  {
    "the_collective": society_position_label(vocabulary, id, lang),
    "the_collective_position": id,
    "what_it_can_do_from_here": moves,
    "note": "The collective has no drive slots. It answers with the same four shapes the subject machine does: moved, held, open, block.",
  }
}

///|
/// Move the collective, and say what came of it.
///
/// The collective has no slots, so there is nothing for the machine to choose
/// for it: the caller names the move and the machine answers. A move that
/// does not exist is refused with the reason, in the same words the panel
/// uses.
pub fn agent_society_step(trigger : String, lang : Lang) -> Json {
  let vocabulary = current_society_vocabulary()
  let before = get_loop_state()
  let from = society_position_id(before.society_state)
  let step = society_step(vocabulary, before.society_state, trigger, lang)
  let what_happened = match step {
    Advanced(_, to) => {
      let landing = society_position_from_id(to)
      match landing {
        Some(state) => {
          set_loop_state(before.with_society_state(state))
          let was = society_position_label(vocabulary, from, lang)
          let now = society_position_label(vocabulary, to, lang)
          match lang {
            English => "The collective moved from " + was + " to " + now + "."
            Chinese => "集体从" + was + "移到了" + now + "。"
          }
        }
        None =>
          match lang {
            English =>
              "The collective did not move: the machine named a place that is not one of its positions."
            Chinese =>
              "集体没有移动：机器给出了一个不属于它的位置。"
          }
      }
    }
    Kept(_, place) => {
      let where_ = society_position_label(vocabulary, place, lang)
      match lang {
        English =>
          "The collective stayed where it was: " +
          where_ +
          " is where that move leads."
        Chinese =>
          "集体停在原地：" +
          where_ +
          " 正是那一步通往的地方。"
      }
    }
    Undecided(_, places) => {
      let names : Array[String] = []
      for place in places {
        names.push(society_position_label(vocabulary, place, lang))
      }
      match lang {
        English =>
          "That move leaves the collective more than one place to be: " +
          names.join(", ") +
          "."
        Chinese =>
          "那一步让集体同时身处不止一处：" +
          names.join("、") +
          "。"
      }
    }
    Refused(_, reason) => reason
  }
  { "what_happened": what_happened, "the_collective": agent_society(lang) }
}

///|
/// The named explorations, and which one is in front of us.
pub fn agent_sessions(db : Database, lang : Lang) -> Json raise {
  let active = active_session_id()
  let items : Array[Json] = []
  for session in db.all_sessions() {
    items.push({
      "id": session.id,
      "name": session.name,
      "steps": db.steps_of_session(session.id).length(),
      "is_the_active_one": session.id == active,
    })
  }
  {
    "the_active_one": active,
    "the_explorations": items,
    "note": match lang {
      English =>
        "An exploration is a named run of steps. maked_export takes one away as Markdown or JSON."
      Chinese =>
        "一次探索就是一串有名字的步。maked_export 可以把它作为 Markdown 或 JSON 带走。"
    },
  }
}

///|
/// One exploration, as something to take away.
///
/// Markdown is the reading form and JSON is the machine form, and both are
/// the same run of steps. The Markdown opens with the run so far and carries
/// the measures, so an exploration is worth reading on its own.
pub fn agent_export(
  db : Database,
  session_id : Int64,
  format : String,
  lang : Lang,
) -> Json raise {
  let session = match db.session_by_id(session_id) {
    Some(s) => s
    None =>
      return {
        "error": "there is no exploration with that id",
        "id": session_id,
      }
  }
  if format == "json" {
    { "format": "json", "the_exploration": export_json(db, session, lang) }
  } else {
    {
      "format": "markdown",
      "the_exploration": Json::string(export_markdown(db, session, lang)),
    }
  }
}

///|
/// The schema of a tool that takes no arguments.
fn agent_no_arguments() -> Json {
  { "type": "object", "properties": {}, "required": [] }
}

///|
/// The schema of a tool that answers in a chosen language.
///
/// The language is an argument rather than a server setting because the
/// caller is the one that knows: an agent reasoning in Chinese wants the
/// model's own words in Chinese, and the same agent on another run may want
/// them in English. Leaving the argument out means English, so a caller that
/// has not heard of the argument still gets a usable answer.
fn agent_lang_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "lang": {
        "type": "string",
        "description": "The language to answer in: \"en\" or \"zh\". Default \"en\".",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the step tool.
fn agent_step_schema() -> Json {
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
      "lang": {
        "type": "string",
        "description": "The language to answer in: \"en\" or \"zh\". Default \"en\".",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the options tool.
fn agent_options_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "depth": {
        "type": "integer",
        "description": "How many steps ahead to look when listing what could happen next. Default 3.",
      },
      "lang": {
        "type": "string",
        "description": "The language to answer in: \"en\" or \"zh\". Default \"en\".",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the society tool.
fn agent_society_schema() -> Json {
  {
    "type": "object",
    "properties": {
      "trigger": {
        "type": "string",
        "description": "The move to take, by the machine's own name (\"RaiseClaims\"). Leave it out to look without moving.",
      },
      "lang": {
        "type": "string",
        "description": "The language to answer in: \"en\" or \"zh\". Default \"en\".",
      },
    },
    "required": [],
  }
}

///|
/// The schema of the export tool.
fn agent_export_schema() -> Json {
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
      "lang": {
        "type": "string",
        "description": "The language to answer in: \"en\" or \"zh\". Default \"en\".",
      },
    },
    "required": [],
  }
}

///|
/// One tool, as the agent's server offers it.
///
/// A type rather than a piece of JSON, so that the agent's server can read
/// the name, the description and the argument schema without parsing
/// anything: the two surfaces that offer these tools are in different
/// packages, and a field access is a thing that cannot be got wrong in
/// two places at once.
pub struct AgentTool {
  name : String
  description : String
  arguments : Json
}

///|
/// The seven tools MAKED offers an agent.
///
/// The names, the descriptions and the argument schemas live here, in the
/// backend, rather than in the agent's server, because two surfaces offer
/// them: the Model Context Protocol server and the discovery document at
/// `GET /api/agent`. Two lists of tools are two lists of tools, and the
/// one that drifts is the one nobody is looking at.
///
/// The handlers are not here -- they need the database, and the database is
/// the agent's server's business -- but the *names* are, and the server
/// matches on them, so a tool that is offered without a handler is a tool
/// the server does not have.
pub fn agent_tool_specs() -> Array[AgentTool] {
  [
    {
      name: "maked_status",
      description: "Where the loop stands: the domain and position, what the last move did in words, what the run adds up to, and whether it is still finding ground.",
      arguments: agent_lang_schema(),
    },
    {
      name: "maked_options",
      description: "What can be done from here and what cannot. The slots that can move, the slots that cannot and why, the successors the table declined to choose between, and what the machine says could happen next.",
      arguments: agent_options_schema(),
    },
    {
      name: "maked_step",
      description: "Take a move. With no slot the table chooses; with a slot the caller chooses; with a target the caller answers a question the table asked. Answers with what happened, in words.",
      arguments: agent_step_schema(),
    },
    {
      name: "maked_model",
      description: "The machine itself as data: the domains, the positions, the slots, and the rule for every pair of them.",
      arguments: agent_no_arguments(),
    },
    {
      name: "maked_society",
      description: "The collective. With no trigger it says where the collective stands and what it can do from there; with a trigger it takes that move.",
      arguments: agent_society_schema(),
    },
    {
      name: "maked_sessions",
      description: "The named explorations, and which one is in front of us.",
      arguments: agent_lang_schema(),
    },
    {
      name: "maked_export",
      description: "One exploration as something to take away: markdown to read, json to process.",
      arguments: agent_export_schema(),
    },
  ]
}

///|
/// The tools, as the discovery document carries them.
///
/// The shape is the Model Context Protocol's: `name`, `description` and
/// `inputSchema`, the three fields a `tools/list` answer carries, so an
/// agent that has read one reads the other.
fn agent_tools_as_json() -> Array[Json] {
  let items : Array[Json] = []
  for tool in agent_tool_specs() {
    items.push({
      "name": tool.name,
      "description": tool.description,
      "inputSchema": tool.arguments,
    })
  }
  items
}

///|
/// What an agent should do first, and what the tools are for.
///
/// The same words the agent's server sends as its instructions, so an agent
/// that speaks the Model Context Protocol and an agent that only reads the
/// discovery document are told the same thing.
pub fn agent_instructions() -> String {
  "Start with maked_status to see where the loop stands and what the last move did. Call maked_options to see what the table offers from here -- it lists the slots that can move and the ones that cannot, and says why. Then call maked_step with one of those slots. If the table declined to choose between several successors, pass one of them as the target. Every answer says in words what happened; the ids are there when you want to be exact."
}

///|
/// The HTTP endpoints an agent can use instead of the tools.
///
/// The tools are the agent's way in; these are the same questions asked over
/// plain HTTP, for an agent that does not speak the Model Context Protocol.
fn agent_http_endpoints() -> Array[Json] {
  [
    {
      "method": "GET",
      "path": "/api/loop/status",
      "tool": "maked_status",
      "what": "where the loop stands",
    },
    {
      "method": "GET",
      "path": "/api/loop/continuations",
      "tool": "maked_options",
      "what": "what the machine says could happen next",
    },
    {
      "method": "POST",
      "path": "/api/loop/step",
      "tool": "maked_step",
      "what": "take a move and let the table choose",
    },
    {
      "method": "POST",
      "path": "/api/loop/step/:slot",
      "tool": "maked_step",
      "what": "take a move with a named slot",
    },
    {
      "method": "GET",
      "path": "/api/model",
      "tool": "maked_model",
      "what": "the machine as data",
    },
    {
      "method": "GET",
      "path": "/api/society",
      "tool": "maked_society",
      "what": "where the collective stands",
    },
    {
      "method": "POST",
      "path": "/api/society/step",
      "tool": "maked_society",
      "what": "take a move for the collective",
    },
    {
      "method": "GET",
      "path": "/api/sessions",
      "tool": "maked_sessions",
      "what": "the named explorations",
    },
    {
      "method": "GET",
      "path": "/api/sessions/:id/export",
      "tool": "maked_export",
      "what": "one exploration as markdown or json",
    },
  ]
}

///|
/// The files MAKED runs on, and the environment variables that name them.
///
/// An agent that wants MAKED to run on its own machine, its own table or
/// its own documents needs to know that these are files and what they are
/// called.
fn agent_files() -> Array[Json] {
  [
    {
      "what": "the machine",
      "variable": "MAKED_MODEL",
      "format": "maked.model.v1",
      "says": "the domains, positions, slots and rules the loop runs on",
    },
    {
      "what": "the mapping table",
      "variable": "MAKED_RESEARCH",
      "format": "maked.research.v1",
      "says": "what a document means: which words make a rule fire, and which slot it drives",
    },
    {
      "what": "the society vocabulary",
      "variable": "MAKED_SOCIETY",
      "format": "maked.society.v1",
      "says": "the English words for the collective's positions and moves",
    },
    {
      "what": "the corpus",
      "variable": "MAKED_CORPUS",
      "format": "maked.corpus.v1",
      "says": "where the documents come from: arxiv, a feed, or your own folder",
    },
  ]
}

///|
/// The discovery document: everything an agent needs to drive MAKED
/// without speaking the Model Context Protocol.
///
/// The Model Context Protocol has its own discovery document, and this is
/// the same information for an agent that would rather use plain HTTP --
/// or that has never heard of the protocol at all.
pub fn agent_discovery() -> Json {
  {
    "format": "maked.agent.v1",
    "name": "MAKED",
    "version": MAKED_VERSION,
    "summary": "MAKED is an adversarial knowledge loop. Five domains in a ring -- Model, Data, Experience, Attack, Knowledge -- each the overcoming of the one before it. Which slot can push a position is answered by the transition table, never by a hard-coded guess, and a position the table cannot move is reported as blocked rather than silently skipped.",
    "protocol": {
      "mcp": "2026-07-28",
      "entry_point": "server/discover",
      "note": "There is no handshake in this version of the protocol: `initialize` is not a method. Every request carries its own version in `params._meta`, under `io.modelcontextprotocol/protocolVersion`, together with `io.modelcontextprotocol/clientCapabilities`. Over HTTP the request also needs the `MCP-Protocol-Version` header and an `Mcp-Method` header naming the method the body carries.",
    },
    "instructions": agent_instructions(),
    "tools": Json::array(agent_tools_as_json()),
    "http": Json::array(agent_http_endpoints()),
    "files": Json::array(agent_files()),
    "note": "A file that cannot be read stops MAKED before it serves anything, and the reason is on stderr. An empty environment variable counts as unset.",
  }
}
