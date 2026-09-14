#!/bin/sh
# permission-request hook（Codex）薄壳：全部逻辑在 ../engine/plan.mjs（sh/ps1 共用单一实现，双平台永不漂移）。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，引擎立即静默退出。
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ENGINE="$DIR/../engine/plan.mjs"
# Windows 的 Git Bash / MSYS：node 是原生程序，不认 /c/... 这类 POSIX 路径（会当成 C://c//...）
if command -v cygpath >/dev/null 2>&1; then ENGINE=$(cygpath -w "$ENGINE"); fi
if command -v node >/dev/null 2>&1; then
  exec node "$ENGINE" hook permission-request "$@"
fi
# 无 node → 静默退出（hook 绝不阻断会话）
exit 0
