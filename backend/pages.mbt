///| The content model, plus the seed content for the ten public pages.
///
/// The content is carried over from the django CMS deployment of MAKED
/// (`mysite/management/commands/bootstrap_maked.py`) -- but not the claims it
/// made. The original site said the cycle had never been written down and
/// that four of the five applications were empty scaffolds, with nothing
/// routing from one domain to the next. That was true of the django
/// deployment; it is not true of this one, and a page that describes a
/// program nobody wrote is worse than no page at all. The pages now say what
/// the machine actually does.
///
/// Two things about the original are preserved deliberately rather than
/// "tidied":
///
///   - The navigation order is M -> D -> E -> A -> K, the clockwise order the
///     logo draws the ring in. That is *not* the order the name is spelled,
///     and the original site made the same choice. `sort` encodes it.
///   - The five domains keep one line each -- the model formulator, the data
///     turbine, the experience absorber, the attack generator, the knowledge
///     distiller -- because that is what the site is built around.
///
/// Every page says what it says in two languages, and the two are written
/// separately rather than translated from one another. A translation keeps the
/// shape of the original, and the shape of an English paragraph is not the
/// shape a Chinese reader expects. A page with no Chinese falls back to its
/// English, which is the same rule the model's own names follow --
/// `Lang::pick`, in one place, so it cannot drift between the pages.

///|
/// `Eq` is derived so tests can assert on page values directly.
pub(all) struct Page {
  slug : String
  title : String
  letter : String
  role : String
  summary : String
  body : String
  in_navigation : Bool
  sort : Int32
  /// The name in Chinese, for the pages that have one.
  ///
  /// Empty when the model has no Chinese name for the domain, and then the
  /// reader sees `title`. See `Lang::pick`.
  title_zh : String
  /// The phrase in Chinese: "模型构建者".
  ///
  /// Empty when the model has no Chinese phrase for the domain, and then the
  /// reader sees `role`.
  role_zh : String
  /// The one-line summary in Chinese.
  summary_zh : String
  /// The body in Chinese: the same prose, written again rather than
  /// translated.
  body_zh : String
} derive(Eq)

// The `implicit_impl_as_method` deprecation warning on that derive is accepted.
// Declaring `extend Page with Eq::{not_equal, equal}` silences it but trades it
// for two `unused_value` warnings, since nothing calls the promoted forms.

///|
/// The page as JSON, in the language asked for.
///
/// The four words a page says -- its name, its role, its summary and its body
/// -- are each held in both languages, and the language decides which of the
/// two is sent. The fallback is `Lang::pick`: a page with no Chinese is shown
/// in English rather than as a blank.
pub fn Page::to_json(self : Page, lang : Lang) -> Json {
  {
    "slug": self.slug,
    "title": lang.pick(self.title, self.title_zh),
    "letter": self.letter,
    "role": lang.pick(self.role, self.role_zh),
    "summary": lang.pick(self.summary, self.summary_zh),
    "body": lang.pick(self.body, self.body_zh),
    "in_navigation": self.in_navigation,
    "sort": self.sort,
  }
}

///|
/// The five domains, in the clockwise order the logo draws them.
///
/// A function rather than a `const` because MoonBit only allows immutable
/// primitives in constants, and this is a list of tuples.
///
/// The names here are the *site's* copy -- the words the pages were written
/// with. The machine's own name for a domain is the model's, and the pages
/// take it from there when the model has one (see `seed_pages`), so the ring
/// and the machine cannot end up calling the same domain two different names.
pub fn ring_domains() -> Array[(String, String, String, String)] {
  [
    ("model", "Model", "M", "the model formulator"),
    ("data", "Data", "D", "the data turbine"),
    ("experience", "Experience", "E", "the experience absorber"),
    ("attack", "Attack", "A", "the attack generator"),
    ("knowledge", "Knowledge", "K", "the knowledge distiller"),
  ]
}

///|
/// The two names a domain has: the one the machine gives it, and the one the
/// site gave it.
///
/// The machine's name wins, in both languages, because the site and the
/// machine are not two different things -- a domain the site called one
/// thing while the machine called it another would be a name the reader
/// could not trust. A domain the machine does not have keeps the site's
/// name, and a name with no Chinese in it is shown in English rather than as
/// a blank: the same rule as everywhere else, and `Lang::pick` is where it
/// lives.
///
/// The four returned strings are the English name, the English phrase, the
/// Chinese name and the Chinese phrase.
pub fn domain_names(
  letter : String,
  stored_title : String,
  stored_role : String,
) -> (String, String, String, String) {
  let model = current_model()
  let named = model.domain_by_letter(letter)
  let title = match named {
    Some(domain) => domain.title
    None => stored_title
  }
  let role = match named {
    Some(domain) => domain.role
    None => stored_role
  }
  let title_zh = match named {
    Some(domain) => domain.title_zh
    None => ""
  }
  let role_zh = match named {
    Some(domain) => domain.role_zh
    None => ""
  }
  (title, role, title_zh, role_zh)
}

///|
fn domain_body(title : String, letter : String, role : String) -> String {
  let head = "<p class=\"lead\"><strong>" +
    title +
    "</strong> &mdash; " +
    role +
    ".</p>"
  let ring = "This page is the <span class=\"letter\">" +
    letter +
    "</span> node of that ring."
  head +
  "<p>The mark arranges the five domains as a closed ring around a taijitu, running clockwise <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong>. " +
  ring +
  "</p>" +
  "<p>The ring is not a picture of the work; it is a transition table. Which slot can push a position is answered by that table and by nothing else, and a position the table cannot move is reported as blocked rather than quietly passed over. Each domain keeps its own state, and the steps you take are written down as you take them: a session you can open again, rewind, fork, or take away as a document.</p>"
}

///|
fn domain_body_zh(
  title_zh : String,
  letter : String,
  role_zh : String,
) -> String {
  let head = "<p class=\"lead\"><strong>" +
    title_zh +
    "</strong> —— " +
    role_zh +
    "。</p>"
  let ring = "这一页是环上 <span class=\"letter\">" +
    letter +
    "</span> 那个节点。"
  head +
  "<p>标记把五个域排成围绕太极图的闭环，顺时针是 <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong>。" +
  ring +
  "</p>" +
  "<p>这个环不是工作的图画，而是一张迁移表：哪一个槽能推动一个位置，由这张表回答，别的什么都不回答；表里推不动的位置会被报成无路可走，而不是悄悄跳过。每一个域各自记着自己的状态，而走过的每一步都会当场写下来——一个可以再打开、可以回退、可以分叉、也可以带走成文档的会话。</p>"
}

///|
fn home_body() -> String {
  "<p class=\"lead\">MAKED organises its work into five domains, one for each letter of its name. The mark arranges them as a closed ring around a taijitu, running clockwise <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong> &mdash; the cards below follow that order, not the order the name is spelled.</p>" +
  "<p>The ring is the machine. A step is a transition the table really has, the steps are written down as they are taken, and what the run adds up to is reported in measures that can be checked. Beside the ring are the collective, the corpus and the mapping table, the causal estimate, the explorations you can come back to, and a workspace for your own records.</p>"
}

///|
fn home_body_zh() -> String {
  "<p class=\"lead\">MAKED 把工作分成五个域，每个域对应名字里的一个字母。标记把它们排成围绕太极图的闭环，顺时针是 <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong>——下面的卡片按的是这个顺序，不是名字拼写的顺序。</p>" +
  "<p>这个环就是机器本身。一步是表里真实存在的一次迁移，走过的每一步都会当场记下来，而这段过程究竟说明了什么，会用可以核对的度量讲出来。环旁边是集体、语料与映射表、因果估计、可以回来接着走的探索，以及放你自己记录的工作台。</p>"
}

///|
fn about_body() -> String {
  "<p>MAKED &mdash; <strong>M</strong>odel, <strong>A</strong>ttack, <strong>K</strong>nowledge, <strong>E</strong>xperience, <strong>D</strong>ata &mdash; is a site built around five domains. Each domain is a page of this site, so the navigation of the site is the structure of the work itself.</p>" +
  "<p>The mark arranges the five as a closed ring around a taijitu, running clockwise <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong> &mdash; a different order from the way the name is spelled, and a cycle rather than a queue. Each domain page carries a single line: <em>the model formulator</em>, <em>the data turbine</em>, <em>the experience absorber</em>, <em>the attack generator</em>, <em>the knowledge distiller</em>.</p>" +
  "<p>What the cycle is meant to <em>do</em> is still the project's own business rather than a written specification, but it is no longer a picture: the ring is a transition table, and a step is an edge that table really has. The machine is a file, so it can be replaced; so can the corpus, the mapping table and the words the collective is given.</p>" +
  "<p>This deployment runs on MoonBit: a rabbita single-page frontend and a small Flask-style micro-framework built on moonback, with the page content served from SQLite.</p>"
}

///|
fn about_body_zh() -> String {
  "<p>MAKED —— <strong>M</strong>模型、<strong>A</strong>攻击、<strong>K</strong>知识、<strong>E</strong>经验、<strong>D</strong>数据 —— 是一个围绕五个域建起来的站点。每个域都是这个站点的一页，所以站点的导航就是工作本身的结构。</p>" +
  "<p>标记把五个域排成围绕太极图的闭环，顺时针是 <strong>M &rarr; D &rarr; E &rarr; A &rarr; K</strong> —— 跟名字拼写的顺序不同，而且是环，不是队列。每一个域的页面上都只有一句话：<em>模型构建者</em>、<em>数据涡轮</em>、<em>经验吸收者</em>、<em>攻击生成者</em>、<em>知识蒸馏者</em>。</p>" +
  "<p>这个环究竟要<em>做</em>什么，仍然是这个项目自己的事，而不是一份写下来的规格；但它已经不再只是一张图：环就是一张迁移表，一步就是表里真实存在的一条边。机器是一个文件，所以可以换掉；语料、映射表和集体被赋予的词汇也都是文件，同样可以换掉。</p>" +
  "<p>这一版部署跑在 MoonBit 上：前端是 rabbita 的单页应用，后端是建在 moonback 上的一个小型 Flask 式微框架，页面内容由 SQLite 提供。</p>"
}

///|
fn tutorial_body() -> String {
  "<h3>Run it</h3><p>The backend serves both the JSON API and the built frontend from a single process:</p>" +
  "<pre><code>moon build --release --target native cmd/server\nmoon build --release --target js cmd/web\nmoon run --target native cmd/server</code></pre>" +
  "<p>Open <code>http://127.0.0.1:8080/</code>. The server holds ten pages &mdash; the five domains, three utility pages, the index and the 404 &mdash; and the browser app is a single page that routes among them; the API is under <code>/api/</code>.</p>" +
  "<h3>Layout</h3><p><code>backend/</code> holds the micro-framework, the SQLite storage layer and the API routes. <code>frontend/</code> holds the rabbita SPA. <code>cmd/server</code> is the native entry point and <code>cmd/web</code> builds the browser bundle.</p>"
}

///|
fn tutorial_body_zh() -> String {
  "<h3>跑起来</h3><p>后端用同一个进程同时提供 JSON API 和构建好的前端：</p>" +
  "<pre><code>moon build --release --target native cmd/server\nmoon build --release --target js cmd/web\nmoon run --target native cmd/server</code></pre>" +
  "<p>打开 <code>http://127.0.0.1:8080/</code>。服务器里存着十页 —— 五个域、三张工具页、首页和 404 —— 浏览器端是一个在这些页面之间路由的单页应用；API 在 <code>/api/</code> 下面。</p>" +
  "<h3>目录</h3><p><code>backend/</code> 放微框架、SQLite 存储层和 API 路由；<code>frontend/</code> 放 rabbita 的单页应用；<code>cmd/server</code> 是原生入口，<code>cmd/web</code> 构建浏览器那份。</p>"
}

///|
fn tasks_body() -> String {
  "<p>The original site's \"task monitor\" was a bare link to a flower instance on the author's LAN, unreachable for anyone else. There is no broker in this deployment, so the page reports what the server itself is doing: the SQLite file it opened, and the pages it serves.</p>" +
  "<p>See <code>GET /api/status</code> for the same information as JSON.</p>"
}

///|
fn tasks_body_zh() -> String {
  "<p>原站点的“任务监视”只是一个链接，指向作者局域网里的一台 flower 实例，别的机器谁也访问不到。这一版部署里没有消息代理，所以这一页报告的是服务器自己在做的事：它打开的 SQLite 文件，以及它提供的页面。</p>" +
  "<p>同样的信息以 JSON 的形式在 <code>GET /api/status</code>。</p>"
}

///|
fn not_found_body() -> String {
  "<p>The loop is closed, but this path is not on the ring. Try one of the five domains, or head back to the <a href=\"/\">index</a>.</p>"
}

///|
fn not_found_body_zh() -> String {
  "<p>环是闭上的，但这条路径不在环上。去看看五个域中的一个，或者回到<a href=\"/\">首页</a>。</p>"
}

///|
pub fn not_found_page() -> Page {
  {
    slug: "404",
    title: "Not found",
    letter: "",
    role: "",
    summary: "off the ring",
    body: not_found_body(),
    in_navigation: false,
    sort: 999,
    title_zh: "未找到",
    role_zh: "",
    summary_zh: "不在环上",
    body_zh: not_found_body_zh(),
  }
}

///|
/// The eight pages the navigation shows, in navigation order.
///
/// The five domain pages are named by the machine rather than by the site:
/// a domain the model has a name for is called what the model calls it, in
/// both languages, and a domain the model does not have keeps the name the
/// site gave it. That is the one place the two could have drifted apart --
/// the site calling a domain one thing and the machine calling it another --
/// so it is settled here rather than in two tables.
pub fn seed_pages() -> Array[Page] {
  let pages = []
  let mut sort = 0
  for (slug, stored_title, letter, stored_role) in ring_domains() {
    let (page_title, page_role, title_zh, role_zh) = domain_names(
      letter, stored_title, stored_role,
    )
    pages.push({
      slug,
      title: page_title,
      letter,
      role: page_role,
      summary: page_role,
      body: domain_body(page_title, letter, page_role),
      // The Chinese body names the domain the way the machine names it, and
      // falls back to the English name when the machine has no Chinese for
      // it -- the same fallback, in the same place, as everywhere else.
      body_zh: domain_body_zh(
        if title_zh == "" {
          page_title
        } else {
          title_zh
        },
        letter,
        if role_zh == "" {
          page_role
        } else {
          role_zh
        },
      ),
      in_navigation: true,
      sort,
      title_zh,
      role_zh,
      summary_zh: role_zh,
    })
    sort += 1
  }
  for
    (slug, title, title_zh, summary, summary_zh, body, body_zh) in [
      (
        "tutorial",
        "Tutorial",
        "教程",
        "how to run it",
        "怎么跑起来",
        tutorial_body(),
        tutorial_body_zh(),
      ),
      (
        "about",
        "About",
        "关于",
        "what this is",
        "这是什么",
        about_body(),
        about_body_zh(),
      ),
      (
        "tasks",
        "Tasks",
        "任务",
        "what the server is doing",
        "服务器在做什么",
        tasks_body(),
        tasks_body_zh(),
      ),
    ] {
    pages.push({
      slug,
      title,
      letter: "",
      role: "",
      summary,
      body,
      in_navigation: true,
      sort,
      title_zh,
      role_zh: "",
      summary_zh,
      body_zh,
    })
    sort += 1
  }
  pages
}

///|
pub fn home_page() -> Page {
  {
    slug: "index",
    title: "Index",
    letter: "",
    role: "",
    summary: "five domains, one closed ring",
    body: home_body(),
    in_navigation: false,
    sort: -1,
    title_zh: "首页",
    role_zh: "",
    summary_zh: "五个域，一个闭环",
    body_zh: home_body_zh(),
  }
}
