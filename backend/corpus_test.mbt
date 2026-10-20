///| Corpus tests.
///
/// Three things are pinned down here, and each of them is a way the corpus
/// could be wrong in a way that looks fine:
///
///   - **A corpus file that says something MAKED does not understand is
///     refused.** A corpus that half-reads is a corpus that reads the wrong
///     documents, and the panel would show them as if they were right.
///   - **Each reader reads what it claims to read.** An arxiv entry, a feed
///     item, a Zotero export, a text file, a markdown file and a PDF all
///     become documents, and each of them becomes the *right* document.
///   - **The corpus MAKED runs is the corpus it reads.** A configuration
///     that is read and then quietly ignored is the failure this project
///     exists to remove, and it is invisible from the outside.

///|
/// A corpus file's text, with the pieces a test wants to change.
fn corpus_payload(
  kind : String,
  query : String,
  url : String,
  path : String,
  max_results : Int32,
) -> String {
  "{\"format\": \"maked.corpus.v1\", \"source\": {\"kind\": \"" +
  kind +
  "\", \"query\": \"" +
  query +
  "\", \"url\": \"" +
  url +
  "\", \"path\": \"" +
  path +
  "\", \"max_results\": " +
  max_results.to_string() +
  "}}"
}

///|
/// The corpus a payload describes, or a failure with the reason.
fn corpus_from(text : String) -> @backend.CorpusConfig raise {
  let json = @json.parse(text) catch {
    err => fail("the payload is not JSON: " + err.to_string())
  }
  match @backend.CorpusConfig::from_json("corpus.yaml", json) {
    @backend.Accepted(config) => config
    @backend.Rejected(reason) => fail("the corpus was refused: " + reason)
  }
}

///|
/// The reason a payload was refused, or a failure saying it was not.
fn refusal_of(text : String) -> String raise {
  let json = @json.parse(text) catch {
    err => fail("the payload is not JSON: " + err.to_string())
  }
  match @backend.CorpusConfig::from_json("corpus.yaml", json) {
    @backend.Accepted(_) =>
      fail("the corpus was accepted, and should not have been")
    @backend.Rejected(reason) => reason
  }
}

///|
/// The built-in corpus is the arxiv query this project was built on.
test "the built-in corpus is the arxiv query the project was built on" {
  let corpus = @backend.CorpusConfig::builtin()
  assert_eq(corpus.kind, @backend.Arxiv)
  assert_true(corpus.query.contains("spiking"))
  assert_eq(corpus.path, "")
}

///|
/// The corpus MAKED runs before anything is installed is the built-in one.
test "the corpus MAKED runs at the start is the built-in one" {
  let corpus = @backend.current_corpus()
  assert_eq(corpus.kind, @backend.Arxiv)
  assert_eq(corpus.path, "")
}

///|
/// A corpus file from a later version is refused rather than half-read.
test "a corpus file with the wrong format is refused" {
  let reason = refusal_of(
    "{\"format\": \"maked.corpus.v9\", \"source\": {\"kind\": \"arxiv\"}}",
  )
  assert_true(reason.contains("maked.corpus.v1"))
}

///|
/// A source that names a kind MAKED does not have is refused.
test "a source with an unknown kind is refused" {
  let reason = refusal_of(corpus_payload("web", "", "", "", 10))
  assert_true(reason.contains("arxiv"))
}

///|
/// An arxiv source with no query has nothing to ask arxiv.
test "an arxiv source with no query is refused" {
  let reason = refusal_of(corpus_payload("arxiv", "", "", "", 10))
  assert_true(reason.contains("query"))
}

///|
/// A feed with no address is not a feed.
test "an rss source with no url is refused" {
  let reason = refusal_of(corpus_payload("rss", "", "", "", 10))
  assert_true(reason.contains("url"))
}

///|
/// A local source with no path has no folder to read.
test "a local source with no path is refused" {
  let reason = refusal_of(corpus_payload("local", "", "", "", 10))
  assert_true(reason.contains("path"))
}

///|
/// A corpus that asks for no documents is a corpus that reads nothing, and
/// that is not what the reader asked for.
test "a corpus that asks for no documents is refused" {
  let reason = refusal_of(corpus_payload("arxiv", "all:snns", "", "", 0))
  assert_true(reason.contains("max_results"))
}

///|
/// The same corpus written in the two syntaxes is the same corpus.
///
/// JSON is a subset of YAML, so a corpus read as the wrong one is a corpus
/// that half-reads: the guard has to be the corpus itself, not the fact
/// that it parsed.
test "the same corpus in JSON and in YAML is the same corpus" {
  let payload = corpus_payload("local", "", "", "./notes", 7)
  let as_json = match
    @backend.parse_data_text("corpus", "corpus.json", payload) {
    Some(value) => value
    None => fail("the JSON was refused")
  }
  let yaml_text = @backend.data_text_for("corpus.yaml", as_json)
  let as_yaml = match
    @backend.parse_data_text("corpus", "corpus.yaml", yaml_text) {
    Some(value) => value
    None => fail("the YAML was refused")
  }
  let from_json = @backend.CorpusConfig::from_json("corpus.json", as_json)
  let from_yaml = @backend.CorpusConfig::from_json("corpus.yaml", as_yaml)
  match (from_json, from_yaml) {
    (@backend.Accepted(a), @backend.Accepted(b)) => {
      assert_eq(a.to_json(), b.to_json())
      assert_eq(a.kind, @backend.Local)
      assert_eq(a.source_path, "./notes")
      assert_eq(a.max_results, 7)
    }
    _ => fail("one of the two syntaxes was refused")
  }
}

///|
/// A corpus written back is the corpus that was read.
///
/// The point of writing it back is that the edit survives the server
/// stopping, and an edit that is read back as a different corpus has not
/// survived anything.
async test "a corpus written back is the corpus that was read" {
  let original = corpus_from(corpus_payload("local", "", "", "./notes", 5))
  let path = "test_corpus_file.yaml"
  let text = @backend.data_text_for(path, original.to_json())
  @fs.write_file(path, text) catch {
    err => fail("the corpus was not written: " + @debug.to_string(err))
  }
  let read_back = match @backend.read_corpus_file(path) {
    Some(config) => config
    None => fail("the corpus that was written was not read back")
  }
  assert_eq(read_back.to_json(), original.to_json())
  // The file's name is remembered, because that is what makes the corpus
  // writable back.
  assert_eq(read_back.path, path)
  @fs.remove(path) catch {
    _ => ()
  }
}

///|
/// A corpus file MAKED cannot read is refused rather than half-read.
async test "a corpus file that cannot be read is refused" {
  let path = "test_corpus_broken.yaml"
  @fs.write_file(path, "this is not a corpus at all") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  let read = @backend.read_corpus_file(path)
  @fs.remove(path) catch {
    _ => ()
  }
  assert_true(read == None)
}

///|
/// The corpus MAKED runs is the corpus that was installed.
///
/// The corpus installed here is the built-in one with a file name, so that
/// a test running beside this one still sees an arxiv corpus while it does.
test "the corpus MAKED runs is the corpus that was installed" {
  let builtin = @backend.CorpusConfig::builtin()
  let corpus = @backend.CorpusConfig::{
    kind: builtin.kind,
    query: builtin.query,
    url: builtin.url,
    source_path: builtin.source_path,
    max_results: builtin.max_results,
    path: "corpus.yaml",
  }
  @backend.install_corpus(corpus)
  let running = @backend.current_corpus()
  @backend.install_corpus(@backend.CorpusConfig::builtin())
  assert_eq(running.path, "corpus.yaml")
  assert_eq(running.kind, @backend.Arxiv)
}

///|
/// An arxiv entry is a document.
test "an arxiv entry is a document" {
  let body = "<feed><entry><id>http://arxiv.org/abs/2401.00001v1</id>" +
    "<title>A Novel Approach to SNN</title>" +
    "<summary>We propose a new method for spiking networks.</summary>" +
    "<author><name>Alice Smith</name></author>" +
    "<category term=\"cs.LG\"/>" +
    "<published>2024-01-02T00:00:00Z</published>" +
    "<link href=\"http://arxiv.org/abs/2401.00001v1\"/>" +
    "</entry></feed>"
  let documents = @backend.parse_feed(body)
  assert_eq(documents.length(), 1)
  let document = documents[0]
  assert_eq(document.title, "A Novel Approach to SNN")
  assert_true(document.summary.contains("new method"))
  assert_eq(document.authors, ["Alice Smith"])
  assert_eq(document.categories, ["cs.LG"])
  assert_eq(document.published, "2024-01-02T00:00:00Z")
  assert_true(document.link.contains("2401.00001"))
}

///|
/// A feed item is a document too, and it says the same things.
test "a feed item is a document" {
  let body = "<rss><channel><item><title>A Reported Failure</title>" +
    "<description>Current methods fail at scale.</description>" +
    "<link>https://example.com/a</link>" +
    "<pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>" +
    "<author>alice@example.com</author>" +
    "<category>news</category>" +
    "</item></channel></rss>"
  let documents = @backend.parse_feed(body)
  assert_eq(documents.length(), 1)
  let document = documents[0]
  assert_eq(document.title, "A Reported Failure")
  assert_true(document.summary.contains("fail at scale"))
  assert_eq(document.link, "https://example.com/a")
  assert_eq(document.authors, ["alice@example.com"])
  assert_eq(document.categories, ["news"])
}

///|
/// A feed that holds nothing is a feed with no documents, and that is not
/// the same thing as a feed that could not be read.
test "a feed that holds nothing holds no documents" {
  let documents = @backend.parse_feed("<rss><channel></channel></rss>")
  assert_eq(documents.length(), 0)
}

///|
/// A description written as HTML is read as text, not as markup.
test "a description written as HTML is read as text" {
  let body = "<rss><channel><item><title>Markup</title>" +
    "<description>&lt;p&gt;We &lt;b&gt;propose&lt;/b&gt; a method&lt;/p&gt;</description>" +
    "</item></channel></rss>"
  let documents = @backend.parse_feed(body)
  assert_eq(documents.length(), 1)
  assert_true(documents[0].summary.contains("propose"))
  assert_true(!documents[0].summary.contains("<b>"))
}

///|
/// A Zotero export is a list of documents.
test "a zotero export is a list of documents" {
  let text = "[{\"id\": \"ABCD1234\", \"type\": \"article-journal\", " +
    "\"title\": \"A Novel Approach to SNN\", " +
    "\"abstract\": \"We propose a new method.\", " +
    "\"author\": [{\"given\": \"Alice\", \"family\": \"Smith\"}], " +
    "\"issued\": {\"date-parts\": [[2020, 5, 1]]}, " +
    "\"URL\": \"https://example.com/paper\", " +
    "\"keyword\": [\"spiking\"]}]"
  let documents = @backend.parse_csl_json(text)
  assert_eq(documents.length(), 1)
  let document = documents[0]
  assert_eq(document.id, "ABCD1234")
  assert_eq(document.title, "A Novel Approach to SNN")
  assert_true(document.summary.contains("new method"))
  assert_eq(document.authors, ["Alice Smith"])
  assert_eq(document.published, "2020-05-01")
  assert_eq(document.link, "https://example.com/paper")
  assert_true(document.categories.contains("spiking"))
}

///|
/// Some tools wrap a Zotero export in an object. It is the same export.
test "a zotero export wrapped in items is the same export" {
  let text = "{\"items\": [{\"id\": \"X\", \"title\": \"A Note\", " +
    "\"abstract\": \"We fail.\"}]}"
  let documents = @backend.parse_csl_json(text)
  assert_eq(documents.length(), 1)
  assert_eq(documents[0].title, "A Note")
}

///|
/// A JSON file that is not a Zotero export is not a document.
test "a json file that is not a zotero export is not a document" {
  assert_eq(@backend.parse_csl_json("{\"unrelated\": true}").length(), 0)
  assert_eq(@backend.parse_csl_json("not json at all").length(), 0)
}

///|
/// A text file is titled by its first line.
test "a text file is titled by its first line" {
  let document = @backend.document_from_text(
    "notes/launch.txt", "What we learned from the failed launch\n\nIt did not scale.\n",
  )
  assert_eq(document.title, "What we learned from the failed launch")
  assert_eq(document.id, "notes/launch.txt")
  assert_true(document.summary.contains("did not scale"))
}

///|
/// A markdown file is titled by its heading, because a markdown file has
/// one and a text file does not.
test "a markdown file is titled by its heading" {
  let document = @backend.document_from_text(
    "notes/launch.md", "# What we learned\n\nWe outperform every baseline.\n",
  )
  assert_eq(document.title, "What we learned")
}

///|
/// A file with no heading is titled by its first line.
test "a file with no heading is titled by its first line" {
  let document = @backend.document_from_text(
    "notes/plain.md", "\n\nJust a note.\n",
  )
  assert_eq(document.title, "Just a note.")
}

///|
/// A local corpus is the documents in the folder it names.
async test "a local corpus is the documents in the folder it names" {
  let dir = "test_corpus_dir"
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    err => fail("the folder was not made: " + @debug.to_string(err))
  }
  @fs.write_file(
    dir + "/note.md",
    "# A Reported Failure\n\nWe fail at scale.\n",
  ) catch {
    err => fail("the note was not written: " + @debug.to_string(err))
  }
  @fs.write_file(dir + "/ignored.png", "not a document") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  let corpus = corpus_from(corpus_payload("local", "", "", dir, 10))
  let documents = @backend.fetch_corpus(corpus) catch { _ => [] }
  @fs.remove(dir + "/note.md") catch {
    _ => ()
  }
  @fs.remove(dir + "/ignored.png") catch {
    _ => ()
  }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  // One document: the picture is not a document, and it is left alone
  // rather than read as something it is not.
  assert_eq(documents.length(), 1)
  assert_eq(documents[0].title, "A Reported Failure")
  assert_true(documents[0].summary.contains("fail at scale"))
}

///|
/// A local folder is read in path order, so that the same folder drives
/// the same steps every time.
///
/// The order is asked of the function that sorts, not of the filesystem:
/// a directory listing that happens to come back in order is a coincidence,
/// and a test that relies on a coincidence is a test that will one day pass
/// for the wrong reason. The two paths are of different lengths on purpose:
/// MoonBit's own string order is by length first, so a sort that used it
/// would put "notes/b.txt" first, and the test would say so.
test "a folder is read in path order" {
  let sorted = @backend.sorted_paths(["notes/b.txt", "notes/a/first.txt"])
  assert_eq(sorted, ["notes/a/first.txt", "notes/b.txt"])
}

///|
/// A page marker in the text is not the title.
///
/// A PDF read as markdown is a list of pages, and the converter marks each
/// one. A document called "Page 2" is a document called nothing at all.
test "a page marker in the text is not the title" {
  let document = @backend.document_from_text(
    "notes/pages.md", "Page 2\n\nThe actual note.\n",
  )
  assert_eq(document.title, "The actual note.")
}

///|
/// A local folder is read in path order, so that the same folder drives
/// the same steps every time.
///
/// The folder has folders in it on purpose. A directory listing that
/// happens to come back in order would hide a reader that stopped sorting:
/// the order would be right for the wrong reason. A tree is not in order
/// until something puts it in order.
async test "a local folder is read in path order" {
  let dir = "test_corpus_order"
  @fs.mkdir(dir, recursive=true, allow_exist=true) catch {
    err => fail("the folder was not made: " + @debug.to_string(err))
  }
  @fs.mkdir(dir + "/a", recursive=true, allow_exist=true) catch {
    err => fail("the folder was not made: " + @debug.to_string(err))
  }
  @fs.mkdir(dir + "/d", recursive=true, allow_exist=true) catch {
    err => fail("the folder was not made: " + @debug.to_string(err))
  }
  @fs.write_file(dir + "/b.txt", "Second\n") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  @fs.write_file(dir + "/c.txt", "Third\n") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  @fs.write_file(dir + "/a/first.txt", "First\n") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  @fs.write_file(dir + "/d/fourth.txt", "Fourth\n") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  let documents = @backend.read_local_documents(dir, 10) catch { _ => [] }
  @fs.remove(dir + "/b.txt") catch {
    _ => ()
  }
  @fs.remove(dir + "/c.txt") catch {
    _ => ()
  }
  @fs.remove(dir + "/a/first.txt") catch {
    _ => ()
  }
  @fs.remove(dir + "/d/fourth.txt") catch {
    _ => ()
  }
  @fs.rmdir(dir + "/a") catch {
    _ => ()
  }
  @fs.rmdir(dir + "/d") catch {
    _ => ()
  }
  @fs.rmdir(dir) catch {
    _ => ()
  }
  assert_eq(documents.length(), 4)
  assert_eq(documents[0].title, "First")
  assert_eq(documents[1].title, "Second")
  assert_eq(documents[2].title, "Third")
  assert_eq(documents[3].title, "Fourth")
}

///|
/// A one-page PDF with a line of text on it.
///
/// The PDF is written here rather than kept as a file in the repository,
/// because a fixture has to be found at a path that depends on where the
/// test runs, and a test that cannot find its own fixture is a test that
/// quietly stops testing anything. The file is written by the test itself,
/// and the xref table is computed rather than copied, so the reader under
/// test has to do real work.
fn sample_pdf() -> String {
  let stream = "BT /F1 18 Tf 72 700 Td (A note about the failed launch) Tj ET"
  let objects : Array[String] = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R " +
    "/Resources << /Font << /F1 5 0 R >> >> >>",
    "<< /Length " +
    stream.length().to_string() +
    " >>\nstream\n" +
    stream +
    "\nendstream",
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ]
  let mut out = "%PDF-1.4\n"
  let offsets : Array[Int32] = []
  for i in 0..<objects.length() {
    let header = (i + 1).to_string() + " 0 obj\n"
    offsets.push(out.length() + header.length())
    out = out + header + objects[i] + "\nendobj\n"
  }
  let xref_offset = out.length()
  out = out + "xref\n0 " + (objects.length() + 1).to_string() + "\n"
  out = out + "0000000000 65535 f \n"
  for offset in offsets {
    out = out + pad_offset(offset) + " 00000 n \n"
  }
  out = out +
    "trailer\n<< /Size " +
    (objects.length() + 1).to_string() +
    " /Root 1 0 R >>\nstartxref\n" +
    xref_offset.to_string() +
    "\n%%EOF\n"
  out
}

///|
/// A number written with ten digits, the way a cross-reference table wants
/// it.
fn pad_offset(number : Int32) -> String {
  let text = number.to_string()
  let mut out = ""
  let mut i = text.length()
  while i < 10 {
    out = out + "0"
    i += 1
  }
  out + text
}

///|
/// A PDF is read as the markdown it holds.
async test "a pdf is read as the markdown it holds" {
  let path = "test_corpus_sample.pdf"
  @fs.write_file(path, sample_pdf()) catch {
    err => fail("the pdf was not written: " + @debug.to_string(err))
  }
  let document = @backend.read_pdf_file(path)
  @fs.remove(path) catch {
    _ => ()
  }
  match document {
    Some(value) => {
      assert_true(value.summary.contains("failed launch"))
      assert_true(value.title.contains("failed launch"))
    }
    None => fail("the pdf was not read")
  }
}

///|
/// A file that is not a PDF is refused rather than read as an empty
/// document.
async test "a file that is not a pdf is refused" {
  let path = "test_corpus_broken.pdf"
  @fs.write_file(path, "this is not a pdf") catch {
    err => fail("the file was not written: " + @debug.to_string(err))
  }
  let document = @backend.read_pdf_file(path)
  @fs.remove(path) catch {
    _ => ()
  }
  assert_true(document == None)
}

///|
/// A local corpus that names a folder that is not there reads nothing, and
/// says so.
async test "a local corpus that names nothing reads nothing" {
  let corpus = corpus_from(
    corpus_payload("local", "", "", "test_corpus_not_here", 10),
  )
  let documents = @backend.fetch_corpus(corpus) catch { _ => [] }
  assert_eq(documents.length(), 0)
}

///|
/// The corpus says where it reads from, in words.
test "the corpus says where it reads from" {
  let local = corpus_from(corpus_payload("local", "", "", "./notes", 10))
  assert_true(local.describe().contains("./notes"))
  let feed = corpus_from(
    corpus_payload("rss", "", "https://example.com/feed", "", 10),
  )
  assert_true(feed.describe().contains("https://example.com/feed"))
  let arxiv = corpus_from(corpus_payload("arxiv", "all:snns", "", "", 10))
  assert_true(arxiv.describe().contains("all:snns"))
}
