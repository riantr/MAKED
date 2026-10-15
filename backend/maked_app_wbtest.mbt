///| maked_app whitebox tests.
///
/// The SPA fallback logic is load-bearing: it distinguishes browser navigations
/// (which should get index.html) from API 404s and asset requests (which should
/// not). The `strip_query_and_fragment` function is pure and easy to test.
/// The `wants_spa_shell` function requires a full `@moonback.Request` which is
/// difficult to construct in tests (Context and RequestBody are opaque types),
/// so it is tested indirectly through integration tests rather than unit tests.

///|
/// strip_query_and_fragment removes query strings.
test "strip_query_and_fragment removes query string" {
  assert_eq(strip_query_and_fragment("/path?query=value"), "/path")
}

///|
/// strip_query_and_fragment removes fragments.
test "strip_query_and_fragment removes fragment" {
  assert_eq(strip_query_and_fragment("/path#section"), "/path")
}

///|
/// strip_query_and_fragment removes both query and fragment.
test "strip_query_and_fragment removes both query and fragment" {
  assert_eq(strip_query_and_fragment("/path?q=1#frag"), "/path")
}

///|
/// strip_query_and_fragment leaves clean paths unchanged.
test "strip_query_and_fragment leaves clean path unchanged" {
  assert_eq(strip_query_and_fragment("/clean/path"), "/clean/path")
}

///|
/// strip_query_and_fragment handles empty query.
test "strip_query_and_fragment handles empty query" {
  assert_eq(strip_query_and_fragment("/path?"), "/path")
}

///|
/// strip_query_and_fragment handles empty fragment.
test "strip_query_and_fragment handles empty fragment" {
  assert_eq(strip_query_and_fragment("/path#"), "/path")
}

///|
/// strip_query_and_fragment handles query with special characters.
test "strip_query_and_fragment handles query with special chars" {
  assert_eq(
    strip_query_and_fragment("/api/pages?slug=about&lang=zh"),
    "/api/pages",
  )
}

///|
/// strip_query_and_fragment handles fragment before query.
test "strip_query_and_fragment stops at fragment even if query follows" {
  // In URLs, # comes after ?, so "path#frag?query" means the fragment is "frag?query"
  assert_eq(strip_query_and_fragment("/path#frag?query"), "/path")
}

///|
/// strip_query_and_fragment handles root path.
test "strip_query_and_fragment handles root path" {
  assert_eq(strip_query_and_fragment("/"), "/")
}

///|
/// strip_query_and_fragment handles root with query.
test "strip_query_and_fragment handles root with query" {
  assert_eq(strip_query_and_fragment("/?ref=home"), "/")
}
