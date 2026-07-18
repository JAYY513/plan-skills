#!/bin/sh
# stop-gate hook：会话收尾校验。
# 校验条件与 plan-task 技能的「完成三合一动作」一致：存在活跃工作区但对应任务未标 ✅
# （无回填归档迹象）→ 输出阻止 / 警告文本。hook 是技能规则的执行者，不是第二套规则。
# 本脚本只读状态文件并输出校验文本，绝不写状态文件；文件缺失时静默退出。命中阻止时以 exit 2 阻断（Claude Code Stop hook 语义）。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

[ "$PLANNING_HOOKS_DISABLED" = "1" ] && exit 0

ROOT="${PLANNING_ROOT:-.}"

[ -d "$ROOT/.planning" ] || exit 0

warn=""
for d in "$ROOT/.planning"/*/; do
  [ -d "$d" ] || continue
  name=$(basename "$d")
  [ "$name" = "done" ] && continue
  # 工作区短名（去掉 YYYY-MM-DD- 日期前缀），用于在 TASKS.md 中匹配 ✅ 标记
  short=$(echo "$name" | sed 's/^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}-//')
  done_mark=""
  if [ -f "$ROOT/TASKS.md" ] && [ -n "$short" ]; then
    done_mark=$(grep -i "$short" "$ROOT/TASKS.md" | grep '✅' | head -1)
  fi
  # slug 短名匹配不到中文任务名时，退一步看 postmortem 是否已固化（占位符已替换）
  if [ -z "$done_mark" ] && [ -f "$d/progress.md" ]; then
    if grep -q '本文档为过程记录' "$d/progress.md" && ! grep -q '<F? 编号>' "$d/progress.md"; then
      done_mark="postmortem-filled"
    fi
  fi
  if [ -z "$done_mark" ]; then
    warn="$warn $name"
  fi
done

if [ -n "$warn" ]; then
  echo "[plan] 阻止收尾：以下活跃工作区的任务未标 ✅：$warn"
  echo "[plan] 若任务已完成，请先执行三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 .planning/done/），再走 plan-task 标 ✅；若任务未完成，请在 progress.md 记录当前进展供下次恢复。"
fi

if [ -n "$warn" ]; then
  exit 2  # Claude Code Stop hook：exit 2 = 阻断收尾
fi
exit 0
