# Claude Code hooks

5 个机制：session-start（注入计划状态）、pre-tool-use（注入当前任务上下文）、post-tool-use（提醒落盘 progress）、pre-compact（上下文压缩前抢写状态提醒）、stop-gate（收尾校验三合一动作）。所有脚本只读状态文件，绝不写状态文件；设置 `PLANNING_HOOKS_DISABLED=1` 可一键禁用全部 hook。

## 首选：随技能自动注册（无需任何手动步骤）

自 vercel-labs/skills CLI 安装本技能包起（`npx skills add JAYY513/plan-skills`），Claude Code hooks 已通过 `skills/plan-task/SKILL.md` 的 YAML frontmatter **随技能自动注册**——脚本在 plan-task 技能目录的 `hooks/` 下，frontmatter 中的 `${CLAUDE_SKILL_DIR}` 会解析到该目录。装完即用，无需复制脚本、无需改 settings。

## 旧版手动安装（仅供参考）

`settings.json` 是本目录保留的旧版手动安装示例：把脚本复制到项目后，将其 `hooks` 片段合并进 `.claude/settings.json`。新版 frontmatter 方式生效后不需要再走这条路。注意 settings.json 中的 `sh hooks/xxx.sh` 以项目根为工作目录，手动安装时请按实际脚本路径调整。

## 验证

```bash
sh <plan-task 技能目录>/hooks/session-start.sh   # 无状态文件时应静默退出，不报错
```

脚本默认以当前目录为项目根；也可用环境变量 `PLANNING_ROOT` 指定项目根。
