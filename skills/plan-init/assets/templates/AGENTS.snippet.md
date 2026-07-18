## 计划纪律

- 所有任务以 TASKS.md 为准，不要凭空发明任务；任务必须服务于 ROADMAP.md 中 ▶ 标记的当前里程碑
- 用户冒出的新想法、调研发现 → 写入 INBOX.md（标注 🔴/⚪），不许当场修改 ROADMAP.md / SPEC.md
- SPEC.md 的任何修改必须在其末尾「变更日志」追加一行（日期 + 变更内容 + 原因）
- 文档间冲突时以 SPEC.md 为准；同一事实只在一个文件维护，其他位置只写引用
- 调研类任务必须带时间盒和产出要求；时间到未出结论就标记"延后"
- 调研结论和重要发现必须写入 FINDINGS.md，不许只留在对话里；结论影响计划时在 INBOX.md 登记并引用 FINDINGS 条目编号
- 失败尝试（试过什么、为什么不行）记录到 FINDINGS.md，避免重复踩坑
- 完成的任务不许删：标记 ✅ 移入 TASKS.md「已完成（待归档）」，由周回顾统一归档到 ROADMAP.md
- 声称任务完成前，逐条核对该任务的 DoD（完成标准）
- 认领跨会话任务前，先读对应 `.planning/<slug>/` 工作区的 plan.md（从「当前位置」恢复，不凭记忆）；任务完成必须走三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 `.planning/done/`）才可标 ✅
- `.planning/` 活跃工作区建议加入 gitignore；`.planning/done/` 提交入库，归档后永不修改
