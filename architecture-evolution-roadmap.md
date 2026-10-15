# MAKED_moonbit 演进路线图

## 当前状态（证据支撑）

### 架构结构
- **5 个包**：backend (native lib), frontend (js lib), cmd/server (native exe), cmd/web (js exe), root
- **双目标编译**：native（后端服务）+ js（前端 SPA）
- **核心集成**：pyroduct 状态机驱动 M→D→E→A→K 五域循环

### 测试覆盖
- 76 个测试全部通过（64 native + 12 JS）
- 单元测试覆盖：Loop 引擎、页面数据、响应构造、App 路由
- 缺失：API 集成测试、Request 包装器测试

### 关键问题
1. **Loop 阻塞**：所有 5 个 domain 的默认 drive slot 在 pyroduct 迁移表中返回 `Block("无路")`
2. **状态管理**：模块级可变状态使用 `Array[LoopState]` 单例模式
3. **测试盲区**：moonback Request 是不透明类型，无法构造测试实例
4. **无配置系统**：迁移规则硬编码在 pyroduct 依赖中

---

## 目标状态

### 功能目标
- Loop 能够正常推进 M→D→E→A→K 循环
- 支持自定义迁移阈值/规则
- Loop 状态可持久化
- 完整的 API 测试覆盖

### 架构目标
- 显式状态管理（依赖注入替代模块级全局）
- 配置驱动的迁移规则
- 清晰的分层：领域逻辑 / 应用服务 / 基础设施
- 生产就绪的可观测性（日志、指标）

---

## 演进切片（按依赖排序）

### 切片 1：解锁 Loop 前进能力（高优先级，低风险）

**问题**：所有 domain 的默认 slot 返回 Block，Loop 无法前进

**方案选项**：
- **A. 使用 step_with_slot API**：让调用者选择非默认 slot
  - 优点：立即可用，不改 pyroduct
  - 缺点：需要前端/客户端理解 slot 语义
- **B. 修改 pyroduct 迁移表**：为 5 个 domain position 配置有效迁移
  - 优点：符合 pyroduct 设计意图
  - 缺点：需要修改外部依赖
- **C. 混合方案**：默认 slot 阻塞时自动尝试备选 slot
  - 优点：保持 API 简洁
  - 缺点：隐藏了迁移语义

**推荐**：先实施方案 A（前端添加 slot 选择器），同时与 pyroduct 维护者协调方案 B

**验证信号**：
- 前端能够执行完整的 M→D→E→A→K 循环
- Loop history 记录 5 个有效事件

**依赖**：无

---

### 切片 2：集成测试基础设施（高优先级，中风险）

**问题**：无法测试 API 端点的完整请求-响应流程

**方案**：
1. 引入 HTTP 客户端测试框架（如 MoonBit 的 http testing 工具）
2. 启动测试服务器实例（随机端口）
3. 编写端到端测试：
   - `GET /api/loop/status` 返回正确 JSON
   - `POST /api/loop/step` 推进状态
   - `POST /api/loop/reset` 重置状态

**技术挑战**：
- moonback 可能缺少测试辅助工具
- 需要处理服务器启动/关闭生命周期

**验证信号**：
- 3 个 Loop API 端点的集成测试通过
- 测试覆盖率报告排除集成测试盲区

**依赖**：无

---

### 切片 3：状态管理重构（中优先级，高风险）

**问题**：模块级 `Array[LoopState]` 单例难以测试和扩展

**当前模式**：
```moonbit
let g_loop_state : Array[LoopState] = [LoopState::new()]
pub fn get_loop_state() -> LoopState { g_loop_state[0] }
```

**目标模式**：显式依赖注入
```moonbit
// 应用上下文
struct AppContext {
  loop_state : Ref[LoopState]  // 或类似的引用类型
  database : Database
  config : AppConfig
}

// API 处理器接收上下文
app.get("/api/loop/status", ctx => {
  let state = ctx.loop_state.get()
  Response::json(state.to_json())
})
```

**迁移步骤**：
1. 创建 `AppContext` 结构体
2. 修改 `maked_app` 构建器接收 context
3. 逐步迁移 API 处理器从全局函数到 context 方法
4. 删除模块级全局状态

**风险**：
- 破坏现有 API 签名
- 需要修改所有测试
- moonback 可能不支持 context 传递

**验证信号**：
- 所有现有测试通过（可能需要更新）
- 可以创建多个独立的 AppContext 实例
- 单元测试可以注入 mock context

**依赖**：切片 2（集成测试确保重构不破坏功能）

---

### 切片 4：配置系统（中优先级，低风险）

**问题**：迁移规则硬编码在 pyroduct 中，无法运行时调整

**方案**：
1. 定义配置结构体：
```moonbit
struct LoopConfig {
  default_slot_strategy : String  // "default" | "round_robin" | "random"
  fallback_slots : Map[Domain, Array[Slot]]
  max_retries_on_block : Int
}
```

2. 从文件/环境变量加载配置
3. Loop 引擎使用配置决定 slot 选择策略

**验证信号**：
- 可以通过配置文件改变 Loop 行为
- 不同配置下的测试通过

**依赖**：切片 3（需要 context 传递配置）

---

### 切片 5：状态持久化（低优先级，中风险）

**问题**：服务器重启丢失 Loop 状态

**方案**：
1. 扩展数据库 schema：
```sql
CREATE TABLE loop_state (
  id INTEGER PRIMARY KEY CHECK (id = 1),  -- 单行表
  current_domain TEXT NOT NULL,
  history_json TEXT NOT NULL,
  updated_at INTEGER NOT NULL
);
```

2. 每次 step 后持久化
3. 启动时从数据库恢复

**验证信号**：
- 重启服务器后 Loop 状态保持一致
- 并发访问不损坏状态

**依赖**：切片 3（需要 context 管理 database 连接）

---

### 切片 6：可观测性（低优先级，低风险）

**问题**：缺少生产环境所需的日志和指标

**方案**：
1. 结构化日志：
   - Loop 每次 step 记录：domain, slot, outcome, duration
   - API 请求记录：method, path, status, duration

2. 指标导出：
   - Loop 循环次数
   - 各 outcome 分布（Moved/Held/Block/Open/Same）
   - API 请求延迟

**验证信号**：
- 日志输出符合结构化格式
- 指标可以通过 `/metrics` 端点访问

**依赖**：切片 3（context 传递 logger/metrics collector）

---

## 演进路线图

```
阶段 1（立即）：解锁核心功能
├─ 切片 1：使用 step_with_slot 解锁 Loop
└─ 切片 2：建立集成测试基础设施

阶段 2（短期）：架构稳固
├─ 切片 3：状态管理重构（依赖注入）
└─ 切片 4：配置系统

阶段 3（中期）：生产就绪
├─ 切片 5：状态持久化
└─ 切片 6：可观测性
```

## 关键决策点

### 决策 1：pyroduct 迁移表策略
- **约束**：pyroduct 是外部依赖，修改需要协调
- **选项**：
  - 等待 pyroduct 更新（被动）
  - fork pyroduct 并自定义（主动）
  - 在 MAKED 层包装 slot 选择逻辑（折中）
- **推荐**：先实施折中方案，同时与 pyroduct 维护者沟通

### 决策 2：状态管理重构时机
- **约束**：重构会破坏现有 API，需要更新所有测试
- **风险**：moonback 框架可能不支持 context 传递模式
- **缓解**：先做小规模实验（单个 API 端点），验证可行性后再全面推广

### 决策 3：测试策略
- **约束**：moonback Request 是不透明类型
- **选项**：
  - 等待 moonback 提供测试辅助
  - 使用 mock server 替代真实请求
  - 只测试不依赖 Request 的逻辑
- **推荐**：混合策略，优先测试领域逻辑，集成测试等待框架支持

## 风险与缓解

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| moonback 不支持 context 传递 | 切片 3 无法实施 | 中 | 先做 POC 验证 |
| pyroduct 维护者不配合 | 切片 1 方案 B 不可行 | 低 | 已有方案 A/C 作为备选 |
| 重构破坏现有功能 | 回归 bug | 中 | 切片 2 先建立集成测试安全网 |
| 持久化引入性能问题 | 响应延迟增加 | 低 | 异步写入 + 批量提交 |

## 下一步行动

1. **本周**：实施切片 1A（前端添加 slot 选择器），验证 Loop 可以完整循环
2. **下周**：实施切片 2（集成测试基础设施），建立回归测试安全网
3. **本月**：评估切片 3 可行性（moonback context 支持），决定是否推进重构

---

## 成功标准

- Loop 能够执行完整的 M→D→E→A→K 循环（切片 1）
- API 集成测试覆盖所有端点（切片 2）
- 可以创建多个独立的 AppContext 实例（切片 3）
- 配置文件可以改变 Loop 行为（切片 4）
- 服务器重启后状态保持一致（切片 5）
- 生产环境可以收集日志和指标（切片 6）
