---
name: plan-task
description: 任务从讨论到完成的全生命周期管理（自动驾驶）。当对话中出现"加个任务""把 xxx 加进计划""帮我拆一下这个任务""下一步做什么""现在什么进度 / 当前状态 / status""开工 / 开始做 X""任务做完了""记录一个新想法"，或在讨论实施计划、拆任务、调研结论、失败尝试时使用——这些信号出现时自动落盘，不依赖用户点名技能。负责分流判断（TASKS / INBOX / FINDINGS）、控制 0.5~2 天粒度、生成 DoD、认领开工时自动建 .planning/ 工作区、执行 2-Action 落盘纪律、完成时走三合一动作并标 ✅。曾用名：new-task、task-plan（两技能已合并为本技能）。
hooks:
  SessionStart:
    - hooks:
        - type: command
          command: "sh \"${CLAUDE_SKILL_DIR}/hooks/session-start.sh\" 2>/dev/null || true"
  PreToolUse:
    - matcher: "Edit|Write|MultiEdit|Bash"
      hooks:
        - type: command
          command: "sh \"${CLAUDE_SKILL_DIR}/hooks/pre-tool-use.sh\" 2>/dev/null || true"
  PostToolUse:
    - matcher: "Edit|Write|MultiEdit"
      hooks:
        - type: command
          command: "sh \"${CLAUDE_SKILL_DIR}/hooks/post-tool-use.sh\" 2>/dev/null || true"
  PreCompact:
    - hooks:
        - type: command
          command: "sh \"${CLAUDE_SKILL_DIR}/hooks/pre-compact.sh\" 2>/dev/null || true"
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "sh \"${CLAUDE_SKILL_DIR}/hooks/user-prompt-submit.sh\" 2>/dev/null || true"
  Stop:
    - hooks:
        - type: command
          command: "sh \"${CLAUDE_SKILL_DIR}/hooks/stop-gate.sh\""
---

# plan-task：任务录入、执行与完成

> 曾用名：new-task（任务录入与拆解）+ task-plan（单任务工作区），两技能已合并为本技能，对话中出现任务信号时自动介入。

## 先读四个文件

ROADMAP.md（找 ▶ 当前里程碑）、TASKS.md、INBOX.md 全文读；FINDINGS.md 只读其「索引」区（每条一行），命中主题再按 F 编号取条目全文，绝不整篇通读。缺失任一文件 → 提示用户先运行 plan-init。

## 分流判断

对话中出现以下信号时自动落盘，不等用户点名：

1. **出现调研结论或重要发现** → 写入 FINDINGS.md 热区（落笔前先 grep 索引查重：同主题 → 在原条目追加「补」小节或标记替代，不另开新条目；条目格式：编号、来源、结论含证据、影响标注；只写结论与关键证据，过程细节留在 `.planning/` 工作区 progress.md，用「过程追溯」行引用）。结论影响计划（改变某里程碑可行性或 SPEC 选型）→ 同步在 INBOX.md 登记一条并引用 FINDINGS 编号，告知用户"已停车，计划变更走 plan-review 时裁决"
2. **出现失败尝试**（试过某方案行不通）→ 写入 FINDINGS.md，来源标"失败尝试"，写清"试过什么、为什么不行"
3. **冒出不服务当前里程碑的新想法 / 待裁决项** → 写入 INBOX.md，标注 🔴（影响当前里程碑）或 ⚪（不影响），告知用户"已停车"，**不要**当场改 ROADMAP.md / SPEC.md；当前里程碑只含 MVP 桶内容时，P0/P1 需求一律停 INBOX.md；服务当前里程碑 → 进 TASKS.md（走下面的录入流程）
4. **出现调研需求** → 登记前先查已有结论（FINDINGS.md 索引、docs/01-wiki、docs/research、个人知识库），命中则直接引用既有条目、不重复调研；未命中才进 TASKS.md「调研（限时探针）」区，必须向用户确认时间盒和产出要求（产出默认要求落 FINDINGS.md），缺了就问。调研时优先一手来源（官方文档、源码、论文），二手文章只作线索；没有来源的结论不写进 FINDINGS.md
5. **用户问"下一步做什么" / 讨论实施计划要拆任务** → 「已拆好（待做）」队首 1~2 个就是答案，直接报给用户；队列为空时才从当前里程碑的验收标准反推候选任务（带 DoD），用户确认后录入
6. **用户问"现在什么进度 / 当前状态 / status"** → 输出状态摘要，只读不写：当前 ▶ 里程碑与验收标准勾选情况、进行中任务及各自 DoD 进度、活跃工作区 plan.md 的「当前位置」、INBOX 待裁决数
7. **用户说"开工 / 开始做 X"** → 认领任务（调引擎 `start` 命令，见下）；未指定任务名时默认认领「已拆好（待做）」队首；若任务符合工作区判据（见下）→ 传 `--workspace` 自动建 `.planning/` 工作区再动手

## 录入流程（进 TASKS.md 的任务）

1. **查重**：先扫 TASKS.md 已有条目（含「已完成（待归档）」），新任务与已有条目重叠 → 不新增，改为合并/指出现有条目并问用户一句
2. **检查粒度**：预估超过 2 天 → 拆成 0.5~2 天的子任务，每个可独立完成
3. **生成 DoD**：每条任务写一条可手动验证的完成标准。
   - 差的 DoD："功能能用"
   - 好的 DoD："点击中断 → 输出立刻停止 → 按钮恢复可发状态，手动验证通过"
4. 追加到 TASKS.md 对应区域（进行中 / 已拆好 / 调研）；进「已拆好（待做）」的默认追加到**队尾**，用户表达"先做 X / X 紧急"→ 插入**队首**（已在队列里的任务则挪到队首）；任务依赖另一个任务完成 → 在该任务行下加一行 `- 前置：<任务名>`
5. **检查队列水位**：「进行中」+「已拆好」合计少于 2 个 → 主动从当前里程碑反推，提议补充任务

## 认领开工与工作区

认领动作由引擎命令完成（在项目根目录执行，任务名按标题精确匹配）：

```bash
node <技能目录>/engine/plan.mjs start "<任务名>"              # 移入「进行中」+ 补开始日期（幂等，重复调不报错）
node <技能目录>/engine/plan.mjs start "<任务名>" --workspace  # 符合工作区判据时加此参数
```

`--workspace` 会自动：从 `assets/templates/` 复制 plan.md / progress.md 到 `.planning/<日期>-<slug>/`、填充任务名与关联条目、在 TASKS.md 任务行下补 `- 工作区：` 关联行（任务与工作区之间唯一的据）；已有工作区的任务会复用，目录丢失则按原 slug 重建并自动写 `⚠️ 工作区曾于 … 丢失` 重建标注。

认领前仍由 agent 负责：先扫该任务的 `前置:` 行，前置任务未标 ✅ → 提醒用户一句"X 还没完成，确定要先做这个？"——是提醒不是阻断，用户说继续就继续。

开工前先对照 SPEC 红线（「不做什么（边界）」+「技术选型」）：本会话已由 session-start hook 注入则直接遵循；未见注入（OpenCode / 未配 hook / `PLANNING_HOOKS_DISABLED=1`）→ 主动读 SPEC.md 这两节。执行中任何步骤将违背边界或选型（引入被排除的方向、换掉已定技术）→ 先停下与用户确认，不静默漂移。红线进入上下文靠 hook 注入或自行阅读，对照判断始终由 agent 负责。

是否传 `--workspace` 由以下判据决定（符合任一 → 传，不问用户，建完告知一句；否则普通小任务不建工作区）：

1. 预计跨 ≥2 个会话才能做完
2. 执行路径边走边定（调研型任务，下一步取决于上一步发现）
3. 用户明确要求建工作区

多个并行任务各自建独立目录，天然隔离，互不读写。

**node 不可用时的兜底**（罕见，引擎依赖 Node ≥ 18）：按原手动规则执行——任务块移入「进行中」段末尾、补 `- 开始：YYYY-MM-DD`；需建工作区时手动复制模板到 `.planning/<日期>-<slug>/`（slug = 任务名转小写连字符）并补 `- 工作区：` 行。

定位不变：项目级 5 文件是每条信息的唯一的家；`.planning/<slug>/` 是单任务的**临时工作区**，只放执行过程，**禁止存放最终结论**——结论的家永远是 FINDINGS.md（活跃条目在热区，历史条目经 plan-review 分诊后进 FINDINGS.archive.md，索引在两处均可按编号检索）。

## 工作区执行纪律

- **每次开工先重读 plan.md**——包括新会话恢复，从「当前位置」接着走，不凭记忆
- **2-Action 规则**：每约 2 次探索 / 修改动作后，把进展、决策、错误落进 progress.md，随手更新 plan.md 的「当前位置」
- **失败路径必须记录**（试过什么、为什么不行），避免跨会话重复踩坑
- **步骤不是子任务**：plan.md 的步骤是该（子）任务的执行顺序，不是再拆一遍子任务；步骤不设 DoD——DoD 只在 TASKS.md 的任务行上

## 完成流程（用户说"做完了"）

分工：**结论内容由 agent 先写，机械动作与校验由引擎 `finish` 命令完成**。

1. 逐条核对该任务的 DoD——实际执行验证步骤，不凭印象，全部通过才算完成；标 ✅ 前把本次改动的 diff 自查一遍：只含本任务相关改动，无顺手带入的无关修改
2. 若该任务有 `.planning/` 工作区 → agent 先写好三合一的内容部分（见下）：结论回填 FINDINGS.md（含「过程追溯」引用行）+ progress.md 顶部固化 postmortem
3. 调引擎完成校验与机械动作：

```bash
node <技能目录>/engine/plan.mjs finish "<任务名>"
```

   校验通过 → 自动把任务移入「已完成（待归档）」、标题加 ✅、补完成日期、工作区移入 `.planning/done/`；校验不通过 → 列出缺失清单并拒绝标 ✅，agent 补齐内容后重跑。完成后 agent 在任务行补一句"实际怎么做的"备注
4. **不许删除**——归档是 plan-review 的职责
5. 过程中踩过的坑、推翻的方案 → 顺手记入 FINDINGS.md
6. 检查队列水位，不足则提议补充

**node 不可用时的兜底**：按原手动规则——核完三合一后手动把任务块移入「已完成（待归档）」、标题加 ✅、补 `- 完成：YYYY-MM-DD`，手动把工作区目录移入 `.planning/done/`。

### 完成三合一动作（一个动作三件事）

缺任何一件，**不许**把任务标 ✅：

1. **结论回填 FINDINGS.md**：按条目格式写入，并加一行引用：`过程追溯：.planning/done/<slug>/progress.md`
2. **固化 postmortem 头**：在 progress.md 顶部 postmortem 区填写——结论 → FINDINGS 编号、一句话坑总结（详情在 FINDINGS）、声明"本文档为过程记录，结论以 FINDINGS 为准"
3. **整个工作区移入 `.planning/done/`**：归档后只读，永不修改（由 `finish` 命令自动执行）

若安装本技能时启用了随技能注册的 stop-gate hook（脚本在本技能目录 `hooks/` 下），它会在会话收尾时校验：门①——存在活跃工作区但关联任务未标 ✅（按 plan.md「关联 TASKS 条目」精确匹配，postmortem 已固化兜底）→ 阻止；门②——「进行中」仍有任务且无任何工作区痕迹 → 阻止，但**开始日期 = 今天的任务豁免**（当天认领的小任务不再误伤，隔天遗留的仍阻止）。hook 只是本技能规则的执行者，不是第二套规则。

## 关联技能

- 计划变更（改 ROADMAP / SPEC / 验收标准）、里程碑交接、INBOX 裁决 → 走 `plan-review`（事件驱动的计划变更门）
- 计划体系未初始化 → 提示用户先运行 `plan-init`
- 不依赖任何外部技能：DoD 实测核对、diff 自查、调研一手来源等纪律均已内置在上述流程中

## 纪律

- 不凭空发明任务；拿不准归属就问用户一句，不要猜
- 「已拆好（待做）」的位置即顺序——调序就是挪条目位置，不设优先级标签、不编号；「进行中」「调研」「已完成」区不排序
- 不修改 ROADMAP.md / SPEC.md——那是 plan-review 的职责
- 调研结论不落 FINDINGS.md 就不算调研完成
- 不要给不需要的任务建工作区——小任务建工作区本身就是腐化
- `.planning/` 活跃区建议 gitignore，`.planning/done/` 提交入库（完成历史不删）
