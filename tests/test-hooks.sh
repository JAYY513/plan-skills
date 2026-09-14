#!/bin/sh
# tests/test-hooks.sh：hooks + 引擎冒烟测试（逻辑单一实现在 skills/plan-task/engine/plan.mjs，hooks/ 下为薄壳）。
# 用 mktemp 临时目录构造场景，断言各 hook / 引擎命令的输出文本与 exit code；每用例一行 PASS/FAIL，结尾汇总，有 FAIL 则 exit 1。
# 运行方式：在仓库根执行 sh tests/test-hooks.sh（需要 node >= 18；有 pwsh 时额外跑 ps1 薄壳冒烟）

HOOKS_DIR="$(cd "$(dirname "$0")/../skills/plan-task/hooks" && pwd)"
ENGINE="$HOOKS_DIR/../engine/plan.mjs"
# 有 cygpath 时（Git Bash / MSYS）转成原生路径，否则 node 找不到模块
if command -v cygpath >/dev/null 2>&1; then ENGINE=$(cygpath -w "$ENGINE"); fi

command -v node >/dev/null 2>&1 || {
  echo "FAIL: 未找到 node，引擎与测试需要 Node.js >= 18"
  exit 1
}

TODAY=$(node -e 'const d=new Date();const p=n=>String(n).padStart(2,"0");console.log(d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate()))')
YESTERDAY=$(node -e 'const d=new Date(Date.now()-86400000);const p=n=>String(n).padStart(2,"0");console.log(d.getFullYear()+"-"+p(d.getMonth()+1)+"-"+p(d.getDate()))')

PASS=0
FAIL=0
TMPDIRS=""

cleanup() {
  for d in $TMPDIRS; do rm -rf "$d"; done
}
trap cleanup EXIT

# Windows 的 Git Bash / MSYS：node 是原生程序，不认 /c/... 这类 POSIX 路径
# （会把 /c/x 解析成 C:////c////x）。给 node 的参数一律先转原生路径。
winpath() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi
}

# mk：回显 POSIX 路径（供 cat / mkdir / rm 使用），同时把原生路径放进 $ROOT（供 PLANNING_ROOT 使用）
mk() {
  d=$(mktemp -d)
  TMPDIRS="$TMPDIRS $d"
  ROOT=$(winpath "$d")
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
  out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/$s.sh")
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
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/session-start.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '当前里程碑：▶ M1：测试里程碑' || ok=1
echo "$out" | grep -q '标记当前里程碑，同时只许有一个' && ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -le 8 ] || { ok=1; echo "  ↳ session-start 行数 $n > 8"; }

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
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/session-start.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '提示：进行中 2 个，INBOX 待裁决 3 条' || ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -le 8 ] || { ok=1; echo "  ↳ session-start 行数 $n > 8"; }
echo "$out" | grep -q '进行中：任务甲、任务乙 ｜ 下一张：任务丙' || ok=1

report "进行中任务 + INBOX 待裁决：提示行数字正确" $ok

# ── 用例 4：活跃工作区无 postmortem → stop-gate 阻止且 exit 2；补齐后 exit 0 ──
dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
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
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
report "补齐 postmortem 后：stop-gate exit 0" $ok

# ── 用例 5：PLANNING_HOOKS_DISABLED=1 → warn 场景下也静默 exit 0 ──
dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "PLANNING_HOOKS_DISABLED=1：stop-gate 静默 exit 0" $ok

# ── 用例 6：pre-compact ────────────────────────────────────────
dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/pre-compact.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '上下文即将压缩' || ok=1
echo "$out" | grep -q '2026-07-18-demo-task' || ok=1
echo "$out" | grep -q 'notes/' && ok=1
report "pre-compact：活跃工作区输出提醒含工作区名" $ok

dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task/notes"
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/pre-compact.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '上下文即将压缩' || ok=1
echo "$out" | grep -q 'notes/' || ok=1
report "pre-compact：已有 notes/ 时催材料落盘" $ok

dir=$(mk)
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/pre-compact.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "pre-compact：无工作区静默 exit 0" $ok

# ── 用例 7：user-prompt-submit ─────────────────────────────────
# 空目录静默 exit 0
dir=$(mk)
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "user-prompt-submit：空目录静默 exit 0" $ok

# 有状态：冷启动心跳恰好 1 行，含指针，不含原文 / DoD / 工作区
dir=$(mk)
cat > "$dir/ROADMAP.md" <<'EOF'
# ROADMAP

## ▶ M1：测试里程碑
EOF
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

- DoD：点击中断后输出立刻停止，手动验证通过
- 备注：这是一条完整备注

## 已拆好（待做）

### 任务乙

- DoD：不应出现的待办 DoD
EOF
mkdir -p "$dir/.planning/2026-07-18-demo-task"
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '进行中：任务甲（1）' || ok=1
echo "$out" | grep -q 'plan.mjs task "任务甲"' || ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ 心跳行数 $n != 1"; }
echo "$out" | grep -q '当前里程碑' && ok=1
echo "$out" | grep -q 'TASKS.md 原文' && ok=1
echo "$out" | grep -q 'DoD：点击中断后输出立刻停止，手动验证通过' && ok=1
echo "$out" | grep -q '活跃工作区' && ok=1
echo "$out" | grep -q '任务乙' && ok=1
report "user-prompt-submit：心跳一行且不注入原文" $ok

# 无进行中 → 指向 next 的 1 行心跳
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS
## 进行中
## 已拆好（待做）
### 不应出现
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q 'plan.mjs next' || ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ 无进行中心跳行数 $n != 1"; }
report "user-prompt-submit：无进行中指向 next" $ok



# 禁用变量 → 静默 exit 0
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲
EOF
out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "user-prompt-submit：PLANNING_HOOKS_DISABLED=1 静默 exit 0" $ok

# ── 用例 8：permission-request ─────────────────────────────────
# 空目录静默 exit 0
dir=$(mk)
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/permission-request.sh")
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
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/permission-request.sh")
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
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/permission-request.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "permission-request：无进行中任务静默 exit 0" $ok

out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/permission-request.sh")
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
echo "$out" | grep -q '\[WARN\] FINDINGS 索引: 缺 plan-index' || ok=1
echo "$out" | grep -q '\[FAIL\] FINDINGS 索引' && ok=1

report "plan-doctor：完整假安装全 PASS 且 exit 0" $ok

# ── 用例 11：stop-gate 门二（未完成阻止）───────────────────────
# 有进行中任务且无活跃工作区 → 阻止 exit 2
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

## 已拆好（待做）

### 任务乙
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 2 ] || ok=1
echo "$out" | grep -q '阻止收尾：TASKS.md「进行中」仍有 1 个未完成任务' || ok=1
echo "$out" | grep -q '任务甲' || ok=1
echo "$out" | grep -q '任务乙' && ok=1
echo "$out" | grep -q '下一步' || ok=1
report "stop-gate 门二：进行中任务无工作区 → 阻止 exit 2" $ok

# 干净会话：进行中为空（任务在待办区）→ 静默 exit 0
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 已拆好（待做）

### 任务乙
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "stop-gate 门二：干净会话静默 exit 0" $ok

# 门二禁用变量 → 静默 exit 0
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲
EOF
out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "stop-gate 门二：PLANNING_HOOKS_DISABLED=1 静默 exit 0" $ok

# ── 用例 12：plan-doctor：全局 hooks.json 属于其他工具 → 不 FAIL 不 WARN ──
dir=$(mk)
fakehome=$(mk)
mkdir -p "$dir/.agents/skills/plan-task/hooks" "$dir/.codex" "$fakehome/.codex"
cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.ps1 "$dir/.agents/skills/plan-task/hooks/"
cp "$(cd "$(dirname "$0")/../skills/plan-task" && pwd)/SKILL.md" "$dir/.agents/skills/plan-task/SKILL.md"
cat > "$dir/.codex/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "sh .agents/skills/plan-task/hooks/session-start.sh" } ] } ] } }
EOF
cat > "$fakehome/.codex/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "headroom wrap" } ] } ] } }
EOF
printf '[features]\nhooks = true\n' > "$fakehome/.codex/config.toml"
out=$(cd "$dir" && HOME="$fakehome" sh "$HOOKS_DIR/plan-doctor.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || { ok=1; echo "$out"; }
echo "$out" | grep -q '全局未安装 Codex hooks' || ok=1
echo "$out" | grep -q '重复触发' && ok=1
echo "$out" | grep -q '\[FAIL\] Codex' && ok=1
report "plan-doctor：全局 hooks.json 属其他工具 → 信息行且无重复警告" $ok

# ── 用例 13：plan-doctor：两处都注册 plan-task → WARN 重复触发 ──
dir=$(mk)
fakehome=$(mk)
mkdir -p "$dir/.agents/skills/plan-task/hooks" "$dir/.codex" "$fakehome/.codex"
cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/*.ps1 "$dir/.agents/skills/plan-task/hooks/"
cp "$(cd "$(dirname "$0")/../skills/plan-task" && pwd)/SKILL.md" "$dir/.agents/skills/plan-task/SKILL.md"
cat > "$dir/.codex/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "sh .agents/skills/plan-task/hooks/session-start.sh" } ] } ] } }
EOF
cat > "$fakehome/.codex/hooks.json" <<'EOF'
{ "hooks": { "SessionStart": [ { "hooks": [ { "type": "command", "command": "sh ~/.codex/skills/plan-task/hooks/session-start.sh" } ] } ] } }
EOF
printf '[features]\nhooks = true\n' > "$fakehome/.codex/config.toml"
out=$(cd "$dir" && HOME="$fakehome" sh "$HOOKS_DIR/plan-doctor.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || { ok=1; echo "$out"; }
echo "$out" | grep -q '都注册了 plan-task，hook 会重复触发' || ok=1
report "plan-doctor：两处都注册 plan-task → WARN 重复触发" $ok

# ── 用例 14：比较集不变心跳 1 行，变了卡片 ≤15 行 ──
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

- DoD：验证点

## 已拆好（待做）

### 任务乙

- DoD：乙的完成标准
EOF
out1=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
out2=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
ok=0
echo "$out1" | grep -q '进行中：任务甲（1）' || ok=1
echo "$out1" | grep -q 'plan.mjs task "任务甲"' || ok=1
n=$(printf '%s\n' "$out1" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ 冷启动心跳 $n != 1"; }
echo "$out2" | grep -q 'plan.mjs task "任务甲"' || ok=1
n=$(printf '%s\n' "$out2" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ 不变心跳 $n != 1"; }
echo "$out2" | grep -q '提示：' && ok=1
[ -f "$dir/.planning/.hook-cache.json" ] || ok=1
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

- DoD：改了也不该出卡片

## 已拆好（待做）

### 任务乙

- DoD：乙的完成标准
EOF
out_dod=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
n=$(printf '%s\n' "$out_dod" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ DoD 不进比较集却出了 $n 行"; }
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务丙

## 已拆好（待做）

### 任务乙

- DoD：乙的完成标准
EOF
out3=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
echo "$out3" | grep -q '进行中：任务丙' || ok=1
echo "$out3" | grep -q 'DoD：乙的完成标准' || ok=1
echo "$out3" | grep -q 'plan.mjs task "任务丙"' || ok=1
n=$(printf '%s\n' "$out3" | wc -l)
[ "$n" -le 15 ] || { ok=1; echo "  ↳ 卡片行数 $n > 15"; }
[ "$n" -gt 1 ] || { ok=1; echo "  ↳ 变化应出卡片，实际 $n 行"; }
out4=$(PLANNING_HOOKS_NO_THROTTLE=1 PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
out5=$(PLANNING_HOOKS_NO_THROTTLE=1 PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/user-prompt-submit.sh")
echo "$out4" | grep -q 'plan.mjs task "任务丙"' || ok=1
n=$(printf '%s\n' "$out4" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ NO_THROTTLE 应心跳 $n"; }
echo "$out5" | grep -q 'plan.mjs task "任务丙"' || ok=1
echo "$out5" | grep -q '提示：' && ok=1
report "user-prompt-submit 比较集：不变心跳、变了卡片、NO_THROTTLE 始终心跳" $ok



# ── 用例 15：stop-gate 门二日期规则（当天开工豁免，隔天阻止）──
dir=$(mk)
cat > "$dir/TASKS.md" <<EOF
# TASKS

## 进行中

### 任务甲
- 开始：$TODAY

## 已拆好（待做）
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "stop-gate 门二：当天开工任务无工作区 → 放行 exit 0" $ok

dir=$(mk)
cat > "$dir/TASKS.md" <<EOF
# TASKS

## 进行中

### 任务甲
- 开始：$YESTERDAY

## 已拆好（待做）
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 2 ] || ok=1
echo "$out" | grep -q '阻止收尾：TASKS.md「进行中」仍有 1 个未完成任务' || ok=1
echo "$out" | grep -q '当天开工' || ok=1
report "stop-gate 门二：隔天任务无工作区 → 阻止 exit 2 且含豁免说明" $ok

# ── 用例 16：stop-gate 门一精确匹配（plan.md 关联条目 → 已完成段 ✅）──
dir=$(mk)
mkdir -p "$dir/.planning/2026-08-01-demo-ws"
cat > "$dir/.planning/2026-08-01-demo-ws/plan.md" <<'EOF'
# 任务工作区：中文任务名

- **关联 TASKS 条目**：中文任务名
EOF
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

## 已拆好（待做）

## 已完成（待归档）

### 中文任务名 ✅
- 完成：2026-08-01
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
[ -z "$out" ] || ok=1
report "stop-gate 门一：plan.md 关联条目精确匹配已完成任务 → exit 0" $ok

# ── 用例 17：引擎 start（认领 + 幂等 + 工作区 + 未知任务）──
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

## 已拆好（待做）

### store.js 扩展 tag 字段
- DoD：过滤查询可用

## 调研（限时探针）

## 已完成（待归档）
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" start "store.js 扩展 tag 字段" --date "$TODAY")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '已认领' || ok=1
sed -n '/^## 进行中/,/^## 已拆好/p' "$dir/TASKS.md" | grep -q '### store.js 扩展 tag 字段' || ok=1
sed -n '/^## 进行中/,/^## 已拆好/p' "$dir/TASKS.md" | grep -q "开始：$TODAY" || ok=1
sed -n '/^## 已拆好/,/^## 调研/p' "$dir/TASKS.md" | grep -q '### store.js' && ok=1
# 重复 start → 幂等 + 建工作区 + 补关联行
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" start "store.js 扩展 tag 字段" --workspace --date "$TODAY")
rc=$?
slug="$TODAY-store-js-扩展-tag-字段"
echo "$out" | grep -q '无需重复认领' || ok=1
[ $rc -eq 0 ] || ok=1
[ -f "$dir/.planning/$slug/plan.md" ] || ok=1
[ -f "$dir/.planning/$slug/progress.md" ] || ok=1
[ -d "$dir/.planning/$slug/notes" ] && ok=1
grep -q "关联 TASKS 条目：store.js 扩展 tag 字段" "$dir/.planning/$slug/plan.md" 2>/dev/null || grep -q "关联 TASKS 条目\*\*：store.js 扩展 tag 字段" "$dir/.planning/$slug/plan.md" || ok=1
grep -q "工作区：.planning/$slug/" "$dir/TASKS.md" || ok=1
# 未知任务 → exit 1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" start "不存在的任务")
rc=$?
[ $rc -eq 1 ] || ok=1
echo "$out" | grep -q '未找到任务' || ok=1
report "引擎 start：认领补日期、幂等、--workspace 建目录补关联行、未知任务 exit 1" $ok

# ── 用例 18：引擎 finish（缺证据 exit 1 → 补齐后 ✅ + 归档）──
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finish "store.js 扩展 tag 字段")
rc=$?
ok=0
[ $rc -eq 1 ] || ok=1
echo "$out" | grep -q '三合一动作缺失' || ok=1
echo "$out" | grep -q '过程追溯' || ok=1
echo "$out" | grep -q 'postmortem' || ok=1
# 补齐三合一证据（结论回填 + postmortem 固化）
cat > "$dir/FINDINGS.md" <<EOF
# FINDINGS

## 索引

- F1：测试结论

## 热区

### F1：测试结论
- 来源：测试
- 结论：过滤查询可用
- 过程追溯：.planning/done/$slug/progress.md
EOF
cat > "$dir/.planning/$slug/progress.md" <<'EOF'
# progress：store.js 扩展 tag 字段

## Postmortem

- **结论**：→ FINDINGS.md F1
- **踩过的坑**：无
- **声明**：本文档为过程记录，结论以 FINDINGS.md 为准。
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finish "store.js 扩展 tag 字段" --date "$TODAY")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "$out"; }
echo "$out" | grep -q '已完成：✅' || ok=1
sed -n '/^## 已完成/,$p' "$dir/TASKS.md" | grep -q '### store.js 扩展 tag 字段 ✅' || ok=1
sed -n '/^## 已完成/,$p' "$dir/TASKS.md" | grep -q "完成：$TODAY" || ok=1
[ -d "$dir/.planning/done/$slug" ] || ok=1
[ -d "$dir/.planning/$slug" ] && ok=1
# finish 后 stop-gate 放行
PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/stop-gate.sh" >/dev/null
[ $? -eq 0 ] || ok=1
report "引擎 finish：缺证据 exit 1 列缺失，补齐后 ✅ + 完成日期 + 工作区移入 done/" $ok

# ── 用例 19：ps1 薄壳冒烟（有 pwsh 且真能跑才跑，否则 SKIP 不计失败）──
# pwsh「存在」≠「能跑」：某些沙箱/安全策略下 pwsh 会被挂住不返回。
# Git Bash / MSYS：GNU timeout 杀不掉原生 Win32 pwsh，预检会空等还可能留僵尸 → 直接 SKIP。
# POSIX：只给空命令预检套 timeout 3（成功路径几乎 0 额外耗时；卡死最多 3s 后 SKIP）。
# 预检通过后的真实用例不再套 timeout，避免第一次 JIT 启动被误杀。
PW=""
if [ -z "${MSYSTEM-}" ] && [ -z "${MINGW_PREFIX-}" ] && command -v pwsh >/dev/null 2>&1; then
  if command -v timeout >/dev/null 2>&1; then
    timeout 3 pwsh -NoProfile -Command "exit 0" >/dev/null 2>&1 && PW=pwsh
  else
    pwsh -NoProfile -Command "exit 0" >/dev/null 2>&1 && PW=pwsh
  fi
fi
if [ -n "$PW" ]; then
  dir=$(mk)
  ok=0
  for s in session-start pre-tool-use post-tool-use stop-gate user-prompt-submit pre-compact permission-request; do
    PLANNING_ROOT="$(winpath "$dir")" "$PW" -NoProfile -ExecutionPolicy Bypass -File "$HOOKS_DIR/$s.ps1" >/dev/null 2>&1
    rc=$?
    [ $rc -eq 0 ] || { ok=1; echo "  ↳ $s.ps1 空目录应 exit 0（实得 $rc）"; }
  done
  dir=$(mk)
  mkdir -p "$dir/.planning/2026-08-01-demo-task"
  PLANNING_ROOT="$(winpath "$dir")" "$PW" -NoProfile -ExecutionPolicy Bypass -File "$HOOKS_DIR/stop-gate.ps1" >/dev/null 2>&1
  rc=$?
  [ $rc -eq 2 ] || { ok=1; echo "  ↳ stop-gate.ps1 阻断场景应 exit 2（实得 $rc）"; }
  report "ps1 薄壳冒烟：静默场景 exit 0、stop-gate 阻断透传 exit 2" $ok
else
  echo "SKIP: ps1 薄壳冒烟（无 pwsh，或 pwsh 存在但不可执行 / 被安全策略阻塞）"
fi

# ── 用例 20：session-start 注入 SPEC 红线（边界 + 选型），空模板无噪音，超长截断 ──
dir=$(mk)
cat > "$dir/SPEC.md" <<'EOF'
# SPEC — 项目规格（锚）

## 项目是什么

- 某工具

## 不做什么（边界）

- 不做 GUI 界面
- 不接第三方支付

## 技术选型与理由

| 决策 | 选择 | 理由 | 日期 |
|---|---|---|---|
| 运行时 | Node.js | 团队熟 | 2026-01-01 |
| 持久化 | JSON 文件 | 零依赖 | 2026-01-01 |

## 变更日志

| 日期 | 变更内容 | 原因 |
|---|---|---|
EOF
touch "$dir/TASKS.md"
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" hook session-start)
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q 'SPEC 红线' || ok=1
echo "$out" | grep -q '边界：不做 GUI 界面' || ok=1
echo "$out" | grep -q '边界：不接第三方支付' || ok=1
echo "$out" | grep -q '选型：运行时 = Node.js' || ok=1
echo "$out" | grep -q '其余红线见 SPEC.md' || ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -le 8 ] || { ok=1; echo "  ↳ session-start 行数 $n > 8"; }

# 未填充的空模板（含注释 + 示例行 + 占位符）不应产生红线噪音
dir2=$(mk)
cat > "$dir2/SPEC.md" <<'EOF'
# SPEC — 项目规格（锚）

## 不做什么（边界）

<!-- 明确排除的方向。例如：本期不做移动端 -->

## 技术选型与理由

| 决策 | 选择 | 理由 | 日期 |
|---|---|---|---|
| 示例：后端框架 | xxx | 一句话理由 | YYYY-MM-DD |
EOF
touch "$dir2/TASKS.md"
out2=$(PLANNING_ROOT="$(winpath "$dir2")" node "$ENGINE" hook session-start)
echo "$out2" | grep -q 'SPEC 红线' && ok=1
echo "$out2" | grep -q '示例：后端框架' && ok=1
# 超长 SPEC → 截断（与 status 同上限 3 条 + 提示）
dir3=$(mk)
{ echo '# SPEC'; echo; echo '## 不做什么（边界）'; echo; for i in $(seq 1 15); do echo "- 边界条目 $i"; done; } > "$dir3/SPEC.md"
touch "$dir3/TASKS.md"
out3=$(PLANNING_ROOT="$(winpath "$dir3")" node "$ENGINE" hook session-start)
n=$(echo "$out3" | grep -c '边界：边界条目')
[ "$n" -eq 3 ] || { ok=1; echo "  ↳ 截断应保留 3 条，实际 $n"; }
echo "$out3" | grep -q '其余红线见 SPEC.md' || ok=1
n=$(printf '%s\n' "$out3" | wc -l)
[ "$n" -le 8 ] || { ok=1; echo "  ↳ 超长红线 session-start 行数 $n > 8"; }
report "session-start 注入 SPEC 红线（边界+选型）、空模板无噪音、超长截断" $ok


# ── 用例 21：调研区 start --workspace 复制 notes/index.md ──
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

## 已拆好（待做）

## 调研（限时探针）

### product ia probe
- 时间盒：2 小时
- 产出：FINDINGS.md 一条结论
- DoD：结论落 FINDINGS

## 已完成（待归档）
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" start "product ia probe" --workspace --date "$TODAY")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
rslug="$TODAY-product-ia-probe"
echo "$out" | grep -q '已认领' || ok=1
echo "$out" | grep -q 'notes/' || ok=1
[ -f "$dir/.planning/$rslug/plan.md" ] || ok=1
[ -f "$dir/.planning/$rslug/progress.md" ] || ok=1
[ -f "$dir/.planning/$rslug/notes/index.md" ] || ok=1
grep -q "notes：product ia probe" "$dir/.planning/$rslug/notes/index.md" || ok=1
grep -q "工作区：.planning/$rslug/" "$dir/TASKS.md" || ok=1
# 进行中仍带时间盒时再 start --workspace 应复用、不丢 notes
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" start "product ia probe" --workspace --date "$TODAY")
echo "$out" | grep -q '工作区已存在' || ok=1
[ -f "$dir/.planning/$rslug/notes/index.md" ] || ok=1
report "引擎 start：调研区 --workspace 复制 notes/index.md，普通复用不覆盖" $ok

# ── 用例 22：status / next / findings / inbox（查询步 1）──
dir=$(mk)
cat > "$dir/ROADMAP.md" <<'EOF'
# ROADMAP
## ▶ M2 tag 过滤
EOF
cat > "$dir/SPEC.md" <<'EOF'
# SPEC
## 不做什么（边界）
- 不做云同步
## 技术选型与理由
| 决策 | 选择 | 理由 | 日期 |
|---|---|---|---|
| CLI 参数解析 | commander.js | 团队熟 | 2026-01-01 |
EOF
cat > "$dir/TASKS.md" <<'EOF'
# TASKS
## 进行中
### store.js 扩展 tag 字段
- DoD：tag 字段可读写
## 已拆好（待做）
### list 命令支持 --tag 过滤
- DoD：list --tag 过滤可用
## 已完成（待归档）
### list --tag 过滤
- DoD：done
EOF
cat > "$dir/FINDINGS.md" <<'EOF'
# FINDINGS
## 热条目
### F2：旧数据缺 tags 会崩
- 日期：2026-07-18
- 来源：开发中发现
- 标签：数据
- 影响：影响 M2
- 状态：有效
- 结论：缺字段要兼容
### F3：逗号拆 tag 失败
- 日期：2026-07-19
- 来源：失败尝试
- 标签：数据
- 状态：有效
### F1：CLI 框架选型——commander.js 满足需求
- 日期：2026-07-01
- 来源：调研探针
- 影响：影响 SPEC 技术选型：CLI
- 状态：有效
EOF
cat > "$dir/INBOX.md" <<'EOF'
# INBOX
## 待裁决
- [ ] 2026-07-20 ⚪ list --tag 过滤 — 灵感
- [ ] 2026-07-21 ⚪ 云同步支持 — 灵感
- 已解决：无关任务 ✅（2026-07-22）
## 已裁决（存档）
- 2026-07-01 旧想法 → 删除 — 不做
EOF

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" status)
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q 'SPEC 红线' || ok=1
echo "$out" | grep -q '边界：不做云同步' || ok=1
echo "$out" | grep -q '选型：CLI 参数解析 = commander.js' || ok=1
echo "$out" | grep -q '当前里程碑：▶ M2 tag 过滤' || ok=1
echo "$out" | grep -q '进行中：store.js 扩展 tag 字段 ｜ 下一张：list 命令支持 --tag 过滤' || ok=1
echo "$out" | grep -q '提示：进行中 1 个，INBOX 待裁决 1 条' || ok=1
echo "$out" | grep -q 'DoD：tag 字段可读写' && ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -le 8 ] || { ok=1; echo "  ↳ status 行数 $n > 8"; }
js=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" status --json)
echo "$js" | grep -q '"inProgress"' || ok=1
echo "$js" | grep -q 'store.js 扩展 tag 字段' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" next)
echo "$out" | grep -q '下一张：list 命令支持 --tag 过滤' || ok=1
echo "$out" | grep -q 'DoD：list --tag 过滤可用' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings)
echo "$out" | grep -q 'F2 | 2026-07-18 | 数据 | 有效 | 旧数据缺 tags 会崩' || ok=1
echo "$out" | grep -q 'F1 | 2026-07-01 | 未分类 | 有效 | CLI 框架选型' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --tag 数据)
echo "$out" | grep -q 'F2 |' || ok=1
echo "$out" | grep -q 'F3 |' || ok=1
echo "$out" | grep -q 'F1 |' && ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --impact spec)
echo "$out" | grep -q 'F1 |' || ok=1
echo "$out" | grep -q 'F2 |' && ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --full F2)
echo "$out" | grep -q '### F2：旧数据缺 tags 会崩' || ok=1
echo "$out" | grep -q '缺字段要兼容' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --full F99)
rc=$?
[ $rc -eq 2 ] || ok=1
echo "$out" | grep -q '未找到 F99' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --nope)
rc=$?
[ $rc -eq 3 ] || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" inbox)
echo "$out" | grep -q 'list --tag 过滤' || ok=1
echo "$out" | grep -q '云同步支持' && ok=1
echo "$out" | grep -q '疑似已实现' || ok=1
echo "$out" | grep -q 'list --tag 过滤' || ok=1
dir2=$(mk)
touch "$dir2/TASKS.md"
out=$(PLANNING_ROOT="$(winpath "$dir2")" node "$ENGINE" next)
rc=$?
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '（无匹配）' || ok=1

report "引擎查询：status/next/findings/inbox 契约与退出码" $ok



# ── 用例 23：task / ws / links + finish 回写（查询步 2）──
dir=$(mk)
mkdir -p "$dir/.planning/demo-ws/notes"
cat > "$dir/.planning/demo-ws/plan.md" <<'EOF'
# 任务工作区
## 当前位置
- 正在改 store.js
- 下一步写测试
- 未提交
EOF
echo 'progress body' > "$dir/.planning/demo-ws/progress.md"
cat > "$dir/TASKS.md" <<'EOF'
# TASKS
## 进行中
### store.js 扩展 tag 字段
- DoD：tag 可读写
- 工作区：.planning/demo-ws/
- 依据：F2
- 来自：INBOX 云同步支持
- 前置：list 命令支持 --tag 过滤
## 已拆好（待做）
### list 命令支持 --tag 过滤
- DoD：过滤可用
## 已完成（待归档）
EOF
cat > "$dir/FINDINGS.md" <<'EOF'
# FINDINGS
## 热条目
### F2：旧数据缺 tags
- 日期：2026-07-18
- 来源：外部输入
- 标签：数据
- 状态：有效
- 过程追溯：.planning/demo-ws/progress.md
EOF
cat > "$dir/INBOX.md" <<'EOF'
# INBOX
## 待裁决
- [ ] 2026-07-20 ⚪ 云同步支持 — 灵感
## 已裁决（存档）
EOF

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task "store.js 扩展 tag 字段")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '### store.js 扩展 tag 字段' || ok=1
echo "$out" | grep -q 'DoD：tag 可读写' || ok=1
echo "$out" | grep -q '依据：F2' || ok=1
echo "$out" | grep -q '来自：INBOX 云同步支持' || ok=1
echo "$out" | grep -q 'F2 | 2026-07-18 | 数据 | 有效 | 旧数据缺 tags' || ok=1
echo "$out" | grep -q 'INBOX 云同步支持' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" inbox)
echo "$out" | grep -q '认领中：store.js 扩展 tag 字段' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task "不存在")
rc=$?
[ $rc -eq 2 ] || ok=1
echo "$out" | grep -q '未找到任务：不存在' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" ws)
echo "$out" | grep -q '.planning/demo-ws' || ok=1
echo "$out" | grep -q '正在改 store.js' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" ws demo-ws)
echo "$out" | grep -q '正在改 store.js' || ok=1
echo "$out" | grep -q 'F2 |' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" ws demo-ws --full)
echo "$out" | grep -q 'progress body' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" ws nosuch)
rc=$?
[ $rc -eq 2 ] || ok=1
echo "$out" | grep -q '未找到工作区：nosuch' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" links --orphan)
echo "$out" | grep -q '（无匹配）' || { ok=1; echo "  ↳ orphan: $out"; }
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" links)
echo "$out" | grep -q 'INBOX 云同步支持 → 认领中 store.js 扩展 tag 字段' || ok=1
echo "$out" | grep -q 'F F2 → 催生任务 store.js 扩展 tag 字段' || ok=1
echo "$out" | grep -q 'T store.js 扩展 tag 字段 → 前置 list 命令支持 --tag 过滤' || ok=1

# finish：回写结论 + 来自翻牌；无索引再生
cat > "$dir/.planning/demo-ws/progress.md" <<'EOF'
# progress
## Postmortem
- **结论**：→ FINDINGS.md F2
- **踩过的坑**：无
- **声明**：本文档为过程记录，结论以 FINDINGS.md 为准。
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finish "store.js 扩展 tag 字段" --date 2026-09-14)
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "$out"; }
echo "$out" | grep -q '已回写结论：F2' || ok=1
echo "$out" | grep -q '已写 INBOX 已解决' || ok=1
grep -q '\- 结论：F2' "$dir/TASKS.md" || ok=1
grep -q '\- 已解决：store.js 扩展 tag 字段 ✅（2026-09-14）' "$dir/INBOX.md" || ok=1
grep -q 'plan-index' "$dir/FINDINGS.md" || ok=1

sed -n '/^## 待裁决/,/^## 已裁决/p' "$dir/INBOX.md" | grep -q '云同步支持' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" inbox --resolved)
echo "$out" | grep -q '云同步支持' || ok=1
echo "$out" | grep -q 'store.js 扩展 tag 字段' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" links)
echo "$out" | grep -q 'T store.js 扩展 tag 字段 → F2' || ok=1
echo "$out" | grep -q '解决 INBOX 云同步支持' || ok=1


# 软警告：无来自、标题相似
dirw=$(mk)
cat > "$dirw/TASKS.md" <<'EOF'
# TASKS
## 进行中
### list --tag 过滤
- DoD：x
## 已拆好（待做）
## 已完成（待归档）
EOF
cat > "$dirw/INBOX.md" <<'EOF'
# INBOX
## 待裁决
- [ ] 2026-07-20 ⚪ list 命令支持 --tag 过滤 — 灵感
## 已裁决（存档）
EOF
out=$(PLANNING_ROOT="$dirw" node "$ENGINE" finish "list --tag 过滤" --date 2026-09-14)
rc=$?
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '与本任务标题相似' || ok=1
grep -q '已解决' "$dirw/INBOX.md" && ok=1

report "引擎 task/ws/links 与 finish 回写索引" $ok



# ── 用例 24：reindex 写入 plan-index 受管区 ──
dir=$(mk)
ok=0
cat > "$dir/FINDINGS.md" <<'EOF'
# FINDINGS
## 索引
## 热条目
### F9：索引再生
- 日期：2026-09-14
- 来源：开发中发现
- 状态：有效
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" reindex)
rc=$?
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '已再生 FINDINGS 索引（1 条）' || ok=1

grep -q 'F9 | 2026-09-14 | 未分类 | 有效 | 索引再生' "$dir/FINDINGS.md" || ok=1

grep -q 'plan-index:begin' "$dir/FINDINGS.md" || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --tag 数据)
echo "$out" | grep -q '（无匹配）' || ok=1
for f in SPEC ROADMAP TASKS INBOX; do echo "# $f" > "$dir/$f.md"; done
dout=$(cd "$dir" && node "$ENGINE" doctor)
echo "$dout" | grep -q '\[PASS\] FINDINGS 索引: 受管标记存在' || ok=1
echo "$dout" | grep -q '\[FAIL\] FINDINGS 索引' && ok=1
report "引擎 reindex 写入 plan-index" $ok



# ══ 写入族（task-add / finding-add / inbox-add / progress-log）══
# 依据 docs/context-query-write-path.md §8：断言退出码 + stdout 行数/关键字 + 落盘内容，不靠目测。

# ── 用例 25：task-add 正常录入（stdout ≤5 行 + 落盘块） ──
dir=$(mk)
ok=0
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### store.js 扩展 tag 字段
- DoD：字段落库

## 已拆好（待做）

### 旧任务
- DoD：占位

## 已完成（待归档）
EOF
cat > "$dir/FINDINGS.md" <<'EOF'
# FINDINGS

## 索引

## 热条目

### F2：CLI 框架选型
- 日期：2026-07-18
- 来源：调研探针
- 标签：技术选型
- 结论：commander.js 满足需求
- 影响：无
- 状态：有效
EOF
cat > "$dir/INBOX.md" <<'EOF'
# INBOX

## 待裁决

- [ ] 2026-09-01 ⚪ 云同步支持
- 已解决：给同步加增量传输 ✅（2026-09-02）

## 已裁决（存档）

- 2026-09-03 旧想法 → 删除 — 不做
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "list 命令支持 --tag 过滤" --dod "list --tag 数据 只出带该 tag 的条目" --tag 数据 --basis F2 --from "INBOX 云同步支持")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -le 5 ] || { ok=1; echo "  ↳ stdout $n 行 > 5"; }
echo "$out" | grep -q '已录入「已拆好（待做）」队尾：list 命令支持 --tag 过滤' || ok=1
echo "$out" | grep -q -- '- DoD：list --tag 数据 只出带该 tag 的条目' || ok=1
echo "$out" | grep -q '关联：依据：F2 ｜ 来自：INBOX 云同步支持' || ok=1
grep -q '^### list 命令支持 --tag 过滤$' "$dir/TASKS.md" || ok=1
grep -q '^- 标签：数据$' "$dir/TASKS.md" || ok=1
grep -q '^- 依据：F2$' "$dir/TASKS.md" || ok=1
grep -q '^- 来自：INBOX 云同步支持$' "$dir/TASKS.md" || ok=1
# 队尾：应排在「旧任务」之后
tail -n 12 "$dir/TASKS.md" | grep -q '^### list 命令支持' || ok=1
report "task-add：正常录入且 stdout ≤5 行" $ok

# ── 用例 26：task-add 查重（重名退 2 / 已解决退 0 且不新建） ──
ok=0
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "list 命令支持 --tag 过滤" --dod "再来一次")
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ 重名 rc=$rc（期望 2）"; }
echo "$out" | grep -q '任务重名，未新建' || ok=1
echo "$out" | grep -q '已拆好 ｜ list 命令支持 --tag 过滤' || ok=1

before=$(grep -c '^### ' "$dir/TASKS.md")
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "给同步加增量传输" --dod "增量")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ 已解决 rc=$rc（期望 0）"; }
echo "$out" | grep -q '已由 给同步加增量传输 ✅ 实现' || ok=1
after=$(grep -c '^### ' "$dir/TASKS.md")
[ "$before" -eq "$after" ] || { ok=1; echo "  ↳ 已解决仍新建了任务（$before → $after）"; }
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "旧想法" --dod "x")
echo "$out" | grep -q '已裁决：旧想法' || ok=1
[ "$(grep -c '^### ' "$dir/TASKS.md")" -eq "$after" ] || ok=1
report "task-add：重名退 2；命中已解决退 0 且不新建" $ok

# ── 用例 27：task-add 参数闸门（缺/超长 --dod、调研区、未知 flag） ──
ok=0
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "没写 DoD 的任务")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 缺 dod rc=$rc（期望 3）"; }
echo "$out" | grep -q '缺少 --dod' || ok=1

long=$(node -e 'process.stdout.write("长".repeat(201))')
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "超长 DoD" --dod "$long")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 超长 dod rc=$rc（期望 3）"; }
echo "$out" | grep -q -- '--dod 超 200 字' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "探针" --dod "x" --section 调研)
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 调研区 rc=$rc（期望 3）"; }
echo "$out" | grep -q '本期不支持 --section 调研' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "瞎参数" --dod "x" --zzz)
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 未知 flag rc=$rc（期望 3）"; }
echo "$out" | grep -q '未知参数：--zzz' || ok=1

# 引用不存在 → 退 2 且不落盘
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "引用坏结论" --dod "x" --basis F99)
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ 坏依据 rc=$rc（期望 2）"; }
grep -q '^### 引用坏结论' "$dir/TASKS.md" && ok=1
report "task-add：参数闸门与引用校验" $ok

# ── 用例 28：task-add --head 插队首 ──
ok=0
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "紧急修线上 bug" --dod "复现脚本通过" --head)
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
echo "$out" | grep -q '队首' || ok=1
# 「已拆好」段内第一个任务块应是它
awk '/^## 已拆好/{f=1;next} /^## /{f=0} f && /^### /{print;exit}' "$dir/TASKS.md" | grep -q '紧急修线上 bug' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "配错 head" --dod "x" --head --section 进行中)
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ --head + 进行中 rc=$rc（期望 3）"; }
report "task-add：--head 插队首且只对已拆好有效" $ok

# ── 用例 29：finding-add 新开（编号 +1 / 立刻可查 / 字段齐全） ──
dir=$(mk)
ok=0
cat > "$dir/FINDINGS.md" <<'EOF'
# FINDINGS

## 索引

## 热条目

### F2：CLI 框架选型
- 日期：2026-07-18
- 来源：调研探针
- 标签：技术选型
- 结论：commander.js 满足需求
- 影响：无
- 状态：有效
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --title "逗号拆 tag 大小写不可靠" --source 失败尝试 --tag 数据 --conclusion "试过用逗号拆分 tag，大小写混乱导致重复条目，改用以空格分隔并统一小写。")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
echo "$out" | grep -q '^F3 | '"$TODAY"' | 数据 | 有效 | 逗号拆 tag 大小写不可靠$' || { ok=1; echo "  ↳ stdout=$out"; }
echo "$out" | grep -q '已再生索引' || ok=1
grep -q '^### F3：逗号拆 tag 大小写不可靠$' "$dir/FINDINGS.md" || ok=1
grep -q "^- 日期：$TODAY$" "$dir/FINDINGS.md" || ok=1
grep -q '^- 来源：失败尝试$' "$dir/FINDINGS.md" || ok=1
grep -q '^- 状态：有效$' "$dir/FINDINGS.md" || ok=1
# 写完立刻可查（索引已再生）
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --tag 数据)
echo "$out" | grep -q 'F3' || ok=1
# 归档文件的编号不复用
echo '### F7：归档老结论' > "$dir/FINDINGS.archive.md"
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --title "另一条独立结论" --source 外部输入 --conclusion "归档已用到 F7，所以新条目应为 F8。")
echo "$out" | grep -q '^F8 ' || { ok=1; echo "  ↳ 编号未跳过归档：$out"; }
report "finding-add：编号递增、字段齐全、写完立刻可查" $ok

# ── 用例 30：finding-add 闸门（同主题退 2 / 问句退 3 / --amend 不新开号） ──
ok=0
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --title "逗号拆 tag 不可靠" --source 失败尝试 --conclusion "再开一条同主题的。")
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ 同主题 rc=$rc（期望 2）"; }
echo "$out" | grep -q '同主题已有 F3' || ok=1
echo "$out" | grep -q -- '--amend F3' || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --title "要不要换 yargs" --source 调研探针 --conclusion "要不要换 yargs？")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 问句 rc=$rc（期望 3）"; }

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --amend F3 --conclusion "补充：mac 上同样复现。")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ amend rc=$rc"; }
echo "$out" | grep -q '已补充 F3' || ok=1
grep -q '^#### 补（'"$TODAY"'）$' "$dir/FINDINGS.md" || ok=1
# --amend 不新开号：F8 之后不应出现 F9
grep -q '^### F9' "$dir/FINDINGS.md" && ok=1
# 补的内容在 --full 里可见（用 #### 而非 ###，否则会被当成新条目边界切断 F3）
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" findings --full F3)
echo "$out" | grep -q 'mac 上同样复现' || ok=1
echo "$out" | grep -q '^### F3：' || ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --amend F3 --source 失败尝试 --conclusion "补充不该带 source。")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ amend+source rc=$rc（期望 3）"; }
# --amend 拒绝条目级字段：写进「补」会覆盖原条目字段（parseFindings 按条目合并同名键），
# 静默丢弃更糟（agent 会以为材料指针记下了）
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --amend F3 --conclusion "补一段。" --material notes/x.md)
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ amend+material rc=$rc（期望 3）"; }
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --amend F3 --conclusion "补一段。" --tag 同步)
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ amend+tag rc=$rc（期望 3）"; }
# --amend 编号格式校验（不拼出 Fundefined 这种编号）
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --amend 乱写 --conclusion "补一段。")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ amend 编号非法 rc=$rc（期望 3）"; }
# 以上被拒的三次都不该落盘
grep -q '补一段' "$dir/FINDINGS.md" && ok=1
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --amend F99 --conclusion "没有这个号。")
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ amend 不存在 rc=$rc（期望 2）"; }
report "finding-add：同主题/问句闸门与 --amend 语义" $ok

# ── 用例 31：finding-add --force 互写参见 ──
ok=0
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" finding-add --title "逗号拆 tag 在 Windows 上另有行为" --source 开发中发现 --conclusion "NTFS 下大小写不敏感，与 mac 表现不同，需显式归一化。" --force)
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
echo "$out" | grep -q '^F9 ' || { ok=1; echo "  ↳ 期望 F9：$out"; }
grep -q '^- 参见：F3$' "$dir/FINDINGS.md" || ok=1
grep -q '^- 参见：F9$' "$dir/FINDINGS.md" || ok=1
report "finding-add：--force 新开同主题并互写参见" $ok

# ── 用例 32：inbox-add（模板格式 + 查重） ──
dir=$(mk)
ok=0
cat > "$dir/INBOX.md" <<'EOF'
# INBOX

## 待裁决

- [ ] 2026-09-01 ⚪ 云同步支持
- 已解决：给同步加增量传输 ✅（2026-09-02）

## 已裁决（存档）
EOF
cat > "$dir/FINDINGS.md" <<'EOF'
# FINDINGS

## 索引

## 热条目

### F2：CLI 框架选型
- 日期：2026-07-18
- 来源：调研探针
- 结论：commander.js 满足需求
- 影响：无
- 状态：有效
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" inbox-add "要不要支持正则过滤" --flag 红 --origin 灵感 --finding F2)
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
echo "$out" | grep -q '已停 INBOX：要不要支持正则过滤' || ok=1
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -le 3 ] || { ok=1; echo "  ↳ stdout $n 行 > 3"; }
# 行含 emoji：用 node 按码点比对（Git Bash 的 grep 吃不下非 ASCII 长模式）
node -e 'const fs=require("fs");const t=fs.readFileSync(process.argv[1],"utf8");const want="- [ ] "+process.argv[2]+" "+String.fromCodePoint(0x1F534)+" 要不要支持正则过滤 — 来源：灵感 ｜ F2";process.exit(t.split("\n").includes(want)?0:1)' "$dir/INBOX.md" "$TODAY"
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" inbox-add "另一个想法" --finding F99)
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ 坏引用 rc=$rc（期望 2）"; }
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" inbox-add "云同步支持")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ 已解决 rc=$rc（期望 0）"; }
echo "$out" | grep -q '已由 给同步加增量传输 ✅ 实现' || ok=1
[ "$(grep -c '^- \[ \]' "$dir/INBOX.md")" -eq 2 ] || ok=1
report "inbox-add：模板格式、引用校验、已解决退 0" $ok

# ── 用例 33：progress-log（--kind 落当天标题 / --position 第一条 / --next 第二条） ──
dir=$(mk)
ok=0
mkdir -p "$dir/.planning/$TODAY-store-js"
cat > "$dir/.planning/$TODAY-store-js/plan.md" <<'EOF'
# 任务工作区：store.js 扩展 tag 字段

## 步骤

- [ ] 步骤1

## 当前位置

- 进行到哪一步：步骤1 改字段
- 下一步要做什么：补测试
- 待决问题：无
EOF
cat > "$dir/.planning/$TODAY-store-js/progress.md" <<'EOF'
# progress：store.js 扩展 tag 字段

## Postmortem

- **声明**：本文档为过程记录，结论以 FINDINGS.md 为准。

---

## 日志

### 2026-09-10

- 进展：开了头
EOF
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log "$TODAY-store-js" --text "改了 store.js 解析")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
n=$(printf '%s\n' "$out" | wc -l)
[ "$n" -eq 1 ] || { ok=1; echo "  ↳ stdout $n 行（期望 1）"; }
echo "$out" | grep -q '已记 progress（进展）' || ok=1
grep -q "^### $TODAY$" "$dir/.planning/$TODAY-store-js/progress.md" || ok=1
grep -q '^- 进展：改了 store.js 解析$' "$dir/.planning/$TODAY-store-js/progress.md" || ok=1

out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log "$TODAY-store-js" --kind 决策 --text "用空格分隔而非逗号" --position "步骤2 改解析器" --next "补单测")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "  ↳ rc=$rc"; }
grep -q '^- 决策：用空格分隔而非逗号$' "$dir/.planning/$TODAY-store-js/progress.md" || ok=1
grep -q '^- 进行到哪一步：步骤2 改解析器$' "$dir/.planning/$TODAY-store-js/plan.md" || ok=1
grep -q '^- 下一步要做什么：补单测$' "$dir/.planning/$TODAY-store-js/plan.md" || ok=1
grep -q '^- 待决问题：无$' "$dir/.planning/$TODAY-store-js/plan.md" || ok=1

long=$(node -e 'process.stdout.write("长".repeat(201))')
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log "$TODAY-store-js" --text "$long")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 超长 rc=$rc（期望 3）"; }
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log "$TODAY-store-js" --kind 瞎写 --text "x")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ 未知 kind rc=$rc（期望 3）"; }
# 没给 --text 时 --kind 无意义：拒绝而不是静默丢弃
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log "$TODAY-store-js" --kind 决策 --position "只改位置")
rc=$?
[ $rc -eq 3 ] || { ok=1; echo "  ↳ kind 无 text rc=$rc（期望 3）"; }
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log nosuch --text "x")
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ 无工作区 rc=$rc（期望 2）"; }
mkdir -p "$dir/.planning/done/2026-09-01-old"
cp "$dir/.planning/$TODAY-store-js/progress.md" "$dir/.planning/done/2026-09-01-old/"
out=$(PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" progress-log 2026-09-01-old --text "x")
rc=$?
[ $rc -eq 2 ] || { ok=1; echo "  ↳ 归档区 rc=$rc（期望 2）"; }
report "progress-log：日志落位、位置改对、闸门齐全" $ok

# ── 用例 34：写入族不改 hook 输出；usage 列出新命令 ──
dir=$(mk)
ok=0
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲
- DoD：一句话
EOF
before=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/session-start.sh")
PLANNING_ROOT="$(winpath "$dir")" node "$ENGINE" task-add "任务乙" --dod "另一句" >/dev/null
after=$(PLANNING_ROOT="$(winpath "$dir")" sh "$HOOKS_DIR/session-start.sh")
[ "$before" = "$after" ] || { ok=1; echo "  ↳ hook 输出被写入族改变了"; }
out=$(node "$ENGINE" xxx 2>&1)
echo "$out" | grep -q 'task-add "<标题>" --dod' || ok=1
echo "$out" | grep -q 'finding-add --title' || ok=1
echo "$out" | grep -q 'inbox-add "<标题>"' || ok=1
echo "$out" | grep -q 'progress-log <slug>' || ok=1
report "写入族：hook 输出不变 + usage 列出 4 个新命令" $ok


# ── 汇总 ───────────────────────────────────────────────────────
echo "-----"
echo "合计 $((PASS + FAIL)) 个用例：PASS $PASS，FAIL $FAIL"
[ $FAIL -eq 0 ] || exit 1
exit 0
