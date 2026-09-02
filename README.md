# plan-skills

面向 vibe coding 的分层计划管理技能包（Agent Skills）。在项目中建立"锚—路标—施工图—停车场—知识库"五文件体系，防止 AI 辅助开发时的计划混乱、调研状态丢失、完成历史蒸发。

## 包含的技能

| 技能 | 作用 |
|---|---|
| `plan-init` | 项目启动时初始化计划体系：创建 SPEC.md（锚）、ROADMAP.md（里程碑 + 产出存档 + MVP/P0/P1 范围分桶）、TASKS.md（当前任务）、INBOX.md（想法停车场）、FINDINGS.md（调研知识库），并向 AGENTS.md 注入自动落盘判断矩阵。全新初始化每个项目只运行一次；已初始化项目重跑时进入升级评估（升级 / 重置 / 不动三选一），不覆盖用户数据 |
| `plan-task` | 任务全生命周期（自动驾驶）：分流判断（TASKS / INBOX / FINDINGS）、0.5~2 天粒度控制与 DoD 生成、开工自动建 `.planning/` 工作区、2-Action 落盘纪律、完成三合一动作与 ✅ 核对。曾用名：`new-task` + `task-plan`（两技能已合并） |
| `plan-review` | 事件驱动的计划变更门：里程碑验收与交接（归档产出 + 启动下一里程碑首批任务）、停滞任务清理、INBOX 裁决、`.planning/` 工作区兜底、文档防腐化。曾用名：`weekly-review` |

## 安装

```bash
# 交互式选择要安装的技能和目标 agent
npx skills add JAYY513/plan-skills

# 直接安装指定技能
npx skills add JAYY513/plan-skills --skill plan-init
npx skills add JAYY513/plan-skills --skill plan-task
npx skills add JAYY513/plan-skills --skill plan-review
```

支持 Claude Code、Codex、Cursor、Gemini CLI 等 60+ 兼容 Agent Skills 标准的 agent。

装完后 hooks 按平台生效情况：

- **Claude Code**：hooks 已随 plan-task 技能自动注册（写在技能 SKILL.md 的 frontmatter 里），装完即用，无需任何手动步骤
- **Codex**：需手动两步（一次性）——把 `hooks/codex/hooks.json` 复制为 `<项目根>/.codex/hooks.json`（模板已直接指向技能目录里的脚本，**脚本无需复制**），并在 `~/.codex/config.toml` 的 `[features]` 节加 `hooks = true`。见 `hooks/codex/README.md`
- **OpenCode**：无 shell hook 机制，为 skill-only 安装，纪律由 SKILL.md + AGENTS.md 保证，见 `hooks/opencode/README.md`

## 使用方式（自动驾驶）

1. 新项目根目录：让 agent 运行一次 `plan-init`，回答 4 个问题，体系就位
2. 之后正常开发即可——和 agent 讨论蓝图、阶段计划、"接下来做 X"、调研结论，agent 按 AGENTS.md 中的自动落盘判断矩阵自己决定写进哪个文件（执行层写后告知，锚和路标写前确认），不需要你点名任何技能
3. 里程碑完成、计划失序或 INBOX 积压时：跑一次 `plan-review`，验收、归档、裁决、启动下一阶段

## 快速上手：说什么 → 发生什么

| 你说 / 讨论中出现 | agent 自动做的事 | 是否先问你 |
|---|---|---|
| "我想做一个 xxx 工具，核心是……" | 更新 SPEC.md 草稿 | 写前确认 |
| "第一阶段先跑通 xxx 就算成" | 写入 ROADMAP.md 里程碑 + 验收标准 | 写前确认 |
| "这个云同步功能以后再说" | 归入 ROADMAP 的 P1 桶（或先停 INBOX） | 写前确认 |
| "接下来做登录页" | 录入 TASKS.md，拆 0.5~2 天粒度，带 DoD | 不问，写后告知一句 |
| "我试过 X 方案，不行，因为……" | 落 FINDINGS.md（失败尝试，含原因） | 不问，写后告知 |
| "开工 / 开始做 X" | 认领任务；跨会话大任务自动建 `.planning/` 工作区 | 不问，写后告知 |
| "做完了" | 核对 DoD → 三合一归档（回填 FINDINGS + postmortem + 移入 done/）→ 标 ✅ | 不问 |
| "周回顾 / 这个阶段做完了" | 跑 plan-review：验收、交接、裁决、体系自检 | 计划变更处确认 |

## hooks 安装（按平台）

- **Claude Code**：无需操作。`npx skills add` 安装 plan-task 技能后，hooks 通过 SKILL.md frontmatter 自动注册，脚本随技能位于 `skills/plan-task/hooks/`
- **Codex**：`npx skills add` 只装技能目录，不会写 Codex 配置，需手动两步（一次性）——① 把 `hooks/codex/hooks.json` 复制为 `<项目根>/.codex/hooks.json`（模板已直接指向 `.agents/skills/plan-task/hooks/` 里的脚本，脚本随技能自动就位、随 `npx skills update` 更新，**无需复制脚本**）；② 在 `~/.codex/config.toml` 的 `[features]` 节加 `hooks = true`。全局安装见 `hooks/codex/README.md`
- **OpenCode**：无 shell hook 机制（官方只有 TypeScript 插件），skill-only 安装即可，详见 `hooks/opencode/README.md`

验证（任意平台）：`sh .agents/skills/plan-task/hooks/plan-doctor.sh` 逐项自检（Windows PowerShell 用同名 `.ps1`）。`hooks/claude-code/` 下保留的 settings.json 仅作旧版手动安装参考。

## 常见问题

- **需要 Node 运行时吗？** 需要。引擎（`engine/plan.mjs`）与所有 hook 薄壳依赖 Node ≥ 18；`npx skills` / Claude Code / Codex CLI 生态本身就依赖 Node，正常安装路径下不会缺。万一缺 node：hook 静默退出不阻断会话，`start` / `finish` / `plan-doctor` 报错退出
- **项目已经做了一半，能中途接入吗？** 能。plan-init 检测到任一计划文件已存在时不会覆盖，而是给出三个选项：升级（结构对齐最新模板、数据原样保留）/ 重置（旧文件备份到 `.planning/legacy-init/` 后重新初始化）/ 不动；回答 4 个问题时按现状填即可
- **技能更新后，旧项目怎么获得新模板的改进？** `npx skills update` 更新技能包后重跑 plan-init 选「升级」：纪律指令与格式说明对齐新模板，里程碑 / 任务 / 调研条目等用户数据永不覆盖；AGENTS.md 的「计划纪律」段按锚点幂等替换，不会重复追加
- **已有 AGENTS.md 会被覆盖吗？** 不会。只动「## 计划纪律」段：没有就追加到文件末尾，已有就整体替换为最新版，其余内容不动
- **装完怎么验证 hooks 真的挂上了？** 跑自检脚本：`sh .agents/skills/plan-task/hooks/plan-doctor.sh`（Windows PowerShell：`powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\plan-task\hooks\plan-doctor.ps1`），逐项输出 PASS / WARN / FAIL，快速定位"静默无 hook"问题；`--global` 只查全局安装
- **想临时关掉 hooks？** 设环境变量 `PLANNING_HOOKS_DISABLED=1`，全部 hook 立即静默（plan-doctor 是诊断工具，不受此变量影响）
- **怎么更新已安装的技能？** 用 `npx skills update`——重新执行 `npx skills add` 不会自动更新已装技能
- **日常要看哪个文件？** 平时只看 TASKS.md（做什么）；讨论结论查 FINDINGS.md；阶段进度看 ROADMAP.md 的 ▶；SPEC.md 和 INBOX.md 不需要日常看
- **多久跑一次 plan-review？** 事件驱动：里程碑验收通过时必跑；其余随意——感觉计划乱了、INBOX 积压了就可以跑，单次 ≤30 分钟

## 双层体系：项目级 vs 单任务级

项目级 5 文件是每条信息的唯一的家；`.planning/` 是单任务的临时工作区，只放执行过程，禁止存放最终结论。

```
<项目根>/
├── SPEC.md / ROADMAP.md / TASKS.md / INBOX.md / FINDINGS.md   # 项目级：唯一信息家
└── .planning/                    # 单任务级：临时工作区
    ├── 2026-06-08-lsp-client/    # 活跃工作区（建议 gitignore）
    │   ├── plan.md               #   步骤 checklist（执行顺序，不设 DoD）+ 当前位置
    │   └── progress.md           #   过程日志 + 顶部 postmortem 区
    └── done/                     # 已归档（提交入库，永不修改，只读）
        └── 2026-05-30-hashline-core/
```

归档规则：

- 任务完成走三合一动作：结论回填 FINDINGS.md（含"过程追溯"引用行）→ progress.md 顶部固化 postmortem → 整个工作区移入 `.planning/done/`，缺一件不许标 ✅
- `.planning/` 活跃区建议 gitignore，`.planning/done/` 提交入库——完成历史不删
- 归档后永不修改；漏归档 / 停滞的工作区由 plan-review 兜底

## 可选 hook 层（薄壳 + 单一引擎）

无 hook 时，上述纪律靠 AGENTS.md + agent 自觉执行；安装平台 hook 后由脚本在关键时机自动注入提醒、强制校验，行为等价只是强度更强。

架构：全部逻辑只有一份，在 `skills/plan-task/engine/plan.mjs`（Node ≥ 18，零依赖）；`hooks/` 下的 16 个 `.sh` / `.ps1` 脚本只是调用引擎的薄壳，不含任何业务逻辑，双平台行为永不漂移。hook 只读状态文件并输出提示文本（唯一写入是节流缓存 `.planning/.hook-cache.json`）；状态文件只由引擎的 `start` / `finish` 命令写入。设置环境变量 `PLANNING_HOOKS_DISABLED=1` 可一键全部禁用；无 node 环境时 hook 静默退出不阻断会话。

| 平台 | 安装方式 |
|---|---|
| Claude Code | 随 plan-task 技能 frontmatter 自动注册（脚本在 `skills/plan-task/hooks/`）；`hooks/claude-code/` 仅保留旧版手动安装示例 |
| Codex | `hooks/codex/`（hooks.json 模板 + 手动安装说明，脚本从技能目录复制） |
| OpenCode | `hooks/opencode/`（无 shell hook 机制，skill-only + 可选 TS 插件说明） |

7 个机制：

- **session-start**：会话开始先注入 **SPEC 红线**（「不做什么」边界 + 技术选型，防执行期隐式漂移，上限 12 行截断），再注入当前里程碑 + 进行中任务 + 活跃工作区列表 + 主动提示行（进行中任务数 / INBOX 待裁决数）
- **user-prompt-submit**：每次用户消息提交时重新注入进行中任务**原文**（TASKS.md「进行中」段含 DoD，超 60 行截断）+ 当前里程碑一行 + 活跃工作区一行，抗 context rot。**节流**：注入内容与上次完全相同时只输出一行摘要（计划状态无变化），不重复刷全文；`PLANNING_HOOKS_NO_THROTTLE=1` 可关闭节流
- **pre-tool-use**：执行类工具前注入当前任务 + 工作区 plan.md「当前位置」摘要。**节流**：内容未变且距上次输出 < 10 分钟 → 静默
- **post-tool-use**：写代码文件后提醒更新 progress.md / 勾选 plan.md 步骤。**节流**：同 pre-tool-use
- **stop-gate**：会话收尾双门校验——①存在活跃工作区但关联任务未标 ✅（按 plan.md「关联 TASKS 条目」精确匹配，postmortem 已固化兜底）→ 阻止并提示三合一动作；②「进行中」仍有任务且无任何工作区痕迹 → 阻止并提示完成或移回待办；**当天豁免**：开始日期 = 今天的进行中任务不被门②阻止（当天认领的小任务不再误伤），隔天遗留或未写开始日期的仍阻止
- **pre-compact**：上下文压缩前提醒把进展 / 「当前位置」抢写进工作区，防漂移
- **permission-request**（仅 Codex）：权限确认弹窗时注入一行当前任务上下文

平台差异：Claude Code 挂前 6 个（无 PermissionRequest 机制，与参考项目一致不挂）；Codex 7 个全挂（见 `hooks/codex/hooks.json`）；OpenCode 无 shell hook 机制。

各平台的安装方式见对应目录的 README.md。未匹配到平台时跳过不报错，靠 AGENTS.md 纪律达到等价行为，强度较弱。

## 参与开发

```bash
# 启用 pre-commit（改 hook 脚本前必跑冒烟测试，失败拒绝提交）
git config core.hooksPath .githooks

# 手动跑测试
sh tests/test-hooks.sh
```

hook 脚本单一来源在 `skills/plan-task/hooks/`（plan-task 是执行期技能，hooks 归它管；plan-init / plan-review 是初始化与回顾动作，不挂执行期 hooks），但薄壳里没有任何业务逻辑——真正的逻辑全部在 `skills/plan-task/engine/plan.mjs`。改行为直接改引擎，测试（`tests/test-hooks.sh`）会同时覆盖引擎命令、hook 输出文本、薄壳透传（含 ps1 冒烟，有 pwsh 才跑）与节流逻辑。

## 设计原则

- 任务层乱是正常的，不需要治；锚（SPEC）和路标（ROADMAP）不许随便动
- 新想法一律先进 INBOX.md，禁止当场改 ROADMAP.md / SPEC.md
- 调研结论一律落 FINDINGS.md，跨会话不丢；失败尝试也记录，避免重复踩坑
- 完成历史不删除：任务归档到 ROADMAP 里程碑下，随时能回答"这个阶段做了什么"
- 每条信息只有一个家，其他文件只引用不复制
- 计划维护时间红线：每天 ≤10 分钟，回顾单次 ≤30 分钟

## License

MIT
