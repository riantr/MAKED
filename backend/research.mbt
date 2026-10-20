///| What a document means.
///
/// This module holds one decision: given a document and the reader's
/// mapping table, which slot does the document drive, and which rule said
/// so. The table lives in `research_config.mbt` and the documents live in
/// `corpus.mbt`; this is the join between them.
///
/// Nothing here decides what a document *is*. A document is an arxiv
/// abstract, a feed item, a note in a folder or a page of a PDF, and the
/// corpus says which; what the document *means* is the reader's table's
/// business, and the table is asked rather than assumed: the same document
/// read under a different table is a different step, and the step in the
/// timeline has to be able to say which table produced it.

///|
/// The slot a document is taken to mean, and the name of the rule that said
/// so.
///
/// The table is the reader's, and it is asked rather than assumed: the same
/// document read under a different table is a different step, and the step in
/// the timeline has to be able to say which table produced it.
pub fn document_to_slot(
  config : ResearchConfig,
  document : Document,
) -> (String, String) {
  config.slot_for_text(document.title + " " + document.summary)
}

///|
/// Lowercase ASCII characters only (for keyword matching).
///
/// The characters are walked one at a time: indexing a string gives the
/// code *unit*, and the words in a table are written in ASCII, so what has
/// to be lower-cased is the ASCII and nothing else.
fn String::to_lowercase_ascii(self : String) -> String {
  let result : Array[String] = []
  for c in self.iter() {
    let code = c.to_int()
    if code >= 65 && code <= 90 {
      match (code + 32).to_uint16().to_char() {
        Some(lower) => result.push(lower.to_string())
        None => result.push(c.to_string())
      }
    } else {
      result.push(c.to_string())
    }
  }
  result.join("")
}

///|
/// Test helpers: expose private functions for blackbox tests.
pub fn to_lowercase_ascii_for_test(s : String) -> String {
  s.to_lowercase_ascii()
}
