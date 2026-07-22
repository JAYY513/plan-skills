# OpenCode：skill-only 安装

OpenCode **没有 shell hook 机制**——官方 hooks 只有 TypeScript 插件形式（vercel-labs/skills 兼容表中 OpenCode 的 Hooks 列为 No）。与 planning-with-files 的做法一致，OpenCode 用户只做 skill-only 安装：

```bash
npx skills add JAYY513/plan-skills -a opencode
```

此时计划纪律由 SKILL.md 正文 + plan-init 注入 AGENTS.md 的自动落盘判断矩阵保证，行为与 hook 版等价，只是少了脚本在关键时机的强制提醒 / 阻断。

## 进阶：自行编写 TS 插件（可选）

有精力的用户可以自行在 `.opencode/plugin/` 下编写 TypeScript 插件，调用 plan-task 技能随装的 shell 脚本（位于 plan-task 技能安装目录的 `hooks/` 下，即本仓库 `skills/plan-task/hooks/`）。事件映射参考：

| 机制 | OpenCode 插件事件 | 脚本 |
|---|---|---|
| session-start | `session.created` | `session-start.sh` |
| pre-tool-use | `tool.execute.before` | `pre-tool-use.sh` |
| post-tool-use | `tool.execute.after` | `post-tool-use.sh` |
| pre-compact | `experimental.session.compacting` | `pre-compact.sh` |
| stop-gate | `session.idle` | `stop-gate.sh` |

所有脚本只读状态文件并输出提示文本，绝不写状态文件；设置 `PLANNING_HOOKS_DISABLED=1` 可一键禁用。具体插件 API 以你所用 OpenCode 版本的插件文档为准。
