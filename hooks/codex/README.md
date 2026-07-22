# Codex hooks

7 个机制：session-start（注入计划状态）、user-prompt-submit（每次用户消息提交时重新注入精简计划状态，抗 context rot）、pre-tool-use（注入当前任务上下文）、post-tool-use（提醒落盘 progress）、pre-compact（上下文压缩前抢写状态提醒）、permission-request（权限确认弹窗时注入一行当前任务上下文）、stop-gate（收尾校验三合一动作）。所有脚本只读状态文件，绝不写状态文件；设置 `PLANNING_HOOKS_DISABLED=1` 可一键禁用全部 hook。

vercel-labs/skills CLI 只安装含 SKILL.md 的技能目录，不会安装本目录，因此 Codex hooks 需要手动安装一次。

## 安装

脚本单一来源在 `skills/plan-task/hooks/`（`npx skills add` 安装 plan-task 后即随技能就位），本目录只保留配置模板。

1. **复制配置（唯一需要复制的文件）**：把本目录的 `hooks.json` 复制为 `<项目根>/.codex/hooks.json`。模板中的 `command` / `commandWindows` 已直接指向技能安装路径 `.agents/skills/plan-task/hooks/`（项目级 `npx skills add ... -a codex` 的实测安装位置），脚本随技能就位、随 `npx skills update` 更新，**无需再复制脚本**。
2. **启用特性**：在 `~/.codex/config.toml` 的 `[features]` 节中启用 hooks（`hooks = true`）。验证已启用：

   ```bash
   codex features list | rg '^(hooks|codex_hooks)\s'
   ```

**注意：不要重复安装**——项目级 `<项目根>/.codex/hooks.json` 和全局 `~/.codex/hooks.json` 只装一处，两处同时存在会导致 hook 重复触发。

全局安装（`-g`，技能在 `~/.codex/skills/plan-task/hooks/`）或其他安装方式的用户：先用 `npx skills list` 确认技能实际路径，再把 hooks.json 复制到 `~/.codex/hooks.json` 并把其中的路径替换为实际路径。

脚本默认以当前目录为项目根；也可用环境变量 `PLANNING_ROOT` 指定项目根。

## 验证

推荐跑安装自检（逐项 PASS / WARN / FAIL，含 hooks.json 注册、JSON 合法性、`hooks = true` 特性开关检查）：

```bash
sh .agents/skills/plan-task/hooks/plan-doctor.sh
# Windows PowerShell：
powershell -NoProfile -ExecutionPolicy Bypass -File .agents\skills\plan-task\hooks\plan-doctor.ps1
```

也可手动抽查单个脚本：`sh .agents/skills/plan-task/hooks/session-start.sh`（无状态文件时应静默退出，不报错）。
