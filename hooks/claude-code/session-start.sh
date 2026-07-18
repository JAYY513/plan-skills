#!/bin/sh
# session-start hook：会话开始时输出当前计划状态。
# 输出内容：当前里程碑（ROADMAP.md 中 ▶ 行）+ TASKS.md 进行中任务 + .planning/ 活跃工作区列表。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

[ "$PLANNING_HOOKS_DISABLED" = "1" ] && exit 0

ROOT="${PLANNING_ROOT:-.}"

# 当前里程碑
if [ -f "$ROOT/ROADMAP.md" ]; then
  milestone=$(grep -m1 '▶' "$ROOT/ROADMAP.md" | sed 's/^#* *//')
  [ -n "$milestone" ] && echo "[plan] 当前里程碑：$milestone"
fi

# 进行中任务
if [ -f "$ROOT/TASKS.md" ]; then
  tasks=$(sed -n '/^## 进行中/,/^## /p' "$ROOT/TASKS.md" | grep '^### ' | sed 's/^### */- /')
  if [ -n "$tasks" ]; then
    echo "[plan] 进行中任务："
    echo "$tasks"
  fi
fi

# 活跃工作区（.planning/ 下除 done/ 外的目录）
if [ -d "$ROOT/.planning" ]; then
  for d in "$ROOT/.planning"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ "$name" = "done" ] && continue
    echo "[plan] 活跃工作区：.planning/$name（开工前先读 plan.md 的「当前位置」）"
  done
fi

exit 0
