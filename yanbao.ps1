$ErrorActionPreference = "Stop"
$BundledApp = Join-Path $PSScriptRoot "yanbao-app.exe"
$Yanxu = if ($env:YANXU_BIN) { $env:YANXU_BIN } else { "yanxu" }
if (-not (Get-Command $Yanxu -ErrorAction SilentlyContinue)) {
    Write-Error "Yanbao requires Yanxu 1.1.17 or newer. Install yanxu first or set YANXU_BIN."
    exit 1
}
$env:YANXU_BIN = $Yanxu
$OriginalOutputEncoding = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    if (Test-Path $BundledApp) {
        & $BundledApp @args
    } else {
        $SourceName = [string]::Concat([char]0x4E3B, ".yx")
        & $Yanxu (Join-Path (Join-Path $PSScriptRoot "src") $SourceName) -- @args
    }
    $ExitCode = $LASTEXITCODE
} finally {
    [Console]::OutputEncoding = $OriginalOutputEncoding
}
exit $ExitCode
