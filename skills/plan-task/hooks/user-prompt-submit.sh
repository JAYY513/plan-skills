#!/bin/sh
# user-prompt-submit hook：每次用户消息提交时重新注入计划状态（抗 context rot）。
# 输出内容：当前里程碑一行 + TASKS.md「进行中」段原文（含 DoD 等完整内容，超 60 行截断）+ 活跃工作区一行提示。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

[ "$PLANNING_HOOKS_DISABLED" = "1" ] && exit 0

ROOT="${PLANNING_ROOT:-.}"

# 无任何状态文件时静默退出
[ -f "$ROOT/ROADMAP.md" ] || [ -f "$ROOT/TASKS.md" ] || [ -d "$ROOT/.planning" ] || exit 0

# 当前里程碑（一行）
if [ -f "$ROOT/ROADMAP.md" ]; then
  milestone=$(grep -m1 '^## *▶' "$ROOT/ROADMAP.md" | sed 's/^#* *//')
  [ -n "$milestone" ] && echo "[plan] 当前里程碑：$milestone"
fi

# 进行中任务：注入 TASKS.md「进行中」段原文（含 DoD），超 60 行截断
if [ -f "$ROOT/TASKS.md" ]; then
  section=$(awk '/^## 进行中/{f=1;print;next} /^## /{if(f)exit} f' "$ROOT/TASKS.md")
  if [ -n "$section" ] && echo "$section" | grep -q '^### '; then
    echo "[plan] 进行中任务（TASKS.md 原文）："
    lines=$(echo "$section" | wc -l)
    if [ "$lines" -gt 60 ]; then
      echo "$section" | head -60
      echo "[plan] 进行中段过长已截断，详见 TASKS.md"
    else
      echo "$section"
    fi
  fi
fi

# 活跃工作区（合并为一行，避免逐条刷屏）
if [ -d "$ROOT/.planning" ]; then
  ws=""
  for d in "$ROOT/.planning"/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    [ "$name" = "done" ] && continue
    ws="$ws $name"
  done
  [ -n "$ws" ] && echo "[plan] 活跃工作区：$ws（开工前先读 plan.md 的「当前位置」）"
fi

exit 0
