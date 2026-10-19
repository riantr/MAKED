// View helpers: the header, the ring cards, and page rendering.
//
// Three rules of rabbita's html module shape everything here:
//
//   - The children parameter is a *generic* `C : IsChildren`, and a bare
//     `String` is itself a valid child. But an `Array` child must be
//     `Array[Html]` -- there is no `Array[String]` impl, so a mixed list like
//     `["text", some_element]` does not typecheck and has to be flattened into
//     a single string or wrapped.
//   - The class parameter is spelled `class`, not `class_` (that spelling is
//     for parameters that would otherwise collide with a keyword, such as
//     `type` on <button>).
//   - `on_click` exists only on `button`, `div`, `li` and `ul` -- notably not
//     on `a`. Navigation handlers therefore sit on a wrapper element.
//
// Page bodies arrive from the backend as HTML fragments and are inserted with
// `dangerous_inner_html`. That is safe here only because the backend is the
// sole writer of that content and it stores the strings itself -- it is not
// user input. A comment saying so belongs next to the call, and did.

///|
/// The site header: mark, wordmark, and the navigation bar.
///
/// The click handler is on the `<li>`, not the `<a>`, because `<a>` has no
/// `on_click`. The anchor keeps its `href`, so the link still behaves for
/// middle-click and "open in new tab"; the handler on the wrapper is what
/// turns an ordinary left click into a client-side navigation.
pub fn header(current : String, pages : Array[Page]) -> @html.Html {
  @html.header(class="maked-header", [
    @html.div(class="maked-header-inner", [
      @html.a(href="/", class="maked-brand", [
        logo_mark(44),
        @html.span(class="maked-brand-text", [
          @html.span(class="maked-brand-mark", "MAKED"),
          @html.span(
            class="maked-brand-sub",
            "Model · Attack · Knowledge · Experience · Data",
          ),
        ]),
      ]),
      @html.nav(class="maked-nav", [@html.ul(nav_items(current, pages))]),
    ]),
  ])
}

///|
/// The navigation list: the seeded pages, then the workspace.
///
/// The workspace is a client-side route rather than a seeded page -- what it
/// shows is the user's own records, not a row in the `pages` table -- so it
/// is appended here instead of coming out of the pages list. It goes last
/// because it is the one destination that holds the user's own work rather
/// than the project's own words.
fn nav_items(current : String, pages : Array[Page]) -> Array[@html.Html] {
  let items : Array[@html.Html] = []
  for page in pages {
    let active = if page.slug == current { " active" } else { "" }
    let target = "/" + page.slug
    items.push(
      @html.li(class=active, on_click=@nav.push_url(target), [
        @html.a(href=target, page.title),
      ]),
    )
  }
  let workspace_active = if current == "workspace" { " active" } else { "" }
  items.push(
    @html.li(class=workspace_active, on_click=@nav.push_url("/workspace"), [
      @html.a(href="/workspace", "Workspace"),
    ]),
  )
  // The sessions come after the workspace: both hold the user's own work,
  // and the workspace is the one that holds their records rather than the
  // path they took to get there.
  let sessions_active = if current == "sessions" { " active" } else { "" }
  items.push(
    @html.li(class=sessions_active, on_click=@nav.push_url("/sessions"), [
      @html.a(href="/sessions", "Sessions"),
    ]),
  )
  items
}

///|
/// The five domain cards on the index page, in ring order.
///
/// Each card is a clickable `<div>` holding a real `<a>`, for the same reason
/// as the header: `<a>` cannot carry the handler.
pub fn domain_cards(pages : Array[Page]) -> @html.Html {
  let cards : Array[@html.Html] = []
  for page in pages {
    if page.letter == "" {
      continue
    }
    let letter_class = "maked-domain maked-domain--" + page.letter
    let target = "/" + page.slug
    cards.push(
      @html.div(class=letter_class, on_click=@nav.push_url(target), [
        @html.a(href=target, [
          @html.span(class="letter", page.letter),
          @html.span(class="name", page.title),
          @html.span(class="role", page.role),
        ]),
      ]),
    )
  }
  @html.div(class="maked-domains", cards)
}

///|
/// Render one page's content.
///
/// The body is inserted with `Attrs::inner_html`, which is rabbita's
/// raw-markup escape hatch. That is safe here only because the backend is the
/// sole writer of this content and stores the strings itself -- it is not user
/// input, and there is no write path in the API to make it so. The compiler's
/// `alert_xss_vulnerable` warning on the next line is the expected consequence
/// and is accepted here on the strength of that argument.
pub fn page_view(page : Page) -> @html.Html {
  let body_attrs = @html.Attrs::build().inner_html(page.body)
  @html.article(class="maked-page", [
    @html.h1(class="maked-page-title", page.title),
    // The children parameter is required even when the content comes from
    // `inner_html`, so it is given `nothing`.
    @html.div(class="maked-body", attrs=body_attrs, @html.nothing),
  ])
}

///|
pub fn not_found_view(slug : String) -> @html.Html {
  @html.article(class="maked-page", [
    @html.h1(class="maked-page-title", "Not found"),
    @html.p(
      class="maked-lede",
      "Nothing at /" +
      slug +
      ". Try one of the five domains, or head back to the index.",
    ),
  ])
}

///|
pub fn loading_view() -> @html.Html {
  @html.article(class="maked-page", [@html.p(class="maked-lede", "Loading…")])
}

///|
pub fn error_view(reason : String) -> @html.Html {
  @html.article(class="maked-page", [
    @html.h1(class="maked-page-title", "Server unavailable"),
    @html.p(class="maked-lede", reason),
  ])
}

///|
/// The sentence that says what the last step did, if there was one.
///
/// The labels say where the machine is; this says how it got there. It comes
/// from the server with the rest of the step, because the sentence needs the
/// transition table to say anything true.
fn last_narration(path : Array[SessionStep]) -> String {
  match path.last() {
    Some(step) => step.narration
    None => ""
  }
}

///|
/// The loop panel on the index page: current position, drive slot, step/reset
/// buttons, and the history of past transitions.
pub fn loop_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let error = if model.loop_error != "" {
    @html.p(class="maked-loop-error", model.loop_error)
  } else {
    @html.nothing
  }
  match model.loop_status {
    None =>
      @html.section(class="maked-loop", [
        @html.h2(class="maked-loop-title", "Loop"),
        @html.p(class="maked-loop-loading", "Loading loop status…"),
        error,
      ])
    Some(status) => {
      let buttons = @html.div(class="maked-loop-buttons", [
        @html.button(
          class="maked-loop-btn",
          on_click=emit(StepClicked),
          "Step → \{status.next_domain}",
        ),
        @html.button(
          class="maked-loop-btn maked-loop-btn--reset",
          on_click=emit(ResetClicked),
          "Reset",
        ),
      ])
      // Rendered from the backend's own slot list, so this panel cannot drift
      // out of step with the machine. Each button says what the transition
      // table says about that slot at this position, which is the whole point:
      // 228 of the 272 position-slot combinations have no outgoing edge, and
      // silently doing nothing is indistinguishable from a broken button.
      let slot_buttons : Array[@html.Html] = []
      for slot in model.slots {
        let live = find_open_slot(status, slot.name)
        let is_drive = if slot.name == status.drive_slot_name {
          " maked-loop-slot--drive"
        } else {
          ""
        }
        let note = match live {
          Some(open) => {
            let outcome = if open.outcome == "" {
              ""
            } else {
              " · \{open.outcome}"
            }
            let targets = if open.targets.length() == 0 {
              ""
            } else {
              " → \{open.targets.join(", ")}"
            }
            "\{open.designation}\{outcome}\{targets}"
          }
          None => "\{slot.designation} · no edge here"
        }
        let state_class = match live {
          Some(_) => " maked-loop-slot--open"
          None => " maked-loop-slot--closed"
        }
        slot_buttons.push(
          @html.button(
            class="maked-loop-slot\{state_class}\{is_drive}",
            title=slot.gloss,
            on_click=emit(SlotStepClicked(slot.name)),
            [
              @html.span(class="maked-loop-slot-name", slot.designation),
              @html.span(class="maked-loop-slot-note", note),
            ],
          ),
        )
      }
      // The one line that turns "nothing happened" into an explanation. It
      // states how many of the eight slots the transition table actually offers
      // here, and says plainly which of the three cases applies.
      let open_count = status.open_slots.length()
      let count_text = open_count.to_string()
      let situation = if status.blocked {
        "Nothing can move from here: no slot has an outgoing edge at this position. That is a property of the model, not a failure, so Step will not change the position."
      } else if status.undecided {
        "The table offers " +
        count_text +
        " outgoing edges here and declines to choose between them. Pick one on purpose."
      } else {
        count_text +
        " of the 8 slots can move this position. The rest have no outgoing edge here and will do nothing."
      }
      let situation_class = if status.blocked {
        " maked-loop-why--blocked"
      } else if status.undecided {
        " maked-loop-why--undecided"
      } else {
        ""
      }
      let slot_selector = @html.div(class="maked-loop-slots", [
        @html.p(
          class="maked-loop-slots-label",
          "Drive slots. Each one says whether the transition table has an outgoing edge from this position; the highlighted one is this domain's drive slot.",
        ),
        @html.p(class="maked-loop-why\{situation_class}", situation),
        @html.div(class="maked-loop-slot-grid", slot_buttons),
      ])
      // What just happened, and what the run of steps adds up to. The labels
      // above say where the machine is; these two say how it got there and
      // what the last few clicks were for. Without them the panel is a
      // position that changes, which is the least legible way to show a
      // machine that is thinking.
      let narration = last_narration(model.session_path)
      let narration_block = if narration == "" {
        @html.nothing
      } else {
        @html.div(class="maked-loop-narration", [
          @html.p(class="maked-loop-narration-label", "What just happened"),
          @html.p(class="maked-loop-narration-text", narration),
        ])
      }
      let summary_block = if model.session_summary == "" {
        @html.nothing
      } else {
        @html.div(class="maked-loop-summary", [
          @html.p(class="maked-loop-summary-label", "The run so far"),
          @html.p(class="maked-loop-summary-text", model.session_summary),
        ])
      }
      // And what the run is worth: whether it is still finding ground, how
      // far it has ranged, and whether it is doing better than it was at the
      // start. The step counter cannot answer any of those.
      let metrics_block_html = metrics_block(model.session_metrics)
      let current = @html.div(class="maked-loop-current", [
        @html.span(class="maked-loop-domain", status.current_domain),
        @html.span(class="maked-loop-sep", "·"),
        @html.span(class="maked-loop-position", status.current_position),
        @html.span(class="maked-loop-gloss", status.current_gloss),
        @html.span(class="maked-loop-sep", "·"),
        @html.span(class="maked-loop-drive", "drive: \{status.drive_slot}"),
      ])
      // Which exploration the steps are being recorded into. A step taken
      // here belongs to a session, and a person taking a step should be able
      // to see which one without going to another page.
      let session_line = if model.active_session.name == "" {
        @html.nothing
      } else {
        @html.div(class="maked-loop-session", [
          @html.span(
            class="maked-loop-session-text",
            "Recording into “\{model.active_session.name}” · " +
            model.session_path.length().to_string() +
            " steps · ",
          ),
          @html.a(href="/sessions", "open the sessions"),
        ])
      }
      let history_items : Array[@html.Html] = []
      let n = status.history.length()
      let mut i = n
      while i > 0 {
        i -= 1
        let e = status.history[i]
        history_items.push(
          @html.li(class="maked-loop-event", [
            @html.span(class="maked-loop-event-domain", e.domain),
            @html.span(class="maked-loop-event-outcome", e.outcome),
            @html.span(class="maked-loop-event-detail", e.detail),
          ]),
        )
      }
      let history = if n == 0 {
        @html.p(class="maked-loop-empty", "No steps yet.")
      } else {
        @html.ul(class="maked-loop-history", history_items)
      }
      @html.section(class="maked-loop", [
        @html.h2(class="maked-loop-title", "Loop"),
        current,
        narration_block,
        summary_block,
        metrics_block_html,
        session_line,
        buttons,
        slot_selector,
        history,
        error,
      ])
    }
  }
}

///|
/// The measures: what the run is worth.
///
/// A number and a reading, side by side. The number alone would be a
/// scoreboard with no units; the reading alone would be a mood. Neither is
/// combined into a single score: one number out of four measures would hide
/// which of them fell, and a number nobody can argue with is not a measure.
///
/// The comparison underneath is the part that answers the question a person
/// has after twenty clicks -- is this run better than the five steps they
/// took at the start? -- and it is written by the server, where the path is.
fn metrics_block(report : MetricReport) -> @html.Html {
  if report.metrics.length() == 0 {
    return @html.nothing
  }
  let items : Array[@html.Html] = []
  for metric in report.metrics {
    let reading = if metric.of > 0 {
      metric.value.to_string() + " of " + metric.of.to_string()
    } else {
      metric.value.to_string()
    }
    items.push(
      @html.li(class="maked-metric", [
        @html.span(class="maked-metric-label", metric.label),
        @html.span(class="maked-metric-value", reading),
        @html.span(class="maked-metric-sentence", metric.sentence),
      ]),
    )
  }
  let comparison = if report.comparison == "" {
    @html.nothing
  } else {
    @html.p(class="maked-metric-comparison", report.comparison)
  }
  @html.div(class="maked-metrics", [
    @html.p(class="maked-metrics-title", "How the run is doing"),
    @html.ul(class="maked-metric-list", items),
    comparison,
  ])
}

///|
/// Research panel: fetch arxiv papers and drive the Loop.
pub fn research_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let buttons = @html.div(class="maked-research-buttons", [
    @html.button(
      class="maked-btn maked-btn-primary",
      on_click=emit(FetchPapersClicked),
      "Fetch SNN Papers",
    ),
    @html.button(
      class="maked-btn maked-btn-accent",
      on_click=emit(DriveLoopClicked),
      "Drive Loop with Papers",
    ),
  ])
  let papers_list = if model.research_papers.length() == 0 {
    @html.p(
      class="maked-research-empty",
      "No papers loaded. Click 'Fetch SNN Papers' to begin.",
    )
  } else {
    let items : Array[@html.Html] = []
    for paper in model.research_papers {
      let title = get_string(paper, "title", "Untitled")
      let authors_array = get_string(paper, "authors", "")
      let summary = get_string(paper, "summary", "")
      let link = get_string(paper, "link", "#")
      items.push(
        @html.li(class="maked-research-paper", [
          @html.a(href=link, class="maked-paper-title", [@html.text(title)]),
          @html.p(class="maked-paper-authors", authors_array),
          @html.p(class="maked-paper-summary", summary),
        ]),
      )
    }
    @html.ul(class="maked-research-list", items)
  }
  let triggers_list = if model.research_triggers.length() == 0 {
    @html.nothing
  } else {
    let items : Array[@html.Html] = []
    for trigger in model.research_triggers {
      let paper_id = get_string(trigger, "paper_id", "")
      let trigger_name = get_string(trigger, "trigger", "")
      let slot = get_string(trigger, "slot", "")
      items.push(
        @html.li(class="maked-research-trigger", [
          @html.span(class="maked-trigger-paper", paper_id),
          @html.span(class="maked-trigger-name", trigger_name),
          @html.span(class="maked-trigger-slot", slot),
        ]),
      )
    }
    @html.div(class="maked-triggers-section", [
      @html.h3(class="maked-triggers-title", "Trigger Mappings"),
      @html.ul(class="maked-triggers-list", items),
    ])
  }
  let error = if model.research_error == "" {
    @html.nothing
  } else {
    @html.p(class="maked-research-error", model.research_error)
  }
  @html.section(class="maked-research", [
    @html.h2(class="maked-research-title", "Arxiv-Driven SNN Research"),
    buttons,
    papers_list,
    triggers_list,
    error,
  ])
}

///|
/// Causal inference panel: estimate the causal effect of paper "novelty" on
/// a synthetic impact score using Double/Debiased Machine Learning.
pub fn causal_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let button = @html.div(class="maked-causal-buttons", [
    @html.button(
      class="maked-btn maked-btn-causal",
      on_click=emit(EstimateCausalClicked),
      "Estimate Causal Effect (DoubleML)",
    ),
  ])
  let result_view = match model.causal_result {
    None =>
      @html.p(
        class="maked-causal-empty",
        "Click the button to run causal inference on research papers.",
      )
    Some(causal) => {
      let theta = get_string(causal, "theta", "0.0")
      let se = get_string(causal, "se", "0.0")
      let ci_lower = get_string(causal, "ci_lower", "0.0")
      let ci_upper = get_string(causal, "ci_upper", "0.0")
      let n_obs = get_string(causal, "n_obs", "0")
      let n_treated = get_string(causal, "n_treated", "0")
      let n_features = get_string(causal, "n_features", "0")
      @html.div(class="maked-causal-results", [
        @html.h3(class="maked-causal-subtitle", "Causal Effect Estimate"),
        @html.dl(class="maked-causal-stats", [
          @html.dt("Treatment Effect (θ)"),
          @html.dd(class="maked-causal-value", theta),
          @html.dt("Standard Error"),
          @html.dd(se),
          @html.dt("95% Confidence Interval"),
          @html.dd("[\{ci_lower}, \{ci_upper}]"),
          @html.dt("Observations"),
          @html.dd(n_obs),
          @html.dt("Treated"),
          @html.dd(n_treated),
          @html.dt("Features"),
          @html.dd(n_features),
        ]),
        @html.p(
          class="maked-causal-interpretation",
          "The estimated causal effect of paper 'novelty' on impact, controlling for confounders via DoubleML.",
        ),
      ])
    }
  }
  let error = if model.causal_error == "" {
    @html.nothing
  } else {
    @html.p(class="maked-causal-error", model.causal_error)
  }
  @html.section(class="maked-causal", [
    @html.h2(class="maked-causal-title", "Causal Inference"),
    button,
    result_view,
    error,
  ])
}

///|
/// The sessions page: the named explorations, the timeline of the one in
/// front of the user, and the two ways out of a step -- go back, or fork.
///

///| Built around what a person wants from a history: what happened, why it

///| was possible, and how to try the other road. The "why" line is written

///| by the backend, so the explanation on screen is the explanation the

///| transition table gives rather than a second reading of it.
///

///| The two buttons on a step do different things and say so. "Go back to

///| here" rewinds the session and keeps the steps it walked back from --

///| they become the roads not taken. "Fork from here" makes a new session

///|
/// with a copy of the path up to that step, and leaves this one alone.
pub fn sessions_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let active = model.active_session
  let compose = @html.div(class="maked-ss-compose", [
    @html.label(
      class="maked-ss-label",
      for_="maked-ss-name",
      "Name a new session",
    ),
    @html.input(
      id="maked-ss-name",
      class="maked-ss-input",
      placeholder="What is this exploration called?",
      value=model.session_name_draft,
      maxlength=120,
      on_input=emit.map(fn(text) { SessionNameChanged(text) }),
    ),
    @html.button(
      class="maked-ss-btn maked-ss-btn--primary",
      on_click=emit(NewSessionClicked),
      "New session",
    ),
  ])
  let status = if model.session_error != "" {
    @html.p(class="maked-ss-error", model.session_error)
  } else if model.session_notice != "" {
    @html.p(class="maked-ss-notice", model.session_notice)
  } else {
    @html.nothing
  }
  // The exports are plain links to the API rather than fetches: the server
  // sends them as attachments, and a link is what a browser knows how to
  // download.
  let export_base = "/api/sessions/" + active.id.to_string() + "/export"
  let exports = @html.div(class="maked-ss-exports", [
    @html.a(
      href=export_base + "?format=md",
      class="maked-ss-btn maked-ss-btn--link",
      "Export Markdown",
    ),
    @html.a(
      href=export_base + "?format=json",
      class="maked-ss-btn maked-ss-btn--link",
      "Export JSON",
    ),
  ])
  let rename = @html.div(class="maked-ss-rename", [
    @html.label(class="maked-ss-label", for_="maked-ss-rename", "Rename"),
    @html.input(
      id="maked-ss-rename",
      class="maked-ss-input",
      value=rename_text(model),
      maxlength=120,
      on_input=emit.map(fn(text) { SessionRenameChanged(text) }),
    ),
    @html.button(
      class="maked-ss-btn",
      on_click=emit(RenameSessionClicked),
      "Rename",
    ),
  ])
  // How many steps the session has, and how many of them are off the path.
  // The second number is the branches: steps that were taken and then walked
  // back from. They are still recorded, and a reader should know they exist.
  let count_text = model.session_path.length().to_string() +
    " steps on this path"
  let count_text = if model.session_others.length() == 0 {
    count_text
  } else {
    count_text +
    " · " +
    model.session_others.length().to_string() +
    " other steps recorded"
  }
  let head = @html.div(class="maked-ss-head", [
    @html.h3(class="maked-ss-current-name", active.name),
    @html.span(class="maked-ss-current-count", count_text),
    @html.div(class="maked-ss-head-actions", [rename, exports]),
  ])
  let step_items : Array[@html.Html] = []
  for step in model.session_path {
    step_items.push(
      @html.li(class="maked-ss-step", [
        @html.div(class="maked-ss-step-head", [
          @html.span(class="maked-ss-step-index", step.index.to_string()),
          @html.span(class="maked-ss-step-domain", step.domain),
          @html.span(class="maked-ss-step-slot", step.slot_designation),
          @html.span(class="maked-ss-step-outcome", step.outcome),
          @html.span(class="maked-ss-step-source", step.source),
        ]),
        // The sentence first: what the step did, in words a reader can
        // follow. The labels above are the machine's vocabulary, for the
        // person who knows it; this is the same step in theirs.
        @html.p(class="maked-ss-step-narration", step.narration),
        @html.p(class="maked-ss-step-detail", step.detail),
        @html.p(class="maked-ss-step-why", step.why),
        @html.div(class="maked-ss-step-actions", [
          @html.button(
            class="maked-ss-btn",
            on_click=emit(ReplayStepClicked(step.id)),
            "Go back to here",
          ),
          @html.button(
            class="maked-ss-btn",
            on_click=emit(BranchStepClicked(step.id)),
            "Fork from here",
          ),
        ]),
      ]),
    )
  }
  let timeline = if model.session_path.length() == 0 {
    @html.p(
      class="maked-ss-empty",
      "No steps yet. Take one in the Loop panel and it will be recorded here.",
    )
  } else {
    @html.ol(class="maked-ss-timeline", step_items)
  }
  let other_items : Array[@html.Html] = []
  for step in model.session_others {
    other_items.push(
      @html.li(class="maked-ss-other", [
        @html.span(class="maked-ss-step-index", step.index.to_string()),
        @html.span(class="maked-ss-step-domain", step.domain),
        @html.span(class="maked-ss-step-slot", step.slot_designation),
        @html.span(class="maked-ss-step-outcome", step.outcome),
        @html.span(class="maked-ss-other-detail", step.detail),
      ]),
    )
  }
  let others = if model.session_others.length() == 0 {
    @html.nothing
  } else {
    @html.div(class="maked-ss-others", [
      @html.h3(class="maked-ss-subtitle", "Other roads taken"),
      @html.p(
        class="maked-ss-note",
        "These steps are recorded in the session but are not on its current path: the branches that were walked and then walked back from.",
      ),
      @html.ul(class="maked-ss-others-list", other_items),
    ])
  }
  let list_items : Array[@html.Html] = []
  for session in model.sessions {
    let active_class = if session.active {
      " maked-ss-item--active"
    } else {
      ""
    }
    let pending = model.session_delete_pending == session.id
    let delete_label = if pending { "Really delete?" } else { "Delete" }
    list_items.push(
      @html.li(class="maked-ss-item\{active_class}", [
        @html.span(class="maked-ss-item-name", session.name),
        @html.span(
          class="maked-ss-item-steps",
          session.steps.to_string() + " steps",
        ),
        @html.button(
          class="maked-ss-btn",
          on_click=emit(OpenSessionClicked(session.id)),
          "Open",
        ),
        @html.button(
          class="maked-ss-btn maked-ss-btn--danger",
          title="Delete this session and every step in it",
          on_click=emit(DeleteSessionClicked(session.id)),
          delete_label,
        ),
      ]),
    )
  }
  let all_sessions = @html.div(class="maked-ss-list", [
    @html.h3(class="maked-ss-subtitle", "All sessions"),
    if model.sessions.length() == 0 {
      @html.p(class="maked-ss-empty", "No sessions yet.")
    } else {
      @html.ul(class="maked-ss-items", list_items)
    },
  ])
  // What the last few steps add up to, above the timeline that lists them
  // one by one. The timeline answers "what did this step do"; this answers
  // "what have these steps done between them", which is the question the
  // timeline alone leaves a reader to work out.
  let summary = if model.session_summary == "" {
    @html.nothing
  } else {
    @html.div(class="maked-ss-summary", [
      @html.h3(class="maked-ss-subtitle", "The run so far"),
      @html.p(class="maked-ss-summary-text", model.session_summary),
    ])
  }
  @html.section(class="maked-sessions", [
    @html.h2(class="maked-ss-title", "Sessions"),
    @html.p(
      class="maked-ss-lede",
      "A session is one exploration, kept. Name it, take steps in it, and come back to it later: the steps are stored with the machine, not in the page, so a restart does not lose them.",
    ),
    compose,
    status,
    head,
    summary,
    metrics_block(model.session_metrics),
    @html.div(class="maked-ss-timeline-section", [
      @html.h3(class="maked-ss-subtitle", "Timeline"),
      timeline,
    ]),
    others,
    all_sessions,
  ])
}

///|
/// The name in the rename box: what the user typed, or the session's own
/// name when they have not typed anything.
///
/// The input shows the session's name until it is typed into, so the box
/// never has to be synced back from the server: a rename that arrived from
/// somewhere else would otherwise leave a stale name in the box.
fn rename_text(model : Model) -> String {
  if model.session_rename_draft == "" {
    model.active_session.name
  } else {
    model.session_rename_draft
  }
}

///|
/// The workspace: the user's own records.
///
/// This is the first screen in MAKED that holds something the user wrote, so
/// it is built around three rules:
///
///   - Nothing happens silently. Every outcome -- saved, refused, unreachable
///     -- says so in words, in the same place, every time.
///   - The domain is chosen by pressing it, not by picking from a dropdown.
///     The five letters are the whole vocabulary, and a row of five buttons
///     says that at a glance where a collapsed dropdown hides it.
///   - The records already saved sit next to the form that made them, so the
///     result of a save is visible where the save happened.
pub fn workspace_view(emit : @cmd.Emit[Msg], model : Model) -> @html.Html {
  let domain_buttons : Array[@html.Html] = []
  for letter in model.entry_domains {
    let active = if letter == model.draft_domain {
      " maked-ws-domain--active"
    } else {
      ""
    }
    domain_buttons.push(
      @html.button(
        class="maked-ws-domain\{active}",
        on_click=emit(DraftDomainClicked(letter)),
        letter,
      ),
    )
  }
  let target = if model.draft_domain == "" {
    "a domain"
  } else {
    "the " + model.draft_domain + " domain"
  }
  let form = @html.div(class="maked-ws-form", [
    @html.p(class="maked-ws-question", "Which domain does this belong to?"),
    @html.div(class="maked-ws-domains", domain_buttons),
    @html.label(class="maked-ws-label", for_="maked-ws-title", "Title"),
    @html.input(
      id="maked-ws-title",
      class="maked-ws-input",
      placeholder="The model, the dataset, the failure",
      value=model.draft_title,
      maxlength=200,
      on_input=emit.map(fn(text) { DraftTitleChanged(text) }),
    ),
    @html.label(class="maked-ws-label", for_="maked-ws-body", "What happened"),
    @html.textarea(
      id="maked-ws-body",
      class="maked-ws-textarea",
      rows=5,
      placeholder="What you tried, what came out, and what you think it means.",
      value=model.draft_body,
      on_input=emit.map(fn(text) { DraftBodyChanged(text) }),
      @html.nothing,
    ),
    @html.button(
      class="maked-ws-save",
      on_click=emit(DraftSubmitClicked),
      "Save to \{target}",
    ),
  ])
  let status = if model.workspace_error != "" {
    @html.p(class="maked-ws-error", model.workspace_error)
  } else if model.workspace_notice != "" {
    @html.p(class="maked-ws-notice", model.workspace_notice)
  } else {
    @html.nothing
  }
  let entry_items : Array[@html.Html] = []
  for entry in model.entries {
    entry_items.push(
      @html.li(class="maked-ws-entry", [
        @html.span(class="maked-ws-entry-domain", entry.domain),
        @html.span(class="maked-ws-entry-title", entry.title),
        @html.p(class="maked-ws-entry-body", entry.body),
        @html.span(class="maked-ws-entry-time", entry.created_at),
        @html.button(
          class="maked-ws-entry-delete",
          on_click=emit(EntryDeleteClicked(entry.id)),
          "Delete",
        ),
      ]),
    )
  }
  let entries_list = if model.entries.length() == 0 {
    @html.p(
      class="maked-ws-empty",
      "Nothing here yet. The first record is usually the thing you most want to forget about.",
    )
  } else {
    @html.ul(class="maked-ws-entries", entry_items)
  }
  @html.section(class="maked-workspace", [
    @html.h2(class="maked-ws-heading", "Workspace"),
    @html.p(
      class="maked-ws-lede",
      "Everything else here is the project's own words. This part is yours: put a model, a dataset, or a failure you want to understand into the domain it belongs to, and it stays on this machine.",
    ),
    @html.div(class="maked-ws-columns", [
      @html.div(class="maked-ws-compose", [form, status]),
      @html.div(class="maked-ws-list", [
        @html.h3(class="maked-ws-list-title", "Your records"),
        entries_list,
      ]),
    ]),
  ])
}
