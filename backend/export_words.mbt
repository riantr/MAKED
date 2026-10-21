///| The fixed words of the exported document.
///
/// The export is the one thing MAKED hands over rather than shows: a Markdown
/// document or a JSON file that the reader takes away and reads later, on
/// their own, with no server to ask. It is therefore written twice, once in
/// each language, and the two are written side by side rather than one being
/// a translation of the other.
///
/// The reason is the same one the rest of the Chinese work has: a translation
/// keeps the shape of the original, and the shape of an English report is not
/// the shape a Chinese reader expects. An English report says "Position:"
/// and "Why:" on their own lines, and its counts are "3 of 8"; a Chinese
/// report says 位置 and 原因, and its counts are 3 / 8. The numbers are the
/// same numbers, but a document that had been translated would read as a
/// Chinese document with English furniture still showing.
///
/// The structure -- the order, the counts, the steps, the sentences -- is
/// shared. Only the words are here.

///|
/// The words of the exported document, in one language.
pub(all) struct ExportWords {
  /// The title line: "# MAKED session: ".
  title : String
  /// "- **Session id:** "
  session_id : String
  /// "- **Created:** "
  created : String
  /// "- **Last updated:** "
  updated : String
  /// "- **Mode:** "
  mode : String
  /// "- **Started on:** "
  started_on : String
  /// "- **Steps on this path:** "
  steps_on_path : String
  /// "- **Other steps recorded in this session:** "
  other_steps : String
  /// "- **Forked from session:** "
  forked_from : String
  /// What joins the forked session's id to the step it forked at.
  at_step : String
  /// What follows the step a fork came from.
  step_suffix : String
  /// "## The run so far"
  run_heading : String
  /// "## How the run is doing"
  doing_heading : String
  /// "## Timeline"
  timeline_heading : String
  /// "- **Position:** "
  position : String
  /// "- **Detail:** "
  detail : String
  /// "- **Why:** "
  why : String
  /// "- **Cursor after:** "
  cursor : String
  /// " · **group:** "
  group : String
  /// " · **taken by:** "
  taken_by : String
  /// "## Other roads taken"
  other_roads : String
  /// The paragraph under the other roads' heading.
  other_prose : String
  /// "- **Step "
  step_bullet : String
  /// What joins a count to its denominator: " of ".
  of : String
  /// The structured mode, as the document names it.
  mode_structured : String
  /// The free mode, as the document names it.
  mode_free : String
  /// A step the table drove itself.
  source_drive : String
  /// A step the reader chose the slot for.
  source_explicit : String
  /// A step a document drove.
  source_research : String
} derive(Eq)

///|
pub extend ExportWords with Eq::{not_equal, equal}

///|
/// The words of the English document.
///
/// The English document is the one that was there first, and it is written
/// here word for word as it was: a reader who has the English export open
/// beside this file should not be able to tell that anything moved.
fn export_words_en() -> ExportWords {
  {
    title: "# MAKED session: ",
    session_id: "- **Session id:** ",
    created: "- **Created:** ",
    updated: "- **Last updated:** ",
    mode: "- **Mode:** ",
    started_on: "- **Started on:** ",
    steps_on_path: "- **Steps on this path:** ",
    other_steps: "- **Other steps recorded in this session:** ",
    forked_from: "- **Forked from session:** ",
    at_step: " at step ",
    step_suffix: "",
    run_heading: "## The run so far",
    doing_heading: "## How the run is doing",
    timeline_heading: "## Timeline",
    position: "- **Position:** ",
    detail: "- **Detail:** ",
    why: "- **Why:** ",
    cursor: "- **Cursor after:** ",
    group: " · **group:** ",
    taken_by: " · **taken by:** ",
    other_roads: "## Other roads taken",
    other_prose: "These steps are recorded in the session but are not on its current path: they are the branches that were walked and then walked back from.",
    step_bullet: "- **Step ",
    of: " of ",
    mode_structured: "structured",
    mode_free: "free",
    source_drive: "drive",
    source_explicit: "explicit",
    source_research: "research",
  }
}

///|
/// The words of the Chinese document.
fn export_words_zh() -> ExportWords {
  {
    title: "# MAKED 会话：",
    session_id: "- **会话 id：** ",
    created: "- **创建时间：** ",
    updated: "- **最后更新：** ",
    mode: "- **模式：** ",
    started_on: "- **起点：** ",
    steps_on_path: "- **本路径上的步数：** ",
    other_steps: "- **本会话中记录的其它步数：** ",
    forked_from: "- **分叉自会话：** ",
    at_step: "，分叉于第 ",
    step_suffix: " 步",
    run_heading: "## 到目前为止的运行",
    doing_heading: "## 这次运行做得如何",
    timeline_heading: "## 时间线",
    position: "- **位置：** ",
    detail: "- **细节：** ",
    why: "- **原因：** ",
    cursor: "- **步后光标：** ",
    group: " · **群体：** ",
    taken_by: " · **取自：** ",
    other_roads: "## 走过的其它路径",
    other_prose: "这些步骤记录在会话中，却不在它当前的路径上：它们是走过又走回来的岔路。",
    step_bullet: "- **第 ",
    of: " / ",
    mode_structured: "结构化",
    mode_free: "自由",
    source_drive: "驱动",
    source_explicit: "指定",
    source_research: "研究",
  }
}

///|
/// The words of the document in the language asked for.
fn export_words(lang : Lang) -> ExportWords {
  match lang {
    English => export_words_en()
    Chinese => export_words_zh()
  }
}
