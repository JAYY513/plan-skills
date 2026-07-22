# permission-request hook（Codex）：权限确认弹窗时注入一行当前任务上下文。
# 极简输出：存在进行中任务则输出一行提示，否则静默退出。
# 本脚本只读状态文件并输出注入文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

# 输出统一为 UTF-8，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }

$tasks = Join-Path $Root "TASKS.md"
if (-not (Test-Path $tasks)) { exit 0 }

$inSection = $false
$firstTask = ""
foreach ($line in Get-Content $tasks -Encoding UTF8) {
  if ($line -match '^## 进行中') { $inSection = $true; continue }
  if ($line -match '^## ') { $inSection = $false }
  if ($inSection -and $line -match '^### ') { $firstTask = ($line -replace '^### ', ''); break }
}
if ($firstTask) { Write-Output ("[plan] 当前进行中任务：" + $firstTask + "（权限请求与计划纪律相关时请对照 TASKS.md / plan.md）") }

exit 0
