# post-tool-use hook：写代码文件后提醒落盘进展。
# 输出内容：若存在活跃工作区，提醒按 2-Action 规则更新 progress.md / 勾选 plan.md 步骤。
# 本脚本只读状态文件并输出提示文本，绝不写状态文件；无活跃工作区时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }
$planning = Join-Path $Root ".planning"
if (-not (Test-Path $planning)) { exit 0 }

$active = Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" }
if ($active.Count -gt 0) {
  $names = ($active | ForEach-Object { $_.Name }) -join " "
  Write-Output "[plan] 存在活跃工作区： $names"
  Write-Output "[plan] 若本次修改属于其中任务，请按 2-Action 规则把进展 / 决策 / 错误落 progress.md，并更新 plan.md 的勾选与「当前位置」。"
}

exit 0
