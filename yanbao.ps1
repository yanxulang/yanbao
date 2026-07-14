$ErrorActionPreference = "Stop"
$Yanxu = if ($env:YANXU_BIN) { $env:YANXU_BIN } else { "yanxu" }
& $Yanxu (Join-Path $PSScriptRoot "src/主.yx") -- @args
exit $LASTEXITCODE
