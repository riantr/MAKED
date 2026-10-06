///| A minimal request wrapper over moonback's `Request`.
///
/// It exists to give handlers the two things they reach for constantly --
/// path parameters and query parameters -- without each handler having to
/// remember that moonback keys path params by `StringView` and hides query
/// params behind a `QueryParams` accessor.

///|
pub(all) struct Request(@moonback.Request)

///|
pub fn Request::verb(self : Request) -> String {
  match self.0.meth {
    @http.Get => "GET"
    @http.Head => "HEAD"
    @http.Post => "POST"
    @http.Put => "PUT"
    @http.Delete => "DELETE"
    @http.Patch => "PATCH"
    @http.Options => "OPTIONS"
    @http.Connect => "CONNECT"
    @http.Trace => "TRACE"
  }
}

///|
pub fn Request::path(self : Request) -> String {
  self.0.path.to_owned()
}

///|
/// Look up a `:name` path parameter captured by the route pattern.
pub fn Request::param(self : Request, name : String) -> String? {
  self.0.params.get(name[:]).map(fn(v) { v.to_owned() })
}

///|
/// First value of a query-string parameter, if present.
pub fn Request::query(self : Request, name : String) -> String? {
  self.0.query().get(name[:])
}

///|
pub fn Request::header(self : Request, name : String) -> String? {
  self.0.headers.get(name).map(fn(v) { v.to_owned() })
}

///|
pub fn Request::accepts_json(self : Request) -> Bool {
  match self.header("Accept") {
    Some(accept) => accept.contains("application/json")
    None => false
  }
}
