# plan-skills

面向 vibe coding 的分层计划管理技能包（Agent Skills）。在项目中建立"锚—路标—施工图—停车场—知识库"五文件体系，防止 AI 辅助开发时的计划混乱、调研状态丢失、完成历史蒸发。

## 包含的技能

| 技能 | 作用 |
|---|---|
| `plan-init` | 项目启动时初始化计划体系：创建 SPEC.md（锚）、ROADMAP.md（里程碑 + 产出存档）、TASKS.md（当前任务）、INBOX.md（想法停车场）、FINDINGS.md（调研知识库），并向 AGENTS.md 注入计划纪律。每个项目只运行一次 |
| `new-task` | 任务录入与拆解：分流（任务 / INBOX / 调研探针 / FINDINGS）、控制 0.5~2 天粒度、生成 DoD、任务完成归档、失败尝试记录 |
| `weekly-review` | 周回顾：里程碑验收与交接（归档产出 + 启动下一里程碑首批任务）、停滞任务清理、INBOX 裁决、文档防腐化 |

## 安装

```bash
# 交互式选择要安装的技能和目标 agent
npx skills add JAYY513/plan-skills

# 直接安装指定技能
npx skills add JAYY513/plan-skills --skill plan-init
npx skills add JAYY513/plan-skills --skill new-task
npx skills add JAYY513/plan-skills --skill weekly-review
```

支持 Claude Code、Codex、Cursor、Gemini CLI 等 60+ 兼容 Agent Skills 标准的 agent。

## 使用顺序

1. 新项目根目录：让 agent 运行 `plan-init`，回答 3 个问题，体系就位
2. 日常开发：新任务 / 新想法 / 调研结论都交给 `new-task` 分流落盘
3. 每周（或里程碑完成时）：运行 `weekly-review`，验收、归档、启动下一阶段

## 设计原则

- 任务层乱是正常的，不需要治；锚（SPEC）和路标（ROADMAP）不许随便动
- 新想法一律先进 INBOX.md，禁止当场改 ROADMAP.md / SPEC.md
- 调研结论一律落 FINDINGS.md，跨会话不丢；失败尝试也记录，避免重复踩坑
- 完成历史不删除：任务归档到 ROADMAP 里程碑下，随时能回答"这个阶段做了什么"
- 每条信息只有一个家，其他文件只引用不复制
- 计划维护时间红线：每天 ≤10 分钟，每周 ≤30 分钟

## License

MIT
