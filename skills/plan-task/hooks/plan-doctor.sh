#!/bin/sh
# plan-doctor 薄壳：全部逻辑在 ../engine/plan.mjs（sh/ps1 共用单一实现，双平台永不漂移）。
# 用法：sh plan-doctor.sh [--global]。诊断工具，由用户显式运行，不受 PLANNING_HOOKS_DISABLED 影响。
# 有 FAIL 时 exit 1，否则 exit 0（WARN 不影响退出码）。
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v node >/dev/null 2>&1; then
  exec node "$DIR/../engine/plan.mjs" doctor "$@"
fi
echo "[FAIL] node 运行时: 未找到 node（引擎与所有 hooks 不可用，请安装 Node.js >= 18）"
echo "-----"
echo "合计 1 项：PASS 0，WARN 0，FAIL 1"
exit 1
