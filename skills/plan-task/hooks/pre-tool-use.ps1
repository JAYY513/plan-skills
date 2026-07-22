# pre-tool-use hook：执行类工具调用前注入当前任务上下文。
# 输出内容：TASKS.md 进行中任务 + 各活跃工作区 plan.md 的「当前位置」摘要。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

# 输出统一为 UTF-8，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }

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

$planning = Join-Path $Root ".planning"
if (Test-Path $planning) {
  Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" } | ForEach-Object {
    $plan = Join-Path $_.FullName "plan.md"
    if (Test-Path $plan) {
      $inPos = $false
      $pos = @()
      foreach ($line in Get-Content $plan -Encoding UTF8) {
        if ($line -match '^## 当前位置') { $inPos = $true; continue }
        if ($line -match '^## ') { $inPos = $false }
        if ($inPos -and $line -match '^- ') { $pos += $line }
      }
      if ($pos.Count -gt 0) {
        Write-Output ("[plan] 工作区 .planning/" + $_.Name + " 当前位置：")
        $pos | Select-Object -First 3 | ForEach-Object { Write-Output $_ }
      }
    }
  }
}

exit 0
