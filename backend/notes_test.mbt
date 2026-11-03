///| The notes the product writes, and the language they are written in.
///
/// A note is the softer half of a refusal: nothing was refused, but
/// something still needs saying -- the corpus could not be read, the table
/// was written back, the collective has no drive slots. The panel shows
/// those sentences, and the panel is in the reader's language.
///
/// Seven of the eleven notes in the tree were English whatever the request
/// asked for, in a project that has a Chinese interface and a `lang`
/// argument on every route that can say anything. The refusals were given a
/// reason in the reader's language; the notes were left as they were found.
///
/// So every note is checked here in both languages: the English one and the
/// Chinese one have to be different sentences, and the Chinese one has to
/// read as Chinese rather than as a translation of the English one.

///|
/// The notes, in the order the two doors answer with them.
///
/// Every kind of note is here, including the three branches of the two
/// notices that say whether a file was written back: a note that is only
/// right in one of its branches is a note that is wrong in the other two.
fn every_note(lang : @backend.Lang) -> Array[String] {
  [
    @backend.corpus_unreadable_notice("local: ./notes", lang),
    @backend.corpus_empty_notice("local: ./notes", lang),
    @backend.research_table_notice("research/table.yaml", true, lang),
    @backend.research_table_notice("", false, lang),
    @backend.research_table_notice("research/table.yaml", false, lang),
    @backend.research_corpus_notice("corpus.yaml", true, lang),
    @backend.research_corpus_notice("", false, lang),
    @backend.research_corpus_notice("corpus.yaml", false, lang),
    @backend.continuations_note(lang),
    @backend.status_note(lang),
    @backend.options_note(lang),
    @backend.declined_note(lang),
    @backend.sessions_note(lang),
    @backend.society_shape_note(lang),
  ]
}

///|
/// Every note the product writes is in the language the request asked for.
test "every note the product writes is in the language" {
  let english = every_note(en())
  let chinese = every_note(zh())
  assert_eq(english.length(), chinese.length())
  assert_eq(english.length(), 14)
  let mut index = 0
  while index < english.length() {
    assert_false(english[index].is_empty())
    // The Chinese note is a different sentence, not the English one.
    assert_true(english[index] != chinese[index])
    // And it is written in Chinese rather than translated: it carries
    // Chinese punctuation, which the English one does not.
    assert_true(
      chinese[index].contains("。") || chinese[index].contains("："),
    )
    assert_false(
      english[index].contains("。") || english[index].contains("："),
    )
    index = index + 1
  }
}

///|
/// A note that names what happened names it in both languages.
///
/// The corpus, the file, the path: those are the reader's own words, and a
/// note that names them in one language and not in the other is a note that
/// tells the reader half of what it should.
test "a note names what it is about in both languages" {
  assert_true(
    @backend.corpus_unreadable_notice("local: ./notes", en()).contains(
      "local: ./notes",
    ),
  )
  assert_true(
    @backend.corpus_unreadable_notice("local: ./notes", zh()).contains(
      "local: ./notes",
    ),
  )
  assert_true(
    @backend.research_table_notice("research/table.yaml", true, en()).contains(
      "research/table.yaml",
    ),
  )
  assert_true(
    @backend.research_table_notice("research/table.yaml", true, zh()).contains(
      "research/table.yaml",
    ),
  )
  assert_true(
    @backend.research_corpus_notice("corpus.yaml", true, en()).contains(
      "corpus.yaml",
    ),
  )
  assert_true(
    @backend.research_corpus_notice("corpus.yaml", true, zh()).contains(
      "corpus.yaml",
    ),
  )
}

///|
/// A note that says a file was written back says so only when it was.
///
/// The three branches are three different facts: it was written, it could
/// not be written, and it is the built-in one that is written nowhere. A note
/// that says "written back" for a file that was not written back is a lie
/// the reader acts on.
test "a note says a file was written back only when it was" {
  let written = @backend.research_table_notice(
    "research/table.yaml",
    true,
    en(),
  )
  let not_written = @backend.research_table_notice(
    "research/table.yaml",
    false,
    en(),
  )
  let built_in = @backend.research_table_notice("", false, en())
  assert_true(written.contains("was written back to"))
  assert_true(not_written.contains("could not be written back to"))
  assert_true(built_in.contains("not written anywhere"))
  assert_false(built_in.contains("written back to"))
}
