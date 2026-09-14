#!/bin/sh
# stop-gate hook 薄壳：全部逻辑在 ../engine/plan.mjs（sh/ps1 共用单一实现，双平台永不漂移）。
# 两道门：①活跃工作区任务未标 ✅ → 阻止；②「进行中」有非当天开工的任务且无工作区痕迹 → 阻止。
# 命中阻止时引擎以 exit 2 阻断（Claude Code Stop hook 语义），本薄壳用 exec 原样透传退出码。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，引擎立即静默退出。
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENGINE="$DIR/../engine/plan.mjs"
# Windows 的 Git Bash / MSYS：node 是原生程序，不认 /c/... 这类 POSIX 路径（会当成 C://c//...）
if command -v cygpath >/dev/null 2>&1; then ENGINE=$(cygpath -w "$ENGINE"); fi
if command -v node >/dev/null 2>&1; then
  exec node "$ENGINE" hook stop-gate "$@"
fi
# 无 node → 静默退出（hook 绝不阻断会话）
exit 0
