# stop-gate hook：会话收尾校验。
# 校验条件与 plan-task 技能的「完成三合一动作」一致：存在活跃工作区但对应任务未标 ✅
# （无回填归档迹象）→ 输出阻止 / 警告文本。hook 是技能规则的执行者，不是第二套规则。
# 本脚本只读状态文件并输出校验文本，绝不写状态文件；文件缺失时静默退出。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }
$planning = Join-Path $Root ".planning"
if (-not (Test-Path $planning)) { exit 0 }

$tasks = Join-Path $Root "TASKS.md"
$tasksContent = if (Test-Path $tasks) { Get-Content $tasks -Raw } else { "" }

$warn = @()
Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" } | ForEach-Object {
  $short = $_.Name -replace '^\d{4}-\d{2}-\d{2}-', ''
  $doneMark = $false
  if ($short -and $tasksContent) {
    $doneMark = ($tasksContent -split "`n" | Where-Object { $_ -match [regex]::Escape($short) -and $_ -match '✅' } | Select-Object -First 1)
  }
  # slug 短名匹配不到中文任务名时，退一步看 postmortem 是否已固化（占位符已替换）
  if (-not $doneMark) {
    $progress = Join-Path $_.FullName "progress.md"
    if (Test-Path $progress) {
      $pc = Get-Content $progress -Raw
      if ($pc -match '本文档为过程记录' -and $pc -notmatch '<F\? 编号>') { $doneMark = $true }
    }
  }
  if (-not $doneMark) { $warn += $_.Name }
}

if ($warn.Count -gt 0) {
  Write-Output ("[plan] 阻止收尾：以下活跃工作区的任务未标 ✅： " + ($warn -join " "))
  Write-Output "[plan] 若任务已完成，请先执行三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 .planning/done/），再走 plan-task 标 ✅；若任务未完成，请在 progress.md 记录当前进展供下次恢复。"
  exit 2  # Stop hook：exit 2 = 阻断收尾
}

exit 0
