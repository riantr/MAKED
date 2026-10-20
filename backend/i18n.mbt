///| The language a surface is rendered in.
///
/// Two, and only two, and the reason is the vocabulary rather than the
/// technology: the model carries one parallel Chinese vocabulary, so a third
/// language would be a language the model has no words for. Adding one means
/// adding a third column to every name in the model, not adding an enum case
/// here.
///
/// The fallback is the other half of the contract, and it is deliberately
/// simple: **a name with no Chinese in it is shown in English.** A model file
/// written before this existed, or written in English only, keeps working
/// unchanged, and a Chinese reader sees the English name rather than a blank.
/// `Lang::pick` is the one place that rule lives, so it cannot drift between
/// the positions, the slots, the domains and the outcomes.

///|
/// The language a surface is rendered in.
///
/// `pub` rather than `pub(all)`, because the agent's server is in another
/// package and has to be able to *name* a language: it reads the caller's
/// `lang` argument and passes the result to the backend, and a type it
/// cannot construct is a type it cannot pass on.
pub enum Lang {
  /// The reading the model writes itself: "Standing", "Situation".
  English
  /// The reading the model has in Chinese: "立位", "处境".
  Chinese
} derive(Eq, Debug)

///|
pub extend Lang with Eq::{not_equal, equal}

///|
pub extend Lang with Debug::{to_repr}

///|
/// The language a request asks for.
///
/// A tag names a language and a region, and the region is not a language:
/// `zh-Hans` and `zh-Hant` are both Chinese, and a request that says which
/// script it wants is still asking for Chinese. So the tag is read down to
/// its language, and everything that is not Chinese is English.
///
/// English is the default rather than an error, because a client that sends
/// nothing, or sends something this version has never heard of, should get
/// the surface it would have got anyway. Refusing an unknown tag would make
/// a new client break against an old server, which is the wrong way round.
pub fn Lang::parse(s : String) -> Lang {
  let tag = s.to_lower().replace_all(old="_", new="-").trim().to_owned()
  if tag == "zh" || tag == "cn" || tag == "chinese" || tag == "中文" {
    return Chinese
  }
  if tag.has_prefix("zh-") {
    return Chinese
  }
  English
}

///|
/// The English reading.
///
/// A function rather than the bare constructor because an enum's
/// constructors are read-only outside the package that defines the enum:
/// the agent's server is in another package, and it has to be able to hand
/// the backend a language it chose itself.
pub fn Lang::english() -> Lang {
  English
}

///|
/// The Chinese reading.
///
/// The same reason as `Lang::english`.
pub fn Lang::chinese() -> Lang {
  Chinese
}

///|
/// The tag this language is written as.
///
/// The same tag `Lang::parse` reads, so a round trip through the two is a
/// fixed point: `Lang::parse(Lang::code(lang)) == lang` for both languages.
pub fn Lang::code(self : Lang) -> String {
  match self {
    English => "en"
    Chinese => "zh"
  }
}

///|
/// The name to show, in this language.
///
/// The fallback lives here and nowhere else: a Chinese name that is missing
/// or empty means "this model has no Chinese for it", and the English name is
/// what the reader gets. An empty string is never shown, because a blank in
/// the middle of a sentence is worse than a word in the wrong language.
pub fn Lang::pick(self : Lang, english : String, chinese : String) -> String {
  match self {
    English => english
    Chinese => if chinese == "" { english } else { chinese }
  }
}

///|
/// The language a request asks for, read from its query string.
///
/// `lang=zh` is the whole of the switch, and an absent or empty parameter
/// means English. The parameter is read from the query string rather than
/// from a header because a header would be a negotiation (the client asking
/// what the server supports) and this is a choice (the client saying which
/// one it wants).
pub fn lang_from_query(query : String?) -> Lang {
  match query {
    Some(value) => Lang::parse(value)
    None => English
  }
}
