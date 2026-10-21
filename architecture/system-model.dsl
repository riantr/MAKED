// MAKED System Model &mdash; Structurizr DSL
// Skill: system-modeler + c4model
//
// Open in Qoder Canvas to render C4 views, or use any Structurizr-compatible
// viewer. Two views are defined: system context and container.
//
// The system has grown a second front door: an agent can now drive the loop
// over the Model Context Protocol, so the agent is an external system here
// and the server that speaks to it is a container.
//
// The domain count and the route the model names are the tree's, and the
// gate (tools/check-docs.sh) says so out loud.

workspace {
  model {
    // --- Actors ---
    user = person "Browser user" "A person who visits the MAKED site"

    // --- External systems ---
    agent = softwareSystem "Another agent" "An agent that drives MAKED over the Model Context Protocol"

    // --- System boundary ---
    maked = softwareSystem "MAKED" "Five-domain content site on MoonBit" {
      // --- Containers ---
      backend = container "Backend server" "Serves JSON API, static files, and SPA fallback" "native binary (moonback + sqlite3)"
      frontend = container "Frontend SPA" "Client-side routing and rendering" "js bundle (rabbita)"
      database = container "SQLite database" "Page content storage" "sqlite3 file"
      agent_server = container "Agent's server" "The loop, as the tools another agent calls" "native binary (MCP over stdio or HTTP)"
    }

    // --- Relationships ---
    user -> backend "Loads site, navigates pages" "HTTPS"
    agent -> agent_server "Spawns it, and speaks MCP to it" "stdio or HTTP"
    agent_server -> backend "Reads where the loop stands, and moves it" "in process"
    backend -> database "Reads/writes page content" "SQLite FFI"
    backend -> frontend "Serves static bundle (index.html, main.js, styles.css)" "HTTP static files"
    frontend -> backend "Fetches the pages and the working state at startup" "HTTP GET /api/bootstrap"
  }

  views {
    systemContext maked "system_context" "System context" {
      include *
      autoLayout
    }

    container maked "containers" "Container view" {
      include *
      autoLayout
    }
  }
}
