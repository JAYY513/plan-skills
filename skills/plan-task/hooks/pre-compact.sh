#!/bin/sh
# pre-compact hook：上下文压缩前抢写状态，防漂移。
# 输出内容：若存在活跃工作区，提醒先把进展 / 决策 / 「当前位置」落盘 progress.md 和 plan.md；TASKS.md 有进行中任务时顺带提醒确认 TASKS 状态已最新。
# 本脚本只读状态文件并输出提示文本，绝不写状态文件；无活跃工作区时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

[ "$PLANNING_HOOKS_DISABLED" = "1" ] && exit 0

ROOT="${PLANNING_ROOT:-.}"

[ -d "$ROOT/.planning" ] || exit 0

active=""
for d in "$ROOT/.planning"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  [ "$name" = "done" ] && continue
  active="$active $name"
done

[ -n "$active" ] || exit 0

for name in $active; do
  echo "[plan] 上下文即将压缩：请先把当前进展、决策、「当前位置」更新进 .planning/$name/progress.md 和 plan.md，再继续"
done

# TASKS.md 有进行中任务时，顺带提醒确认 TASKS 状态已最新
if [ -f "$ROOT/TASKS.md" ]; then
  task_count=$(sed -n '/^## 进行中/,/^## /p' "$ROOT/TASKS.md" | grep -c '^### ')
  [ "$task_count" -gt 0 ] && echo "[plan] 另：TASKS.md 有 $task_count 个进行中任务，请确认 TASKS 状态已最新。"
fi

exit 0
