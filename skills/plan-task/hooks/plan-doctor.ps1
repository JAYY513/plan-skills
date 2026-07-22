# plan-doctor：plan-skills 安装自检工具，逐项输出 [PASS]/[WARN]/[FAIL] 单行结果，定位"静默无 hook"问题。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File plan-doctor.ps1 [-Global]（-Global 只查全局安装）
# 本脚本为诊断工具，由用户显式运行，不受 PLANNING_HOOKS_DISABLED 影响；只读不修改任何文件。
# 有 FAIL 时 exit 1，否则 exit 0（WARN 不影响退出码）。

param([switch]$Global)

# 输出统一为 UTF-8，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

$script:Pass = 0
$script:Warn = 0
$script:Fail = 0

function Pass($msg) { $script:Pass++; Write-Output "[PASS] $msg" }
function Warn($msg) { $script:Warn++; Write-Output "[WARN] $msg" }
function Fail($msg) { $script:Fail++; Write-Output "[FAIL] $msg" }

$Scripts = @("session-start", "user-prompt-submit", "pre-tool-use", "post-tool-use", "pre-compact", "stop-gate", "permission-request")
$CcEvents = @("SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreCompact", "Stop")

# ── 1. 技能安装 ────────────────────────────────────────────────
$candidates = @()
if (-not $Global) { $candidates += @("./.agents/skills/plan-task", "./.claude/skills/plan-task") }
$candidates += @("$HOME/.claude/skills/plan-task", "$HOME/.codex/skills/plan-task", "$HOME/.config/opencode/skills/plan-task")

$found = @()
foreach ($d in $candidates) {
  if (Test-Path (Join-Path $d "SKILL.md")) { $found += $d }
}

if ($found.Count -gt 0) {
  Pass ("技能安装: 发现 plan-task 于: " + ($found -join " "))
} else {
  Fail "技能安装: 未发现 plan-task（运行 npx skills add JAYY513/plan-skills --skill plan-task）"
}

# ── 2. hook 脚本齐全 ───────────────────────────────────────────
foreach ($d in $found) {
  $missing = @()
  foreach ($s in $Scripts) {
    if (-not (Test-Path (Join-Path $d "hooks/$s.sh"))) { $missing += "$s.sh" }
    if (-not (Test-Path (Join-Path $d "hooks/$s.ps1"))) { $missing += "$s.ps1" }
  }
  if ($missing.Count -eq 0) {
    Pass "hook 脚本齐全: $d（7 对 sh/ps1）"
  } else {
    Fail ("hook 脚本齐全: $d 缺失: " + ($missing -join " ") + "（运行 npx skills update 更新技能）")
  }
}

# ── 3. Claude Code hooks 注册（frontmatter）────────────────────
foreach ($d in $found) {
  if ($d -notmatch '\.claude') { continue }
  $lines = Get-Content (Join-Path $d "SKILL.md") -Encoding UTF8 -TotalCount 100
  $fm = @()
  foreach ($line in $lines) {
    $fm += $line
    if ($fm.Count -gt 1 -and $line -match '^---$') { break }
  }
  if (-not ($fm | Where-Object { $_ -match '^hooks:' })) {
    Fail "Claude Code hooks 注册: $d 的 SKILL.md frontmatter 缺少 hooks: 键（旧版本？运行 npx skills update）"
    continue
  }
  $missingEv = @()
  foreach ($ev in $CcEvents) {
    if (-not ($fm | Where-Object { $_ -match "^  ${ev}:" })) { $missingEv += $ev }
  }
  if ($missingEv.Count -eq 0) {
    Pass "Claude Code hooks 注册: $d frontmatter 6 个事件齐全"
  } else {
    Fail ("Claude Code hooks 注册: $d 缺少事件: " + ($missingEv -join " "))
  }
}

# ── 4. Codex hooks 注册 ────────────────────────────────────────
$hjCandidates = @()
if (-not $Global) { $hjCandidates += "./.codex/hooks.json" }
$hjCandidates += "$HOME/.codex/hooks.json"

$hjFound = @()
foreach ($f in $hjCandidates) {
  if (Test-Path $f) { $hjFound += $f }
}

if ($hjFound.Count -gt 0) {
  # 逐文件检查 JSON 合法性并标记是否含 plan-task
  $ptFiles = @()
  foreach ($f in $hjFound) {
    $raw = Get-Content $f -Raw -Encoding UTF8
    if ($raw -match 'plan-task') {
      $ptFiles += $f
      try {
        $null = $raw | ConvertFrom-Json -ErrorAction Stop
        Pass "Codex hooks 注册: $f 存在、含 plan-task、JSON 合法"
      } catch {
        Fail "Codex hooks 注册: $f 不是合法 JSON"
      }
    }
  }
  # 重复触发警告：仅当两处都注册了 plan-task
  if ($ptFiles.Count -ge 2) {
    Warn "Codex hooks 注册: 项目级与全局 hooks.json 都注册了 plan-task，hook 会重复触发，请只保留一处"
  }
  # plan-task 注册判定：任一处含 plan-task 即可；全局不含仅作信息行
  if ($ptFiles.Count -gt 0) {
    foreach ($f in $hjFound) {
      if ($ptFiles -notcontains $f) {
        Pass "Codex hooks 注册: $f 未注册 plan-task（全局未安装 Codex hooks，可选）"
      }
    }
  } else {
    Fail "Codex hooks 注册: 项目级与全局 hooks.json 均不含 plan-task 路径（参考 hooks/codex/README.md 安装）"
  }
  # hooks 特性开关（仅在存在 plan-task 注册时检查）
  if ($ptFiles.Count -gt 0) {
    $cfg = "$HOME/.codex/config.toml"
    if ((Test-Path $cfg) -and ((Get-Content $cfg -Raw -Encoding UTF8) -match 'hooks\s*=\s*true')) {
      Pass "Codex hooks 特性: $cfg 含 hooks = true"
    } else {
      Warn "Codex hooks 特性: 未在 $cfg 找到 hooks = true（请在 [features] 节配置，或用 codex features list 验证）"
    }
  }
} else {
  Warn "Codex hooks 注册: 未发现 hooks.json（使用 Codex 时参考 hooks/codex/README.md 安装；不用 Codex 可忽略）"
}

# ── 5. sh 可用性 / powershell 版本 ─────────────────────────────
$sh = Get-Command sh -ErrorAction SilentlyContinue
if ($sh) {
  Pass ("sh 可用: " + $sh.Source)
} else {
  Fail "sh 可用: 未找到 sh（hooks 的 sh 入口全部无法运行）"
}
Pass ("powershell 可用: " + $PSVersionTable.PSVersion.ToString())

# ── 6. 状态文件（当前目录是否已 plan-init）─────────────────────
if (-not $Global) {
  $missingSf = @()
  foreach ($sf in @("SPEC.md", "ROADMAP.md", "TASKS.md", "INBOX.md", "FINDINGS.md")) {
    if (-not (Test-Path $sf)) { $missingSf += $sf }
  }
  if ($missingSf.Count -eq 0) {
    Pass "状态文件: 当前目录已初始化计划体系（5 文件齐全）"
  } else {
    Warn ("状态文件: 当前目录缺少: " + ($missingSf -join " ") + "（尚未运行 plan-init；hooks 会静默跳过，属预期）")
  }
}

# ── 汇总 ───────────────────────────────────────────────────────
Write-Output "-----"
Write-Output ("合计 " + ($script:Pass + $script:Warn + $script:Fail) + " 项：PASS $script:Pass，WARN $script:Warn，FAIL $script:Fail")
if ($script:Fail -gt 0) { exit 1 }
exit 0
