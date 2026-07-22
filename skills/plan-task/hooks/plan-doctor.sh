#!/bin/sh
# plan-doctor：plan-skills 安装自检工具，逐项输出 [PASS]/[WARN]/[FAIL] 单行结果，定位"静默无 hook"问题。
# 用法：sh plan-doctor.sh [--global]（--global 只查全局安装，默认查当前目录项目级 + 全局）
# 本脚本为诊断工具，由用户显式运行，不受 PLANNING_HOOKS_DISABLED 影响；只读不修改任何文件。
# 有 FAIL 时 exit 1，否则 exit 0（WARN 不影响退出码）。

PASS=0
WARN=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "[PASS] $1"; }
warn() { WARN=$((WARN + 1)); echo "[WARN] $1"; }
fail() { FAIL=$((FAIL + 1)); echo "[FAIL] $1"; }

GLOBAL_ONLY=0
[ "$1" = "--global" ] && GLOBAL_ONLY=1

SCRIPTS="session-start user-prompt-submit pre-tool-use post-tool-use pre-compact stop-gate permission-request"
CC_EVENTS="SessionStart UserPromptSubmit PreToolUse PostToolUse PreCompact Stop"

# ── 1. 技能安装 ────────────────────────────────────────────────
candidates=""
[ $GLOBAL_ONLY -eq 0 ] && candidates="./.agents/skills/plan-task ./.claude/skills/plan-task"
candidates="$candidates $HOME/.claude/skills/plan-task $HOME/.codex/skills/plan-task $HOME/.config/opencode/skills/plan-task"

found=""
for d in $candidates; do
  [ -f "$d/SKILL.md" ] && found="$found $d"
done

if [ -n "$found" ]; then
  pass "技能安装: 发现 plan-task 于:$found"
else
  fail "技能安装: 未发现 plan-task（运行 npx skills add JAYY513/plan-skills --skill plan-task）"
fi

# ── 2. hook 脚本齐全 ───────────────────────────────────────────
for d in $found; do
  [ -d "$d" ] || continue
  missing=""
  for s in $SCRIPTS; do
    [ -f "$d/hooks/$s.sh" ] || missing="$missing $s.sh"
    [ -f "$d/hooks/$s.ps1" ] || missing="$missing $s.ps1"
  done
  if [ -z "$missing" ]; then
    pass "hook 脚本齐全: $d（7 对 sh/ps1）"
  else
    fail "hook 脚本齐全: $d 缺失:$missing（运行 npx skills update 更新技能）"
  fi
done

# ── 3. Claude Code hooks 注册（frontmatter）────────────────────
for d in $found; do
  case "$d" in
    */.claude/*) ;;
    *) continue ;;
  esac
  fm=$(sed -n '1,/^---$/p' "$d/SKILL.md" | head -100)
  if ! echo "$fm" | grep -q '^hooks:'; then
    fail "Claude Code hooks 注册: $d 的 SKILL.md frontmatter 缺少 hooks: 键（旧版本？运行 npx skills update）"
    continue
  fi
  missing_ev=""
  for ev in $CC_EVENTS; do
    echo "$fm" | grep -q "^  $ev:" || missing_ev="$missing_ev $ev"
  done
  if [ -z "$missing_ev" ]; then
    pass "Claude Code hooks 注册: $d frontmatter 6 个事件齐全"
  else
    fail "Claude Code hooks 注册: $d 缺少事件:$missing_ev"
  fi
done

# ── 4. Codex hooks 注册 ────────────────────────────────────────
hj_candidates=""
[ $GLOBAL_ONLY -eq 0 ] && hj_candidates="./.codex/hooks.json"
hj_candidates="$hj_candidates $HOME/.codex/hooks.json"

hj_found=""
for f in $hj_candidates; do
  [ -f "$f" ] && hj_found="$hj_found $f"
done

if [ -n "$hj_found" ]; then
  # 项目级与全局同时存在 → 重复触发警告
  n_hj=$(echo $hj_found | wc -w)
  [ "$n_hj" -ge 2 ] && \
    warn "Codex hooks 注册: 项目级与全局 hooks.json 同时存在，hook 会重复触发，请只保留一处"
  for f in $hj_found; do
    [ -f "$f" ] || continue
    if ! grep -q 'plan-task' "$f"; then
      fail "Codex hooks 注册: $f 不含 plan-task 路径"
      continue
    fi
    PY=""
    command -v python3 >/dev/null 2>&1 && PY=python3
    [ -z "$PY" ] && command -v python >/dev/null 2>&1 && PY=python
    if [ -n "$PY" ]; then
      if "$PY" -c "import json,sys; json.load(open(sys.argv[1], encoding='utf-8'))" "$f" >/dev/null 2>&1; then
        pass "Codex hooks 注册: $f 存在、含 plan-task、JSON 合法"
      else
        fail "Codex hooks 注册: $f 不是合法 JSON"
      fi
    else
      warn "Codex hooks 注册: $f 存在且含 plan-task（无 python，跳过 JSON 合法性校验）"
    fi
  done
  # hooks 特性开关
  cfg="$HOME/.codex/config.toml"
  if [ -f "$cfg" ] && grep -q 'hooks *= *true' "$cfg"; then
    pass "Codex hooks 特性: $cfg 含 hooks = true"
  else
    warn "Codex hooks 特性: 未在 $cfg 找到 hooks = true（请在 [features] 节配置，或用 codex features list 验证）"
  fi
else
  warn "Codex hooks 注册: 未发现 hooks.json（使用 Codex 时参考 hooks/codex/README.md 安装；不用 Codex 可忽略）"
fi

# ── 5. sh 可用性 / Windows powershell ──────────────────────────
if command -v sh >/dev/null 2>&1; then
  pass "sh 可用: $(command -v sh)"
else
  fail "sh 可用: 未找到 sh（hooks 的 sh 入口全部无法运行）"
fi

is_windows=0
[ "$OS" = "Windows_NT" ] && is_windows=1
uname 2>/dev/null | grep -qiE 'cygwin|mingw|msys' && is_windows=1
if [ $is_windows -eq 1 ]; then
  if command -v pwsh >/dev/null 2>&1; then
    pass "powershell 可用: pwsh $(pwsh -NoProfile -Command '$PSVersionTable.PSVersion.Major' 2>/dev/null)"
  elif command -v powershell >/dev/null 2>&1; then
    pass "powershell 可用: $(command -v powershell)"
  elif [ -x /c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]; then
    pass "powershell 可用: Windows PowerShell 5.x（不在 PATH，但系统路径存在）"
  else
    warn "powershell 可用: 未找到 powershell（Windows 下 ps1 hook 不可用，sh 入口仍可用时可忽略）"
  fi
fi

# ── 6. 状态文件（当前目录是否已 plan-init）─────────────────────
if [ $GLOBAL_ONLY -eq 0 ]; then
  missing_sf=""
  for sf in SPEC.md ROADMAP.md TASKS.md INBOX.md FINDINGS.md; do
    [ -f "$sf" ] || missing_sf="$missing_sf $sf"
  done
  if [ -z "$missing_sf" ]; then
    pass "状态文件: 当前目录已初始化计划体系（5 文件齐全）"
  else
    warn "状态文件: 当前目录缺少:$missing_sf（尚未运行 plan-init；hooks 会静默跳过，属预期）"
  fi
fi

# ── 汇总 ───────────────────────────────────────────────────────
echo "-----"
echo "合计 $((PASS + WARN + FAIL)) 项：PASS $PASS，WARN $WARN，FAIL $FAIL"
[ $FAIL -eq 0 ] || exit 1
exit 0
