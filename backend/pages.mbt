///| The content model, plus the seed content for the nine public pages.
///
/// The content is carried over from the django CMS deployment of MAKED
/// (`mysite/management/commands/bootstrap_maked.py`). Two things about that
/// source are preserved deliberately rather than "tidied":
///
///   - The navigation order is M -> D -> E -> A -> K, the clockwise order the
///     logo draws the ring in. That is *not* the order the name is spelled,
///     and the original site made the same choice. `sort` encodes it.
///   - What the cycle is meant to achieve was never written down, and four of
///     the five domains were still empty. That is stated on the site itself,
///     so it is stated here rather than invented around.

///|
pub(all) struct Page {
  slug : String
  title : String
  letter : String
  role : String
  summary : String
  body : String
  in_navigation : Bool
  sort : Int
}

///|
pub fn Page::to_json(self : Page) -> Json {
  {
    "slug": self.slug,
    "title": self.title,
    "letter": self.letter,
    "role": self.role,
    "summary": self.summary,
    "body": self.body,
    "in_navigation": self.in_navigation,
    "sort": self.sort,
  }
}

///|
/// The five domains, in the clockwise order the logo draws them.
/// A function rather than a `const` because MoonBit only allows immutable
/// primitives in constants, and this is a list of tuples.
pub fn ring_domains() -> Array[(String, String, String, String)] {
  [
    ("model", "Model", "M", "the model formulator"),
    ("data", "Data", "D", "the data turbine"),
    ("experience", "Experience", "E", "the experience absorber"),
    ("attack", "Attack", "A", "the attack generator"),
    ("knowledge", "Knowledge", "K", "the knowledge distiller"),
  ]
}

///|
fn domain_body(title : String, letter : String, role : String) -> String {
  let head = "<p class=\"lead\"><strong>" + title + "</strong> &mdash; " + role + ".</p>"
  let ring =
    "This page is the <span class=\"letter\">" + letter +
    "</span> node of that ring."
  let tail =
    "<p>What the cycle is meant to achieve was never written down. Four of the five applications are still empty scaffolds.</p>"
  head +
  "<p>The mark arranges the five domains as a closed ring around a taijitu, running clockwise <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong>. " +
  ring + "</p>" + tail
}

///|
fn home_body() -> String {
  "<p class=\"lead\">MAKED organises its work into five domains, one for each letter of its name. The mark arranges them as a closed ring around a taijitu, running clockwise <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong> &mdash; the cards below follow that order, not the order the name is spelled.</p>" +
  "<p>Each domain is both an application and a page of this site, so the navigation <em>is</em> the taxonomy. What the cycle is meant to achieve was never written down; four of the five applications are still empty.</p>"
}

///|
fn about_body() -> String {
  "<p>MAKED &mdash; <strong>M</strong>odel, <strong>A</strong>ttack, <strong>K</strong>nowledge, <strong>E</strong>xperience, <strong>D</strong>ata &mdash; is a site built around five domains. Each domain is an application <em>and</em> a top-level page, so the navigation of the site is the structure of the work itself.</p>" +
  "<p>The mark arranges the five as a closed ring around a taijitu, running clockwise <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong> &mdash; a different order from the way the name is spelled, and a cycle rather than a queue. Each domain page in the original carried a single line: <em>the model formulator</em>, <em>the data turbine</em>, <em>the experience absorber</em>, <em>the attack generator</em>, <em>the knowledge distiller</em>.</p>" +
  "<p>What the cycle was meant to <em>do</em> was never written down. Four of the five applications are still empty scaffolds, and no code routes anything from one domain to the next &mdash; the loop currently exists as navigation and as a logo.</p>" +
  "<p>This deployment runs on MoonBit: a rabbita single-page frontend and a small Flask-style micro-framework built on moonback, with the page content served from SQLite.</p>"
}

///|
fn tutorial_body() -> String {
  "<h3>Run it</h3><p>The backend serves both the JSON API and the built frontend from a single process:</p>" +
  "<pre><code>moon build --release --target native cmd/server\nmoon build --release --target js cmd/web\nmoon run --target native cmd/server</code></pre>" +
  "<p>Open <code>http://127.0.0.1:8080/</code>. The nine public pages are client-side routes; the API is under <code>/api/</code>.</p>" +
  "<h3>Layout</h3><p><code>backend/</code> holds the micro-framework, the SQLite storage layer and the API routes. <code>frontend/</code> holds the rabbita SPA. <code>cmd/server</code> is the native entry point and <code>cmd/web</code> builds the browser bundle.</p>"
}

///|
fn tasks_body() -> String {
  "<p>The original site's \"task monitor\" was a bare link to a flower instance on the author's LAN, unreachable for anyone else. There is no broker in this deployment, so the page reports what the server itself is doing: the SQLite file it opened, and the pages it serves.</p>" +
  "<p>See <code>GET /api/status</code> for the same information as JSON.</p>"
}

///|
fn not_found_body() -> String {
  "<p>The loop is closed, but this path is not on the ring. Try one of the five domains, or head back to the <a href=\"/\">index</a>.</p>"
}

///|
pub fn not_found_page() -> Page {
  {
    slug: "404",
    title: "Not found",
    letter: "",
    role: "",
    summary: "off the ring",
    body: not_found_body(),
    in_navigation: false,
    sort: 999,
  }
}

///|
/// The nine public pages, in navigation order.
pub fn seed_pages() -> Array[Page] {
  let pages = []
  let mut sort = 0
  for (slug, title, letter, role) in ring_domains() {
    pages.push({
      slug,
      title,
      letter,
      role,
      summary: role,
      body: domain_body(title, letter, role),
      in_navigation: true,
      sort,
    })
    sort += 1
  }
  for (slug, title, summary, body) in [
    ("tutorial", "Tutorial", "how to run it", tutorial_body()),
    ("about", "About", "what this is", about_body()),
    ("tasks", "Tasks", "what the server is doing", tasks_body()),
  ] {
    pages.push({
      slug,
      title,
      letter: "",
      role: "",
      summary,
      body,
      in_navigation: true,
      sort,
    })
    sort += 1
  }
  pages
}

///|
pub fn home_page() -> Page {
  {
    slug: "index",
    title: "Index",
    letter: "",
    role: "",
    summary: "five domains, one closed ring",
    body: home_body(),
    in_navigation: false,
    sort: -1,
  }
}
