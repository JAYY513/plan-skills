#!/bin/sh
# permission-request hook（Codex）：权限确认弹窗时注入一行当前任务上下文。
# 极简输出：存在进行中任务则输出一行提示，否则静默退出。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

[ "$PLANNING_HOOKS_DISABLED" = "1" ] && exit 0

ROOT="${PLANNING_ROOT:-.}"

[ -f "$ROOT/TASKS.md" ] || exit 0

first_task=$(sed -n '/^## 进行中/,/^## /p' "$ROOT/TASKS.md" | grep -m1 '^### ' | sed 's/^### *//')
[ -n "$first_task" ] && echo "[plan] 当前进行中任务：$first_task（权限请求与计划纪律相关时请对照 TASKS.md / plan.md）"

exit 0
