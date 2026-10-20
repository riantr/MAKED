// Typed accessors over the backend's JSON.
//
// The backend is the only writer of this data, so the shapes here mirror
// `backend/pages.mbt` and `Page::to_json`. Two details of MoonBit's builtin
// `Json` shape the code:
//
//   - A `{ ... }` literal is a `Map`, not a `Json`; it only becomes a `Json`
//     where the expected type is known. Every literal here is annotated.
//   - JSON has a single number type, which surfaces as `Number`. Booleans are
//     the *variants* `True` and `False`, not a `Boolean` constructor.
//
// Each accessor is total: a missing or wrong-typed field yields the supplied
// fallback rather than raising, so one malformed row cannot take down a page.

///|
pub(all) struct Page {
  slug : String
  title : String
  letter : String
  role : String
  summary : String
  body : String
  in_navigation : Bool
  sort : Int32
} derive(Eq)

// `Eq` is not optional here: rabbita's `create_state_with_init` uses it to
// decide whether a re-render is needed. That makes the `implicit_impl_as_method`
// deprecation warning below unavoidable -- declaring `extend Page with
// Eq::{not_equal, equal}` explicitly silences it but trades it for two
// `unused_value` warnings, since nothing calls the promoted forms directly.

///|
pub fn field(json : Json, key : String) -> Json? {
  match json {
    Object(fields) => fields.get(key)
    _ => None
  }
}

///|
/// A nested object, or an empty one.
///
/// A missing nested field is a backend change, not a reason for the page
/// to die: a page that dies on a missing field shows the reader nothing
/// at all, which is worse than showing a row without its number.
pub fn sub(json : Json, key : String) -> Json {
  match field(json, key) {
    Some(value) => value
    None => Json::object({})
  }
}

///|
pub fn get_string(json : Json, key : String, fallback : String) -> String {
  match field(json, key) {
    Some(String(s)) => s
    _ => fallback
  }
}

///|
pub fn get_int(json : Json, key : String, fallback : Int32) -> Int32 {
  match field(json, key) {
    Some(Number(n, ..)) => n.to_int()
    _ => fallback
  }
}

///|
/// The number in a field, or the fallback.
///
/// A JSON number is not a JSON string, so reading one with `get_string`
/// always returns the fallback. The causal panel did exactly that, and so
/// displayed the fallback "0.0" for every estimate it ever made -- a panel
/// that looked right and had never once shown a number.
pub fn get_double(json : Json, key : String, fallback : Double) -> Double {
  match field(json, key) {
    Some(Number(n, ..)) => n
    _ => fallback
  }
}

///|
/// The strings in a list field, or an empty list.
///
/// A field that is missing, or is not a list of strings, yields an empty
/// list rather than raising: one malformed row cannot take down a page.
pub fn get_strings(json : Json, key : String) -> Array[String] {
  let out : Array[String] = []
  match field(json, key) {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(s) => out.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  out
}

///|
/// Public because `loop_state.mbt` decodes the backend's `blocked` /
/// `undecided` flags with it.
pub fn get_bool(json : Json, key : String, fallback : Bool) -> Bool {
  match field(json, key) {
    Some(True) => true
    Some(False) => false
    _ => fallback
  }
}

///|
fn page_from_json(json : Json) -> Page {
  {
    slug: get_string(json, "slug", ""),
    title: get_string(json, "title", ""),
    letter: get_string(json, "letter", ""),
    role: get_string(json, "role", ""),
    summary: get_string(json, "summary", ""),
    body: get_string(json, "body", ""),
    in_navigation: get_bool(json, "in_navigation", false),
    sort: get_int(json, "sort", 0),
  }
}

///|
/// Decode `{"pages": [...]}` into a list of pages. Rows that fail to decode
/// are skipped rather than faked, so a backend change shows up as a missing
/// page instead of a blank one.
pub fn decode_pages(json : Json) -> Array[Page] {
  match field(json, "pages") {
    Some(Array(items)) => items.map(fn(item) { page_from_json(item) })
    _ => []
  }
}

///|
/// The page list in navigation order: `index` first, then the five domains in
/// ring order, then the utility pages.
///
/// Sorted with a comparison function rather than `sort_by` on the subtraction,
/// because the comparator is total-ordered rather than numeric and a plain
/// insertion sort keeps the existing order for equal keys.
pub fn navigation(pages : Array[Page]) -> Array[Page] {
  let items = pages.filter(fn(p) { p.in_navigation })
  let sorted = [..items]
  sorted.sort_by(fn(a, b) { a.sort.compare(b.sort) })
  sorted
}

///|
pub fn find_page(pages : Array[Page], slug : String) -> Page? {
  for page in pages {
    if page.slug == slug {
      return Some(page)
    }
  }
  None
}
