# Codex hooks

5 个机制：session-start（注入计划状态）、pre-tool-use（注入当前任务上下文）、post-tool-use（提醒落盘 progress）、pre-compact（上下文压缩前抢写状态提醒）、stop-gate（收尾校验三合一动作）。所有脚本只读状态文件，绝不写状态文件；设置 `PLANNING_HOOKS_DISABLED=1` 可一键禁用全部 hook。

vercel-labs/skills CLI 只安装含 SKILL.md 的技能目录，不会安装本目录，因此 Codex hooks 需要手动安装一次。

## 安装

脚本单一来源在 `skills/plan-task/hooks/`（`npx skills add` 安装 plan-task 后即随技能就位），本目录只保留配置模板。

1. **复制脚本**：把 plan-task 技能安装目录下 `hooks/` 中的 5 对 `.sh` + `.ps1` 复制到 `<项目根>/.codex/hooks/`（全局生效则复制到 `~/.codex/hooks/`）。经实测，项目级 `npx skills add ... -a codex` 会把技能装到 `.agents/skills/plan-task/`（Agent Skills 标准路径），脚本即在 `.agents/skills/plan-task/hooks/`；其他安装方式的路径可用 `npx skills list` 查看。
2. **复制配置**：把本目录的 `hooks.json` 复制为 `<项目根>/.codex/hooks.json`（全局则 `~/.codex/hooks.json`）。模板已按上述路径写好 `command`（sh）与 `commandWindows`（powershell）双入口，一般无需改动。
3. **启用特性**：在 Codex 配置中启用 hooks 特性（具体字段以你所用 Codex 版本的 hooks 文档为准）。

脚本默认以当前目录为项目根；也可用环境变量 `PLANNING_ROOT` 指定项目根。

## 验证

```bash
sh .codex/hooks/session-start.sh   # 无状态文件时应静默退出，不报错
```
