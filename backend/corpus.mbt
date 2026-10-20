///| The corpus: the set of documents the research loop reads.
///
/// MAKED used to read exactly one thing: recent SNN papers from arxiv, with
/// the query written into the program. That is a corpus written as code, and
/// it has every fault the mapping table had before it became a file -- the
/// reader cannot point MAKED at their own reading, and the only way to find
/// out what was read is to read the source of a web application.
///
/// A corpus is a file. It says where the documents come from, and MAKED reads
/// the corpus it was given.
///
/// The three kinds, and why there are three:
///
///   - **arxiv** asks a question of a public index and gets back a list of
///     abstracts. It is the corpus this project was built on.
///   - **rss** reads a feed the reader already subscribes to, which is the
///     corpus most people actually have.
///   - **local** reads the reader's own files: a folder of notes, a Zotero
///     export, a PDF. This is the corpus that makes the loop theirs.
///
/// A local corpus is a folder of documents, and the kind of a file says how
/// to read it: `.txt` and `.md` are read as text, `.pdf` is read through a
/// PDF reader that turns it into markdown, and `.json` is read as a Zotero
/// CSL-JSON export. A file of a kind MAKED does not know is left alone
/// rather than guessed at.
///
/// The same three rules the model file and the research file follow apply
/// here: the format is asked for, a file that cannot be read is refused
/// rather than half-read, and the syntax a file is written in is decided by
/// its name.

///|
/// The format a corpus file says it is written in, so that a file from a
/// later version is refused rather than read as if it were this one.
pub const CORPUS_FORMAT : String = "maked.corpus.v1"

///|
/// A document the corpus produced.
///
/// The same shape whatever the corpus was: an arxiv abstract, an RSS item, a
/// note in a folder and a page of a PDF are all "a document with an id, a
/// title and some text". The mapping table reads the title and the text, and
/// the causal analysis reads the same two, so the shape is what both of them
/// need and nothing more.
pub(all) struct Document {
  /// Something that identifies the document. For a local file it is the path.
  id : String
  /// The document's own name, taken from whatever the source has.
  title : String
  /// The text of the document, which is what the mapping table matches.
  summary : String
  /// Who wrote it, when the source says.
  authors : Array[String]
  /// What it is about, when the source says.
  categories : Array[String]
  /// When it was written, when the source says.
  published : String
  /// Where it can be read, when the source says.
  link : String
} derive(Eq, Debug)

///|
pub extend Document with Eq::{not_equal, equal}

///|
pub extend Document with Debug::{to_repr}

///|
/// Convert a Document to JSON for the API.
///
/// The same fields the arxiv reader always sent, so that the panel and the
/// export do not have to learn a new shape every time the corpus changes.
pub fn Document::to_json(self : Document) -> Json {
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
/// Where the documents come from.
pub(all) enum CorpusKind {
  /// An arxiv query: a question asked of the arxiv index.
  Arxiv
  /// An RSS or Atom feed: a subscription the reader already has.
  Rss
  /// A file or a folder on this machine.
  Local
} derive(Eq, Debug)

///|
pub extend CorpusKind with Eq::{not_equal, equal}

///|
pub extend CorpusKind with Debug::{to_repr}

///|
/// The corpus configuration MAKED is running.
pub(all) struct CorpusConfig {
  /// Where the documents come from.
  kind : CorpusKind
  /// The arxiv query, when the kind is arxiv.
  query : String
  /// The feed address, when the kind is rss.
  url : String
  /// The file or folder, when the kind is local.
  source_path : String
  /// How many documents to read. More than the source has is not an error.
  max_results : Int32
  /// Where the configuration was read from. Empty when it is the built-in
  /// one, and that is the difference between a corpus that can be written
  /// back and one that cannot.
  path : String
} derive(Eq, Debug)

///|
pub extend CorpusConfig with Eq::{not_equal, equal}

///|
pub extend CorpusConfig with Debug::{to_repr}

///|
/// A corpus configuration, or the reason there is not one.
///
/// The reason is carried rather than printed, because the caller is usually
/// a request from a person who typed something, and a person is owed an
/// answer rather than a line in the server's log.
pub(all) enum CorpusRead {
  Accepted(CorpusConfig)
  Rejected(String)
}

///|
/// The name of a kind, as it is written in a file and shown in the panel.
pub fn corpus_kind_text(kind : CorpusKind) -> String {
  match kind {
    Arxiv => "arxiv"
    Rss => "rss"
    Local => "local"
  }
}

///|
/// The corpus MAKED runs when nothing else is installed.
///
/// The arxiv query the project was built on, kept as it was: this is the
/// corpus a reader gets when they have not chosen one, and changing it
/// would change what the built-in example means.
pub fn CorpusConfig::builtin() -> CorpusConfig {
  {
    kind: Arxiv,
    query: SNN_QUERY,
    url: "",
    source_path: "",
    max_results: 20,
    path: "",
  }
}

///|
/// Read a corpus configuration out of JSON.
///
/// The format is asked for, the same way the model file asks for its own: a
/// file from a later version is refused rather than read as if it were this
/// one.
///
/// Each kind is asked for the one thing it cannot work without -- an arxiv
/// source without a query, a feed without an address, a local source without
/// a path -- because a corpus that names a source it cannot read is a corpus
/// that silently reads nothing.
pub fn CorpusConfig::from_json(path : String, json : Json) -> CorpusRead {
  let format = json_string(json, "format")
  if format != CORPUS_FORMAT {
    return Rejected(
      "format must be \"" + CORPUS_FORMAT + "\"; got \"" + format + "\"",
    )
  }
  let source = match json_field(json, "source") {
    Some(Object(fields)) => fields
    _ => return Rejected("source must say where the documents come from")
  }
  let kind_text = match source.get("kind") {
    Some(String(value)) => value
    _ => return Rejected("source must name a kind: arxiv, rss or local")
  }
  let kind = match kind_text {
    "arxiv" => Arxiv
    "rss" => Rss
    "local" => Local
    _ =>
      return Rejected(
        "source kind must be arxiv, rss or local; got \"" + kind_text + "\"",
      )
  }
  let query = match source.get("query") {
    Some(String(value)) => value
    _ => ""
  }
  let url = match source.get("url") {
    Some(String(value)) => value
    _ => ""
  }
  let local_path = match source.get("path") {
    Some(String(value)) => value
    _ => ""
  }
  match kind {
    Arxiv => if query == "" { return Rejected("an arxiv source needs a query") }
    Rss => if url == "" { return Rejected("an rss source needs a url") }
    Local =>
      if local_path == "" {
        return Rejected("a local source needs a path")
      }
  }
  let max_results = match source.get("max_results") {
    Some(Number(value, ..)) => value.to_int()
    _ => 20
  }
  if max_results <= 0 {
    return Rejected("max_results must be at least 1")
  }
  Accepted({ kind, query, url, source_path: local_path, max_results, path, })
}

///|
/// The corpus configuration as JSON: the form a reader can edit and hand
/// back.
///
/// Every name the corpus uses is written down, so the file is the corpus and
/// not a pointer to one. The fields that do not belong to the kind being
/// described are still written, and written empty: a file that only had the
/// fields its kind uses would be a different shape for every kind, and a
/// shape that changes is a shape that breaks a client.
pub fn CorpusConfig::to_json(self : CorpusConfig) -> Json {
  {
    "format": CORPUS_FORMAT,
    "source": {
      "kind": corpus_kind_text(self.kind),
      "query": self.query,
      "url": self.url,
      "path": self.source_path,
      "max_results": self.max_results,
    },
  }
}

///|
/// A one-line description of where the documents come from, for the panel.
pub fn CorpusConfig::describe(self : CorpusConfig) -> String {
  match self.kind {
    Arxiv => "arxiv: " + self.query
    Rss => "rss: " + self.url
    Local => "local: " + self.source_path
  }
}

///|
/// The corpus configuration MAKED is running.
///
/// Held in a one-element array because MoonBit has no mutable module-level
/// binding, and the element is mutable in place.
let g_corpus : Array[CorpusConfig] = [CorpusConfig::builtin()]

///|
/// The corpus configuration MAKED is running.
pub fn current_corpus() -> CorpusConfig {
  g_corpus[0]
}

///|
/// Install a corpus configuration as the one MAKED reads.
///
/// The loop is *not* reset, and it should not be: the corpus says what
/// MAKED reads, and changing what MAKED reads does not change where the
/// loop is standing.
pub fn install_corpus(config : CorpusConfig) -> Unit {
  g_corpus[0] = config
}

///|
/// The corpus file named by `MAKED_CORPUS`, if there is one.
///
/// The same shape as the model file's switch: unset means the built-in
/// corpus, set means the corpus the operator asked for, and an empty value
/// counts as unset because an empty environment variable is a mistake
/// rather than a filename.
pub fn corpus_path_from_env() -> String? {
  match @env.get_env_var("MAKED_CORPUS") {
    Some(path) if path != "" => Some(path)
    _ => None
  }
}

///|
/// Read a corpus configuration from a file.
///
/// None when the file cannot be read or is not a corpus this version
/// understands, with the reason printed. A corpus that cannot be read whole
/// is not read at all: a server that quietly fell back to arxiv would show
/// a full panel of papers while the reader's own documents went unread, and
/// that is the failure this project exists to remove.
pub async fn read_corpus_file(path : String) -> CorpusConfig? {
  let json = match read_data_text("corpus", path) {
    Some(json) => json
    None => return None
  }
  match CorpusConfig::from_json(path, json) {
    Accepted(config) => Some(config)
    Rejected(reason) => {
      eprintln(
        "error: corpus file \{path} is not a corpus this version understands: \{reason}",
      )
      None
    }
  }
}

///|
/// Write a corpus configuration back to the file it came from.
///
/// False when the configuration did not come from a file -- the built-in
/// corpus has nowhere to be written -- or when the file could not be
/// written. The reason is printed either way, because a corpus that was
/// edited and not saved is a corpus the reader believes is saved and is
/// not.
///
/// The file is written in the syntax its name asks for, and its comments are
/// not kept: the corpus is data, and data is written back as data.
pub async fn write_corpus_file(config : CorpusConfig) -> Bool {
  if config.path == "" {
    eprintln(
      "note: the built-in corpus is not written anywhere; it is the corpus MAKED starts with.",
    )
    return false
  }
  let text = data_text_for(config.path, config.to_json())
  @fs.write_file(config.path, text) catch {
    err => {
      eprintln("error: corpus file \{config.path} unwritable: \{err}")
      return false
    }
  }
  true
}
