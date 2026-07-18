# Claude Code hooks

4 个机制：session-start（注入计划状态）、pre-tool-use（注入当前任务上下文）、post-tool-use（提醒落盘 progress）、stop-gate（收尾校验三合一动作）。所有脚本只读状态文件，绝不写状态文件；设置 `PLANNING_HOOKS_DISABLED=1` 可一键禁用全部 hook。

## 安装

1. 把本目录 4 个 `.sh` 脚本复制到项目（例如 `<项目根>/hooks/`）
2. 把 `settings.json` 中的 `hooks` 片段合并进项目 `.claude/settings.json`，按实际脚本路径调整 `command`
3. Windows 无 Git Bash 环境时改用 `.ps1` 版本，`command` 形如：
   `powershell -NoProfile -ExecutionPolicy Bypass -File hooks/session-start.ps1`

## 验证

```bash
sh hooks/session-start.sh   # 无状态文件时应静默退出，不报错
```

脚本默认以当前目录为项目根；也可用环境变量 `PLANNING_ROOT` 指定项目根。
