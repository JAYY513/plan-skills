#!/bin/sh
# pre-tool-use hook：执行类工具调用前注入当前任务上下文。
# 输出内容：TASKS.md 进行中任务 + 各活跃工作区 plan.md 的「当前位置」摘要。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

[ "$PLANNING_HOOKS_DISABLED" = "1" ] && exit 0

ROOT="${PLANNING_ROOT:-.}"

if [ -f "$ROOT/TASKS.md" ]; then
  tasks=$(sed -n '/^## 进行中/,/^## /p' "$ROOT/TASKS.md" | grep '^### ' | sed 's/^### */- /')
  if [ -n "$tasks" ]; then
    echo "[plan] 进行中任务："
    echo "$tasks"
  fi
fi

if [ -d "$ROOT/.planning" ]; then
  for d in "$ROOT/.planning"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ "$name" = "done" ] && continue
    [ -f "$d/plan.md" ] || continue
    pos=$(sed -n '/^## 当前位置/,$p' "$d/plan.md" | grep '^- ' | head -3)
    if [ -n "$pos" ]; then
      echo "[plan] 工作区 .planning/$name 当前位置："
      echo "$pos"
    fi
  done
fi

exit 0
