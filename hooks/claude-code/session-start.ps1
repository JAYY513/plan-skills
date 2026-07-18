# session-start hook：会话开始时输出当前计划状态。
# 输出内容：当前里程碑（ROADMAP.md 中 ▶ 行）+ TASKS.md 进行中任务 + .planning/ 活跃工作区列表 + 主动提示行（进行中任务数 / INBOX 待裁决数）。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }

$roadmap = Join-Path $Root "ROADMAP.md"
if (Test-Path $roadmap) {
  $milestone = Select-String -Path $roadmap -Pattern "▶" | Select-Object -First 1
  if ($milestone) { Write-Output ("[plan] 当前里程碑：" + ($milestone.Line -replace '^#* ', '')) }
}

$tasks = Join-Path $Root "TASKS.md"
if (Test-Path $tasks) {
  $inSection = $false
  $items = @()
  foreach ($line in Get-Content $tasks) {
    if ($line -match '^## 进行中') { $inSection = $true; continue }
    if ($line -match '^## ') { $inSection = $false }
    if ($inSection -and $line -match '^### ') { $items += ("- " + ($line -replace '^### ', '')) }
  }
  if ($items.Count -gt 0) {
    Write-Output "[plan] 进行中任务："
    $items | ForEach-Object { Write-Output $_ }
  }
}

$planning = Join-Path $Root ".planning"
if (Test-Path $planning) {
  Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" } | ForEach-Object {
    Write-Output ("[plan] 活跃工作区：.planning/" + $_.Name + "（开工前先读 plan.md 的「当前位置」）")
  }
}

# 主动提示：进行中任务数 + INBOX 待裁决数（文件缺失 / 无匹配时显示 0，不报错）
$taskCount = 0
$tasksFile = Join-Path $Root "TASKS.md"
if (Test-Path $tasksFile) {
  $inSec = $false
  foreach ($line in Get-Content $tasksFile) {
    if ($line -match '^## 进行中') { $inSec = $true; continue }
    if ($line -match '^## ') { $inSec = $false }
    if ($inSec -and $line -match '^### ') { $taskCount++ }
  }
}
$inboxCount = 0
$inbox = Join-Path $Root "INBOX.md"
if (Test-Path $inbox) {
  $inSec = $false
  foreach ($line in Get-Content $inbox) {
    if ($line -match '^## 待裁决') { $inSec = $true; continue }
    if ($line -match '^## ') { $inSec = $false }
    if ($inSec -and $line -match '^- \[ \]') { $inboxCount++ }
  }
}
Write-Output "[plan] 提示：进行中任务 $taskCount 个，INBOX 待裁决 $inboxCount 条"

exit 0
