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
    Json(json) => res.send_json(json, status=self.status, headers=self.headers)
  }
}
