# plan-doctor 薄壳：全部逻辑在 ..\engine\plan.mjs（sh/ps1 共用单一实现，双平台永不漂移）。
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File plan-doctor.ps1 [--global]
# 诊断工具，由用户显式运行，不受 PLANNING_HOOKS_DISABLED 影响。有 FAIL 时 exit 1，否则 exit 0。
# 输出统一按 UTF-8 解码，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$engine = Join-Path $PSScriptRoot '..\engine\plan.mjs'
if (Get-Command node -ErrorAction SilentlyContinue) {
  node $engine doctor @args
  exit $LASTEXITCODE
}
Write-Output "[FAIL] node 运行时: 未找到 node（引擎与所有 hooks 不可用，请安装 Node.js >= 18）"
Write-Output "-----"
Write-Output "合计 1 项：PASS 0，WARN 0，FAIL 1"
exit 1
