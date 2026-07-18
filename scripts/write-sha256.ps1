param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,
    [Parameter(Mandatory = $true)]
    [string]$AssetName
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $InputPath -PathType Leaf)) {
    throw "input archive does not exist: $InputPath"
}
if ($AssetName -notmatch "^[A-Za-z0-9._-]+$") {
    throw "asset name contains unsupported characters"
}

$Checksum = (Get-FileHash -LiteralPath $InputPath -Algorithm SHA256).Hash.ToLowerInvariant()
$Line = "$Checksum  $AssetName`n"
$Ascii = New-Object System.Text.ASCIIEncoding
[System.IO.File]::WriteAllText($OutputPath, $Line, $Ascii)

$Bytes = [System.IO.File]::ReadAllBytes($OutputPath)
if ($Bytes.Length -eq 0 -or $Bytes[-1] -ne 10 -or $Bytes -contains 13) {
    throw "checksum file must end with one LF and must not contain CR"
}
$Written = [System.IO.File]::ReadAllText($OutputPath, $Ascii)
if ($Written -ne $Line) {
    throw "checksum file content changed during write"
}
