// The language of the interface, and the words it is made of.
//
// The frontend cannot ask the backend which language it is speaking: the two
// are separate packages and separate targets -- the backend builds for native,
// this builds for js -- so the backend's `Lang` is not reachable from here.
// The frontend therefore carries its own language type. It is the same two
// languages and the same rule about them: `zh` means Chinese, anything else
// means English, and an unknown language is answered rather than refused.
//
// The words are the interface's own: the furniture around the machine, the
// buttons, the empty states, the sentences the client writes for itself. The
// words the *machine* has -- the positions, the slots, the glosses, the
// narrations -- are the backend's, and they come back in the language the
// request asked for. Two vocabularies, two places, one switch.
//
// The Chinese here is written in Chinese. It is not the English translated:
// a translated sentence keeps the English's shape (an article where Chinese
// does not have one, a capital letter, "and" where Chinese would use a
// comma), and a sentence in that shape reads as neither language. The
// translation is therefore a second set of sentences rather than a lookup
// table, and where the English is a template the Chinese is a template too.
//
// The two sets are held in one record per area and built twice, once per
// language. That is deliberate: a record has to name every field it has, so a
// string added to one language and forgotten in the other is a compile error
// rather than a blank button.
//
// A word with a hole in it -- a sentence that mentions a number or a name --
// is a function rather than a field. A field would have to interpolate at the
// point it was written, where the value to interpolate is not yet in scope.

///|
/// The language the interface is speaking.
///
/// `pub` rather than `pub(all)`, for the same reason the backend's `Lang` is:
/// an enum's constructors are read-only outside the package that defines it,
/// so the ways of *having* a language are the two functions below rather than
/// the bare variants.
pub enum UiLang {
  /// The reading MAKED was built with.
  English
  /// The reading the table has in Chinese.
  Chinese
} derive(Eq, Debug)

///|
pub extend UiLang with Eq::{not_equal, equal}

///|
pub extend UiLang with Debug::{to_repr}

///|
/// The English reading.
///
/// A function rather than the bare constructor, so that a package outside this
/// one -- the blackbox test package, or anything that mounts the app -- can
/// hold a language without being able to write one.
pub fn UiLang::english() -> UiLang {
  English
}

///|
/// The Chinese reading.
///
/// The same reason as `UiLang::english`.
pub fn UiLang::chinese() -> UiLang {
  Chinese
}

///|
/// The query-string spelling of a language.
///
/// This is what goes after `?lang=`, and it is what the backend's own
/// `lang_of` reads on the other end of the same request.
pub fn UiLang::code(self : UiLang) -> String {
  match self {
    English => "en"
    Chinese => "zh"
  }
}

///|
/// Read a language out of a query string.
///
/// The rule is the backend's rule: `zh` is Chinese, everything else is
/// English. An unknown language is not an error -- a client that asks for a
/// language this server does not have should still get an answer, and the
/// answer it gets is the one it would have got without asking.
pub fn UiLang::parse(s : String) -> UiLang {
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
/// The other language: what the switch in the header switches to.
pub fn UiLang::other(self : UiLang) -> UiLang {
  match self {
    English => Chinese
    Chinese => English
  }
}

///|
/// The five domains, in the words the model uses for them.
///
/// The page titles come from the database, where they were seeded in English,
/// and the pages themselves are prose the database holds -- so the titles are
/// translated here rather than asked for, and the prose is left as it is.
/// A letter is the stable name of a domain; the title is not.
pub fn domain_title(letter : String, lang : UiLang) -> String {
  match (letter, lang) {
    ("M", Chinese) => "模型"
    ("D", Chinese) => "数据"
    ("E", Chinese) => "经验"
    ("A", Chinese) => "攻击"
    ("K", Chinese) => "知识"
    (_, English) =>
      match letter {
        "M" => "Model"
        "D" => "Data"
        "E" => "Experience"
        "A" => "Attack"
        "K" => "Knowledge"
        _ => letter
      }
    (_, Chinese) => letter
  }
}

///|
/// What a domain is for, in the model's own words.
pub fn domain_role(letter : String, lang : UiLang) -> String {
  match (letter, lang) {
    ("M", Chinese) => "模型构建者"
    ("D", Chinese) => "数据涡轮"
    ("E", Chinese) => "经验吸收者"
    ("A", Chinese) => "攻击生成者"
    ("K", Chinese) => "知识蒸馏者"
    (_, English) =>
      match letter {
        "M" => "Model Builder"
        "D" => "Data Turbine"
        "E" => "Experience Absorber"
        "A" => "Attack Generator"
        "K" => "Knowledge Distiller"
        _ => ""
      }
    (_, Chinese) => ""
  }
}

///|
/// The words of the shell: the header, the navigation, and the three states
/// every page can be in.
pub struct NavWords {
  tagline : String
  workspace : String
  sessions : String
  timeline : String
  not_found : String
  loading : String
  server_unavailable : String
}

///|
/// The words of the loop panel: the buttons, and the three sentences that
/// explain what the machine did or refused to do.
pub struct LoopWords {
  title : String
  loading_status : String
  reset : String
  blocked : String
  drive_slots : String
  what_happened : String
  run_so_far : String
  open_sessions : String
  no_steps : String
  how_doing : String
}

///|
/// The words of the corpus panel and of the mapping table under it.
pub struct ResearchWords {
  corpus_title : String
  read_corpus : String
  drive_with : String
  not_read : String
  no_documents : String
  untitled : String
  trigger_mappings : String
  mapping_table : String
  show_table : String
  the_table : String
  run_table : String
  table_running : String
  saving : String
  table_unavailable : String
  table_refused : String
  table_not_saved : String
}

///|
/// The words of the sessions page: the timeline, and everything said about a
/// session that has been named, opened, forked or forgotten.
pub struct SessionWords {
  title : String
  lede : String
  name_label : String
  name_placeholder : String
  new_session : String
  export_md : String
  export_json : String
  rename : String
  go_back : String
  fork : String
  no_steps : String
  other_roads : String
  other_roads_note : String
  really_delete : String
  delete : String
  delete_title : String
  open : String
  all_sessions : String
  no_sessions : String
  run_so_far : String
  timeline : String
  started : String
  opened : String
  went_back : String
  forked : String
  renamed : String
  forgot : String
  give_name : String
  starting : String
  opening : String
  going_back : String
  forking : String
  renaming : String
  deleting : String
  confirm_delete : String
  branch : String
  branch_suffix : String
}

///|
/// The words of the workspace: the user's own records.
pub struct WorkspaceWords {
  title : String
  lede : String
  your_records : String
  question : String
  title_label : String
  title_placeholder : String
  body_label : String
  body_placeholder : String
  save_to : String
  target_none : String
  delete : String
  saving : String
  deleting : String
  empty : String
  refused : String
  removed : String
  no_domain : String
  wrong_domain : String
  no_title : String
}

///|
/// The words the client writes for itself: the failures that are not the
/// server's to explain.
pub struct StatusWords {
  server_unreachable : String
  loop_unavailable : String
  step_failed : String
  reset_failed : String
  research_unavailable : String
  research_drive_failed : String
  causal_unavailable : String
  society_unavailable : String
  move_unreached : String
}

///|
/// The words of the causal panel.
pub struct CausalWords {
  title : String
  lede : String
  estimate_button : String
  empty : String
  not_made : String
  groups_looked : String
  treatment : String
  outcome : String
  effect : String
  standard_error : String
  confidence_interval : String
  documents : String
  controlled_nothing : String
  robustness : String
  worst_case : String
  sign_survives : String
  yes : String
  no : String
  what_estimated : String
  what_controlled : String
  confounders_note : String
  balance : String
  overlap : String
  overlap_yes : String
  what_that_means : String
  how_wrong : String
  impact_note : String
  no_balance : String
  variable : String
  treated : String
  untreated : String
  difference : String
  verdict : String
  verdict_no_overlap : String
  verdict_close : String
  verdict_differ : String
}

///|
/// The words of the collective's panel.
pub struct SocietyWords {
  title : String
  lede : String
  read : String
  not_read : String
  stayed : String
  multi : String
  no_move : String
  where_stands : String
  position : String
  phase : String
  what_it_means : String
  what_it_can_do : String
  the_machine : String
  positions : String
  moves_in_machine : String
  words_from : String
  shipped_words : String
  behind_machine : String
  behind_machine_note : String
  no_move_out : String
  move_word : String
  lands_at : String
}

///|
/// Every word the interface says that the machine does not.
///
/// The language is part of it, because the sentences with a hole in them are
/// functions that need to know which language to write themselves in.
pub struct Chrome {
  lang : UiLang
  nav : NavWords
  loop_panel : LoopWords
  research : ResearchWords
  sessions : SessionWords
  workspace : WorkspaceWords
  status : StatusWords
  causal : CausalWords
  society : SocietyWords
}

///|
/// The words of the shell, in English.
fn nav_en() -> NavWords {
  {
    tagline: "Model · Attack · Knowledge · Experience · Data",
    workspace: "Workspace",
    sessions: "Sessions",
    timeline: "Timeline",
    not_found: "Not found",
    loading: "Loading…",
    server_unavailable: "Server unavailable",
  }
}

///|
/// The words of the shell, in Chinese.
fn nav_zh() -> NavWords {
  {
    tagline: "模型 · 攻击 · 知识 · 经验 · 数据",
    workspace: "工作台",
    sessions: "会话",
    timeline: "时间线",
    not_found: "未找到",
    loading: "加载中…",
    server_unavailable: "服务不可用",
  }
}

///|
/// The words of the loop panel, in English.
fn loop_en() -> LoopWords {
  {
    title: "Loop",
    loading_status: "Loading loop status…",
    reset: "Reset",
    blocked: "Nothing can move from here: no slot has an outgoing edge at this position. That is a property of the model, not a failure, so Step will not change the position.",
    drive_slots: "Drive slots. Each one says whether the transition table has an outgoing edge from this position; the highlighted one is this domain's drive slot.",
    what_happened: "What just happened",
    run_so_far: "The run so far",
    open_sessions: "open the sessions",
    no_steps: "No steps yet.",
    how_doing: "How the run is doing",
  }
}

///|
/// The words of the loop panel, in Chinese.
fn loop_zh() -> LoopWords {
  {
    title: "环",
    loading_status: "正在读取环的状态…",
    reset: "复位",
    blocked: "从这里动不了：这个位置上没有任何槽有出边。这是模型本身的性质，不是故障，所以步进不会改变位置。",
    drive_slots: "驱动槽。每一个都说明迁移表在这个位置上有没有出边；高亮的那个是本域的驱动槽。",
    what_happened: "刚刚发生了什么",
    run_so_far: "到此为止的记录",
    open_sessions: "打开会话列表",
    no_steps: "还没有步进。",
    how_doing: "这段过程目前如何",
  }
}

///|
/// The words of the corpus panel, in English.
fn research_en() -> ResearchWords {
  {
    corpus_title: "The Corpus",
    read_corpus: "Read the corpus",
    drive_with: "Drive the loop with them",
    not_read: "The corpus has not been read yet.",
    no_documents: "No documents yet. Click 'Read the corpus' to begin.",
    untitled: "Untitled",
    trigger_mappings: "Trigger Mappings",
    mapping_table: "The mapping table",
    show_table: "Show the table",
    the_table: "The table",
    run_table: "Run this table",
    table_running: "The table is running.",
    saving: "Saving…",
    table_unavailable: "the mapping table is unavailable",
    table_refused: "the server refused the table",
    table_not_saved: "the table could not be saved",
  }
}

///|
/// The words of the corpus panel, in Chinese.
fn research_zh() -> ResearchWords {
  {
    corpus_title: "语料",
    read_corpus: "读取语料",
    drive_with: "用它们驱动环",
    not_read: "语料还没有被读取。",
    no_documents: "还没有文档。点击“读取语料”开始。",
    untitled: "无标题",
    trigger_mappings: "触发映射",
    mapping_table: "映射表",
    show_table: "显示表格",
    the_table: "表格",
    run_table: "运行这张表",
    table_running: "表格正在运行。",
    saving: "保存中…",
    table_unavailable: "映射表不可用",
    table_refused: "服务器拒绝了这张表",
    table_not_saved: "这张表没能保存",
  }
}

///|
/// The words of the sessions page, in English.
fn sessions_en() -> SessionWords {
  {
    title: "Sessions",
    lede: "A session is one exploration, kept. Name it, take steps in it, and come back to it later: the steps are stored with the machine, not in the page, so a restart does not lose them.",
    name_label: "Name a new session",
    name_placeholder: "What is this exploration called?",
    new_session: "New session",
    export_md: "Export Markdown",
    export_json: "Export JSON",
    rename: "Rename",
    go_back: "Go back to here",
    fork: "Fork from here",
    no_steps: "No steps yet. Take one in the Loop panel and it will be recorded here.",
    other_roads: "Other roads taken",
    other_roads_note: "These steps are recorded in the session but are not on its current path: the branches that were walked and then walked back from.",
    really_delete: "Really delete?",
    delete: "Delete",
    delete_title: "Delete this session and every step in it",
    open: "Open",
    all_sessions: "All sessions",
    no_sessions: "No sessions yet.",
    run_so_far: "The run so far",
    timeline: "Timeline",
    started: "Started a new session.",
    opened: "Opened that session and put the loop back where it was.",
    went_back: "Went back to that step. The steps after it are still recorded.",
    forked: "Forked a new session at that step. The loop is standing there; pick a slot to try another road.",
    renamed: "Renamed the session.",
    forgot: "Forgot that session and its steps.",
    give_name: "give the session a name",
    starting: "Starting…",
    opening: "Opening…",
    going_back: "Going back…",
    forking: "Forking…",
    renaming: "Renaming…",
    deleting: "Deleting…",
    confirm_delete: "Click Delete again to delete that session and every step in it.",
    branch: "Branch",
    branch_suffix: " (branch)",
  }
}

///|
/// The words of the sessions page, in Chinese.
fn sessions_zh() -> SessionWords {
  {
    title: "会话",
    lede: "一个会话就是一次被留住的探索。给它起个名字，在里面走步进，日后回来接着走：步进跟机器存在一起，不存在页面里，所以重启不会丢掉它们。",
    name_label: "给新会话起个名字",
    name_placeholder: "这次探索叫什么？",
    new_session: "新建会话",
    export_md: "导出 Markdown",
    export_json: "导出 JSON",
    rename: "重命名",
    go_back: "回到这里",
    fork: "从这里分叉",
    no_steps: "还没有步进。在环面板里走一步，就会记录在这里。",
    other_roads: "走过的其他岔路",
    other_roads_note: "这些步进记录在会话里，但不在当前路径上：那是走过又退回来的岔路。",
    really_delete: "真的要删除吗？",
    delete: "删除",
    delete_title: "删除这个会话及其中的每一步",
    open: "打开",
    all_sessions: "所有会话",
    no_sessions: "还没有会话。",
    run_so_far: "到此为止的记录",
    timeline: "时间线",
    started: "新会话已开始。",
    opened: "已打开那个会话，并把环放回原来的位置。",
    went_back: "已退回那一步。它之后的步进仍然记录着。",
    forked: "已在那一步分叉出新会话。环就停在那里；选一个槽，走另一条路。",
    renamed: "会话已改名。",
    forgot: "已忘掉那个会话及其中的步进。",
    give_name: "给会话起个名字",
    starting: "启动中…",
    opening: "打开中…",
    going_back: "回退中…",
    forking: "分叉中…",
    renaming: "重命名中…",
    deleting: "删除中…",
    confirm_delete: "再点一次“删除”才会删除那个会话及其中的每一步。",
    branch: "分叉",
    branch_suffix: "（分叉）",
  }
}

///|
/// The words of the workspace, in English.
fn workspace_en() -> WorkspaceWords {
  {
    title: "Workspace",
    lede: "Everything else here is the project's own words. This part is yours: put a model, a dataset, or a failure you want to understand into the domain it belongs to, and it stays on this machine.",
    your_records: "Your records",
    question: "Which domain does this belong to?",
    title_label: "Title",
    title_placeholder: "The model, the dataset, the failure",
    body_label: "What happened",
    body_placeholder: "What you tried, what came out, and what you think it means.",
    save_to: "Save to ",
    target_none: "a domain",
    delete: "Delete",
    saving: "Saving…",
    deleting: "Deleting…",
    empty: "Nothing here yet. The first record is usually the thing you most want to forget about.",
    refused: "the server refused the entry",
    removed: "Removed one record.",
    no_domain: "choose a domain first",
    wrong_domain: "the domain must be one of M, D, E, A, K",
    no_title: "give the entry a title",
  }
}

///|
/// The words of the workspace, in Chinese.
fn workspace_zh() -> WorkspaceWords {
  {
    title: "工作台",
    lede: "这里其余的，都是这个项目自己的话。这一部分是你的：把一个模型、一份数据集，或者一次你想弄明白的失败，放进它所属的域里，它就留在这台机器上。",
    your_records: "你的记录",
    question: "这属于哪个域？",
    title_label: "标题",
    title_placeholder: "模型、数据集、失败",
    body_label: "发生了什么",
    body_placeholder: "你试了什么、得到了什么、以及你认为这意味着什么。",
    save_to: "保存到",
    target_none: "某个域",
    delete: "删除",
    saving: "保存中…",
    deleting: "删除中…",
    empty: "这里还什么都没有。第一条记录，通常是你最想忘掉的那一条。",
    refused: "服务器拒绝了这条记录",
    removed: "已删除一条记录。",
    no_domain: "先选一个域",
    wrong_domain: "域必须是 M、D、E、A、K 之一",
    no_title: "给这条记录起个标题",
  }
}

///|
/// The words the client writes for itself, in English.
fn status_en() -> StatusWords {
  {
    server_unreachable: "could not reach the server",
    loop_unavailable: "loop status unavailable",
    step_failed: "step failed",
    reset_failed: "reset failed",
    research_unavailable: "research data unavailable",
    research_drive_failed: "research drive failed",
    causal_unavailable: "causal inference unavailable",
    society_unavailable: "the collective is unavailable",
    move_unreached: "the move did not reach the server",
  }
}

///|
/// The words the client writes for itself, in Chinese.
fn status_zh() -> StatusWords {
  {
    server_unreachable: "连不上服务器",
    loop_unavailable: "环的状态不可用",
    step_failed: "步进失败",
    reset_failed: "复位失败",
    research_unavailable: "研究数据不可用",
    research_drive_failed: "研究驱动失败",
    causal_unavailable: "因果推断不可用",
    society_unavailable: "集体不可用",
    move_unreached: "这一步没有到达服务器",
  }
}

///|
/// The words of the causal panel, in English.
fn causal_en() -> CausalWords {
  {
    title: "Causal Inference",
    lede: "What claiming to be new is worth, on MAKED's own measure of a document -- and what that answer rests on.",
    estimate_button: "Estimate Causal Effect (DoubleML)",
    empty: "Click the button to run causal inference on the corpus.",
    not_made: "The estimate was not made",
    groups_looked: "What the two groups looked like",
    treatment: "Treatment",
    outcome: "Outcome",
    effect: "Effect (θ)",
    standard_error: "Standard error",
    confidence_interval: "95% confidence interval",
    documents: "Documents",
    controlled_nothing: "This estimate controlled for nothing.",
    robustness: "Robustness value",
    worst_case: "Worst-case interval",
    sign_survives: "Does the sign survive the worst case?",
    yes: "yes",
    no: "no",
    what_estimated: "What is being estimated",
    what_controlled: "What was controlled for",
    confounders_note: "Each of those is compared between the two groups below. A variable the two groups differ on is not doing its job.",
    balance: "Balance of the two groups",
    overlap: "Overlap",
    overlap_yes: "The two groups overlap",
    what_that_means: "What that means",
    how_wrong: "How wrong could this be?",
    impact_note: "The impact score is MAKED's own measure of a document's shape -- its length, its authorship and its breadth. It is not a citation count, so this is an estimate about that score and not about the literature.",
    no_balance: "No balance was reported.",
    variable: "Variable",
    treated: "Treated",
    untreated: "Untreated",
    difference: "Difference",
    verdict: "Verdict",
    verdict_no_overlap: "the two groups do not overlap on this",
    verdict_close: "the two groups are close on this",
    verdict_differ: "the two groups differ on this",
  }
}

///|
/// The words of the causal panel, in Chinese.
fn causal_zh() -> CausalWords {
  {
    title: "因果推断",
    lede: "以 MAKED 自己衡量文档的方式，“声称是新的”值多少——以及这个答案站在什么之上。",
    estimate_button: "估计因果效应（DoubleML）",
    empty: "点击按钮，对语料做因果推断。",
    not_made: "估计没有做出",
    groups_looked: "两组各自是什么样子",
    treatment: "处理变量",
    outcome: "结果变量",
    effect: "效应（θ）",
    standard_error: "标准误",
    confidence_interval: "95% 置信区间",
    documents: "文档",
    controlled_nothing: "这个估计没有控制任何东西。",
    robustness: "稳健性值",
    worst_case: "最坏情形区间",
    sign_survives: "符号在最坏情形下还在吗？",
    yes: "是",
    no: "否",
    what_estimated: "正在估计什么",
    what_controlled: "控制了哪些变量",
    confounders_note: "下面每一项都在两组之间比较。两组在某项上不同，说明这一项没有起作用。",
    balance: "两组的均衡",
    overlap: "重叠",
    overlap_yes: "两组有重叠",
    what_that_means: "这意味着什么",
    how_wrong: "这可能错到什么程度？",
    impact_note: "影响力分数是 MAKED 对文档形态的自己的度量——它的长度、作者与广度。它不是引用次数，所以这里估计的是那个分数，而不是文献本身。",
    no_balance: "没有报告均衡情况。",
    variable: "变量",
    treated: "处理组",
    untreated: "未处理组",
    difference: "差异",
    verdict: "判定",
    verdict_no_overlap: "两组在这一项上没有重叠",
    verdict_close: "两组在这一项上很接近",
    verdict_differ: "两组在这一项上有差异",
  }
}

///|
/// The words of the collective's panel, in English.
fn society_en() -> SocietyWords {
  {
    title: "Society",
    lede: "The collective: where it stands, what it can do from there, and what the last move actually did.",
    read: "Read the Collective",
    not_read: "The collective has not been read yet. MAKED will ask the machine where it stands.",
    stayed: "The collective stayed where it was.",
    multi: "The move left the collective more than one place to be.",
    no_move: "The collective did not move.",
    where_stands: "Where the collective stands",
    position: "Position",
    phase: "Phase",
    what_it_means: "What it means",
    what_it_can_do: "What it can do from here",
    the_machine: "The machine",
    positions: "Positions",
    moves_in_machine: "Moves in the machine",
    words_from: "The words come from",
    shipped_words: "the words MAKED ships with",
    behind_machine: "The vocabulary is behind the machine",
    behind_machine_note: "These are names the machine has and the vocabulary file does not. The panel shows them rather than rendering the positions blank.",
    no_move_out: "No move leads out of this position. The collective is stuck here until something else changes.",
    move_word: "Move",
    lands_at: "Lands at",
  }
}

///|
/// The words of the collective's panel, in Chinese.
fn society_zh() -> SocietyWords {
  {
    title: "社会",
    lede: "集体：它站在哪里、从那里能做什么，以及上一次移动究竟做了什么。",
    read: "读取集体",
    not_read: "集体还没有被读取。MAKED 会向机器问它站在哪里。",
    stayed: "集体停在原地。",
    multi: "这一步让集体同时身处不止一处。",
    no_move: "集体没有移动。",
    where_stands: "集体站在哪里",
    position: "位置",
    phase: "阶段",
    what_it_means: "这意味着什么",
    what_it_can_do: "从这里能做什么",
    the_machine: "机器",
    positions: "位置",
    moves_in_machine: "机器里的迁移",
    words_from: "这些词来自",
    shipped_words: "MAKED 自带的词",
    behind_machine: "词汇落后于机器",
    behind_machine_note: "这些名字机器有，而词汇文件没有。这里把它们列出来，而不是把位置渲染成空白。",
    no_move_out: "没有迁移能离开这个位置。集体卡在这里，直到别的东西发生变化。",
    move_word: "迁移",
    lands_at: "落到",
  }
}

///|
/// The words of the interface, in the language asked for.
pub fn chrome(lang : UiLang) -> Chrome {
  match lang {
    English =>
      {
        lang,
        nav: nav_en(),
        loop_panel: loop_en(),
        research: research_en(),
        sessions: sessions_en(),
        workspace: workspace_en(),
        status: status_en(),
        causal: causal_en(),
        society: society_en(),
      }
    Chinese =>
      {
        lang,
        nav: nav_zh(),
        loop_panel: loop_zh(),
        research: research_zh(),
        sessions: sessions_zh(),
        workspace: workspace_zh(),
        status: status_zh(),
        causal: causal_zh(),
        society: society_zh(),
      }
  }
}

///|
/// The words of the interface, in the language asked for, for a caller that
/// has a language and not a table.
pub fn chrome_of(lang : UiLang) -> Chrome {
  chrome(lang)
}

///|
/// The query string that tells the server which language to answer in.
///
/// Only the endpoints that read it carry it. The server honours `?lang=` on
/// the endpoints that answer about the loop, the timeline and the research;
/// the others answer in one language only, and carrying the switch there
/// would be a promise the server does not keep.
pub fn lang_query(lang : UiLang) -> String {
  "?lang=" + lang.code()
}

// --- the sentences with a hole in them ------------------------------------
//
// Each of these writes itself in the language it is asked for. The English
// and the Chinese are two sentences rather than one sentence and a
// substitution, because a Chinese sentence is not an English sentence with
// its nouns replaced.

///|
pub fn nothing_at(c : Chrome, slug : String) -> String {
  match c.lang {
    English =>
      "Nothing at /" +
      slug +
      ". Try one of the five domains, or head back to the index."
    Chinese =>
      "/" +
      slug +
      " 上什么都没有。可以去看看五个域中的一个，或者回到首页。"
  }
}

///|
pub fn step_caption(c : Chrome, next_domain : String) -> String {
  match c.lang {
    English => "Step → " + next_domain
    Chinese => "步进 → " + next_domain
  }
}

///|
pub fn no_edge(c : Chrome, designation : String) -> String {
  match c.lang {
    English => designation + " · no edge here"
    Chinese => designation + " · 此处无出边"
  }
}

///|
pub fn undecided_situation(c : Chrome, count : String) -> String {
  match c.lang {
    English =>
      "The table offers " +
      count +
      " outgoing edges here and declines to choose between them. Pick one on purpose."
    Chinese =>
      "表格在这里给出 " +
      count +
      " 条出边，却不肯替你在其中选一条。请自己选一条。"
  }
}

///|
pub fn normal_situation(c : Chrome, count : String) -> String {
  match c.lang {
    English =>
      count +
      " of the 8 slots can move this position. The rest have no outgoing edge here and will do nothing."
    Chinese =>
      "8 个槽里有 " +
      count +
      " 个能移动这个位置。其余的在这里没有出边，按下去什么也不会发生。"
  }
}

///|
pub fn way_out(c : Chrome, count : String, designation : String) -> String {
  match c.lang {
    English =>
      "The table offered " +
      count +
      " ways out of here through " +
      designation +
      " and would not choose between them. Pick one:"
    Chinese =>
      "表格通过" +
      designation +
      "给出 " +
      count +
      " 条出路，却不肯替你选。请选一条："
  }
}

///|
pub fn drive_slot(c : Chrome, slot : String) -> String {
  match c.lang {
    English => "drive: " + slot
    Chinese => "驱动槽：" + slot
  }
}

///|
pub fn recording_into(c : Chrome, name : String, count : String) -> String {
  match c.lang {
    English => "Recording into “" + name + "” · " + count + " steps · "
    Chinese => "正记录到“" + name + "” · " + count + " 步 · "
  }
}

///|
pub fn metric_reading(c : Chrome, value : String, total : String) -> String {
  match c.lang {
    English => value + " of " + total
    Chinese => value + " / " + total
  }
}

///|
pub fn corpus_source(c : Chrome, source : String) -> String {
  match c.lang {
    English => "Reading: " + source
    Chinese => "正在读取：" + source
  }
}

///|
pub fn not_json(c : Chrome, reason : String) -> String {
  match c.lang {
    English => "that is not JSON: " + reason
    Chinese => "那不是 JSON：" + reason
  }
}

///|
pub fn steps_on_path(c : Chrome, count : String) -> String {
  match c.lang {
    English => count + " steps on this path"
    Chinese => "这条路径上有 " + count + " 步"
  }
}

///|
pub fn other_steps(c : Chrome, count : String) -> String {
  match c.lang {
    English => " · " + count + " other steps recorded"
    Chinese => " · 另有 " + count + " 步被记录"
  }
}

///|
pub fn session_steps(c : Chrome, count : String) -> String {
  match c.lang {
    English => count + " steps"
    Chinese => count + " 步"
  }
}

///|
pub fn save_to(c : Chrome, target : String) -> String {
  match c.lang {
    English => "Save to " + target
    Chinese => "保存到" + target
  }
}

///|
pub fn domain_target(c : Chrome, letter : String) -> String {
  match c.lang {
    English => "the " + letter + " domain"
    Chinese => letter + " 域"
  }
}

///|
pub fn saved_entry(c : Chrome, title : String, domain : String) -> String {
  match c.lang {
    English => "Saved “" + title + "” to the " + domain + " domain."
    Chinese => "已把“" + title + "”保存到 " + domain + " 域。"
  }
}

///|
pub fn documents_count(c : Chrome, count : String, treated : String) -> String {
  match c.lang {
    English => count + " (" + treated + " treated)"
    Chinese => count + "（其中 " + treated + " 被处理）"
  }
}

///|
pub fn collective_moved_to(c : Chrome, label : String) -> String {
  match c.lang {
    English => "The collective moved to " + label + "."
    Chinese => "集体移到了" + label + "。"
  }
}

///|
pub fn collective_moved_from(
  c : Chrome,
  from : String,
  label : String,
) -> String {
  match c.lang {
    English => "The collective moved from " + from + " to " + label + "."
    Chinese => "集体从" + from + "移到了" + label + "。"
  }
}
