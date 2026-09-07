#!/bin/sh
# tests/test-hooks.sh：hooks + 引擎冒烟测试（逻辑单一实现在 skills/plan-task/engine/plan.mjs，hooks/ 下为薄壳）。
# 用 mktemp 临时目录构造场景，断言各 hook / 引擎命令的输出文本与 exit code；每用例一行 PASS/FAIL，结尾汇总，有 FAIL 则 exit 1。
# 运行方式：在仓库根执行 sh tests/test-hooks.sh（需要 node >= 18；有 pwsh 时额外跑 ps1 薄壳冒烟）

HOOKS_DIR="$(cd "$(dirname "$0")/../skills/plan-task/hooks" && pwd)"
ENGINE="$HOOKS_DIR/../engine/plan.mjs"

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
echo "$out" | grep -q 'notes/' && ok=1
report "pre-compact：活跃工作区输出提醒含工作区名" $ok

dir=$(mk)
mkdir -p "$dir/.planning/2026-07-18-demo-task/notes"
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/pre-compact.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '上下文即将压缩' || ok=1
echo "$out" | grep -q 'notes/' || ok=1
report "pre-compact：已有 notes/ 时催材料落盘" $ok

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

# 有状态：输出里程碑 + 进行中段原文（含 DoD）+ 工作区一行，且不含 INBOX 计数提示行
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
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '当前里程碑：▶ M1：测试里程碑' || ok=1
echo "$out" | grep -q '进行中任务（TASKS.md 原文）：' || ok=1
echo "$out" | grep -q '### 任务甲' || ok=1
echo "$out" | grep -q 'DoD：点击中断后输出立刻停止，手动验证通过' || ok=1
echo "$out" | grep -q '活跃工作区： 2026-07-18-demo-task' || ok=1
echo "$out" | grep -q '任务乙' && ok=1
echo "$out" | grep -q 'INBOX' && ok=1
report "user-prompt-submit：进行中段原文注入（含 DoD）且不越界" $ok

# 进行中段超 60 行 → 截断并附提示行
dir=$(mk)
{
  echo '# TASKS'
  echo ''
  echo '## 进行中'
  echo ''
  echo '### 长任务'
  i=0; while [ $i -lt 70 ]; do echo "- 细节行 $i"; i=$((i + 1)); done
  echo ''
  echo '## 已拆好（待做）'
  echo ''
  echo '### 不应出现'
} > "$dir/TASKS.md"
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '进行中段过长已截断，详见 TASKS.md' || ok=1
echo "$out" | grep -q '细节行 69' && ok=1
echo "$out" | grep -q '不应出现' && ok=1
report "user-prompt-submit：进行中段超 60 行截断" $ok

# 禁用变量 → 静默 exit 0
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲
EOF
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
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
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
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
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
out=$(PLANNING_HOOKS_DISABLED=1 PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
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

# ── 用例 14：user-prompt-submit 节流（内容未变只发摘要，变了恢复全量）──
dir=$(mk)
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

- DoD：验证点

## 已拆好（待做）
EOF
out1=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
out2=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
ok=0
echo "$out1" | grep -q '进行中任务（TASKS.md 原文）：' || ok=1
echo "$out2" | grep -q '计划状态无变化（进行中任务 1 个）' || ok=1
echo "$out2" | grep -q '原文' && ok=1
[ -f "$dir/.planning/.hook-cache.json" ] || ok=1
# 修改进行中段 → 恢复全量
cat > "$dir/TASKS.md" <<'EOF'
# TASKS

## 进行中

### 任务甲

### 任务乙

## 已拆好（待做）
EOF
out3=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
echo "$out3" | grep -q '进行中任务（TASKS.md 原文）：' || ok=1
echo "$out3" | grep -q '任务乙' || ok=1
# PLANNING_HOOKS_NO_THROTTLE=1 → 始终全量
out4=$(PLANNING_HOOKS_NO_THROTTLE=1 PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
out5=$(PLANNING_HOOKS_NO_THROTTLE=1 PLANNING_ROOT="$dir" sh "$HOOKS_DIR/user-prompt-submit.sh")
echo "$out4" | grep -q '原文' || ok=1
echo "$out5" | grep -q '原文' || ok=1
echo "$out5" | grep -q '无变化' && ok=1
report "user-prompt-submit 节流：未变发摘要、变了恢复全量、NO_THROTTLE 始终全量" $ok

# ── 用例 15：stop-gate 门二日期规则（当天开工豁免，隔天阻止）──
dir=$(mk)
cat > "$dir/TASKS.md" <<EOF
# TASKS

## 进行中

### 任务甲
- 开始：$TODAY

## 已拆好（待做）
EOF
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
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
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
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
out=$(PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh")
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
out=$(PLANNING_ROOT="$dir" node "$ENGINE" start "store.js 扩展 tag 字段" --date "$TODAY")
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q '已认领' || ok=1
sed -n '/^## 进行中/,/^## 已拆好/p' "$dir/TASKS.md" | grep -q '### store.js 扩展 tag 字段' || ok=1
sed -n '/^## 进行中/,/^## 已拆好/p' "$dir/TASKS.md" | grep -q "开始：$TODAY" || ok=1
sed -n '/^## 已拆好/,/^## 调研/p' "$dir/TASKS.md" | grep -q '### store.js' && ok=1
# 重复 start → 幂等 + 建工作区 + 补关联行
out=$(PLANNING_ROOT="$dir" node "$ENGINE" start "store.js 扩展 tag 字段" --workspace --date "$TODAY")
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
out=$(PLANNING_ROOT="$dir" node "$ENGINE" start "不存在的任务")
rc=$?
[ $rc -eq 1 ] || ok=1
echo "$out" | grep -q '未找到任务' || ok=1
report "引擎 start：认领补日期、幂等、--workspace 建目录补关联行、未知任务 exit 1" $ok

# ── 用例 18：引擎 finish（缺证据 exit 1 → 补齐后 ✅ + 归档）──
out=$(PLANNING_ROOT="$dir" node "$ENGINE" finish "store.js 扩展 tag 字段")
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
out=$(PLANNING_ROOT="$dir" node "$ENGINE" finish "store.js 扩展 tag 字段" --date "$TODAY")
rc=$?
[ $rc -eq 0 ] || { ok=1; echo "$out"; }
echo "$out" | grep -q '已完成：✅' || ok=1
sed -n '/^## 已完成/,$p' "$dir/TASKS.md" | grep -q '### store.js 扩展 tag 字段 ✅' || ok=1
sed -n '/^## 已完成/,$p' "$dir/TASKS.md" | grep -q "完成：$TODAY" || ok=1
[ -d "$dir/.planning/done/$slug" ] || ok=1
[ -d "$dir/.planning/$slug" ] && ok=1
# finish 后 stop-gate 放行
PLANNING_ROOT="$dir" sh "$HOOKS_DIR/stop-gate.sh" >/dev/null
[ $? -eq 0 ] || ok=1
report "引擎 finish：缺证据 exit 1 列缺失，补齐后 ✅ + 完成日期 + 工作区移入 done/" $ok

# ── 用例 19：ps1 薄壳冒烟（有 pwsh 才跑，无则 SKIP 不计失败）──
if command -v pwsh >/dev/null 2>&1; then
  dir=$(mk)
  ok=0
  for s in session-start pre-tool-use post-tool-use stop-gate user-prompt-submit pre-compact permission-request; do
    PLANNING_ROOT="$dir" pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOOKS_DIR/$s.ps1" >/dev/null 2>&1
    [ $? -eq 0 ] || { ok=1; echo "  ↳ $s.ps1 空目录应 exit 0"; }
  done
  dir=$(mk)
  mkdir -p "$dir/.planning/2026-08-01-demo-task"
  PLANNING_ROOT="$dir" pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOOKS_DIR/stop-gate.ps1" >/dev/null 2>&1
  [ $? -eq 2 ] || { ok=1; echo "  ↳ stop-gate.ps1 阻断场景应 exit 2"; }
  report "ps1 薄壳冒烟：静默场景 exit 0、stop-gate 阻断透传 exit 2" $ok
else
  echo "SKIP: ps1 薄壳冒烟（无 pwsh）"
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
out=$(PLANNING_ROOT="$dir" node "$ENGINE" hook session-start)
rc=$?
ok=0
[ $rc -eq 0 ] || ok=1
echo "$out" | grep -q 'SPEC 红线' || ok=1
echo "$out" | grep -q '边界：不做 GUI 界面' || ok=1
echo "$out" | grep -q '边界：不接第三方支付' || ok=1
echo "$out" | grep -q '选型：运行时 = Node.js' || ok=1
echo "$out" | grep -q '选型：持久化 = JSON 文件' || ok=1
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
out2=$(PLANNING_ROOT="$dir2" node "$ENGINE" hook session-start)
echo "$out2" | grep -q 'SPEC 红线' && ok=1
echo "$out2" | grep -q '示例：后端框架' && ok=1
# 超长 SPEC → 截断（上限 12 行 + 提示）
dir3=$(mk)
{ echo '# SPEC'; echo; echo '## 不做什么（边界）'; echo; for i in $(seq 1 15); do echo "- 边界条目 $i"; done; } > "$dir3/SPEC.md"
touch "$dir3/TASKS.md"
out3=$(PLANNING_ROOT="$dir3" node "$ENGINE" hook session-start)
n=$(echo "$out3" | grep -c '边界：边界条目')
[ "$n" -eq 12 ] || { ok=1; echo "  ↳ 截断应保留 12 条，实际 $n"; }
echo "$out3" | grep -q '已截断' || ok=1
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
out=$(PLANNING_ROOT="$dir" node "$ENGINE" start "product ia probe" --workspace --date "$TODAY")
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
out=$(PLANNING_ROOT="$dir" node "$ENGINE" start "product ia probe" --workspace --date "$TODAY")
echo "$out" | grep -q '工作区已存在' || ok=1
[ -f "$dir/.planning/$rslug/notes/index.md" ] || ok=1
report "引擎 start：调研区 --workspace 复制 notes/index.md，普通复用不覆盖" $ok

# ── 汇总 ───────────────────────────────────────────────────────
echo "-----"
echo "合计 $((PASS + FAIL)) 个用例：PASS $PASS，FAIL $FAIL"
[ $FAIL -eq 0 ] || exit 1
exit 0
