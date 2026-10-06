// The MAKED single-page app.
//
// Routing is client-side over the History API: `on_url_changed` maps the
// browser path to a slug and the rendered page follows the model. The backend
// serves `index.html` for every non-API path (its static middleware uses a
// history fallback), so a deep link like /about works on a cold load as well
// as after a client-side navigation.

///|
enum Msg {
  Loaded(Result[Json, Error])
  UrlChanged(@url.Url)
}

///|
/// The whole client state: every page the backend knows about, plus the slug
/// currently on screen. Content is small and read-only, so it is fetched once
/// and held; a route change is then a lookup rather than another request.
///
/// `Eq` is required by `create_state_with_init`, which uses it to decide
/// whether a re-render is needed; `Page` derives it for the same reason.
pub(all) struct Model {
  pages : Array[Page]
  current : String
  loaded : Bool
  error : String
} derive(Eq)

///|
fn initial() -> Model {
  { pages: [], current: "index", loaded: false, error: "" }
}

///|
fn Model::page(self : Model) -> Page? {
  find_page(self.pages, self.current)
}

///|
/// Map a URL path to a slug: `/about` -> `about`, `/` -> `index`.
fn slug_of(path : String) -> String {
  let s = if path.has_prefix("/") { path[1:].to_owned() } else { path }
  if s == "" || s == "index" {
    "index"
  } else {
    s
  }
}

///|
/// `update` takes the emitter as a third parameter even though this app never
/// issues a command from an update: the signature is fixed by
/// `create_state_with_init`, so the parameter is named `_emit` to record that.
fn update(
  model : Model,
  msg : Msg,
  _emit : @cmd.Emit[Msg],
) -> (Model, @cmd.Cmd) {
  match msg {
    Loaded(Ok(json)) =>
      (
        {
          pages: decode_pages(json),
          current: model.current,
          loaded: true,
          error: "",
        },
        @cmd.none,
      )
    Loaded(Err(_)) =>
      (
        { ..model, loaded: true, error: "could not reach the server" },
        @cmd.none,
      )
    UrlChanged(url) => ({ ..model, current: slug_of(url.path) }, @cmd.none)
  }
}

///|
/// `on_url_changed` and `expect_json` each take an emitter for *their own*
/// message type. `Emit::map` is the intended lift: it retypes an emitter so
/// that a foreign message is wrapped in one of ours before it is dispatched.
/// Without it there is no way to feed a `Url` into an `Emit[Msg]`.
fn subscriptions(model : Model, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.on_url_changed(emit.map(fn(url) { UrlChanged(url) }))
}

///|
/// Start-up: kick off the single request this app makes.
///
/// The current slug is not read here. `on_url_changed` is a subscription, and
/// rabbita emits the current URL on mount when routing is configured, so a
/// cold load on /about is corrected by the same path a client-side navigation
/// takes -- one route, no special case.
///
/// The name is not `init`: MoonBit treats a function called `init` as a module
/// initialiser, which must take no arguments and return nothing, and rejects
/// this one outright.
fn start(emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  let request = @http
    .get("/api/pages")
    .expect_json(emit.map(fn(result) { Loaded(result) }))
  (initial(), request)
}

///|
fn view(model : Model) -> @html.Html {
  let nav_pages = navigation(model.pages)
  let content = if !model.loaded {
    loading_view()
  } else if model.error != "" {
    error_view(model.error)
  } else {
    match model.page() {
      Some(page) => page_view(page)
      None => not_found_view(model.current)
    }
  }
  let body = if model.current == "index" {
    let hero = @html.div(class="maked-hero", [logo(240), content])
    @html.div([hero, domain_cards(nav_pages)])
  } else {
    content
  }
  @html.div([
    header(model.current, nav_pages),
    // rabbita's html set has no <main>; a classed div carries the same
    // landmark role through the stylesheet.
    @html.div(class="maked-main", [body]),
    @html.footer(
      class="maked-footer",
      "MAKED · MoonBit · rabbita + moonback + sqlite3",
    ),
  ])
}

///| The root component. Public because `cmd/web` mounts it.
pub fn app() -> @rabbita.Val[@html.Html] {
  // The first argument's label is `init~` -- the label is fixed by the
  // signature, but the function passed to it is free to be called anything
  // except `init` itself.
  let (model, _emit) = @rabbita.create_state_with_init(
    init=start,
    update~,
    subscriptions~,
  )
  model.map(view)
}
