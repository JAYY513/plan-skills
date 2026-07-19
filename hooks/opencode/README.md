# OpenCode hooks

5 个机制：session-start（注入计划状态）、pre-tool-use（注入当前任务上下文）、post-tool-use（提醒落盘 progress）、pre-compact（上下文压缩前抢写状态提醒）、stop-gate（收尾校验三合一动作）。所有脚本只读状态文件，绝不写状态文件；设置 `PLANNING_HOOKS_DISABLED=1` 可一键禁用全部 hook。

## 安装

1. 把本目录 5 个 `.sh` 脚本复制到项目（例如 `<项目根>/hooks/`）
2. 在 OpenCode 插件 / hook 配置中按事件注册脚本（Windows 无 Git Bash 时改用同名 `.ps1`）：
   - 会话启动事件 → `sh hooks/session-start.sh`
   - 工具执行前（edit / write / bash 等执行类工具）→ `sh hooks/pre-tool-use.sh`
   - 工具执行后（写代码文件类工具）→ `sh hooks/post-tool-use.sh`
   - 上下文压缩前事件 → `sh hooks/pre-compact.sh`
   - 会话结束事件 → `sh hooks/stop-gate.sh`
3. 具体配置字段以你所用 OpenCode 版本的插件 / hooks 文档为准；脚本输出即为注入 / 提示文本。

## 验证

```bash
sh hooks/session-start.sh   # 无状态文件时应静默退出，不报错
```

脚本默认以当前目录为项目根；也可用环境变量 `PLANNING_ROOT` 指定项目根。
