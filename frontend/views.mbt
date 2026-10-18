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
      @html.nav(class="maked-nav", [
        @html.ul(
          pages.map(fn(page) {
            let active = if page.slug == current { " active" } else { "" }
            let target = "/" + page.slug
            @html.li(class=active, on_click=@nav.push_url(target), [
              @html.a(href=target, page.title),
            ])
          }),
        ),
      ]),
    ]),
  ])
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
      let current = @html.div(class="maked-loop-current", [
        @html.span(class="maked-loop-domain", status.current_domain),
        @html.span(class="maked-loop-sep", "·"),
        @html.span(class="maked-loop-position", status.current_position),
        @html.span(class="maked-loop-gloss", status.current_gloss),
        @html.span(class="maked-loop-sep", "·"),
        @html.span(class="maked-loop-drive", "drive: \{status.drive_slot}"),
      ])
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
        buttons,
        slot_selector,
        history,
        error,
      ])
    }
  }
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
