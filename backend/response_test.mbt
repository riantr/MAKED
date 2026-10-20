///| Response helper tests.
///
/// The Response type is a pure data structure. These tests verify the
/// constructors produce the expected shape and that with_header appends
/// correctly.

///|
/// Response::text creates a text response with default status.
test "Response::text creates text body with status 200" {
  let r = @backend.Response::text("hello")
  assert_eq(r.status, 200)
  assert_eq(r.headers.length(), 0)
  match r.body {
    @backend.Text(s) => assert_eq(s, "hello")
    _ => fail("body is not Text")
  }
}

///|
/// Response::text respects custom status.
test "Response::text with custom status" {
  let r = @backend.Response::text("not found", status=404)
  assert_eq(r.status, 404)
  match r.body {
    @backend.Text(s) => assert_eq(s, "not found")
    _ => fail("body is not Text")
  }
}

///|
/// Response::json creates a json response with default status.
test "Response::json creates json body with status 200" {
  let json : Json = { "key": "value" }
  let r = @backend.Response::json(json)
  assert_eq(r.status, 200)
  assert_eq(r.headers.length(), 0)
  match r.body {
    @backend.Json(j) =>
      match j {
        Object(fields) =>
          match fields.get("key") {
            Some(String(s)) => assert_eq(s, "value")
            _ => fail("key is not a string")
          }
        _ => fail("json is not an object")
      }
    _ => fail("body is not Json")
  }
}

///|
/// Response::json respects custom status.
test "Response::json with custom status" {
  let json : Json = { "error": "bad_request" }
  let r = @backend.Response::json(json, status=400)
  assert_eq(r.status, 400)
}

///|
/// Response::with_header appends a header.
test "Response::with_header adds one header" {
  let r = @backend.Response::text("ok")
  let r2 = r.with_header("X-Custom", "value")
  assert_eq(r2.headers.length(), 1)
  assert_eq(r2.headers[0].0, "X-Custom")
  assert_eq(r2.headers[0].1, "value")
}

///|
/// Response::with_header preserves existing headers.
test "Response::with_header appends to existing headers" {
  let r = @backend.Response::text("ok").with_header("X-First", "1")
  let r2 = r.with_header("X-Second", "2")
  assert_eq(r2.headers.length(), 2)
  assert_eq(r2.headers[0].0, "X-First")
  assert_eq(r2.headers[1].0, "X-Second")
}

///|
/// Response::with_header does not mutate the original.
test "Response::with_header returns a new response" {
  let r = @backend.Response::text("ok")
  let r2 = r.with_header("X-Custom", "value")
  assert_eq(r.headers.length(), 0)
  assert_eq(r2.headers.length(), 1)
}

///|
/// Response constructors handle all body types.
test "Response constructors produce correct body types" {
  let text_r = @backend.Response::text("hello")
  let json_r = @backend.Response::json({ "k": "v" })
  match text_r.body {
    @backend.Text(_) => ()
    _ => fail("text response has wrong body type")
  }
  match json_r.body {
    @backend.Json(_) => ()
    _ => fail("json response has wrong body type")
  }
}

///|
/// The JSON body says what it is written in.
///
/// The JSON spec says a JSON body is UTF-8, and a client that reads the spec
/// never needs to be told. A client that does not read the spec -- Windows
/// PowerShell's `Invoke-WebRequest` is one -- falls back to Latin-1, and then
/// every Chinese name in the body arrives as mojibake. The charset is the one
/// word that stops that, and it is on the content type because there is
/// nowhere else to put it.
test "a JSON body says that it is written in UTF-8" {
  let content_type = @backend.JSON_CONTENT_TYPE
  assert_true(content_type.contains("application/json"))
  assert_true(content_type.contains("charset=utf-8"))
}
