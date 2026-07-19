# pre-compact hook：上下文压缩前抢写状态，防漂移。
# 输出内容：若存在活跃工作区，提醒先把进展 / 决策 / 「当前位置」落盘 progress.md 和 plan.md；TASKS.md 有进行中任务时顺带提醒确认 TASKS 状态已最新。
# 本脚本只读状态文件并输出提示文本，绝不写状态文件；无活跃工作区时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }
$planning = Join-Path $Root ".planning"
if (-not (Test-Path $planning)) { exit 0 }

$active = @(Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" })
if ($active.Count -eq 0) { exit 0 }

foreach ($ws in $active) {
  Write-Output ("[plan] 上下文即将压缩：请先把当前进展、决策、「当前位置」更新进 .planning/" + $ws.Name + "/progress.md 和 plan.md，再继续")
}

# TASKS.md 有进行中任务时，顺带提醒确认 TASKS 状态已最新
$tasks = Join-Path $Root "TASKS.md"
if (Test-Path $tasks) {
  $inSec = $false
  $taskCount = 0
  foreach ($line in Get-Content $tasks) {
    if ($line -match '^## 进行中') { $inSec = $true; continue }
    if ($line -match '^## ') { $inSec = $false }
    if ($inSec -and $line -match '^### ') { $taskCount++ }
  }
  if ($taskCount -gt 0) { Write-Output "[plan] 另：TASKS.md 有 $taskCount 个进行中任务，请确认 TASKS 状态已最新。" }
}

exit 0
