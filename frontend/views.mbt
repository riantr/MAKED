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
      @html.div(
        class=letter_class,
        on_click=@nav.push_url(target),
        [
          @html.a(href=target, [
            @html.span(class="letter", page.letter),
            @html.span(class="name", page.title),
            @html.span(class="role", page.role),
          ]),
        ],
      ),
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
/// input, and there is no write path in the API to make it so.
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
      "Nothing at /" + slug +
      ". Try one of the five domains, or head back to the index.",
    ),
  ])
}

///|
pub fn loading_view() -> @html.Html {
  @html.article(class="maked-page", [
    @html.p(class="maked-lede", "Loading…"),
  ])
}

///|
pub fn error_view(reason : String) -> @html.Html {
  @html.article(class="maked-page", [
    @html.h1(class="maked-page-title", "Server unavailable"),
    @html.p(class="maked-lede", reason),
  ])
}
