# user-prompt-submit hook：每次用户消息提交时重新注入精简计划状态（抗 context rot）。
# 输出内容（比 session-start 精简，避免每轮上下文膨胀）：当前里程碑一行 + 进行中任务标题列表 + 活跃工作区一行提示。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

# 输出统一为 UTF-8，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }

# 无任何状态文件时静默退出
if (-not ((Test-Path (Join-Path $Root "ROADMAP.md")) -or (Test-Path (Join-Path $Root "TASKS.md")) -or (Test-Path (Join-Path $Root ".planning")))) { exit 0 }

# 当前里程碑（一行）
$roadmap = Join-Path $Root "ROADMAP.md"
if (Test-Path $roadmap) {
  $milestone = Select-String -Path $roadmap -Encoding UTF8 -Pattern "^## *▶" | Select-Object -First 1
  if ($milestone) { Write-Output ("[plan] 当前里程碑：" + ($milestone.Line -replace '^#* ', '')) }
}

# 进行中任务标题列表
$tasks = Join-Path $Root "TASKS.md"
if (Test-Path $tasks) {
  $inSection = $false
  $items = @()
  foreach ($line in Get-Content $tasks -Encoding UTF8) {
    if ($line -match '^## 进行中') { $inSection = $true; continue }
    if ($line -match '^## ') { $inSection = $false }
    if ($inSection -and $line -match '^### ') { $items += ("- " + ($line -replace '^### ', '')) }
  }
  if ($items.Count -gt 0) {
    Write-Output "[plan] 进行中任务："
    $items | ForEach-Object { Write-Output $_ }
  }
}

# 活跃工作区（合并为一行，避免逐条刷屏）
$planning = Join-Path $Root ".planning"
if (Test-Path $planning) {
  $names = Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" } | ForEach-Object { $_.Name }
  if ($names) { Write-Output ("[plan] 活跃工作区： " + ($names -join " ") + "（开工前先读 plan.md 的「当前位置」）") }
}

exit 0
