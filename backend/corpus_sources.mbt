///| Reading the documents a corpus names.
///
/// Three sources, three ways of asking the same question -- "what is there to
/// read?" -- and one answer shape, so that the mapping table and the causal
/// analysis never have to know where a document came from.
///
/// The arxiv reader is the one this project was built on. The feed reader
/// reads a subscription the reader already has. The local reader reads the
/// reader's own files, and the kind of a file says how to read it: `.txt`
/// and `.md` are read as text, `.pdf` is read through a PDF reader that
/// turns it into markdown, and `.json` is read as a Zotero CSL-JSON export.
///
/// A file of a kind MAKED does not know is left alone rather than guessed
/// at. A folder of notes that happens to sit next to a photo should give the
/// notes and not a broken document.

///|
/// The arxiv API base URL.
const ARXIV_API : String = "http://export.arxiv.org/api/query"

///|
/// SNN-related search terms for arxiv.
///
/// The corpus the project was built on, kept as it was: a reader who has not
/// chosen a corpus gets this one, and changing it would change what the
/// built-in example means.
const SNN_QUERY : String = "(all:spiking+AND+all:neural+AND+all:network)+OR+all:SNN+OR+(ti:spiking+AND+ti:network)"

///|
/// The extensions the local reader knows how to read.
fn is_readable_extension(path : String) -> Bool {
  let lower = path.to_lower()
  lower.has_suffix(".txt") ||
  lower.has_suffix(".md") ||
  lower.has_suffix(".markdown") ||
  lower.has_suffix(".pdf") ||
  lower.has_suffix(".json")
}

///|
/// Whether a path names a PDF.
fn is_pdf_path(path : String) -> Bool {
  path.to_lower().has_suffix(".pdf")
}

///|
/// Whether a path names a JSON file.
fn is_json_path(path : String) -> Bool {
  path.to_lower().has_suffix(".json")
}

///|
/// The documents a corpus gives, read through the reader it names.
pub async fn fetch_corpus(config : CorpusConfig) -> Array[Document] {
  match config.kind {
    Arxiv => fetch_arxiv_documents(config.query, config.max_results)
    Rss => fetch_rss_documents(config.url, config.max_results)
    Local => read_local_documents(config.source_path, config.max_results)
  }
}

///|
/// Read recent documents from arxiv.
///
/// The address is the whole request: the query goes into it, and the reader
/// is asked for the full URL rather than for a client and a path, because a
/// client built from a URL that carries a path is a client that refuses to
/// be built at all. That refusal was silent: the old reader asked arxiv for
/// a path it could not name, the answer was an empty list, and the panel
/// showed an empty list as if the reader had read nothing at all.
pub async fn fetch_arxiv_documents(
  query : String,
  max_results : Int32,
) -> Array[Document] {
  let url = "\{ARXIV_API}?search_query=\{query}&start=0&max_results=\{max_results}&sortBy=submittedDate&sortOrder=descending"
  let body = fetch_text(url)
  if body == "" {
    return []
  }
  limit_documents(parse_feed(body), max_results)
}

///|
/// Read the documents in an RSS or Atom feed.
///
/// The feed is the reader's own subscription, so the reader already knows
/// what is in it; MAKED's job is only to read it.
pub async fn fetch_rss_documents(
  url : String,
  max_results : Int32,
) -> Array[Document] {
  let body = fetch_text(url)
  if body == "" {
    return []
  }
  limit_documents(parse_feed(body), max_results)
}

///|
/// Read the documents in a file or a folder on this machine.
///
/// A folder is read in path order, not in whatever order the filesystem
/// hands back. A corpus read in a different order on every run is a corpus
/// that drives the loop differently every run, and a reader who replays
/// yesterday's session would not get yesterday's steps.
pub async fn read_local_documents(
  path : String,
  max_results : Int32,
) -> Array[Document] {
  if !@fs.exists(path) {
    println("error: the local corpus \{path} does not exist")
    return []
  }
  let kind = @fs.kind(path)
  let files : Array[String] = if kind == Directory {
    collect_files(path)
  } else {
    [path]
  }
  let documents : Array[Document] = []
  for file in files {
    if documents.length() >= max_results {
      break
    }
    if !is_readable_extension(file) {
      continue
    }
    match read_local_file(file) {
      Some(document) => documents.push(document)
      None => ()
    }
  }
  documents
}

///|
/// Every file under a folder, in path order.
///
/// The folder is walked with a work list rather than by recursion, so that a
/// deep tree cannot run out of stack, and the result is sorted so that the
/// order the documents are read in is the order their names say.
async fn collect_files(root : String) -> Array[String] {
  let found : Array[String] = []
  let pending : Array[String] = [root]
  while pending.length() > 0 {
    let directory = match pending.pop() {
      Some(value) => value
      None => break
    }
    let names = @fs.readdir(directory) catch { _ => continue }
    for name in names {
      let full = join_path(directory, name)
      match @fs.kind(full) {
        Regular => found.push(full)
        Directory => pending.push(full)
        _ => ()
      }
    }
  }
  sorted_paths(found)
}

///|
/// The paths, in path order.
///
/// The order a filesystem hands entries back is not an order a reader can
/// predict, and a corpus read in that order drives the loop differently
/// every time. Sorting the names is what makes a folder a corpus rather
/// than a lottery: the same folder, the same documents, the same steps.
pub fn sorted_paths(paths : Array[String]) -> Array[String] {
  let sorted = paths.copy()
  sorted.sort_by(fn(a, b) { compare_paths(a, b) })
  sorted
}

///|
/// The order two paths are in.
///
/// MoonBit's own string order is by length first and only then by content,
/// which puts "notes/b.txt" before "notes/a/first.txt" -- a folder read in
/// that order is a folder read in an order no reader would predict, and it
/// looks sorted while it is not. Paths are therefore compared the way a
/// reader reads them: from the first character, and by length only when one
/// path is a prefix of the other.
pub fn compare_paths(a : String, b : String) -> Int32 {
  let la = a.length()
  let lb = b.length()
  let shortest = if la < lb { la } else { lb }
  let mut i = 0
  while i < shortest {
    let ca = a[i].to_int()
    let cb = b[i].to_int()
    if ca != cb {
      return if ca < cb { -1 } else { 1 }
    }
    i += 1
  }
  if la == lb {
    0
  } else if la < lb {
    -1
  } else {
    1
  }
}

///|
/// A path made of a directory and a name.
///
/// The separator is the one this platform uses, because a path that reads
/// one way on the machine it was made and another way when it is shown is a
/// path the reader cannot copy.
fn join_path(directory : String, name : String) -> String {
  if directory.has_suffix("/") || directory.has_suffix("\\") {
    directory + name
  } else if directory.contains("\\") {
    directory + "\\" + name
  } else {
    directory + "/" + name
  }
}

///|
/// Read one local file, according to what kind of file it is.
///
/// None when the file cannot be read, with the reason printed: a file that
/// was counted and not read is a document the reader believes was read.
pub async fn read_local_file(path : String) -> Document? {
  if is_pdf_path(path) {
    return read_pdf_file(path)
  }
  let text = @fs.read_file(path).text() catch {
    err => {
      println("error: \{path} unreadable: \{err}")
      return None
    }
  }
  if is_json_path(path) {
    let documents = parse_csl_json(text)
    if documents.length() == 0 {
      println(
        "note: \{path} holds no Zotero CSL-JSON items, so it was left alone",
      )
      return None
    }
    return Some(documents[0])
  }
  Some(document_from_text(path, text))
}

///|
/// Read a PDF as the markdown it holds.
///
/// A PDF that cannot be read is refused rather than read as an empty
/// document: an empty document is a document that says nothing, and the
/// mapping table would answer "nothing" for it as if the reader had read it.
pub async fn read_pdf_file(path : String) -> Document? {
  let data = @fs.read_file(path) catch {
    err => {
      println("error: \{path} unreadable: \{err}")
      return None
    }
  }
  let text = @pdflite_md.pdf_bytes_to_markdown(data.binary()) catch {
    err => {
      println("error: \{path} is not a PDF MAKED can read: \{err}")
      return None
    }
  }
  Some(document_from_text(path, text))
}

///|
/// A document made of a piece of text.
///
/// The title is the document's own first line, or its first heading when it
/// has one. A file called `notes.txt` whose first line is "What we learned
/// from the failed launch" should be listed under that sentence and not
/// under its name.
pub fn document_from_text(path : String, text : String) -> Document {
  {
    id: path,
    title: title_of_text(text),
    summary: text,
    authors: [],
    categories: [],
    published: "",
    link: "",
  }
}

///|
/// Whether a line is a page marker rather than a title.
///
/// A PDF read as markdown is a list of pages, and the converter marks each
/// one with a heading. A document called "Page 1" is a document called
/// nothing at all, so a line that says nothing but which page it is says
/// nothing about the document either.
fn is_page_marker(line : String) -> Bool {
  let trimmed = line.trim().to_owned()
  if !trimmed.has_prefix("Page ") && !trimmed.has_prefix("page ") {
    return false
  }
  let rest = trimmed[5:].to_owned().trim()
  if rest == "" {
    return false
  }
  for c in rest.iter() {
    if !(c >= '0' && c <= '9') {
      return false
    }
  }
  true
}

///|
/// The title of a piece of text: its first heading, or its first line.
///
/// A heading is preferred because markdown files have one and text files do
/// not, and the first line of a text file is usually the title anyway. A
/// page marker is not a heading: it says which page it is, not what the
/// document is called.
fn title_of_text(text : String) -> String {
  let mut heading = ""
  let mut first_line = ""
  for raw in text.split("\n") {
    let line = raw.trim().to_owned()
    if line == "" || is_page_marker(line) {
      continue
    }
    if line.has_prefix("#") {
      let candidate = line.trim_start(chars="#").trim().to_owned()
      if candidate != "" && !is_page_marker(candidate) && heading == "" {
        heading = candidate
      }
      continue
    }
    if first_line == "" {
      first_line = line
    }
  }
  if heading != "" {
    return clip(heading, 120)
  }
  if first_line != "" {
    return clip(first_line, 120)
  }
  "Untitled"
}

///|
/// A string cut to a length, with three dots when it was cut.
///
/// A title is a label, and a label that is a whole paragraph is a label
/// nobody can scan. The cut is made on a character boundary: a title that
/// ends in half a character renders as a question mark, and a title with a
/// question mark in it is a title the reader cannot copy.
fn clip(text : String, limit : Int32) -> String {
  if text.char_length() <= limit {
    return text
  }
  let chars : Array[String] = []
  let mut count = 0
  for c in text.iter() {
    if count < limit {
      chars.push(c.to_string())
      count += 1
    }
  }
  chars.join("") + "..."
}

///|
/// The documents a Zotero CSL-JSON export holds.
///
/// Zotero exports an array of items, and some tools wrap that array in an
/// object under "items"; both are read, because a reader's export is the
/// one file they are sure of, and refusing it because of a wrapper would be
/// refusing the reader's file for a reason they cannot see.
///
/// A `.json` file that is not CSL-JSON at all is not a corpus: it is read,
/// found to hold no items, and left alone.
pub fn parse_csl_json(text : String) -> Array[Document] {
  let json = @json.parse(text) catch { _ => return [] }
  let items = match json {
    Array(values) => values
    Object(fields) =>
      match fields.get("items") {
        Some(Array(values)) => values
        _ => return []
      }
    _ => return []
  }
  let documents : Array[Document] = []
  for item in items {
    let title = json_string(item, "title")
    if title == "" {
      continue
    }
    let id = match json_string(item, "id") {
      "" => title
      value => value
    }
    let summary = match json_string(item, "abstract") {
      "" => json_string(item, "note")
      value => value
    }
    let link = match json_string(item, "URL") {
      "" => json_string(item, "url")
      value => value
    }
    let categories = json_strings(item, "subject")
    for keyword in json_strings(item, "keyword") {
      categories.push(keyword)
    }
    let item_type = json_string(item, "type")
    if item_type != "" {
      categories.push(item_type)
    }
    documents.push({
      id,
      title,
      summary,
      authors: csl_authors(item),
      categories,
      published: csl_date(item),
      link,
    })
  }
  documents
}

///|
/// The authors of a CSL-JSON item.
///
/// CSL writes an author either as a name object with a given name and a
/// family name, or as a plain string. Both are read, because both are what
/// the tools that produce the export produce.
fn csl_authors(item : Json) -> Array[String] {
  let authors : Array[String] = []
  for entry in json_array(item, "author") {
    match entry {
      Object(fields) => {
        let given = match fields.get("given") {
          Some(String(value)) => value
          _ => ""
        }
        let family = match fields.get("family") {
          Some(String(value)) => value
          _ => ""
        }
        let literal = match fields.get("literal") {
          Some(String(value)) => value
          _ => ""
        }
        if literal != "" {
          authors.push(literal)
        } else if family != "" {
          authors.push(if given == "" { family } else { given + " " + family })
        } else if given != "" {
          authors.push(given)
        }
      }
      String(value) => authors.push(value)
      _ => ()
    }
  }
  authors
}

///|
/// The date of a CSL-JSON item.
///
/// Only as much of the date as the item actually says: a year is a year and
/// is written as one, because writing "2020-01-01" for an item that only
/// said "2020" says something the item did not say.
fn csl_date(item : Json) -> String {
  let issued = match json_field(item, "issued") {
    Some(value) => value
    None => return ""
  }
  let parts = match json_field(issued, "date-parts") {
    Some(Array(values)) => values
    _ => return ""
  }
  if parts.length() == 0 {
    return ""
  }
  let first = match parts[0] {
    Array(values) => values
    _ => return ""
  }
  if first.length() == 0 {
    return ""
  }
  let year = match first[0] {
    Number(value, ..) => value.to_int().to_string()
    _ => return ""
  }
  if first.length() == 1 {
    return year
  }
  let month = match first[1] {
    Number(value, ..) => pad_two(value.to_int())
    _ => return year
  }
  if first.length() == 2 {
    return year + "-" + month
  }
  let day = match first[2] {
    Number(value, ..) => pad_two(value.to_int())
    _ => return year + "-" + month
  }
  year + "-" + month + "-" + day
}

///|
/// A number written with two digits, so that a month is "05" and not "5".
fn pad_two(number : Int32) -> String {
  if number < 10 {
    "0" + number.to_string()
  } else {
    number.to_string()
  }
}

///|
/// The documents in a feed body.
///
/// A feed is either Atom -- `<entry>` -- or RSS -- `<item>` -- and both are
/// read, because "an RSS feed" is what people say about both of them and
/// because a feed that happens to be Atom is still a feed.
pub fn parse_feed(body : String) -> Array[Document] {
  let documents = parse_blocks(body, "<entry>", "</entry>", parse_atom_entry)
  if documents.length() > 0 {
    return documents
  }
  parse_blocks(body, "<item>", "</item>", parse_rss_item)
}

///|
/// The blocks between an opening and a closing tag, and what each says.
///
/// The blocks are read left to right and the reader is applied to each one,
/// so that a feed with an entry MAKED cannot read does not hide the entries
/// it can.
fn parse_blocks(
  body : String,
  open_tag : String,
  close_tag : String,
  reader : (String) -> Document?,
) -> Array[Document] {
  let documents : Array[Document] = []
  let mut pos = 0
  while pos < body.length() {
    match find_from(body, open_tag, pos) {
      Some(start) => {
        let content_start = start + open_tag.length()
        match find_from(body, close_tag, content_start) {
          Some(end) => {
            match reader(body[content_start:end].to_owned()) {
              Some(document) => documents.push(document)
              None => ()
            }
            pos = end + close_tag.length()
          }
          None => break
        }
      }
      None => break
    }
  }
  documents
}

///|
/// Read one Atom entry.
fn parse_atom_entry(entry : String) -> Document? {
  let id = clean_text(extract_tag(entry, "id"))
  let title = clean_text(strip_markup(extract_tag(entry, "title")))
  if title == "" {
    return None
  }
  let summary = clean_text(
    strip_markup(
      match extract_tag(entry, "summary") {
        "" => extract_tag(entry, "content")
        value => value
      },
    ),
  )
  let published = match extract_tag(entry, "published") {
    "" => extract_tag(entry, "updated")
    value => value
  }
  Some({
    id: if id == "" {
      title
    } else {
      id
    },
    title,
    summary,
    authors: extract_authors(entry),
    categories: extract_categories(entry),
    published,
    link: extract_link(entry),
  })
}

///|
/// Read one RSS item.
fn parse_rss_item(item : String) -> Document? {
  let title = clean_text(strip_markup(extract_tag(item, "title")))
  if title == "" {
    return None
  }
  let summary = clean_text(
    strip_markup(
      match extract_tag(item, "description") {
        "" => extract_tag(item, "content:encoded")
        value => value
      },
    ),
  )
  let link = match extract_tag(item, "link") {
    "" => extract_tag(item, "guid")
    value => value
  }
  let published = match extract_tag(item, "pubDate") {
    "" => extract_tag(item, "dc:date")
    value => value
  }
  let authors : Array[String] = []
  for author in extract_plain_authors(item) {
    authors.push(author)
  }
  Some({
    id: if link == "" {
      title
    } else {
      link
    },
    title,
    summary,
    authors,
    categories: extract_plain_categories(item),
    published,
    link,
  })
}

///|
/// Where a piece of text is, counting from a point in it.
///
/// `find` always starts at the beginning, which is the wrong question when
/// a feed holds two of the same thing: the second `<link>` is found first,
/// and the reader reads the first one again. Every search in a feed is
/// therefore made from where the last one stopped.
fn find_from(text : String, needle : String, from : Int32) -> Int32? {
  if from <= 0 {
    return text.find(needle)
  }
  if from >= text.length() {
    return None
  }
  match text[from:].to_owned().find(needle) {
    Some(index) => Some(from + index)
    None => None
  }
}

///|
/// The content of an XML tag.
fn extract_tag(xml : String, tag : String) -> String {
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  match xml.find(open) {
    Some(start) => {
      let content_start = start + open.length()
      match find_from(xml, close, content_start) {
        Some(end) => xml[content_start:end].to_owned()
        None => ""
      }
    }
    None => ""
  }
}

///|
/// Author names from `<author><name>...</name></author>` blocks.
fn extract_authors(entry : String) -> Array[String] {
  let authors : Array[String] = []
  let open = "<author>"
  let close = "</author>"
  let name_open = "<name>"
  let name_close = "</name>"
  let mut pos = 0
  while pos < entry.length() {
    match find_from(entry, open, pos) {
      Some(start) =>
        match find_from(entry, close, start) {
          Some(end) => {
            let block = entry[start:end].to_owned()
            match block.find(name_open) {
              Some(ns) =>
                match find_from(block, name_close, ns + name_open.length()) {
                  Some(ne) => {
                    let name = clean_text(
                      block[ns + name_open.length():ne].to_owned(),
                    )
                    if name != "" {
                      authors.push(name)
                    }
                  }
                  None => ()
                }
              None => ()
            }
            pos = end + close.length()
          }
          None => break
        }
      None => break
    }
  }
  authors
}

///|
/// Author names from `<author>someone@example.com</author>`, as RSS writes
/// them.
fn extract_plain_authors(entry : String) -> Array[String] {
  let authors : Array[String] = []
  for raw in extract_all_tags(entry, "author") {
    let name = clean_text(raw)
    if name != "" {
      authors.push(name)
    }
  }
  authors
}

///|
/// Every tag's content, in order.
fn extract_all_tags(xml : String, tag : String) -> Array[String] {
  let contents : Array[String] = []
  let open = "<" + tag + ">"
  let close = "</" + tag + ">"
  let mut pos = 0
  while pos < xml.length() {
    match find_from(xml, open, pos) {
      Some(start) => {
        let content_start = start + open.length()
        match find_from(xml, close, content_start) {
          Some(end) => {
            contents.push(xml[content_start:end].to_owned())
            pos = end + close.length()
          }
          None => break
        }
      }
      None => break
    }
  }
  contents
}

///|
/// Categories from `<category term="..."/>` tags.
fn extract_categories(entry : String) -> Array[String] {
  let cats : Array[String] = []
  let tag = "<category "
  let mut pos = 0
  while pos < entry.length() {
    match find_from(entry, tag, pos) {
      Some(start) =>
        match find_from(entry, "term=\"", start) {
          Some(term_pos) => {
            let val_start = term_pos + 6
            match find_from(entry, "\"", val_start) {
              Some(val_end) => {
                cats.push(entry[val_start:val_end].to_owned())
                pos = val_end + 1
              }
              None => break
            }
          }
          None => break
        }
      None => break
    }
  }
  cats
}

///|
/// Categories from `<category>...</category>`, as RSS writes them.
fn extract_plain_categories(entry : String) -> Array[String] {
  let cats : Array[String] = []
  for raw in extract_all_tags(entry, "category") {
    let name = clean_text(raw)
    if name != "" {
      cats.push(name)
    }
  }
  cats
}

///|
/// The first `<link href="..."/>` that is an abstract or pdf link.
fn extract_link(entry : String) -> String {
  let tag = "<link "
  let mut pos = 0
  while pos < entry.length() {
    match find_from(entry, tag, pos) {
      Some(start) =>
        match find_from(entry, "href=\"", start) {
          Some(href_pos) => {
            let val_start = href_pos + 6
            match find_from(entry, "\"", val_start) {
              Some(val_end) => {
                let href = entry[val_start:val_end].to_owned()
                if href.contains("abs/") || href.contains("/pdf") {
                  return href
                }
                pos = val_end + 1
              }
              None => break
            }
          }
          None => break
        }
      None => break
    }
  }
  ""
}

///|
/// Clean whitespace from extracted text.
///
/// The text is walked a character at a time rather than indexed: indexing a
/// string gives the code *unit*, and writing that number out would turn
/// every character into its own number. A title read that way is a title
/// made of digits, and a table that matched on the digits is a table that
/// matched on nothing.
pub fn clean_text(s : String) -> String {
  let chars : Array[String] = []
  let mut prev_space = true
  for c in s.iter() {
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      if !prev_space {
        chars.push(" ")
        prev_space = true
      }
    } else {
      chars.push(c.to_string())
      prev_space = false
    }
  }
  chars.join("").trim().to_owned()
}

///|
/// The text of a fragment, without its markup.
///
/// A feed writes its description as HTML often enough that the reader would
/// otherwise read the tags as words, and a table that matches on the word
/// "href" is a table that matched on markup.
pub fn strip_markup(text : String) -> String {
  let chars : Array[String] = []
  let mut inside = false
  for c in text.iter() {
    if c == '<' {
      inside = true
    } else if c == '>' {
      inside = false
    } else if !inside {
      chars.push(c.to_string())
    }
  }
  unescape_entities(chars.join(""))
}

///|
/// The few entities a feed writes often.
fn unescape_entities(text : String) -> String {
  let result = text.replace(old="&lt;", new="<")
  result
  .replace(old="&gt;", new=">")
  .replace(old="&quot;", new="\"")
  .replace(old="&#39;", new="'")
  .replace(old="&nbsp;", new=" ")
  .replace(old="&amp;", new="&")
}

///|
/// The body of a URL, read as text.
///
/// An empty string when the URL cannot be read, with the reason printed. The
/// reason matters: a reader who pointed MAKED at a feed and got nothing
/// needs to know whether the feed is empty or the address is wrong.
async fn fetch_text(url : String) -> String {
  let (response, data) = @http.get(url) catch {
    err => {
      println("error: cannot read \{url}: \{err}")
      return ""
    }
  }
  if response.code != 200 {
    println("error: \{url} answered \{response.code}")
    return ""
  }
  data.text() catch {
    err => {
      println("error: \{url} sent a body that is not text: \{err}")
      return ""
    }
  }
}

///|
/// The first `max_results` documents, and no more.
fn limit_documents(
  documents : Array[Document],
  max_results : Int32,
) -> Array[Document] {
  if documents.length() <= max_results {
    return documents
  }
  let out : Array[Document] = []
  for i in 0..<max_results {
    out.push(documents[i])
  }
  out
}
