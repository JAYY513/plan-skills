---
name: plan-init
description: 为项目初始化分层计划体系（vibe coding 防计划混乱）。当用户说"初始化计划体系""开始新项目规划""帮我建立 SPEC/ROADMAP/TASKS""setup 计划文档"或在新项目根目录准备开始开发时使用。会创建 SPEC.md、ROADMAP.md、INBOX.md、TASKS.md、FINDINGS.md 五个状态文件，并向 AGENTS.md 注入计划纪律段落。每个项目只运行一次。
---

# plan-init：项目计划体系初始化

## 目标

在项目根目录建立四层结构：状态文件（SPEC/ROADMAP/INBOX/TASKS/FINDINGS）+ 纪律（AGENTS.md）。
状态文件管"现在是什么"，AGENTS.md 管"永远不许怎样"。

各文件分工：
- SPEC.md = 锚：项目是什么、不做什么、技术选型，基本不动
- ROADMAP.md = 路标：3~5 个里程碑 + 已完成里程碑的产出存档
- TASKS.md = 施工图：仅当前里程碑的任务，完成的待归档不删
- INBOX.md = 停车场：新想法、待裁决项
- FINDINGS.md = 知识库：调研结论、重要发现、失败尝试，跨会话不丢

## 执行步骤

1. 检查项目根目录是否已存在 SPEC.md / ROADMAP.md / TASKS.md / INBOX.md / FINDINGS.md：
   - 已存在任一 → 停止并告知用户，不要覆盖
   - 不存在 → 继续
2. 向用户提 3 个问题（一次性问完，不要逐个问）：
   - 这个项目最终要交付什么？（1~3 条，写进 SPEC 和 ROADMAP）
   - 第一个里程碑想做成什么样、怎么算验收通过？
   - 技术栈是否已确定？（确定则写进 SPEC，不确定则在 SPEC 标记"待定"）
3. 将 `assets/templates/` 下 5 个模板（SPEC/ROADMAP/INBOX/TASKS/FINDINGS）复制到项目根目录，用用户的回答填充占位内容。
4. 处理 AGENTS.md：
   - 不存在 → 新建，内容用 `assets/templates/AGENTS.snippet.md`
   - 已存在 → 追加 snippet 内容到文件末尾，保持用户原有内容不动
5. 完成后输出一段简短的使用说明：每天看什么、新想法怎么处理、调研结论落哪里、什么时候跑周回顾。

## 原则（向用户解释时引用）

- 任务层乱是正常的，不需要治；锚（SPEC）和路标（ROADMAP）不许随便动
- 新想法一律先进 INBOX.md，禁止当场改 ROADMAP.md / SPEC.md
- 调研结论一律落 FINDINGS.md，禁止只留在对话里
- 每条信息只有一个家，其他文件只引用不复制
- 完成历史不删除：任务归档到 ROADMAP 里程碑下，随时能回答"这个阶段做了什么"
- 计划维护时间红线：每天 ≤10 分钟，每周 ≤30 分钟
