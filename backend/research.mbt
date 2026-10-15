///| Arxiv-driven SNN research cycle.
///
/// This module implements the "D" (Data) domain of MAKED: fetching recent
/// Spiking Neural Network papers from arxiv and mapping them to pyroduct
/// triggers so the Loop can be driven by real research output.
///
/// The arxiv API returns Atom XML; we parse the minimal subset needed
/// (entry -> id, title, summary, categories, published).
///
/// Paper -> Trigger mapping heuristic:
///   - "benchmark", "dataset", "evaluation" -> FeelFinitude (Occasion)
///   - "novel", "new method", "propose" -> ActInFreedom (Act)
///   - "outperform", "state-of-the-art", "improve" -> AbsorbGlory (Feedback)
///   - "fail", "limitation", "challenge" -> Sting (Feedback)
///   - "review", "survey", "overview" -> KeepContinuity (Hold)
///   - Default -> TouchFuture (Antecedent)

///|
pub(all) struct Paper {
  id : String
  title : String
  summary : String
  authors : Array[String]
  categories : Array[String]
  published : String
  link : String
} derive(Eq, Debug)

///|
pub extend Paper with Eq::{not_equal, equal}

///|
pub extend Paper with Debug::{to_repr}

///|
/// The arxiv API base URL.
const ARXIV_API : String = "http://export.arxiv.org/api/query"

///|
/// SNN-related search terms for arxiv.
const SNN_QUERY : String = "(all:spiking+AND+all:neural+AND+all:network)+OR+all:SNN+OR+(ti:spiking+AND+ti:network)"

///|
/// Fetch recent SNN papers from arxiv.
pub async fn fetch_snn_papers(max_results : Int32) -> Array[Paper] {
  let url = "\{ARXIV_API}?search_query=\{SNN_QUERY}&start=0&max_results=\{max_results}&sortBy=submittedDate&sortOrder=descending"
  let client = @http.Client(url) catch { _ => return [] }
  defer client.close()
  let response = client.get("/") catch { _ => return [] }
  if response.code != 200 {
    return []
  }
  let body = client.read_all().text().to_string() catch { _ => return [] }
  parse_arxiv_response(body)
}

///|
/// Parse the arxiv Atom XML response into papers.
fn parse_arxiv_response(body : String) -> Array[Paper] {
  let papers : Array[Paper] = []
  let entries = split_entries(body)
  for entry in entries {
    match parse_entry(entry) {
      Some(paper) => papers.push(paper)
      None => ()
    }
  }
  papers
}

///|
/// Split the XML body into individual <entry>...</entry> blocks.
fn split_entries(body : String) -> Array[String] {
  let entries : Array[String] = []
  let open_tag = "<entry>"
  let close_tag = "</entry>"
  let mut pos = 0
  while pos < body.length() {
    match body.find(open_tag) {
      Some(start) if start >= pos => {
        let content_start = start + open_tag.length()
        match body.find(close_tag) {
          Some(end) if end > content_start => {
            entries.push(body[content_start:end].to_owned())
            pos = end + close_tag.length()
          }
          _ => break
        }
      }
      _ => break
    }
  }
  entries
}

///|
/// Parse a single <entry> block into a Paper.
fn parse_entry(entry : String) -> Paper? {
  let id = extract_tag(entry, "id")
  let title = extract_tag(entry, "title")
  let summary = extract_tag(entry, "summary")
  let published = extract_tag(entry, "published")
  if id == "" || title == "" {
    return None
  }
  let authors = extract_authors(entry)
  let categories = extract_categories(entry)
  let link = extract_link(entry)
  Some({
    id: clean_text(id),
    title: clean_text(title),
    summary: clean_text(summary),
    authors,
    categories,
    published,
    link,
  })
}

///|
/// Extract the content of an XML tag.
fn extract_tag(xml : String, tag : String) -> String {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  match xml.find(open) {
    Some(start) => {
      let content_start = start + open.length()
      match xml.find(close) {
        Some(end) if end > content_start => xml[content_start:end].to_owned()
        _ => ""
      }
    }
    None => ""
  }
}

///|
/// Extract author names from <author><name>...</name></author> blocks.
fn extract_authors(entry : String) -> Array[String] {
  let authors : Array[String] = []
  let open = "<author>"
  let close = "</author>"
  let name_open = "<name>"
  let name_close = "</name>"
  let mut pos = 0
  while pos < entry.length() {
    match entry.find(open) {
      Some(start) if start >= pos =>
        match entry.find(close) {
          Some(end) if end > start => {
            let block = entry[start:end]
            match block.find(name_open) {
              Some(ns) =>
                match block.find(name_close) {
                  Some(ne) if ne > ns => {
                    let name = block[ns + name_open.length():ne].to_owned()
                    authors.push(clean_text(name))
                  }
                  _ => ()
                }
              None => ()
            }
            pos = end + close.length()
          }
          _ => break
        }
      _ => break
    }
  }
  authors
}

///|
/// Extract categories from <category term="..."/> tags.
fn extract_categories(entry : String) -> Array[String] {
  let cats : Array[String] = []
  let tag = "<category "
  let mut pos = 0
  while pos < entry.length() {
    match entry.find(tag) {
      Some(start) if start >= pos =>
        match entry.find("term=\"") {
          Some(term_pos) if term_pos > start => {
            let val_start = term_pos + 6
            match entry.find("\"") {
              Some(val_end) if val_end > val_start => {
                cats.push(entry[val_start:val_end].to_owned())
                pos = val_end + 1
              }
              _ => break
            }
          }
          _ => break
        }
      _ => break
    }
  }
  cats
}

///|
/// Extract the first <link href="..."/> that is an abstract or pdf link.
fn extract_link(entry : String) -> String {
  let tag = "<link "
  let mut pos = 0
  while pos < entry.length() {
    match entry.find(tag) {
      Some(start) if start >= pos =>
        match entry.find("href=\"") {
          Some(href_pos) if href_pos > start => {
            let val_start = href_pos + 6
            match entry.find("\"") {
              Some(val_end) if val_end > val_start => {
                let href = entry[val_start:val_end].to_owned()
                if href.contains("abs/") || href.contains("/pdf") {
                  return href
                }
                pos = val_end + 1
              }
              _ => break
            }
          }
          _ => break
        }
      _ => break
    }
  }
  ""
}

///|
/// Clean whitespace from extracted text.
fn clean_text(s : String) -> String {
  let chars : Array[String] = []
  let mut prev_space = true
  for i in 0..<s.length() {
    let c = s[i].to_string()
    if c == "\n" || c == "\r" || c == "\t" || c == " " {
      if !prev_space {
        chars.push(" ")
        prev_space = true
      }
    } else {
      chars.push(c)
      prev_space = false
    }
  }
  chars.join("").trim().to_owned()
}

///|
/// Map a paper to a pyroduct Trigger based on keyword heuristics.
pub fn paper_to_trigger(paper : Paper) -> @sm.Trigger {
  let text = (paper.title + " " + paper.summary).to_lowercase_ascii()
  if text.contains("state-of-the-art") ||
    text.contains("outperform") ||
    text.contains("sota") {
    return @sm.AbsorbGlory
  }
  if text.contains("limitation") ||
    text.contains("fail") ||
    text.contains("challenge") ||
    text.contains("struggle") {
    return @sm.Sting
  }
  if text.contains("novel") ||
    text.contains("propose") ||
    text.contains("new method") ||
    text.contains("introduce") {
    return @sm.ActInFreedom
  }
  if text.contains("survey") ||
    text.contains("review") ||
    text.contains("overview") ||
    text.contains("tutorial") {
    return @sm.KeepContinuity
  }
  if text.contains("benchmark") ||
    text.contains("dataset") ||
    text.contains("evaluation") {
    return @sm.FeelFinitude
  }
  @sm.TouchFuture
}

///|
/// Map a Trigger to its Slot.
pub fn trigger_to_slot(trigger : @sm.Trigger) -> @sm.Slot {
  trigger.slot()
}

///|
/// Lowercase ASCII characters only (for keyword matching).
fn String::to_lowercase_ascii(self : String) -> String {
  let result = []
  for i in 0..<self.length() {
    let c = self[i]
    let code = c.to_int()
    if code >= 65 && code <= 90 {
      result.push((code + 32).to_uint16())
    } else {
      result.push(c)
    }
  }
  let bytes : Array[UInt16] = result
  bytes
  .map(fn(b) {
    match b.to_char() {
      Some(c) => c.to_string()
      None => ""
    }
  })
  .join("")
}

///|
/// Convert a Paper to JSON for the API.
pub fn Paper::to_json(self : Paper) -> Json {
  {
    "id": self.id,
    "title": self.title,
    "summary": self.summary,
    "authors": self.authors,
    "categories": self.categories,
    "published": self.published,
    "link": self.link,
  }
}

///|
/// Test helpers: expose private functions for blackbox tests.
pub fn to_lowercase_ascii_for_test(s : String) -> String {
  s.to_lowercase_ascii()
}

///|
pub fn clean_text_for_test(s : String) -> String {
  clean_text(s)
}

///|
pub fn extract_tag_for_test(xml : String, tag : String) -> String {
  extract_tag(xml, tag)
}

///|
pub fn split_entries_for_test(body : String) -> Array[String] {
  split_entries(body)
}

///|
pub fn parse_entry_for_test(entry : String) -> Paper? {
  parse_entry(entry)
}
