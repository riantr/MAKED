# MAKED on MoonBit

**递归自进化建模框架** — 以对抗性知识循环为设计哲学。

MAKED 是一个五相递归认知架构：Model → Data → Experience → Attack → Knowledge 构成闭环，每一相都是上一相的对抗与超越。系统通过自身的循环驱动状态迁移，从 arxiv 研究论文到因果推断再到 pyroduct 状态机，形成自驱动的知识进化闭环。

技术实现：[rabbita](https://mooncakes.io/docs/moonbit-community/rabbita@0.16.4) 单页前端 + [moonback](https://mooncakes.io) 上的 Flask 风格微框架后端，SQLite 存储。

## 核心概念

### 五相环 (M → D → E → A → K)

| 相 | 域 | Pyroduct 位置 | 驱动槽 | 结构关系 |
|---|---|---|---|---|
| M | Model | 立位 Standing | 共在 CoBeing | 模型立足，一脚踏入过去，一脚踏入未来 |
| D | Data | 相遇 Encounter | 反馈 Feedback | 模型与他者（数据）的不可回避的遭遇 |
| E | Experience | 受赏 Honor | 揭蔽 Unveil | 经验作为来自偶像的奖赏被吸收 |
| A | Attack | 受挫 Evil | 持存 Hold | 攻击作为收缩视域的冰冷之物 |
| K | Knowledge | 修习 Discipline | 取向 Orientation | 知识通过承受与消除暗礁而蒸馏 |

环序 M → D → E → A → K 是 logo 顺时针绘制的路径，不是名字拼写的顺序。

### 三层状态机

1. **主体层**：每个域拥有独立的 pyroduct 状态机（34 位置 × 8 槽 × 53 迁移）
2. **群组层**：域间协调的群组状态（散在 → 趋同 → 共语 → 宁定，20 状态）
3. **社会层**：待实现

**灵活起点**：Loop 可以从任意域开始（默认 Model），通过 `POST /api/loop/reset/:domain` 切换起点。每个域的状态机独立初始化，仅 `current` 指针改变。

### 对抗性知识循环

区别于传统数据管道的关键：**Attack 域**。模型不是被数据"喂养"的，而是被攻击"锤炼"的。研究论文通过关键词启发映射到 pyroduct 触发器，驱动状态机迁移；DoubleML 因果推断估计论文"新颖性"对"影响力"的因果效应。

## 快速开始

```bash
.\build.ps1
moon run --release --target native cmd/server
```

打开 <http://127.0.0.1:8080/>。

`build.ps1` 构建浏览器包、暂存到后端服务位置、类型检查后端、运行全部测试、构建服务器。后端同时提供 JSON API 和前端静态文件，无需第二个 web 服务器，无需配置 CORS。

### 环境变量

| 变量 | 默认值 | 含义 |
|---|---|---|
| `MAKED_PORT` | `8080` | 监听端口 |
| `MAKED_DB` | `maked.db` | SQLite 文件路径 |
| `MAKED_DIST` | `frontend/dist` | 前端构建产物目录 |

## API

### 页面与域

| 路由 | 返回 |
|---|---|
| `GET /api/status` | 数据库路径、页面数、五域信息 |
| `GET /api/pages` | 所有页面（按 sort 排序）|
| `GET /api/pages/:slug` | 单个页面，或 404 |
| `GET /api/domains` | 五域（环序）|

### 状态循环

| 路由 | 返回 |
|---|---|
| `GET /api/loop/status` | 当前域、位置、历史、域状态、群组状态、模式 |
| `GET /api/loop/slots` | 八个驱动槽（两字定名 + 英文 + 释义）|
| `GET /api/loop/mode` | 当前模式（structured/free）|
| `POST /api/loop/step` | 步进一环（使用当前域的默认驱动槽）|
| `POST /api/loop/step/:slot` | 步进一环（使用指定槽，支持英文或两字定名）|
| `POST /api/loop/reset` | 重置到初始状态 |
| `POST /api/loop/reset/:domain` | 重置到指定域为起点（支持字母或英文名）|
| `POST /api/loop/mode/:mode` | 切换模式（structured/free 或 结构/自由）|

### 循环模式

- **结构模式 (Structured)**：遵循环序 M→D→E→A→K，每域使用指定驱动槽，步进后总是前进到下一域
- **自由模式 (Free)**：任意槽驱动，探索状态空间；当结果为"无路"(Block)时停留在当前域，否则前进

默认使用结构模式。自由模式允许探索 pyroduct 状态空间中非环序的迁移路径。

### 研究循环

| 路由 | 返回 |
|---|---|
| `GET /api/research/papers` | arxiv SNN 论文 + 触发映射 |
| `POST /api/research/drive` | 获取论文并驱动循环 |
| `GET /api/research/causal` | DoubleML 因果推断结果 |

## 项目结构

```
backend/          微框架、存储层、API 路由、状态循环引擎
  app.mbt           App: 路由表 + 有序中间件链
  request.mbt       Request 封装
  response.mbt      Response 值与分发
  database.mbt      SQLite 存储层
  pages.mbt         内容模型 + 九页种子数据
  api.mbt           JSON API 路由
  loop.mbt          五相环状态循环引擎（主体 + 群组状态机）
  research.mbt      arxiv 研究论文获取与触发映射
  causal.mbt        DoubleML 因果推断
  maked_app.mbt     组装、静态文件、SPA 回退
frontend/         rabbita 单页应用
  app.mbt           状态机与路由
  views.mbt         头部、域卡片、页面渲染
  logo.mbt          五环标记（SVG）
  loop_state.mbt    循环状态可视化
  page.mbt          后端 JSON 的类型化访问器
cmd/server/       native 入口
cmd/web/          js 入口（浏览器包）
tools/            CI 与测试工具
ci.sh             CI 流水线（15 门禁）
```

## CI 流水线

```bash
bash ci.sh              # 全部 15 门禁
bash ci.sh --quick      # 跳过慢速门禁
bash ci.sh --unit-only  # 仅类型检查 + 单元测试
```

| 门禁 | 工具 | 检查内容 |
|---|---|---|
| native-check | `moon check --target native` | 后端类型安全 |
| js-check | `moon check --target js` | 前端类型安全 |
| fmt | `moon fmt --check` | 代码格式 |
| tree | `moon tree` | 依赖审计 |
| unit-native | `moon test --target native` | 120 后端测试 |
| unit-js | `moon test --target js` | 12 前端测试 |
| coverage | `moon test --enable-coverage` | 覆盖率 |
| bench | `moon bench` | 基准测试 |
| prove | `moon prove` | 形式化验证 (Why3) |
| bdd | `bdd_test.mbt` | 14 个 Given/When/Then 场景 |
| contract | `contract-test.sh` | 46 个 API 契约断言 |
| component | `component-test.sh` | 6 个跨模块集成检查 |
| sast | `sast-check.sh` | 11 个静态安全检查 |
| mutation | `mutation-test.sh` | 10 个变异测试 (80% 杀灭率) |
| dast | `dast-check.sh` | 5 个动态安全检查 |

## 请求处理

三层，由外到内：

1. `static_files`：从 `frontend/dist` 提供真实文件
2. `spa_fallback`：未匹配的浏览器导航返回 `index.html`（支持 `/about` 冷加载）
3. 路由器：服务 `/api/...`，其余返回 JSON 404

回退排除 `/api/` 路径。含点号的末段被视为资源（缺失样式表返回 404 而非 HTML）。路由冲突中止启动（`fail`，非 `raise`）。

## SQLite 存储层

三个关键行为（已验证，非假设）：

1. `prepare` 只编译不执行。未 `step` 的语句被 `finalize` 静默丢弃——DDL 走 `exec`
2. 执行完毕的语句必须 `reset` 后才能重用。`bind` 原地覆盖绑定
3. `finalize` 报告最近一次求值的错误码——失败的 `step` 会污染后续的 `finalize`

## 发版约定

- 补丁版本递进：v0.1.x（除非指定，不发次版本）
- Gitee 做日常存储，GitHub 用于发版
- 发版前跑 `bash ci.sh` 全绿

## License

Apache-2.0
