// The MAKED single-page app.
//
// Routing is client-side over the History API: `on_url_changed` maps the
// browser path to a slug and the rendered page follows the model. The backend
// serves `index.html` for every non-API path (its static middleware uses a
// history fallback), so a deep link like /about works on a cold load as well
// as after a client-side navigation.

///|
/// `pub(all)` because rabbita needs `Msg` to name the subscription's message
/// type in the generated `.mbti`.
pub(all) enum Msg {
  Loaded(Result[Json, Error])
  LoopLoaded(Result[Json, Error])
  LoopStepped(Result[Json, Error])
  LoopReset(Result[Json, Error])
  StepClicked
  SlotStepClicked(String)
  ResetClicked
  ResearchLoaded(Result[Json, Error])
  ResearchDriven(Result[Json, Error])
  CausalLoaded(Result[Json, Error])
  FetchPapersClicked
  DriveLoopClicked
  EstimateCausalClicked
  UrlChanged(@url.Url)
}

///|
/// The whole client state: every page the backend knows about, plus the slug
/// currently on screen. Content is small and read-only, so it is fetched once
/// and held; a route change is then a lookup rather than another request.
///
/// `Eq` is required by `create_state_with_init`, which uses it to decide
/// whether a re-render is needed; `Page` derives it for the same reason. The
/// `implicit_impl_as_method` warning on that derive is the accepted cost --
/// see `page.mbt`.
pub(all) struct Model {
  pages : Array[Page]
  current : String
  loaded : Bool
  error : String
  loop_status : LoopStatus?
  loop_error : String
  research_papers : Array[Json]
  research_triggers : Array[Json]
  research_error : String
  causal_result : Json?
  causal_error : String
} derive(Eq)

///|
fn initial() -> Model {
  {
    pages: [],
    current: "index",
    loaded: false,
    error: "",
    loop_status: None,
    loop_error: "",
    research_papers: [],
    research_triggers: [],
    research_error: "",
    causal_result: None,
    causal_error: "",
  }
}

///|
fn Model::page(self : Model) -> Page? {
  find_page(self.pages, self.current)
}

///|
/// Map a URL path to a slug: `/about` -> `about`, `/` -> `index`.
///
/// Public only because `frontend_test.mbt` asserts it. MoonBit compiles
/// `_test.mbt` as a blackbox package that can see `pub` items and nothing
/// else, so an internal is untestable until it is exported. Nothing in `cmd/web`
/// calls it.
pub fn slug_of(path : String) -> String {
  let s = if path.has_prefix("/") { path[1:].to_owned() } else { path }
  if s == "" || s == "index" {
    "index"
  } else {
    s
  }
}

///|
/// `update` takes the emitter as the first parameter. The signature is fixed by
/// `@rabbita.cell`, which passes the emitter so the view can issue commands.
fn update(model : Model, msg : Msg, emit : @cmd.Emit[Msg]) -> (Model, @cmd.Cmd) {
  match msg {
    Loaded(Ok(json)) =>
      (
        {
          pages: decode_pages(json),
          current: model.current,
          loaded: true,
          error: "",
          loop_status: model.loop_status,
          loop_error: model.loop_error,
          research_papers: model.research_papers,
          research_triggers: model.research_triggers,
          research_error: model.research_error,
          causal_result: model.causal_result,
          causal_error: model.causal_error,
        },
        @cmd.none,
      )
    Loaded(Err(_)) =>
      (
        { ..model, loaded: true, error: "could not reach the server", },
        @cmd.none,
      )
    LoopLoaded(Ok(json)) =>
      (
        {
          ..model,
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
        },
        @cmd.none,
      )
    LoopLoaded(Err(_)) =>
      ({ ..model, loop_error: "loop status unavailable", }, @cmd.none)
    LoopStepped(Ok(json)) =>
      (
        {
          ..model,
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
        },
        @cmd.none,
      )
    LoopStepped(Err(_)) => ({ ..model, loop_error: "step failed", }, @cmd.none)
    LoopReset(Ok(json)) =>
      (
        {
          ..model,
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
        },
        @cmd.none,
      )
    LoopReset(Err(_)) => ({ ..model, loop_error: "reset failed", }, @cmd.none)
    StepClicked =>
      (
        model,
        @http.post("/api/loop/step").expect_json(
          emit.map(fn(result) { LoopStepped(result) }),
        ),
      )
    SlotStepClicked(slot) => {
      let name = match slot {
        "处境" => "occasion"
        "取向" => "orientation"
        "先行" => "antecedent"
        "行动" => "act"
        "反馈" => "feedback"
        "持存" => "hold"
        "共在" => "cobeing"
        "揭蔽" => "unveil"
        _ => slot
      }
      (
        model,
        @http.post("/api/loop/step/\{name}").expect_json(
          emit.map(fn(result) { LoopStepped(result) }),
        ),
      )
    }
    ResetClicked =>
      (
        model,
        @http.post("/api/loop/reset").expect_json(
          emit.map(fn(result) { LoopReset(result) }),
        ),
      )
    ResearchLoaded(Ok(json)) =>
      (
        {
          ..model,
          research_papers: decode_research_papers(json),
          research_triggers: decode_research_triggers(json),
          research_error: "",
        },
        @cmd.none,
      )
    ResearchLoaded(Err(_)) =>
      ({ ..model, research_error: "research data unavailable", }, @cmd.none)
    ResearchDriven(Ok(json)) =>
      (
        {
          ..model,
          loop_status: Some(decode_loop_status(json)),
          loop_error: "",
          research_papers: [],
          research_triggers: [],
          research_error: "",
        },
        @cmd.none,
      )
    ResearchDriven(Err(_)) =>
      ({ ..model, loop_error: "research drive failed", }, @cmd.none)
    FetchPapersClicked =>
      (
        model,
        @http.get("/api/research/papers").expect_json(
          emit.map(fn(result) { ResearchLoaded(result) }),
        ),
      )
    DriveLoopClicked =>
      (
        model,
        @http.post("/api/research/drive").expect_json(
          emit.map(fn(result) { ResearchDriven(result) }),
        ),
      )
    CausalLoaded(Ok(json)) =>
      (
        {
          ..model,
          causal_result: decode_causal_result(json),
          causal_error: "",
        },
        @cmd.none,
      )
    CausalLoaded(Err(_)) =>
      ({ ..model, causal_error: "causal inference unavailable", }, @cmd.none)
    EstimateCausalClicked =>
      (
        model,
        @http.get("/api/research/causal").expect_json(
          emit.map(fn(result) { CausalLoaded(result) }),
        ),
      )
    UrlChanged(url) => ({ ..model, current: slug_of(url.path), }, @cmd.none)
  }
}

///|
/// `on_url_changed` and `expect_json` each take an emitter for *their own*
/// message type. `Emit::map` is the intended lift: it retypes an emitter so
/// that a foreign message is wrapped in one of ours before it is dispatched.
/// Without it there is no way to feed a `Url` into an `Emit[Msg]`.
fn subscriptions(_model : Model, emit : @cmd.Emit[Msg]) -> @sub.Sub {
  @sub.on_url_changed(emit.map(fn(url) { UrlChanged(url) }))
}

///|
fn view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
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
    let loop_panel = loop_view(emit, model)
    let research_panel = research_view(emit, model)
    let causal_panel = causal_view(emit, model)
    @html.div([
      hero,
      loop_panel,
      research_panel,
      causal_panel,
      domain_cards(nav_pages),
    ])
  } else {
    content
  }
  @html.div([
    header(model.current, nav_pages),
    @html.div(class="maked-main", [body]),
    @html.footer(
      class="maked-footer",
      "MAKED · MoonBit · rabbita + moonback + sqlite3",
    ),
  ])
}

///|
/// The root component. Public because `cmd/web` mounts it.
///
/// Uses `create_state` inside a builder so the view receives the emitter and
/// can issue commands (step/reset POST requests) from button clicks. The
/// initial data fetch is issued through the emitter right after state
/// creation.
pub fn app() -> @rabbita.App {
  @rabbita.new(fn() {
    let (model, emit) = @rabbita.create_state(
      initial(),
      update~,
      subscriptions~,
    )
    let pages_request = @http.get("/api/pages").expect_json(
      emit.map(fn(result) { Loaded(result) }),
    )
    let loop_request = @http.get("/api/loop/status").expect_json(
      emit.map(fn(result) { LoopLoaded(result) }),
    )
    @cmd.batch([pages_request, loop_request]) |> ignore
    model.map(fn(m) { view(emit, m) })
  })
}

///|
fn decode_research_papers(json : Json) -> Array[Json] {
  match field(json, "papers") {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn decode_research_triggers(json : Json) -> Array[Json] {
  match field(json, "triggers") {
    Some(Array(items)) => items
    _ => []
  }
}

///|
fn decode_causal_result(json : Json) -> Json? {
  match field(json, "causal") {
    Some(obj) => Some(obj)
    _ => None
  }
}
