///| Response helpers.
///
/// moonback's `Responder` owns the socket and is only valid for the duration of
/// one request, so a handler must finish writing before it returns. These
/// helpers keep that discipline in one place and give handlers Flask-ish
/// vocabulary instead of raw status codes and header arrays.

///|
/// JSON response payload plus the status and headers a handler wants.
pub(all) struct Response {
  status : Int
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
pub fn Response::text(body : String, status? : Int = 200) -> Response {
  { status, headers: [], body: Text(body) }
}

///|
pub fn Response::json(body : Json, status? : Int = 200) -> Response {
  { status, headers: [], body: Json(body) }
}

///|
pub fn Response::with_header(
  self : Response,
  name : String,
  value : String,
) -> Response {
  { status: self.status, headers: [..self.headers, (name, value)], body: self.body }
}

///|
async fn Response::send(self : Response, res : @moonback.Responder) -> Unit {
  match self.body {
    Empty => res.send_void(status=self.status, headers=self.headers)
    Text(text) => res.send_text(text, status=self.status, headers=self.headers)
    Json(json) => res.send_json(json, status=self.status, headers=self.headers)
  }
}
