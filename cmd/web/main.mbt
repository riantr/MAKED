///| Browser entry point.
///
/// `moon build --release --target js cmd/web` emits a single self-contained
/// `main.js` with no import/export statements, so it loads with a plain
/// `<script src>` and needs no bundler or import map.

///|
fn main {
  @frontend.app().mount("app")
}
