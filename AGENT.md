# Driving MAKED from another agent

MAKED is an adversarial knowledge loop: five domains in a ring — Model, Data,
Experience, Attack, Knowledge — each the overcoming of the one before it. Which
slot can push a position is answered by the transition table, never by a
hard-coded guess, and a position the table cannot move is reported as blocked
rather than silently skipped.

Two things an agent can do with it: **read** where the loop stands and what it
may do next, and **move** it. There are two ways in, and they answer the same
questions.

## The short version

```
1. GET /api/agent
```

That is the discovery document. It carries the seven tools with their argument
schemas, the instructions for calling them, the plain HTTP endpoints that ask
the same questions, and the four files MAKED runs on. An agent that reads it
needs nothing else to drive the loop.

## The Model Context Protocol

MAKED speaks MCP, version **2026-07-28**. Build the server and point your
agent at it:

```bash
moon build --release --target native cmd/mcp
```

```json
{
  "mcpServers": {
    "maked": {
      "command": "/path/to/MAKED_moonbit/_build/native/release/build/cmd/mcp/mcp.exe"
    }
  }
}
```

The server speaks stdio by default. Set `MAKED_MCP_PORT` and it speaks HTTP
instead, on the port you name, at `/mcp`.

Two things about this protocol version are worth knowing before you wire it up:

- **There is no handshake.** `initialize` is not a method in 2026-07-28; the
  server answers it with `-32601 Method not found`. The entry point is
  `server/discover`.
- **Every request carries its own version.** Each request's `params._meta` must
  contain `io.modelcontextprotocol/protocolVersion` (a string) and
  `io.modelcontextprotocol/clientCapabilities` (an object). A request without
  them is refused with `-32602`.

Over HTTP there are two more: the `MCP-Protocol-Version: 2026-07-28` header,
and an `Mcp-Method: <method>` header naming the method the body carries.

> The agent's server is **not** in the published release artifacts yet — those
> carry the web server and the browser bundle. It is built from this
> repository.

## The seven tools

| Tool | Arguments | What it answers |
|---|---|---|
| `maked_status` | — | where the loop stands, what the last move did, what the run adds up to, whether it is still finding ground |
| `maked_options` | `depth` | the slots that can move, the slots that cannot and why, the successors the table declined to choose between |
| `maked_step` | `slot`, `target` | take a move, and say what happened |
| `maked_model` | — | the machine as data: domains, positions, slots, and the rule for every pair |
| `maked_society` | `trigger` | where the collective stands; with a trigger, take that move |
| `maked_sessions` | — | the named explorations, and which one is in front of us |
| `maked_export` | `session_id`, `format` | one exploration as Markdown (to read) or JSON (to process) |

The order that works: **`maked_status` → `maked_options` → `maked_step`**.

`maked_step` with no slot lets the table choose; with a slot you choose; with
a `target` you answer a question the table asked. Every answer is in
sentences, with the ids beside them for when you want to be exact.

## The same questions over plain HTTP

| Method | Path | Tool |
|---|---|---|
| `GET` | `/api/loop/status` | `maked_status` |
| `GET` | `/api/loop/continuations` | `maked_options` |
| `POST` | `/api/loop/step` | `maked_step` |
| `POST` | `/api/loop/step/:slot` | `maked_step` |
| `GET` | `/api/model` | `maked_model` |
| `GET` | `/api/society` | `maked_society` |
| `POST` | `/api/society/step` | `maked_society` |
| `GET` | `/api/sessions` | `maked_sessions` |
| `GET` | `/api/sessions/:id/export` | `maked_export` |

## The four files

Everything a person would want to change is a file, and the environment
variable names it.

| File | Named by | What it decides |
|---|---|---|
| The machine | `MAKED_MODEL` | the domains, positions, slots and rules the loop runs on |
| The mapping table | `MAKED_RESEARCH` | what a document means — which words make a rule fire, and which slot it drives |
| The society vocabulary | `MAKED_SOCIETY` | the English words for the collective's positions and moves |
| The corpus | `MAKED_CORPUS` | where the documents come from: arxiv, a feed, or your own folder |

A file that cannot be read stops MAKED before it serves anything, and the
reason is on stderr. A rule that names a slot the running machine does not
have is refused at start-up: it is a rule about nowhere.

## Working *on* MAKED rather than driving it

If your job is to change MAKED — not to run it — read [AGENTS.md](AGENTS.md)
instead: the MoonBit conventions, the build rules, and the two gates that
check the tests themselves.
