///| Response helpers.
///
/// moonback's `Responder` owns the socket and is only valid for the duration of
/// one request, so a handler must finish writing before it returns. These
/// helpers keep that discipline in one place and give handlers Flask-ish
/// vocabulary instead of raw status codes and header arrays.

///|
/// JSON response payload plus the status and headers a handler wants.
pub(all) struct Response {
  status : Int32
  headers : Array[(String, String)]
  body : Body
}

///|
pub(all) enum Body {
  Empty
  Text(String)
  Json(Json)
}

///|
pub fn Response::text(body : String, status~ : Int32 = 200) -> Response {
  { status, headers: [], body: Text(body), }
}

///|
pub fn Response::json(body : Json, status~ : Int32 = 200) -> Response {
  { status, headers: [], body: Json(body), }
}

///|
pub fn Response::with_header(
  self : Response,
  name : String,
  value : String,
) -> Response {
  {
    status: self.status,
    headers: [..self.headers, (name, value)],
    body: self.body,
  }
}

///|
/// The headers to send, with a content type unless the caller named one.
///
/// moonback's `send_text` puts its own `text/plain` in front of the caller's
/// headers, so a response that names its own content type ends up with two
/// of them -- and a message with two `Content-Type` headers has a content
/// type that is neither. Deciding here, where the headers are known, is what
/// keeps the export's `text/markdown` from being shadowed by `text/plain`.
fn with_content_type(
  headers : Array[(String, String)],
  fallback : String,
) -> Array[(String, String)] {
  for (name, _) in headers {
    if name.to_lower() == "content-type" {
      return headers
    }
  }
  [("Content-Type", fallback), ..headers]
}

///|
/// The content type a JSON body is sent with.
///
/// `charset=utf-8` is on the end of it, and it is there for the clients that
/// do not read the JSON spec's promise that a JSON body is UTF-8. The spec
/// says it, and a client that honours the spec never needs the parameter; a
/// client that defaults to Latin-1 -- Windows PowerShell's `Invoke-WebRequest`
/// among them -- mangles every Chinese name in the body into mojibake without
/// it, and no amount of correctness on the server's side fixes that.
///
/// The parameter is harmless where the spec is honoured: a body that is UTF-8
/// says so, and a body that is UTF-8 is what is sent.
pub const JSON_CONTENT_TYPE : String = "application/json; charset=utf-8"

///|
async fn Response::send(self : Response, res : @moonback.Responder) -> Unit {
  match self.body {
    Empty => res.send_void(status=self.status, headers=self.headers)
    Text(text) => {
      // Written through `respond` rather than `send_text`, so that the
      // content type is the one this response chose.
      let writer = res.respond(
        status=self.status,
        headers=with_content_type(self.headers, "text/plain; charset=utf-8"),
      )
      writer.write(text)
    }
    Json(json) => {
      // Written through `respond` rather than `send_json`, because
      // `send_json` puts its own `application/json` in front of the caller's
      // headers -- and a message with two `Content-Type` headers has a
      // content type that is neither. The charset has to be on the one that
      // survives, and there is only one way to have one: write the body.
      let writer = res.respond(
        status=self.status,
        headers=with_content_type(self.headers, JSON_CONTENT_TYPE),
      )
      writer.write(json.stringify())
    }
  }
}
