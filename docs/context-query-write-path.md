# plan-skills 写入命令化（追加不整读）

状态：定稿待施工
日期：2026-09-14
范围：`skills/plan-task/`（引擎、SKILL.md、`usage()`）、`skills/plan-init/`（AGENTS 片段、`templates/FINDINGS.md` 索引注释一行）；plan-review 只改「有 node 时不要为追加而整读」一句
不破坏：2-Action、对齐门、三合一、DoD 实测、stop-gate 两门、查询命令契约（`docs/context-query-redesign.md`）
修订上一份：
1. §9「任务创建命令化」从「不做」改为「做薄写入；判断仍在参数里」
2. 原则 3「允许写入的集合仅 finish 四动作 + reindex」、§6.1「再生时机 **仅** finish / reindex」→ 追加 `finding-add` / `--amend`（见 §2.4）；模板 `plan-index` 注释措辞同步

读法：效果看 §3；契约看 §4–§5；施工看 §8；验收看 §9。

## 0. 和上一份的关系

上一份解决 **查**：有 node 不整读 FINDINGS / INBOX / progress。
这一份解决 **写**：有 node 不为了追加一条而去整读 TASKS / FINDINGS / INBOX。

判断活（标题、DoD、结论一段话）仍由 agent 想好，经参数交给引擎。引擎不代写 DoD、不编结论。

人在编辑器里改 markdown **永远合法**。对 agent：**有 node 只走命令**，禁止「命令和改文件两套同等推荐」。

**追加**与**改已有**是两回事：本期只命令化追加。改 DoD / 挪队 / 删卡仍手改（§4.5），手改就得读文件——SKILL 禁的是「为了追加一条而整读状态文件」，不是禁读。

## 1. 问题

1. 查已命令化，写仍 Read 整文件再 Edit。TASKS / FINDINGS 变长后，加一条的上下文随文件线性涨。
2. 字段名靠自觉（`依据` / `来自` / `标签`）。错了要等 `links --orphan`。
3. 查重「已做过」只写在 SKILL 上，引擎不挡复建。
4. 新 FINDINGS 要到 `finish` / 手跑 `reindex` 才进索引；人看索引会漂。查询读正文所以正确，但「写完立刻可查」不成立。
5. Windows 上长文本进 argv 易炸。结论纪律本来就是一段话——命令应强制这段话够短，章节继续走 notes/。

## 2. 原则

1. **人改文件，agent 走命令。** 双轨只存在于「人 vs agent」，不存在于 agent 内部。
2. **判断在参数，搬砖在引擎。** 缺 DoD / 缺结论正文 → 退出 3，不落盘。
3. **追加成功只回几行**（编号、插入位置、查重命中），不回文件全文。
4. **写 FINDINGS 正文的命令必须再生索引**（`finding-add` / `--amend`）——放宽上一份 §6.1「仅 finish / reindex」。`task-add` / `inbox-add` / `progress-log` 不碰 FINDINGS。落盘顺序：先写正文、后再生索引；**索引再生失败仍退 0** 并提示手动 `reindex`（索引是派生视图，漂移不影响正确性）。
5. **notes / SPEC / ROADMAP 仍直接读写。** 章节不是一段话，不进 argv。
6. **无 node：维持手改文件**（与查询降级同一条）。命令非 0。
7. **查重归引擎，不归 agent。** agent 不必为录入先跑 `inbox` / `task`；引擎落盘前查完并把结果写进 stdout。

## 3. 端到端（agent 有 node）

「加个任务：list 支持 --tag」→ `task-add "list 命令支持 --tag 过滤" --dod "…" --from "INBOX 云同步支持"`（**不必先跑 `inbox`**，查重在引擎里）  
命中已解决 → stdout `已由 X ✅ 实现`，退出 0，不新建。  
未命中 → 追加到「已拆好」队尾，回 3～5 行。全程不把 TASKS.md 读进模型上下文。

「试过逗号拆 tag 不行」→ `finding-add --title "逗号拆 tag 大小写不可靠" --source 失败尝试 --tag 数据 --conclusion "…一段话…"`  
→ 分配 F4，写入热区，再生索引，回 `F4 | …` 一行。

干活 2-Action → `progress-log <slug> --kind 进展 --text "改了 store.js 解析"`  
收工顺手 `--position "…" --next "…"`，只改这两条，不读 progress 全文。

人在 VS Code 里改 TASKS：合法，下一轮 `task "名"` 仍能读到。

## 4. 命令契约

入口新增 **4 个**，全部写；与现有 `start` / `finish` / `reindex` 同类。不加 `--json`。

退出码沿用上一份：0 成功（**含查重命中「已做过」——此时没新建，只看退出码会误判，必须看 stdout**）；1 无计划体系；2 引用的 F / INBOX / 工作区不存在、任务名歧义、**标题重名（含已完成区）**；3 缺参 / 未知 flag / 正文超限（DoD >200、结论 >500、日志 >200）、flag 互斥。

### 4.1 `task-add "<标题>" --dod "<一句>"`

| 参数 | 必填 | 含义 |
|---|---|---|
| 标题 | 是 | 精确标题；重名（含已完成）→ 退出 2 并列已有区名 |
| `--dod` | 是 | 一句可验证 DoD；>200 字 → 退出 3（同 §1.5 的 argv 理由） |
| `--section 已拆好\|进行中` | 否 | 默认 `已拆好`（队尾）。`进行中` 只预写块，**不**当 `start`：不补 `- 开始：`、不建工作区；后续 `start` 幂等补日期，心跳照常显示 |
| `--tag` `--basis F2` `--from "INBOX 标题"` `--pre "前置任务名"` | 否 | 写入 `- 标签：` / `- 依据：` / `- 来自：` / `- 前置：`；`basis`/`from`/`pre` 引用不存在 → 退出 2，不落盘 |
| `--head` | 否 | 插入「已拆好」队首（紧急）。与 `--section` 非 `已拆好` 同用 → 退出 3 |

**本期不支持 `--section 调研`**：TASKS 模板与 SKILL 要求调研任务带 `- 时间盒：` + `- 产出：`，且时间盒须先向用户确认；命令化会把这条纪律绕过。要支持就先加 `--timebox` / `--产出` 必填（下一期）。

查重（落盘前，引擎做；agent 不必预跑 `inbox`）：

1. TASKS 任意区标题重叠（`normTitle` 或 `similarTitles`）→ 退出 2，列出已有区名，不新建。
2. `inbox` 已解决（`- 已解决` 行或「已裁决」区）相似 → 退出 0，stdout：`[plan] 已由 <任务名> ✅ 实现`，不新建。  
   「相似」同时比**停车项标题**和**解决它的那个任务名**（`- 已解决：X ✅` 里的 X）——任务已归档进 ROADMAP 时 TASKS 查重抓不到，靠 X 兜住。命中旧「已裁决」区条目时没有任务名可回 → stdout `[plan] 已裁决：<INBOX 标题>`（不瞎编任务名）。  
   未解决相似 → 软警告一行仍新建（避免把未裁决停车项当成已做）。

> 施工修正：标题命中一律「精确相等 **或** 相似」。`similarTitles` 对 normalize 后 < 4 字的短标题恒为 false（上一份 §7.2 的规则），只写相似会让「旧想法」这类短标题漏查。

成功 stdout ≤5 行：区名、标题、DoD、可选关联行。

### 4.2 `finding-add --title "<主题一句话>" --source <来源> --conclusion "<一段话>"`

| 参数 | 必填 | 含义 |
|---|---|---|
| `--title` | 是（新开） | 写进 `### F<n>：<主题>`，索引第 5 列与同主题查重都靠它——引擎 `parseFindings` 只认这个标题行。>40 字 → 退出 3 |
| `--source` | 是（新开） | `调研探针｜开发中发现｜失败尝试｜外部输入`；`--amend` 时禁止 |
| `--conclusion` | 是 | 一段话，非问句 |
| `--tag` | 否 | `- 标签：` |
| `--impact` | 否 | `- 影响：`，默认 `无` |
| `--material <相对路径>` | 否 | `- 材料：`，路径打不开 → 退出 2 |
| `--trace <progress 相对路径>` | 否 | `- 过程追溯：`（字段名与模板一致，flag 名沿用引擎既有命名） |

固定写入：`- 日期：<今天，本地时区>`、`- 状态：有效`。**不提供 `--date`**——结论日期不回溯，与 `start` / `finish` 的补记场景不同。

行为：

- 编号 = 热区 + `FINDINGS.archive.md` 已用最大 `F<n>` + 1；永不复用（复用 `finish` 三合一里读 archive 的现成逻辑）。
- 结论以 `?` 结尾或含「待确认/待决」→ 退出 3。`--conclusion` > 500 字 → 退出 3，提示改 notes + `--material`。
- 同主题（`--title` 或结论 `similarTitles` 命中已有有效条目）→ 退出 2，提示改用 `--amend F?`。确有第二条独立结论 → `--force` 新开，并在两条下互写 `- 参见：F?`（沿用上一份「误伤比漏判烦」的取舍，给逃生舱）。
- 写热区末尾 → **再生索引**；索引失败仍退 0 + 提示手动 `reindex`。
- stdout：新条目索引行 1 行 + `已再生索引`。

`--amend F3 --conclusion "…"`：在 F3 下追加 `#### 补（<今天>）` + 结论段，不新开号；F3 不存在 → 退出 2；同样再生索引。与 `--title` / `--source` / `--force` 同用 → 退出 3（**不存在「既新开又补」的用法**）。

> 施工修正：`--amend` 还拒绝 `--tag` / `--impact` / `--material` / `--trace`（→ 退出 3）。这四个是**条目级**字段，`parseFindings` 按条目合并同名键，写进「补」里会**覆盖原条目字段**；而静默丢弃会让 agent 以为材料指针记下了。`--amend` 的编号也校验格式（非 `F<n>` / `<n>` → 退出 3），不再拼出 `Fundefined` 这种编号。

> 施工修正：补小节用 **4 个 `#`** 而非 `###`。`parseFindings` 把 `^###\s` 当作条目边界（`plan.mjs` 的 flush 分支），`### 补` 会把 F3 的块当场切断、补的内容在 `findings --full F3` 里看不见。`####` 既留在 F3 的 `raw` 里，也不会被当成新条目。

### 4.3 `inbox-add "<标题>"`

可选：`--flag 红|白`（默认白 → ⚪）、`--origin "<来源>"`（写 `— <来源：…>` 尾注，缺则整段省略）、`--finding F?`（引用必须存在）、`--date`（默认今天）。  
写入「待裁决」，行格式逐字段照模板：`- [ ] <YYYY-MM-DD> 🔴/⚪ <标题> — <来源：…>`。不移区、不写已解决。  
标题与未决相似 → 软警告仍写入；与已解决相似 → 退出 0，回 `已由 … 实现`（同 task-add 第 2 条）。  
stdout ≤3 行。

### 4.4 `progress-log <slug> --text "<一行>"`

- slug 必须是活跃工作区（`done/` 只读 → 退出 2）。无 progress.md → 退出 2。
- `--kind 进展|决策|错误`（默认 `进展`）：在 `## 日志` 下找当天的 `### YYYY-MM-DD` 标题，无则建一个；在其下追加 `- <kind>：<text>`。**不动日志区的结构**——对齐门重读「决策 / 错误」的约定就靠这个结构。没给 `--text` 时给 `--kind` → 退出 3（没有日志行可归类）。
- `--text` > 200 字 → 退出 3（详情写 notes）。
- `--position "<一行>"`：换 plan.md「当前位置」**第一条**（`- 进行到哪一步：`）。  
  `--next "<一行>"`：换**第二条**（`- 下一步要做什么：`）。收工通常两条一起给；只给 `--position` 时「下一步」会留旧。第三条「待决问题」不进命令。  
  只换值、**保留模板标签**（行仍是 `- 进行到哪一步：<值>`）；值里已带同名标签时不重复拼。
- 不读、不回 progress 全文。stdout 1 行。

### 4.5 明确仍用手改

| 内容 | 原因 |
|---|---|
| notes/ 章节、对比表 | 超 argv；本就是材料文件 |
| SPEC / ROADMAP | 写前确认，plan-review |
| progress postmortem 头 | 对齐门判断活；`finish` 只校验 |
| 改已有任务 DoD / 挪队 / 删卡 | 默认定稿；改卡先问用户。**此时读文件不禁**——手改就必然要读，SKILL 禁的是「为追加而整读」。需要时下一期再加 `task-edit`（本期不做） |

## 5. SKILL / AGENTS

`plan-task` SKILL：

- 有 node：录入任务 / 落结论 / 停 INBOX / 2-Action 日志 → **必须**对应 `task-add` / `finding-add` / `inbox-add` / `progress-log`。
- 硬句要**成对**写，避免 agent 挪队时以为被禁读：
  - 追加（新增一条）→ 走命令，禁止为追加而 Read TASKS / FINDINGS / INBOX。
  - 改 DoD / 挪队 / 删卡 → 仍手改，允许 Read；改卡先问用户。
- 无 node：手改文件（现兜底）。
- 查重「做云同步」改由 `task-add` 退出 0 承担；SKILL 写「看 stdout——`已由 … 实现` 就是没新建，不要再扫文件」。

AGENTS 片段：在「有 node 用 plan.mjs 查」旁加「有 node 用 plan.mjs 追加；不要整读了再 Edit」。

plan-review：分诊归档仍可手改 FINDINGS（判断活）+ `reindex`；不要为「加一条停车」去整读 INBOX，用 `inbox-add`。

## 6. 与现有写入命令的边界

| 命令 | 写什么 | 本期不动 |
|---|---|---|
| `start` / `finish` / `reindex` | 认领、收工机械活、再生索引 | 契约不改 |
| `task-add` | 只追加块 | 不 `start`；不进「调研」区（§4.1） |
| `finding-add` | 热区 + 索引 | 不写 ROADMAP；不改已有条目（那是 `--amend`） |
| `inbox-add` | 「待裁决」一行 | 不移区、不写已解决 |
| `progress-log` | 一条日志 + 可选前两条位置 | 不固化 postmortem |
| 7 个 hook | 推底线 / 心跳 / 双门 | **本期不动**：写命令不改变注入内容，尚未观察。心跳指针句要不要加一句 `task-add`，等观察期结束由 plan-review 定（同上一份 §11 的处理） |

## 7. 风险

| 风险 | 对策 |
|---|---|
| agent 仍 Edit 文件 | SKILL 硬句；观察期与上一份相同。不靠 hook |
| Windows 引号 | DoD ≤200 / 结论 ≤500 / 日志 ≤200；超限赶去 notes。含空格与引号的标题一律用 `--k=v` 形式 |
| 手改与命令交错 | markdown 仍是事实源；命令每次重新解析再写 |
| 同主题误伤 | finding 同主题挡新开、逼 `--amend`，但留 `--force` 逃生舱；inbox 未决相似只警告 |
| 索引再生失败 | 正文已落盘 → 仍退 0 + 提示手动 `reindex`；索引是派生视图，不影响正确性 |
| 心跳不提新命令，agent 想不起来用 | 观察期与上一份相同：两周后由 plan-review 记一条 FINDINGS（来源：外部输入，标签：运营），再决定要不要改指针句 |

## 8. 施工顺序

新增用例全部进 `tests/test-hooks.sh`（仓库唯一测试文件，现有 36 PASS），fixture 沿用该文件的 `mk` 临时目录做法，不新增目录。断言退出码 + stdout 行数/关键字 + 落盘后文件内容，不靠目测（沿用上一份 §10 的教训）。

| 步 | 内容 | 退出（可断言） |
|---|---|---|
| 1 | `task-add` + 查重 + `usage()` 补 4 个命令 | 新建 stdout ≤5 行退 0；命中已解决 stdout 含 `已由` 退 0 **且 TASKS 无新增块**；重名退 2；缺/超长 `--dod`、`--head` 配非 `已拆好` 区退 3 |
| 2 | `finding-add` / `--amend` / `--force` + 写后再生索引 | 编号 = max(热区, archive)+1；`findings` 立刻含新行且含 `--title` 主题；`--amend` 不新开号；问句 / >500 / `--amend` 配 `--source` 退 3；模板 `plan-index` 注释已同步 |
| 3 | `inbox-add` + `progress-log`；SKILL / AGENTS 文案 | `inbox` 未决 +1 且行格式逐字段对模板；日志行落在当天 `### 日期` 下、带 `- 进展：`；`--position` 只动第一条、`--next` 只动第二条；`--text` >200 退 3；SKILL 里「追加走命令」与「改/挪/删手改」成对出现，无 node 手改路径仍在 |
| 4 | 回归 | `tests/test-hooks.sh` 全绿（原 36 + 本期新增）；`task-add` 后 `status` / 心跳行数与施工前一致；hook 输出逐字未变 |

每步可单独回滚（删子命令）。hook 不动（§6）。

### 8.1 施工记录（2026-09-14）

四步已按序落地。`tests/test-hooks.sh` **45 个用例全绿**（原 36 + 本期新增 10；`ps1 薄壳冒烟` 因本机 Git Bash 下 pwsh 被安全策略阻塞而 SKIP，未计入）。施工中偏离文档的两处已回填到 §4.1 / §4.2。

| 步 | 落点 | 备注 |
|---|---|---|
| 1 | `cmdTaskAdd` + `titleHit` / `solvedHit` + `usage()` | `similarTitles` 对 <4 字归一化标题恒 false，故查重一律走 `titleHit`（精确 **或** 相似） |
| 2 | `cmdFindingAdd`（`--amend` / `--force`）+ 写后 `cmdReindex(root, true)` | 追加条用 `#### 补（date）`：`parseFindings` 把 `^###\s` 当条目边界，`###` 会切断当前块 |
| 3 | `cmdInboxAdd` + `cmdProgressLog` + SKILL / AGENTS 文案 | progress **逐字对齐模板**：新建当天标题时 `### <日期>` 下**有**空行再接 `- 进展：`（模板第 17~19 行就是这样）；追加到已有当天标题时条目之间不插空行 |
| 4 | 回归 | 10 个新用例 + hook 输出逐字比对不变 |

顺带修掉四处**本期范围外**的环境问题（否则本机连存量用例都跑不起来，无法验证本期）：

| 问题 | 位置 | 说明 |
|---|---|---|
| Git Bash 把 POSIX 路径交给原生 node | `tests/test-hooks.sh` + `skills/plan-task/hooks/*.sh`（8 个） | node 把 `/c/...` 当 `C:\c\...` → 全部 hook 在 Windows 下静默失效（真实产品缺陷，非测试问题） |
| 测试 harness 传 POSIX 路径 | `tests/test-hooks.sh` | 加 `winpath()`（`cygpath -w`），`PLANNING_ROOT` 全部转换 |
| Git Bash grep 匹配不了 emoji | `tests/test-hooks.sh` | INBOX 🔴 断言改 `node -e` 码点比较 |
| `pwsh` 存在但被安全策略挂住 | `tests/test-hooks.sh` | 原 `command -v pwsh` 预检过不去（存在≠能跑）→ 整条套件永久卡死。Git Bash / MSYS 不启动原生 pwsh（GNU timeout 杀不掉 Win32 进程）。POSIX 只给空命令预检套 `timeout 3`（成功路径几乎 0 额外耗时；卡死最多 3s 后 SKIP）；预检通过后的真实用例不再套 timeout |

### 8.2 复查记录（2026-09-14，施工后）

复查方式：不读代码「看着对」，而是拿引擎 + 真模板建临时项目**逐条实跑**，再回读落盘文件。查出三处**静默行为**，全部改为显式退 3：

| 问题 | 现象 | 修法 |
|---|---|---|
| `--amend` 静默丢弃条目级 flag | `--amend F3 --conclusion x --material notes/a.md` 退 0，但 `- 材料：` 没落盘——agent 会以为记下了指针 | `--tag` / `--impact` / `--material` / `--trace` 与 `--amend` 同用 → 退 3。**不能写进「补」**：`parseFindings` 按条目合并同名键，补里的 `- 标签：` 会覆盖原条目字段 |
| `--amend` 编号不校验 | `--amend`（漏值）拼出 `Fundefined`，报「未找到 Fundefined」 | 非 `F<n>` / `<n>` → 退 3，回显收到的值 |
| `progress-log --kind` 无 `--text` | `--kind 决策 --position "…"` 退 0，kind 被无声忽略 | 没给 `--text` 就给 `--kind` → 退 3 |

已实跑确认**符合模板**、无需改的几处：

- `progress-log` 新建当天标题时，`### <日期>` 下**有**空行再接 `- 进展：`——模板第 17~19 行就是这样，**不要删**。
- `--position` / `--next` 只换值、保留 `- 进行到哪一步：` 标签，第三条「待决问题」不动。
- `task-add` 队尾 / `--head` 队首落位正确；`inbox-add` 行逐字段对模板（`- [ ] <日期> 🔴 <标题> — 来源：X ｜ F1`）。

复查后重跑：**45 用例 PASS 45 / FAIL 0**（新增 6 条断言：amend+material / amend+tag / amend 编号非法 / 三者均不落盘 / kind 无 text）。

## 9. 验收

- [x] 有 node 的 SKILL 条文禁止为追加而整读 TASKS/FINDINGS/INBOX，且明写「改/挪/删仍手改、允许读」
- [x] `task-add` 命中已解决 INBOX → 退出 0 且不新建（TASKS 无新块）；命中旧「已裁决」区 → stdout `已裁决：<标题>`，不瞎编任务名
- [x] `task-add` 重名（含已完成区）→ 退 2 不落盘；`--dod` >200 → 退 3
- [x] `finding-add` 后 `findings` 能立刻看到新行（索引已再生），行内含 `--title` 主题
- [x] 新块含 `- 日期：` / `- 状态：有效` / `### F<n>：<主题>`；`--amend` 不新开号；问句结论退 3；`--amend` 配 `--source` 退 3
- [x] `--force` 新开同主题条目并互写 `- 参见：F?`
- [x] `inbox-add` 行格式逐字段对模板（🔴/⚪、日期、来源尾注）
- [x] `progress-log --kind 决策` 落在当天 `### 日期` 下；`--position` 改第一条、`--next` 改第二条；stdout 1 行；`ws <slug> --full` 才看得到刚写的那一行
- [x] 人手工改 TASKS / FINDINGS 后追加命令仍正确（写前重新解析）；`task "<名>"` 仍 0
- [x] 无 node 手改路径仍在 SKILL；Windows 含空格/引号标题用 `--k=v` 能过
- [x] hook 输出与施工前逐字相同；现有 `tests/test-hooks.sh` 查询/finish/hook 用例全绿

> 逐项证据见 §8.1 施工记录。Git Bash：`ps1 薄壳冒烟` SKIP（MSYS 不启动原生 pwsh）。Debian WSL + 便携 Node 20 / pwsh 7.4：`sh tests/test-hooks.sh` **46 PASS / 0 FAIL**，其中 `ps1 薄壳冒烟` 真跑过。
