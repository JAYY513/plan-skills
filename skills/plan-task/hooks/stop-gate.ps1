# stop-gate hook：会话收尾校验，两道门。
# 门一（工作区门）：存在活跃工作区但对应任务未标 ✅（无回填归档迹象）→ 阻止。
# 门二（未完成阻止门）：TASKS.md「进行中」仍有任务且不存在活跃工作区（未做任何完成动作）→ 阻止。
# 校验条件与 plan-task 技能的「完成三合一动作」一致，hook 是技能规则的执行者，不是第二套规则。
# 本脚本只读状态文件并输出校验文本，绝不写状态文件；文件缺失时静默退出。命中阻止时以 exit 2 阻断（Stop hook 语义）。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，本脚本立即退出。

# 输出统一为 UTF-8，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($env:PLANNING_HOOKS_DISABLED -eq "1") { exit 0 }

$Root = if ($env:PLANNING_ROOT) { $env:PLANNING_ROOT } else { "." }
$planning = Join-Path $Root ".planning"
$tasks = Join-Path $Root "TASKS.md"

# 无任何可校验状态时静默退出（干净会话不误伤）
if (-not ((Test-Path $planning) -or (Test-Path $tasks))) { exit 0 }

$tasksContent = if (Test-Path $tasks) { Get-Content $tasks -Encoding UTF8 -Raw } else { "" }

# ── 门一：活跃工作区未归档 ─────────────────────────────────────
$activeWs = 0
$warn = @()
if (Test-Path $planning) {
  Get-ChildItem $planning -Directory | Where-Object { $_.Name -ne "done" } | ForEach-Object {
    $activeWs++
    $short = $_.Name -replace '^\d{4}-\d{2}-\d{2}-', ''
    $doneMark = $false
    if ($short -and $tasksContent) {
      $doneMark = ($tasksContent -split "`n" | Where-Object { $_ -match [regex]::Escape($short) -and $_ -match '✅' } | Select-Object -First 1)
    }
    # slug 短名匹配不到中文任务名时，退一步看 postmortem 是否已固化（占位符已替换）
    if (-not $doneMark) {
      $progress = Join-Path $_.FullName "progress.md"
      if (Test-Path $progress) {
        $pc = Get-Content $progress -Encoding UTF8 -Raw
        if ($pc -match '本文档为过程记录' -and $pc -notmatch '<F\? 编号>') { $doneMark = $true }
      }
    }
    if (-not $doneMark) { $warn += $_.Name }
  }
}

if ($warn.Count -gt 0) {
  Write-Output ("[plan] 阻止收尾：以下活跃工作区的任务未标 ✅： " + ($warn -join " "))
  Write-Output "[plan] 若任务已完成，请先执行三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 .planning/done/），再走 plan-task 标 ✅；若任务未完成，请在 progress.md 记录当前进展供下次恢复。"
  exit 2  # Stop hook：exit 2 = 阻断收尾
}

# ── 门二：进行中任务未做任何完成动作 ──────────────────────────
# 有进行中任务且没有任何活跃工作区（既未开工留痕也未归档）→ 阻止
if ((Test-Path $tasks) -and $activeWs -eq 0) {
  $inSection = $false
  $openTasks = @()
  foreach ($line in Get-Content $tasks -Encoding UTF8) {
    if ($line -match '^## 进行中') { $inSection = $true; continue }
    if ($line -match '^## ') { if ($inSection) { break } }
    if ($inSection -and $line -match '^### ') { $openTasks += ($line -replace '^### ', '') }
  }
  if ($openTasks.Count -gt 0) {
    Write-Output ("[plan] 阻止收尾：TASKS.md「进行中」仍有 " + $openTasks.Count + " 个未完成任务：")
    $openTasks | ForEach-Object { Write-Output ("[plan] - " + $_) }
    Write-Output "[plan] 下一步：若任务已完成，标 ✅ 前先走完成三合一动作（结论回填 FINDINGS.md + progress.md 顶部固化 postmortem + 工作区移入 .planning/done/）；若确认暂停，请把任务移回「已拆好（待做）」并记录当前进展供下次恢复。"
    exit 2
  }
}

exit 0
