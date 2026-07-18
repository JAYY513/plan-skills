---
name: task-plan
description: 为单个跨会话任务建立独立工作区（作战室）。当用户说"开始做任务 X""开工""认领这个任务""这个调研开始做"，或 new-task 判定任务跨会话 / 执行路径不确定并建议启动时使用。会在 .planning/<slug>/ 下建立 plan.md（步骤 + 当前位置）与 progress.md（过程日志），执行 2-Action 落盘纪律，任务完成时执行三合一动作（回填 FINDINGS + postmortem + 移入 done/）。普通小任务不要使用本技能。
---

# task-plan：单任务工作区（作战室）

## 定位

项目级 5 文件（SPEC/ROADMAP/TASKS/INBOX/FINDINGS）是每条信息的唯一的家，这个分工不变。
`.planning/<slug>/` 是单任务的**临时工作区**：只放执行过程（步骤、日志、中间结论），**禁止存放最终结论**——结论的家永远是 FINDINGS.md。

## 启用判据（不看时长）

满足任一即启用，否则普通小任务不要建工作区：

1. 预计跨 ≥2 个会话才能做完
2. 执行路径边走边定（调研型任务，下一步取决于上一步发现）
3. 用户明确要求建工作区

## 先读四个文件

ROADMAP.md（找 ▶ 当前里程碑）、TASKS.md（确认任务条目与 DoD）、INBOX.md、FINDINGS.md。缺失任一文件 → 提示用户先运行 plan-init。

## 建工作区

1. 定 slug：`YYYY-MM-DD-任务短名`（短名用小写连字符，如 `2026-06-08-lsp-client`）
2. 建目录 `.planning/<slug>/`，从 `assets/templates/` 复制两个模板：
   - `plan.md`：任务名、目标、关联 TASKS 条目、步骤 checklist、「当前位置」标记区
   - `progress.md`：顶部预留 postmortem 区（完成时才填），下方为日志区
3. 多个并行任务各自建独立目录，天然隔离，互不读写

## 执行纪律

- **每次开工先重读 plan.md**——包括新会话恢复，从「当前位置」接着走，不凭记忆
- **2-Action 规则**：每约 2 次探索 / 修改动作后，把进展、决策、错误落进 progress.md，随手更新 plan.md 的「当前位置」
- **失败路径必须记录**（试过什么、为什么不行），避免跨会话重复踩坑

## 完成三合一动作（一个动作三件事）

缺任何一件，**不许**把任务标 ✅：

1. **结论回填 FINDINGS.md**：按条目格式写入，并加一行引用：`过程追溯：.planning/done/<slug>/progress.md`
2. **固化 postmortem 头**：在 progress.md 顶部 postmortem 区填写——结论 → FINDINGS 编号、踩过的坑、声明"本文档为过程记录，结论以 FINDINGS 为准"
3. **整个工作区移入 `.planning/done/`**：归档后只读，永不修改

## 与 hook 的关系（stop-gate）

若项目安装了 `hooks/` 下的平台 hook，stop-gate 会在会话收尾时校验上述三合一动作：存在活跃工作区但对应任务未标 ✅（无回填归档迹象）→ 输出阻止 / 警告。hook 只是本技能规则的执行者，校验条件与「完成三合一动作」完全一致，不是第二套规则。

## 关联技能

- 认领任务、标完成（DoD 核对、✅ 标记）→ 走 `new-task`；new-task 标 ✅ 前会检查本工作区是否已完成三合一动作
- 工作区归档兜底（漏归档、停滞清理）→ 走 `weekly-review`

## 纪律

- 工作区不是第二个信息家：最终结论只落 FINDINGS.md，plan.md / progress.md 里可以写"见 FINDINGS F?"
- `.planning/` 活跃区建议 gitignore，`.planning/done/` 提交入库（完成历史不删）
- 不要给不需要的任务建工作区——小任务建工作区本身就是腐化
