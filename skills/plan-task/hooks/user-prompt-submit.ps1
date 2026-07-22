# user-prompt-submit hook：每次用户消息提交时重新注入计划状态（抗 context rot）。
# 输出内容：当前里程碑一行 + TASKS.md「进行中」段原文（含 DoD 等完整内容，超 60 行截断）+ 活跃工作区一行提示。
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

# 进行中任务：注入 TASKS.md「进行中」段原文（含 DoD），超 60 行截断
$tasks = Join-Path $Root "TASKS.md"
if (Test-Path $tasks) {
  $inSection = $false
  $section = @()
  foreach ($line in Get-Content $tasks -Encoding UTF8) {
    if ($line -match '^## 进行中') { $inSection = $true; $section += $line; continue }
    if ($line -match '^## ') { if ($inSection) { break } }
    if ($inSection) { $section += $line }
  }
  if ($section.Count -gt 0 -and ($section | Where-Object { $_ -match '^### ' })) {
    Write-Output "[plan] 进行中任务（TASKS.md 原文）："
    if ($section.Count -gt 60) {
      $section | Select-Object -First 60 | ForEach-Object { Write-Output $_ }
      Write-Output "[plan] 进行中段过长已截断，详见 TASKS.md"
    } else {
      $section | ForEach-Object { Write-Output $_ }
    }
  }
}

# 活跃工作区（合并为一行，避免逐条刷屏）
$planning = Join-Path $Root ".planning"
if (Test-Path $planning) {
  $names = Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" } | ForEach-Object { $_.Name }
  if ($names) { Write-Output ("[plan] 活跃工作区： " + ($names -join " ") + "（开工前先读 plan.md 的「当前位置」）") }
}

exit 0
