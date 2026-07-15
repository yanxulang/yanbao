$ErrorActionPreference = "Stop"
$BundledRuntime = Join-Path $PSScriptRoot "yanxu-1.1.6.exe"
$BundledApp = Join-Path $PSScriptRoot "yanbao-app.exe"
$Yanxu = if ($env:YANXU_BIN) { $env:YANXU_BIN } elseif (Test-Path $BundledRuntime) { $BundledRuntime } else { "yanxu" }
if ((Test-Path $BundledApp) -and (Test-Path $BundledRuntime)) {
    $env:YANXU_BIN = $Yanxu
    & $BundledApp @args
} else {
    & $Yanxu (Join-Path $PSScriptRoot "src/主.yx") -- @args
}
exit $LASTEXITCODE
