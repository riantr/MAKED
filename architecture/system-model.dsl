// MAKED System Model &mdash; Structurizr DSL
// Skill: system-modeler + c4model
//
// Open in Qoder Canvas to render C4 views, or use any Structurizr-compatible
// viewer. Two views are defined: system context and container.

workspace {
  model {
    // --- Actors ---
    user = person "Browser user" "A person who visits the MAKED site"

    // --- External systems ---
    // (none &mdash; the system is self-contained)

    // --- System boundary ---
    maked = softwareSystem "MAKED" "Five-domain content site on MoonBit" {
      // --- Containers ---
      backend = container "Backend server" "Serves JSON API, static files, and SPA fallback" "native binary (moonback + sqlite3)"
      frontend = container "Frontend SPA" "Client-side routing and rendering" "js bundle (rabbita)"
      database = container "SQLite database" "Page content storage" "sqlite3 file"
    }

    // --- Relationships ---
    user -> backend "Loads site, navigates pages" "HTTPS"
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
