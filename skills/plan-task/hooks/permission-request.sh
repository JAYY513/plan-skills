#!/bin/sh
# permission-request hook（Codex）薄壳：全部逻辑在 ../engine/plan.mjs（sh/ps1 共用单一实现，双平台永不漂移）。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，引擎立即静默退出。
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v node >/dev/null 2>&1; then
  exec node "$DIR/../engine/plan.mjs" hook permission-request "$@"
fi
# 无 node → 静默退出（hook 绝不阻断会话）
exit 0
