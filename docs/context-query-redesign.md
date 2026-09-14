# plan-skills 上下文瘦身与查询化重设计

状态：已施工
日期：2026-09-14
范围：`skills/plan-task/`（引擎、hooks、SKILL.md）、`skills/plan-init/`（模板、AGENTS 片段）、`skills/plan-review/`（回顾清账）
不破坏：2-Action 纪律、对齐门、三合一、DoD 实测、stop-gate 双门

读法：效果看 §3；契约看 §5–§6；施工记录看 §8 / §10 / §12。§1 是施工前证据。


## 1. 问题（施工前证据，均在当时仓库）


### 1.1 user-prompt-submit 重推原文，最大浪费源

`engine/plan.mjs:333`：每次用户消息注入 TASKS.md「进行中」段**原文**（含 DoD/前置/工作区，上限 60 行）。

现状节流契约（施工对照）：哈希字段 = `milestone + 进行中段原文 + 活跃工作区名`（`plan.mjs:342`）。逐字相同才改发 1 行摘要；补开始日期、挪区、改 DoD 任一字节即整段重推。

实测节奏：每会话 3~8 次 × 20~40 行 ≈ **100~300 行/会话**。本方案能省掉的上限（早期估算「40 轮 × 60 行」高估了，以本节为准）。

### 1.2 FINDINGS 路由靠纸面约定

新模板已有 `## 索引` 区（`skills/plan-init/assets/templates/FINDINGS.md:29`），由 plan-review **手工维护**——新条目进热区到下次回顾之间，索引与正文必然漂移。现索引四列：编号|日期|状态|主题，**不能按标签/来源/影响过滤**。来源、影响字段正文里已有，只是没进查询面。agent 实际只能 grep `^### F` 或整篇读。

### 1.3 会话恢复成本线性增长

纪律要求「每次开工先重读 plan.md」，progress.md 随任务无上限膨胀；引擎已有 `workspacePosition()`（pre-tool-use 在用）却无对应 CLI——取三行「当前位置」必须读整个文件。

### 1.4 引擎查询面为空

现有命令 `start / finish / status / doctor` + 7 个 hook。`status` 无分级、无过滤。所有「读」都退化成品格文件的整读。`status --json` 已存在，本方案保留，不删。

### 1.5 无关联模型

任务↔结论↔INBOX 的关联靠散文引用，机器不可遍历：

- 任务**产出**哪条结论：finish 时可机械推出（追溯路径含 slug），但今天没人写
- 任务**因**哪条结论而生（动机）：写在开工之前，finish 扫描永远抓不到
- INBOX 被任务实现后**了结**：无状态机；现 SKILL 靠 agent 把条目移入「已裁决」。漏了 → 下次又建任务

## 2. 参考与取舍（repowiki / LoomWiki）

| repowiki 做法 | 采纳 | 映射 |
|---|---|---|
| Route-before-body：页面 `triggers`，按意图加载 | ✅ | 索引行 = 路由层；查询默认索引，正文 `--full` 才取 |
| 机器可查询状态（snapshot/state/plan.json） | ✅ | 引擎直接解析 5 文件，不引入额外状态文件 |
| 受管区块（AGENTS.md 包 HTML 标记，幂等重写） | ✅ | FINDINGS 索引区包 `plan-index` 标记，引擎再生 |
| CLI 一等公民 + `--quiet` + 退出码给 hook | 半采纳 | 新命令输出人类可读文本；hook 走引擎内部函数。**现有 `status --json` 保留**；新查询命令不加 `--json` |
| freshness baseline / content_hash / 退出码 10=stale | ❌ | 5 文件就是事实源，无过期概念 |
| OKF bundle / dimension cards | ❌ | 5 个状态文件用是过度设计 |

## 3. 端到端案例（用起来什么样）

设定：todo-cli，里程碑 M2「tag 过滤」；TASKS 有进行中「store.js 扩展 tag 字段」（昨天开工、有工作区）+ 队首「list 命令支持 --tag 过滤」；FINDINGS 有 F1/F2；SPEC 红线「CLI 解析 = commander.js」。

**① 周一开会话（你什么都没说）**，session-start 注入 `status`：

```
[plan] SPEC 红线（执行期护栏，与其他文档冲突以 SPEC.md 为准）：
- 边界：不做云同步
- 选型：CLI 参数解析 = commander.js
[plan] 当前里程碑：M2 tag 过滤（验收：add/list/done + tag 过滤全链路可用）
[plan] 进行中：store.js 扩展 tag 字段 ｜ 下一张：list 命令支持 --tag 过滤
[plan] 提示：进行中 1 个，INBOX 待裁决 0 条
```

6 行。（现状 ≈12~15 行。）

**② 你说「继续 store.js 那个」** → `plan.mjs ws store-js`（默认就是当前位置三行 + 本现场结论索引行），接着干。无 slug 时列出全部活跃工作区一行式。

**③ 干活中每轮消息** → 心跳 1 行：

```
[plan] 进行中：store.js 扩展 tag 字段（1）｜详情 plan.mjs task "store.js 扩展 tag 字段"
```

中途你把 list 任务挪队首 → 下一轮推一次卡片（≤15 行：新状态 + 下一张 DoD + 同一指针句），之后回到心跳。比较集见 §8，不含 DoD 正文。

**④ 你问「旧数据没 tags 字段会不会崩」** → `plan.mjs findings` 索引行 → 命中 F2 → `findings --full F2`。共约 10 行。FINDINGS 到 50 条时仍约 10 行。

**⑤ 你说「要不换 yargs」** → 红线已在上下文，0 行成本拦住。

**⑥ 你说「我试过逗号拆 tag，大小写混乱不行」** → agent 写 FINDINGS F3（来源：失败尝试，标签：数据）。索引等 **finish / reindex** 再生；查询解析正文，不信索引。

**⑦ 你说「做完了」** → 对齐门 → `plan.mjs finish "store.js 扩展 tag 字段"`：

1. 扫 FINDINGS 追溯路径含本 slug → 任务块回写 `- 结论：F2`（多条则逗号连接）
2. 本例无 `- 来自：`、无 `--resolve` → **不写** INBOX 已解决行
3. 未决 INBOX 标题相似 → 软警告一行，不挡
4. 再生 FINDINGS 索引区

**⑧ 你问「接下来做啥」** → `plan.mjs next`：标题 + DoD，≤5 行。

**⑨ 你问「跟 tag 有关的结论」** → `plan.mjs findings --tag 数据`：F2、F3 两行。不是另造 `context` 命令。

**⑩ 关会话** → stop-gate 通过，退出。

**周二**：底线 6 行 → 「开工 list 那条」→ `start` → 工作区 → 同剧本。

**全天账（10 轮）**：本方案 ≈30 行 vs 现状 ≈70~200 行。

## 4. 设计原则

1. **有 node 时引擎即接口**：agent 查计划状态跑命令，不整读 FINDINGS / progress.md / INBOX。markdown 是存储 + 人读视图。
2. **推底线、拉详情**：session-start 推 `status`（≤8 行）；user-prompt-submit 推心跳 1 行或变化卡片 ≤15 行。DoD / 结论全文 / 位置按需拉。
3. **markdown 是事实源**：引擎默认只解析、校验。允许写入的集合仅：`finish` 四动作（结论行、已解决行、软警告、索引再生）、`reindex`（只再生索引）。**`start` 不写 FINDINGS。** 与现有三合一机械动作同类。
4. **不追求完美录入，追求遗漏可见**：关联判不全就判不全——读时现算「疑似」，周期清账。
5. **命令只为过滤、join、底线压缩存在**：无过滤的人读直接打开文件。禁止再加「status + 全量 findings」这类提取命令。

例外优先级（读路径，高优先）：

1. 有 node → 命令（§5）
2. 无 node → SKILL 写明降级：读 FINDINGS 受管索引区、TASKS 进行中标题行、plan.md「当前位置」区；命令本身非 0 退出
3. 人在编辑器里读文件 → 不受限

## 5. 命令契约

入口共 **11 个**：现有 4（`status` / `start` / `finish` / `doctor`）+ 新查询 6（`next` / `task` / `findings` / `inbox` / `ws` / `links`）+ 新维护 1（`reindex`）。

全局：项目根执行；人类可读文本（仅 `status --json` 例外，现网保留）；`PLANNING_HOOKS_DISABLED=1` 只影响 hook。

退出码：

| 码 | 何时 |
|---|---|
| 0 | 成功（过滤无命中也是 0，输出「（无匹配）」） |
| 1 | 未找到计划体系（提示先 plan-init） |
| 2 | 具名实体不存在或任务名歧义（列出候选） |
| 3 | 用法错误（缺参、未知 flag） |

正文解析残缺：跳过坏条目，命令仍 0；坏条目出现在 `links --orphan`。不另占退出码。

### 5.1 查询族（只读，7 个，含现有 `status`）

| 命令 | 默认输出 | 升级 / 滤参 |
|---|---|---|
| `status` | 底线：红线 + 里程碑 + 进行中一行 + 下一张标题 + INBOX 未决计数（≤8 行）。session-start 推这个 | `--json` **保留**（现网）；结构不扩到其他命令 |
| `next` | 队首待做：标题 + DoD（≤5 行） | — |
| `task "<名>"` | 块卡片（DoD/前置/工作区/标签/依据/来自/结论）+ 关联区（相关结论索引行、解决的 INBOX）。催生反向不在这里，去 `links` | `--full` 展开关联条目全文 |
| `findings` | 索引行，每条一行：`F3 \| 2026-07-18 \| 技术选型 \| 有效 \| 主题≤40字`；无标签显示 `未分类` | `--full F3` 单条全文；滤参见下 |
| `inbox` | 未决索引行 + 「疑似已实现」段（⚠️ 现算） | `--resolved` 已解决及解决者；`--all` 全部 |
| `ws [slug]` | 有 slug：当前位置三行 + 本现场结论索引行。无 slug：活跃工作区一行式 | `--full` 该 slug 的 progress.md 全文。无 `--position` flag——默认就是位置 |
| `links` | 每行一条边 + 尾部统计 | `--unlinked` 无关联任务（含正常小任务，见 §7.3）；`--orphan` 只列数据毛病 |

`findings` 滤参（可组合，均对**正文**过滤，不信索引）：

| flag | 读哪个已有/新字段 | 匹配 |
|---|---|---|
| `--tag X` | `- 标签：`（新、可选） | 逗号列表含 X；缺标签只命中 `--tag 未分类` |
| `--source S` | `- 来源：`（模板已有） | 子串；典型值：`调研探针` / `开发中发现` / `失败尝试` / `外部输入` |
| `--status 有效\|推翻` | `- 状态：`（模板已有） | `有效` = 整行等于 `有效`；`推翻` = 行内含 `推翻`（覆盖 `已被 F? 推翻`） |
| `--impact spec\|M2\|none` | `- 影响：`（模板已有） | `none` = `无`；`spec` = 含 `SPEC`；`M2` = 含 `M2` / `M?` 字面 |

未知滤参 → 退出码 3。

失败金句：

- `task "不存在"` → `[plan] 未找到任务：不存在` 退出 2
- `task "foo"` 两条同标题 → `[plan] 任务名歧义：foo` + 候选区名 退出 2
- `findings --full F99` → `[plan] 未找到 F99` 退出 2
- `ws nosuch` → `[plan] 未找到工作区：nosuch` 退出 2

### 5.2 写/维护族（现有 3 + 新 1）

| 命令 | 行为 |
|---|---|
| `start "<名>" [--workspace] [--date YYYY-MM-DD]` | 现有，不动。**不**再生 FINDINGS 索引 |
| `finish "<名>" [--resolve "<INBOX标题>"] [--date YYYY-MM-DD]` | 现有校验不动（有工作区仍须 FINDINGS 追溯，过不了则根本不写回）。`--date` 保留。新增四动作：① 回写 `- 结论：` 为本次扫到的 F 编号（多条逗号连接）② 有 `- 来自：INBOX x` 或 `--resolve` → 在对应待裁决条目下写 `- 已解决：<任务名> ✅（YYYY-MM-DD）`，**不移区** ③ 无来自且无 `--resolve` 且标题相似未了结 → 软警告一行，不挡、不写 ④ 再生 FINDINGS 索引 |
| `reindex` | 只再生 FINDINGS 索引区 |
| `doctor` | 现有 FAIL/WARN 不动。新增：**WARN**（不是 FAIL）— findings/inbox 不可解析条目、缺 `plan-index` 标记 |

### 5.3 分级（写进 SKILL.md）

| 级 | 内容 | 入口 |
|---|---|---|
| 底线 | 红线 + 里程碑 + 进行中一行 + 下一张标题 + 计数 | `status`（session-start） |
| 索引 | 编号/日期/标签/状态/主题；INBOX 行；边 | `findings` `inbox` `links` |
| 卡片 | 元数据、DoD、当前位置、关联区 | `next` `task` `ws` |
| 全文 | 原始条目块、progress.md | 各命令 `--full` |
| 材料 | notes/、done/ | 卡片里的路径，直接读文件 |

不设 `context` 命令。SKILL 组合拳：用户问「跟 X 有关」→ `findings --tag` / 标题命中不够再 `--full` 单条。

## 6. 数据模型与文件格式变化

缺新字段 = 该维不参与过滤/关联，不报错。旧「已裁决」区双读，见 §6.3。

### 6.1 FINDINGS.md

查询维（过滤读正文，不要求索引含这些列）：

- **已有**：`- 来源：`、`- 影响：`、`- 状态：`、`- 日期：`、材料/过程追溯路径
- **新、可选**：`- 标签：<域1,域2>`（词表不强制，引擎动态收集；plan-review 收敛同义词）

`## 索引` 区受管标记：

```markdown
<!-- plan-index:begin | 引擎维护：finish / reindex 时从正文重新生成，手改会被覆盖 -->
- F1 | 2026-07-18 | 技术选型 | 有效 | CLI 框架选型——commander.js 满足需求
<!-- plan-index:end -->
```

- 索引是**派生视图**：命令解析正文，永不信任索引
- 再生时机：**仅** `finish`、`reindex`。首次出现：第一次 `finish` 或手动 `reindex`。缺标记 ≠ 错误（doctor WARN）

### 6.2 TASKS.md（任务块新增可选行）

```markdown
### 给同步加增量传输
- DoD：万级条目下列表 <100ms，手动验证通过
- 标签：性能                     ← 可选
- 依据：F5                      ← 可选，因哪条结论而生（可多个 F 编号）
- 来自：INBOX 云同步支持          ← 可选，由哪条停车项提升
- 前置：store.js 扩展 tag 字段    ← 已有
```

- `依据`/`来自`：录入时 agent 写；引擎校验引用存在，悬空进 `links --orphan`
- `- 结论：F2,F3`：`finish` 自动回写
- 查重：扫 TASKS（含已完成）+ `inbox`；命中已解决 → 答「已由 X ✅ 实现」，不建任务

### 6.3 INBOX.md（双读，不替换旧区）

已解决（查询与查重）当且仅当下面**任一**成立：

1. 条目下有 `- 已解决：<任务名> ✅（YYYY-MM-DD）`（本方案 `finish` 写入，条目可仍留在「待裁决」）
2. 条目位于 `## 已裁决（存档）`（旧 SKILL / plan-review 移区）

「认领中」仍是现算：被某未 ✅ 任务 `- 来自：` 引用 → `inbox` 显示「认领中：<任务名>」，不写文件。

三态：`未决 → 认领中（现算）→ 已解决（行或旧区）`。

引擎 `finish` **不**把条目移入「已裁决」。并入里程碑 / 归桶 / 删除仍是 plan-review。SKILL 完成流程的「INBOX 核销」改为：有来自/`--resolve` 则依赖引擎写已解决行；不再要求 agent 移区。

### 6.4 不变量（`links --orphan` 报告，不挡操作）

1. 有工作区的任务 ⇒ 块上有 `- 结论：` 行（含「无新结论」存根）——仅已 ✅ 任务；进行中尚未 finish 的不报
2. `- 已解决：` 指向的任务存在且已 ✅
3. finding 的材料/追溯路径可打开（活目录或 `done/`）
4. `- 依据：F?` / `- 来自：INBOX x` 的引用存在

plan-review 清单加一条：跑 `links --orphan`，清 ⚠️。

## 7. 关联模型与生命周期

### 7.1 五种边

| 边 | 方向 | 记录方式 | 谁写 |
|---|---|---|---|
| 产出 | 任务 → finding | `- 结论：F?` | finish 自动 |
| 动机 | finding → 任务 | `- 依据：F?` | 录入时 agent |
| 提升 | INBOX → 任务 | `- 来自：INBOX x` | 录入时 agent |
| 解决 | 任务 → INBOX | `- 已解决：` 或旧「已裁决」区 | finish 自动（来自或 --resolve）/ 历史移区 |
| 前置 | 任务 → 任务 | `- 前置：` | 已有 |

### 7.2 兜底四层 + 相似算法

| 层 | 时机 | 动作 | 抓什么 |
|---|---|---|---|
| 1 | finish 时 | 标题相似软警告 | 忘写来自/`--resolve` |
| 2 | `inbox` 读时 | 「疑似已实现」现算，不写状态 | 漏网每次浮出 |
| 3 | 录入查重 | 跑 `inbox`，命中 ⚠️ 先问是否同一件事 | 复建拦截 |
| 4 | plan-review | `links --orphan` 人工扫 | 周期清账 |

相似（finish 软警告与 inbox 疑似共用）：

```
normalize(s)：小写；删 `"'`「」《》【】` 与首尾空白；压缩空白；去掉行首日期 YYYY-MM-DD、🔴、⚪、`- [ ]`
similar(a,b)：
  较短方 normalize 后 < 4 字 → false
  一方包含另一方 → true
  否则把连续非空白当 token，|交集| / |较短 token 数| ≥ 0.6 → true
  双方都无空白（纯 CJK）→ 用相邻二字 bigram，|交集| / |较短 bigram 集| ≥ 0.6
```

| 左 | 右 | 结果 |
|---|---|---|
| `list 命令支持 --tag 过滤` | `list --tag 过滤` | 命中（token 3/3） |
| `云同步支持` | `给同步加增量传输` | 不命中 |
| `store.js 扩展 tag 字段` | `store.js 扩展 tag 字段` | 命中（包含） |
| `CLI 框架选型` | `换 yargs` | 不命中 |

### 7.3 语义护栏

「不关联」≠异常：

- 任务无结论：无工作区的小任务正常；**已 ✅ 且有工作区的必须有**（不变量 1）
- finding 无任务：来源 = 外部输入正常；来源 = 调研探针/开发中发现 且材料路径无工作区 → `--orphan` 毛病
- INBOX 无任务：未决 = 日常态

`--unlinked` 列出无边任务，**不**打 ⚠️。⚠️ 只出现在 `--orphan`。

## 8. hook 改动

| hook | 现状 | 改后 | 理由 |
|---|---|---|---|
| session-start | 红线 + 任务多行 + 工作区逐行 + 计数（≈12~15） | 推 `status` 文本（≤8 行） | 底线 |
| user-prompt-submit | 进行中原文 ≤60 行；哈希见 §1.1 | 无变化：心跳 1 行（§3 ③ 指针句）。有变化：≤15 行卡片（status 压缩态 + 下一张 DoD + 指针） | 不再哈希原文 |
| pre-tool-use | 进行中 + 当前位置（10 分钟节流） | 保留；与 `ws <slug>` 默认输出同一内部函数（不 spawn CLI，无 `--position`） | 本来就小 |
| 其余 4 个 | 条件提醒/双门 | **不动** | 无关 |

**状态变化比较集**（新哈希，仅这些）：进行中标题集合（有序列表）+ 队首待做标题 + INBOX 未决计数。不含 DoD 正文、不含工作区当前位置、不含红线全文。

无 node：hook 静默（现行为，不改）。命令非 0。SKILL 降级读路径见原则 5 例外。

## 9. 明确不做

| 不做 | 理由 |
|---|---|
| 新查询命令加 `--json` | 无消费者；`status --json` 已有则保留 |
| `context` 命令 / 中文分词 | 提取不是命令价值；「跟 X 有关」用 `findings --tag` |
| finish 硬阻断 `--resolve` | 误伤比漏判烦；软警告 + 四层兜底 |
| `start` 再生索引 | start 不改 FINDINGS 正文 |
| 任务创建命令化 | 标题/DoD 是判断活 |
| 受控标签词表 + enforce | 动态收集 + plan-review 收敛 |
| 旧项目迁移工具 / 把待裁决批量移区 | 双读已裁决；索引标记首次 finish/reindex 出现 |
| freshness baseline / 快照 | 5 文件是事实源 |

## 10. 施工顺序（四步，每步可停）

| 步 | 内容 | 退出条件 | 回滚 |
|---|---|---|---|
| 1 | 只读：`status`（含现 `--json`）`next` `findings` `inbox` | fixture 输出与 §5 一致；快照测过 | 删新子命令；`status` 回到施工前 |
| 2 | `task` `ws` `links`；finish 四动作（结论行 / 已解决行 / 软警告；**此步尚可不再生索引**） | §3 ⑥⑦ 手工跑通；`links --orphan` 对全关联 fixture 无 ⚠️ | finish 去掉四动作；删三命令 |
| 3 | `plan-index` 受管区、`reindex`、**仅 finish** 接线、plan-init 模板 + SKILL（查重、核销改依赖已解决行、分级读法） | finish 后索引更新；手改索引被再生成纠正；缺标记旧 fixture doctor = WARN | 删标记与 `reindex`；finish 不再写索引 |
| 4 | hook：session-start=`status` 文本；user-prompt-submit=§8 比较集 + 指针心跳 | `tests/test-hooks.sh` 对 fixture **断言 stdout 行数**（session-start ≤8、无变化心跳 =1、变化卡片 ≤15），不是「目测符合 §3」 | hook 回到原文注入 + 旧哈希 |

任何一步失败只回滚该步；已合并的前步可留。
四步已落地（2026-09-14）。`tests/test-hooks.sh` 36 PASS。plan-review 清账见该技能步骤 6。


## 11. 风险与对策

| 风险 | 对策 |
|---|---|
| 弱模型凭记忆不跑命令 | 心跳必带指针（§3 ③）；SKILL 纪律；观察两周，到期由 plan-review 写一条 FINDINGS（来源：外部输入，标签：运营）记「是否出现整读 FINDINGS / 凭记忆编 DoD」 |
| FINDINGS 格式变松 | 坏条目进 `--orphan`；索引派生，漂移无正确性影响 |
| 标签同义词 | 动态收集 + plan-review；不 enforce |
| 软警告误报 | 忽略、不留痕、不阻断 |
| 引擎膨胀 | 936 行 → 预估 +350（砍掉 `context` 与 start 再生后低于原 +450）；解析器复用块解析；按 §10 回滚 |

## 12. 验收标准

- [x] session-start ≤8 行（含红线）
- [x] 比较集不变 → 心跳恰好 1 行且含 `plan.mjs task` 或 `plan.mjs next`；比较集变 → 卡片 ≤15 行
- [x] 「旧数据会不会崩」：`findings` 索引 + `findings --full F?`，测试不打开整篇 FINDINGS 当命令输入
- [x] 「做完了」有 `- 来自：` 或 `--resolve` → 任务块有 `- 结论：`，对应 INBOX 有 `- 已解决：` 行，索引再生；**两者都没有** → 不写已解决行，stdout 含软警告一行
- [x] 「做云同步」：查重命中已解决（行或旧已裁决区）→ 答已做过，不复建
- [x] 「跟 X 有关」：`findings --tag` 一条命令出结果
- [x] 「来龙去脉」：`task "<名>"` 一次看到依据/产出/解决的 INBOX/前置
- [x] 全关联 fixture：`links --orphan` 无 ⚠️；缺 `plan-index` 的旧 fixture：`doctor` WARN 非 FAIL
- [x] `status --json` 仍 0 且可解析（回归，不删）
