// The MAKED mark: five domain nodes on a closed ring around a taijitu.
//
// Redrawn as SVG from the original `logo-maked.jpg` rather than reused as a
// bitmap, so it scales, themes with the rest of the site, and stays crisp.
//
// Two details are load-bearing and were read off the original image rather
// than assumed:
//
//   - The ring runs **clockwise M -> D -> E -> A -> K**, which is not the
//     order the name is spelled. A is at the lower left, K at the upper left.
//     Any "obvious" M-A-K-E-D ordering would silently contradict the mark.
//   - Each node keeps the colour it has in the original: M indigo, D green,
//     E red, A yellow, K grey. K is deliberately the muted one, matching the
//     source image where the knowledge node is grey rather than a fifth
//     saturated hue.
//
// The letters are HTML positioned over the SVG rather than SVG `<text>`.
// rabbita's `svg.text` takes only a string with no position, and its `Attrs`
// type is opaque with no public constructor, so there is no supported way to
// place SVG text. Overlaying HTML keeps the letters in the page font, lets
// them scale with the container, and sidesteps the gap entirely.

///|
/// Node letters and colours, clockwise from the top.
/// A function rather than a `const`: MoonBit only allows immutable primitives
/// in constants, and this is a list of tuples.
///
/// Public, and with `node_xy`/`node_percent` purely so `frontend_test.mbt`
/// can pin the mark: `_test.mbt` is a blackbox package and sees only `pub`.
/// The letters-in-ring-order property is the one thing here a plausible
/// plausible "tidying" would break while still rendering a plausible logo.
pub fn nodes() -> Array[(String, String)] {
  [
    ("M", "#2c3e9e"),
    ("D", "#27ae60"),
    ("E", "#e74c3c"),
    ("A", "#f1c40f"),
    ("K", "#7f8c8d"),
  ]
}

///|
/// The SVG coordinate space; the viewBox is 0 0 200 200.
const VIEW : Int32 = 200

// Private on purpose: the tests assert literal coordinates rather than
// recomputing them from these, because an expectation derived from the
// implementation's own inputs cannot fail when those inputs change.

///|
const CX : Int32 = 100

///|
const CY : Int32 = 100

///|
const RING_R : Int32 = 68

///|
const NODE_R : Int32 = 22

///|
/// Angle in radians for node `i` of 5, clockwise from straight up.
fn node_angle(i : Int32) -> Double {
  // 72 degrees per node; -90 degrees puts node 0 at the top.
  let degrees = -90.0 + 72.0 * i.to_double()
  degrees * 3.141592653589793 / 180.0
}

///|
/// Integer centre for node `i`. SVG coordinates are `Int`, so the trig is
/// rounded rather than left fractional.
pub fn node_xy(i : Int32) -> (Int32, Int32) {
  let angle = node_angle(i)
  let x = CX.to_double() + RING_R.to_double() * @math.cos(angle)
  let y = CY.to_double() + RING_R.to_double() * @math.sin(angle)
  (x.round().to_int(), y.round().to_int())
}

///|
/// The same centre as a percentage of the viewBox, for the HTML overlay.
pub fn node_percent(i : Int32) -> (String, String) {
  let (x, y) = node_xy(i)
  (
    (x.to_double() * 100.0 / VIEW.to_double()).to_string() + "%",
    (y.to_double() * 100.0 / VIEW.to_double()).to_string() + "%",
  )
}

///|
/// The taijitu at the centre: a light half and a dark half meeting in an S,
/// with a dot of the opposite colour in each lobe. Same construction as the
/// original image.
fn taijitu() -> @svg.Svg {
  let r = 26
  let half = r / 2
  @svg.g([
    // left half, light
    @svg.path(
      d="M \{CX} \{CY - r} A \{r} \{r} 0 0 0 \{CX} \{CY + r} Z",
      fill="#d8d8d8",
    ),
    // right half, dark
    @svg.path(
      d="M \{CX} \{CY - r} A \{r} \{r} 0 0 1 \{CX} \{CY + r} Z",
      fill="#1c1c1c",
    ),
    // the S: upper lobe dark, lower lobe light
    @svg.path(
      d="M \{CX} \{CY} A \{half} \{half} 0 0 1 \{CX} \{CY - r} A \{half} \{half} 0 0 0 \{CX} \{CY} Z",
      fill="#1c1c1c",
    ),
    @svg.path(
      d="M \{CX} \{CY} A \{half} \{half} 0 0 0 \{CX} \{CY + r} A \{half} \{half} 0 0 1 \{CX} \{CY} Z",
      fill="#d8d8d8",
    ),
    // the two eyes
    @svg.circle(cx=CX + half, cy=CY - half, r=5, fill="#d8d8d8"),
    @svg.circle(cx=CX - half, cy=CY + half, r=5, fill="#1c1c1c"),
  ])
}

///|
/// The ring and the five discs, without letters. `svg.svg` is a *root*
/// element and returns `Html`, not `Svg` -- a `Svg` can only be a child.
fn ring_svg() -> @html.Html {
  let children : Array[@svg.Svg] = [
    @svg.circle(
      cx=CX,
      cy=CY,
      r=RING_R,
      stroke="#a8e6a3",
      stroke_width=6,
      fill="none",
    ),
    taijitu(),
  ]
  for i in 0..<5 {
    let (x, y) = node_xy(i)
    children.push(
      @svg.circle(
        cx=x,
        cy=y,
        r=NODE_R,
        fill=nodes()[i].1,
        stroke="#ffffff",
        stroke_width=2,
      ),
    )
  }
  @svg.svg(
    width=100,
    height=100,
    view_box="0 0 \{VIEW} \{VIEW}",
    xmlns="http://www.w3.org/2000/svg",
    children,
  )
}

///|
/// The letters, positioned over the ring.
fn ring_letters() -> @html.Html {
  @html.div(
    class="maked-ring-letters",
    {
      let letters = []
      for i in 0..<5 {
        let (left, top) = node_percent(i)
        letters.push(
          @html.span(
            class="maked-ring-letter",
            style=["left: " + left, "top: " + top],
            nodes()[i].0,
          ),
        )
      }
      letters
    },
  )
}

///|
/// The complete mark with letters, for the index hero.
pub fn logo(size : Int32) -> @html.Html {
  @html.div(
    class="maked-mark",
    style=["width: \{size}px", "height: \{size}px"],
    [ring_svg(), ring_letters()],
  )
}

///|
/// A compact variant for the header: the ring without the letter text, which
/// stays legible at small sizes.
pub fn logo_mark(size : Int32) -> @html.Html {
  @html.div(
    class="maked-mark",
    style=["width: \{size}px", "height: \{size}px"],
    ring_svg(),
  )
}
