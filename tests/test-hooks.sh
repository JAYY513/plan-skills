#!/bin/sh
# tests/test-hooks.sh：hooks 冒烟测试（脚本单一来源在 skills/plan-task/hooks/，测一处即可）。
# 用 mktemp 临时目录构造场景，断言各 hook 的输出文本与 exit code；每用例一行 PASS/FAIL，结尾汇总，有 FAIL 则 exit 1。
# 运行方式：在仓库根执行 sh tests/test-hooks.sh

HOOKS_DIR="$(cd "$(dirname "$0")/../skills/plan-task/hooks" && pwd)"

PASS=0
FAIL=0
TMPDIRS=""

cleanup() {
  for d in $TMPDIRS; do rm -rf "$d"; done
}
trap cleanup EXIT

mk() {
  d=$(mktemp -d)
  TMPDIRS="$TMPDIRS $d"
  echo "$d"
}

# report <用例名> <0=通过 1=失败>
report() {
  if [ "$2" -eq 0 ]; then
    PASS=$((PASS + 1)); echo "PASS: $1"
  else
    FAIL=$((FAIL + 1)); echo "FAIL: $1"
  fi
}

# ── 用例 1：空目录 → 4 个脚本全部静默 exit 0 ──────────────────
dir=$(mk)
ok=0
for s in session-start pre-tool-use post-tool-use stop-gate; do
  out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/$s.sh")
  rc=$?
  if [ $rc -ne 0 ] || [ -n "$out" ]; then
    ok=1
    echo "  ↳ $s：rc=$rc，输出=${out:-<空>}"
  fi
done
report "空目录：4 个脚本静默 exit 0" $ok

# ── 用例 2：ROADMAP 含头部注释引用块的 ▶ 与真实 `## ▶ M1` 标题 ──
# session-start 必须输出 M1 行，且不能误抓注释行
dir=$(mk)
cat > "$dir/ROADMAP.md" <<'EOF'
# ROADMAP — 里程碑（路标）

> ▶ 标记当前里程碑，同时只许有一个。

## ▶ M1：测试里程碑
EOF
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/session-start.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '当前里程碑：▶ M1：测试里程碑' || ok=1
echo "$out" | grep -q '标记当前里程碑，同时只许有一个' && ok=1
report "ROADMAP：输出 M1 行且不含注释行" $ok

# ── 用例 3：进行中任务 + INBOX 待裁决 → 提示行数字正确 ─────────
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲
### 任务乙

## 已拆好（待做）

### 任务丙
EOF
cat > "$dir/INBOX.md" <<'EOF'
# INBOX

## 待裁决

- [ ] 想法一
- [ ] 想法二
- [ ] 想法三

## 已裁决（存档）

- [x] 旧想法
EOF
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/session-start.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '提示：进行中任务 2 个，INBOX 待裁决 3 条' || ok=1
report "进行中任务 + INBOX 待裁决：提示行数字正确" $ok

# ── 用例 4：活跃工作区无 postmortem → stop-gate 阻止且 exit 2；补齐后 exit 0 ──
dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 2 ] || ok=1
echo "$out" | grep -q '阻止收尾' || ok=1
echo "$out" | grep -q '2026-07-18-demo-task' || ok=1
report "活跃工作区无 postmortem：stop-gate 阻止文本且 exit 2" $ok

cat > "$dir/.planning/2026-07-18-demo-task/progress.md" <<'EOF'
# postmortem

- 结论 → FINDINGS F1
- 一句话坑总结：无
- 本文档为过程记录，结论以 FINDINGS 为准
EOF
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
report "补齐 postmortem 后：stop-gate exit 0" $ok

# ── 用例 5：PLANNING_HOOKS_DISABLED=1 → warn 场景下也静默 exit 0 ──
dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "PLANNING_HOOKS_DISABLED=1：stop-gate 静默 exit 0" $ok

# ── 用例 6：pre-compact ────────────────────────────────────────
dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/pre-compact.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '上下文即将压缩' || ok=1
echo "$out" | grep -q '2026-07-18-demo-task' || ok=1
report "pre-compact：活跃工作区输出提醒含工作区名" $ok

dir=$(mk)
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/pre-compact.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "pre-compact：无工作区静默 exit 0" $ok

# ── 用例 7：user-prompt-submit ─────────────────────────────────
# 空目录静默 exit 0
dir=$(mk)
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "user-prompt-submit：空目录静默 exit 0" $ok

# 有状态：输出里程碑 + 任务列表 + 工作区一行，且不含 INBOX 计数提示行
dir=$(mk)
cat > "$dir/ROADMAP.md" <<'EOF'
# ROADMAP

## ▶ M1：测试里程碑
EOF
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲
EOF
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '当前里程碑：▶ M1：测试里程碑' || ok=1
echo "$out" | grep -q '进行中任务：' || ok=1
echo "$out" | grep -q '任务甲' || ok=1
echo "$out" | grep -q '活跃工作区： 2026-07-18-demo-task' || ok=1
echo "$out" | grep -q 'INBOX' && ok=1
report "user-prompt-submit：精简输出正确且不含 INBOX 计数" $ok

# 禁用变量 → 静默 exit 0
out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "user-prompt-submit：PLANNING_HOOKS_DISABLED=1 静默 exit 0" $ok

# ── 用例 8：permission-request ─────────────────────────────────
# 空目录静默 exit 0
dir=$(mk)
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/permission-request.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "permission-request：空目录静默 exit 0" $ok

# 有进行中任务 → 输出一行任务提示；无进行中任务 → 静默
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

## 已拆好（待做）

### 任务乙
EOF
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/permission-request.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '当前进行中任务：任务甲' || ok=1
echo "$out" | grep -q '任务乙' && ok=1
report "permission-request：输出首个进行中任务一行提示" $ok

dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 已拆好（待做）

### 任务乙
EOF
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/permission-request.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "permission-request：无进行中任务静默 exit 0" $ok

out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$dir" sh "$HOOKS_DIR/permission-request.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "permission-request：PLANNING_HOOKS_DISABLED=1 静默 exit 0" $ok

# ── 用例 9：plan-doctor：空目录可运行、输出汇总行、exit 1 ──────
dir=$(mk)
fakehome=$(mk)
out=$(cd "$dir" && HOME="$fakehome" sh "$HOOKS_DIR/plan-doctor.sh")
rc=$?
ok=0
[ $rc -eq 1 ] || ok=1
echo "$out" | grep -q '合计 .* 项：PASS .*，WARN .*，FAIL ' || ok=1
echo "$out" | grep -q '\[FAIL\] 技能安装' || ok=1
report "plan-doctor：空目录输出汇总行且 exit 1" $ok

# ── 用例 10：plan-doctor：完整假安装全 PASS、exit 0 ────────────
dir=$(mk)
fakehome=$(mk)
mkdir -p "$dir/.agents/skills/plan-task/hooks" "$dir/.claude/skills/plan-task/hooks" "$dir/.codex" "$fakehome/.codex"
cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.ps1 "$dir/.agents/skills/plan-task/hooks/"
cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.ps1 "$dir/.claude/skills/plan-task/hooks/"
cp "$(cd "$(dirname "$0")/../skills/plan-task" && pwd)/SKILL.md" "$dir/.agents/skills/plan-task/SKILL.md"
cp "$(cd "$(dirname "$0")/../skills/plan-task" && pwd)/SKILL.md" "$dir/.claude/skills/plan-task/SKILL.md"
cat > "$dir/.codex/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "sh .agents/skills/plan-task/hooks/session-start.sh" } ] } ] } }
EOF
printf '[features]\nhooks = true\n' > "$fakehome/.codex/config.toml"
for f in SPEC ROADMAP TASKS INBOX FINDINGS; do touch "$dir/$f.md"; done
out=$(cd "$dir" && HOME="$fakehome" sh "$HOOKS_DIR/plan-doctor.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || { ok=1; echo "$out"; }
echo "$out" | grep -q 'FAIL 0' || ok=1
echo "$out" | grep -q '\[PASS\] Claude Code hooks 注册' || ok=1
echo "$out" | grep -q '\[PASS\] Codex hooks 注册' || ok=1
report "plan-doctor：完整假安装全 PASS 且 exit 0" $ok

# ── 汇总 ───────────────────────────────────────────────────────
echo "-----"
echo "合计 $((PASS + FAIL)) 个用例：PASS $PASS，FAIL $FAIL"
[ $FAIL -eq 0 ] || exit 1
exit 0
