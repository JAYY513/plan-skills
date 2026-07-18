# plan-skills

面向 vibe coding 的分层计划管理技能包（Agent Skills）。在项目中建立"锚—路标—施工图—停车场—知识库"五文件体系，防止 AI 辅助开发时的计划混乱、调研状态丢失、完成历史蒸发。

## 包含的技能

| 技能 | 作用 |
|---|---|
| `plan-init` | 项目启动时初始化计划体系：创建 SPEC.md（锚）、ROADMAP.md（里程碑 + 产出存档 + MVP/P0/P1 范围分桶）、TASKS.md（当前任务）、INBOX.md（想法停车场）、FINDINGS.md（调研知识库），并向 AGENTS.md 注入自动落盘判断矩阵。每个项目只运行一次 |
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

## 使用方式（自动驾驶）

1. 新项目根目录：让 agent 运行一次 `plan-init`，回答 4 个问题，体系就位
2. 之后正常开发即可——和 agent 讨论蓝图、阶段计划、"接下来做 X"、调研结论，agent 按 AGENTS.md 中的自动落盘判断矩阵自己决定写进哪个文件（执行层写后告知，锚和路标写前确认），不需要你点名任何技能
3. 里程碑完成、计划失序或 INBOX 积压时：跑一次 `plan-review`，验收、归档、裁决、启动下一阶段

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

## 可选 hook 层

无 hook 时，上述纪律靠 AGENTS.md + agent 自觉执行；安装平台 hook 后由脚本在关键时机自动注入提醒、强制校验，行为等价只是强度更强。hook 脚本只读状态文件并输出提示文本，绝不写状态文件；设置环境变量 `PLANNING_HOOKS_DISABLED=1` 可一键全部禁用。

| 平台 | 目录 |
|---|---|
| Claude Code | `hooks/claude-code/`（settings.json 片段 + 脚本） |
| Codex | `hooks/codex/` |
| OpenCode | `hooks/opencode/` |

4 个机制：

- **session-start**：会话开始注入当前里程碑 + 进行中任务 + 活跃工作区列表 + 主动提示行（进行中任务数 / INBOX 待裁决数）
- **pre-tool-use**：执行类工具前注入当前任务 + 工作区 plan.md「当前位置」摘要
- **post-tool-use**：写代码文件后提醒更新 progress.md / 勾选 plan.md 步骤
- **stop-gate**：会话收尾校验——存在活跃工作区但任务未标 ✅ → 阻止并提示三合一动作

各平台的安装方式见对应目录的 README.md。未匹配到平台时跳过不报错，靠 AGENTS.md 纪律达到等价行为，强度较弱。

## 设计原则

- 任务层乱是正常的，不需要治；锚（SPEC）和路标（ROADMAP）不许随便动
- 新想法一律先进 INBOX.md，禁止当场改 ROADMAP.md / SPEC.md
- 调研结论一律落 FINDINGS.md，跨会话不丢；失败尝试也记录，避免重复踩坑
- 完成历史不删除：任务归档到 ROADMAP 里程碑下，随时能回答"这个阶段做了什么"
- 每条信息只有一个家，其他文件只引用不复制
- 计划维护时间红线：每天 ≤10 分钟，回顾单次 ≤30 分钟

## License

MIT
