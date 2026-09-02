# user-prompt-submit hook 薄壳：全部逻辑在 ..\engine\plan.mjs（sh/ps1 共用单一实现，双平台永不漂移）。
# 禁用方式：设置环境变量 PLANNING_HOOKS_DISABLED=1，引擎立即静默退出。
# 输出统一按 UTF-8 解码，避免 Windows PowerShell 默认 GBK 编码把 ▶ 等字符转成 ?
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$engine = Join-Path $PSScriptRoot '..\engine\plan.mjs'
if (Get-Command node -ErrorAction SilentlyContinue) {
  node $engine hook user-prompt-submit @args
  exit $LASTEXITCODE
}
# 无 node → 静默退出（hook 绝不阻断会话）
exit 0
