$ErrorActionPreference = "Stop"
$BundledApp = Join-Path $PSScriptRoot "yanbao-app.exe"
$Yanxu = if ($env:YANXU_BIN) { $env:YANXU_BIN } else { "yanxu" }
if (-not (Get-Command $Yanxu -ErrorAction SilentlyContinue)) {
    Write-Error "言包需要言序 1.1.6 或更高版本；请先安装 yanxu，或通过 YANXU_BIN 指定其路径。"
    exit 1
}
$env:YANXU_BIN = $Yanxu
if (Test-Path $BundledApp) {
    & $BundledApp @args
} else {
    & $Yanxu (Join-Path $PSScriptRoot "src/主.yx") -- @args
}
exit $LASTEXITCODE
