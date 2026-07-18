$ErrorActionPreference = "Stop"
# Keep this script ASCII-only so Windows PowerShell 5.1 can run it both as a file and through irm | iex.

function Get-Sha256([string]$Path) {
    $Stream = [System.IO.File]::OpenRead($Path)
    try {
        $Hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            return ([System.BitConverter]::ToString($Hasher.ComputeHash($Stream))).Replace("-", "").ToLowerInvariant()
        } finally {
            $Hasher.Dispose()
        }
    } finally {
        $Stream.Dispose()
    }
}

function Invoke-Utf8Process([string]$Path, [string]$Arguments) {
    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo
    $StartInfo.FileName = $Path
    $StartInfo.Arguments = $Arguments
    $StartInfo.UseShellExecute = $false
    $StartInfo.CreateNoWindow = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError = $true
    $StartInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $StartInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $StartInfo
    try {
        if (-not $Process.Start()) { throw "could not start $Path" }
        $Stdout = $Process.StandardOutput.ReadToEnd()
        $Stderr = $Process.StandardError.ReadToEnd()
        $Process.WaitForExit()
        return [pscustomobject]@{
            ExitCode = $Process.ExitCode
            Text = ($Stdout + $Stderr).Trim()
        }
    } finally {
        $Process.Dispose()
    }
}

$Repository = if ($env:YANBAO_REPOSITORY) { $env:YANBAO_REPOSITORY } else { "YanXuLang/yanbao" }
$Version = if ($env:YANBAO_VERSION) { $env:YANBAO_VERSION } else { "latest" }
$InstallDir = if ($env:YANBAO_INSTALL_DIR) { $env:YANBAO_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\Yanbao\bin" }
$AssetDir = if ($env:YANBAO_ASSET_DIR) { [System.IO.Path]::GetFullPath($env:YANBAO_ASSET_DIR) } else { $null }
if ($AssetDir -and -not [System.IO.Directory]::Exists($AssetDir)) {
    throw "Yanbao installation failed: YANBAO_ASSET_DIR is not a directory"
}
$Yanxu = if ($env:YANXU_BIN) { $env:YANXU_BIN } else { "yanxu" }
if (-not (Get-Command $Yanxu -ErrorAction SilentlyContinue)) {
    throw "Yanbao installation failed: Yanxu 1.1.17 or newer is required; install yanxu or set YANXU_BIN"
}
$env:YANXU_BIN = $Yanxu
$ToolchainProbe = Invoke-Utf8Process $Yanxu "version --json"
if ($ToolchainProbe.ExitCode -ne 0) {
    throw "Yanbao installation failed: could not read the installed Yanxu version: $($ToolchainProbe.Text)"
}
try {
    $ReportedYanxuVersion = [string](($ToolchainProbe.Text | ConvertFrom-Json).version)
    $YanxuWithoutBuild = ($ReportedYanxuVersion -split "\+", 2)[0]
    $YanxuCoreText = ($YanxuWithoutBuild -split "-", 2)[0]
    $YanxuCoreVersion = [version]$YanxuCoreText
} catch {
    throw "Yanbao installation failed: invalid installed Yanxu version report"
}
$MinimumYanxuVersion = [version]"1.1.17"
$MinimumPrerelease = $YanxuCoreVersion -eq $MinimumYanxuVersion -and $YanxuWithoutBuild.Contains("-")
if ($YanxuCoreVersion -lt $MinimumYanxuVersion -or $MinimumPrerelease) {
    throw "Yanbao installation failed: Yanxu 1.1.17 or newer is required; found $ReportedYanxuVersion"
}
try {
    $InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
} catch {
    throw "Yanbao installation failed: invalid installation directory: $($_.Exception.Message)"
}

$Architecture = if ($env:PROCESSOR_ARCHITEW6432) {
    $env:PROCESSOR_ARCHITEW6432
} else {
    $env:PROCESSOR_ARCHITECTURE
}
switch ($Architecture) {
    "AMD64" { $Target = "x86_64-pc-windows-msvc" }
    "ARM64" { $Target = "aarch64-pc-windows-msvc" }
    default { throw "Yanbao installation failed: unsupported processor architecture $Architecture" }
}

$Headers = @{}
if ($env:YANBAO_GITHUB_TOKEN) { $Headers.Authorization = "Bearer $($env:YANBAO_GITHUB_TOKEN)" }
$Asset = "yanbao-$Target.zip"
$ChecksumAsset = "yanbao-$Target.sha256"
if ($AssetDir -and $Version -eq "latest") {
    throw "Yanbao installation failed: YANBAO_VERSION is required when YANBAO_ASSET_DIR is set"
} elseif ($Version -eq "latest") {
    try {
        $ApiHeaders = @{
            Accept = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        if ($env:YANBAO_GITHUB_TOKEN) { $ApiHeaders.Authorization = "Bearer $($env:YANBAO_GITHUB_TOKEN)" }
        $Release = Invoke-RestMethod -Headers $ApiHeaders -Uri "https://api.github.com/repos/$Repository/releases/latest"
        if (-not $Release.tag_name) { throw "the repository has no installable release" }
        $Tag = $Release.tag_name
        $VersionLabel = "latest release $Tag"
    } catch {
        throw "Yanbao installation failed: could not query the latest release: $($_.Exception.Message)"
    }
} else {
    $Tag = if ($Version -match "^v") { $Version } else { "v$Version" }
    $VersionLabel = $Tag
}
$BaseUrl = "https://github.com/$Repository/releases/download/$Tag"
$ReleaseVersion = $Tag -replace "^v", ""

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("yanbao-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $TempDir | Out-Null
$Staged = @()

try {
    Write-Host "Installing Yanbao $VersionLabel ($Target)..."
    $ArchivePath = Join-Path $TempDir $Asset
    $ChecksumPath = Join-Path $TempDir $ChecksumAsset
    if ($AssetDir) {
        $LocalArchive = Join-Path $AssetDir $Asset
        $LocalChecksum = Join-Path $AssetDir $ChecksumAsset
        if (-not [System.IO.File]::Exists($LocalArchive)) {
            throw "local asset directory is missing $Asset"
        }
        if (-not [System.IO.File]::Exists($LocalChecksum)) {
            throw "local asset directory is missing $ChecksumAsset"
        }
        Copy-Item -LiteralPath $LocalArchive -Destination $ArchivePath
        Copy-Item -LiteralPath $LocalChecksum -Destination $ChecksumPath
    } else {
        Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri "$BaseUrl/$Asset" -OutFile $ArchivePath
        Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri "$BaseUrl/$ChecksumAsset" -OutFile $ChecksumPath
    }

    $Expected = ((Get-Content $ChecksumPath -Raw).Trim() -split "\s+")[0]
    if ($Expected -notmatch "^[0-9A-Fa-f]{64}$") { throw "invalid SHA-256 checksum file" }
    $Expected = $Expected.ToLowerInvariant()
    $Actual = Get-Sha256 $ArchivePath
    if ($Expected -ne $Actual) { throw "SHA-256 checksum mismatch" }
    Remove-Item Env:YANBAO_GITHUB_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:YANBAO_ASSET_DIR -ErrorAction SilentlyContinue

    $Expanded = Join-Path $TempDir "expanded"
    Expand-Archive -Path $ArchivePath -DestinationPath $Expanded
    $Required = @("yanbao.cmd", "yanbao.ps1", "yanbao-app.exe")
    foreach ($Name in $Required) {
        if (-not (Test-Path (Join-Path $Expanded $Name))) { throw "the release archive is missing $Name" }
    }

    $VersionProbe = Invoke-Utf8Process (Join-Path $Expanded "yanbao-app.exe") "--version"
    if ($VersionProbe.ExitCode -ne 0) { throw "the release archive cannot run with the installed Yanxu: $($VersionProbe.Text)" }
    $ProductName = [string]::Concat([char]0x8A00, [char]0x5305)
    $ExpectedVersion = "$ProductName $ReleaseVersion"
    if (@($VersionProbe.Text -split "\r?\n") -notcontains $ExpectedVersion) { throw "release archive version is not $ExpectedVersion" }
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    foreach ($Name in $Required) {
        $Temporary = Join-Path $InstallDir (".$Name." + [guid]::NewGuid() + ".tmp")
        Copy-Item (Join-Path $Expanded $Name) $Temporary
        $Staged += $Temporary
    }
    foreach ($Name in $Required) {
        $Temporary = $Staged | Where-Object { [System.IO.Path]::GetFileName($_).StartsWith(".$Name.") } | Select-Object -First 1
        Move-Item -Force $Temporary (Join-Path $InstallDir $Name)
        $Staged = @($Staged | Where-Object { $_ -ne $Temporary })
    }

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathParts = @($UserPath -split ";" | Where-Object { $_ })
    if ($PathParts -notcontains $InstallDir) {
        [Environment]::SetEnvironmentVariable("Path", (($PathParts + $InstallDir) -join ";"), "User")
        Write-Host "Added $InstallDir to the user PATH; it will be available in new terminals."
    }
    if (@($env:Path -split ";") -notcontains $InstallDir) { $env:Path = "$env:Path;$InstallDir" }
    $InstalledVersion = Invoke-Utf8Process (Join-Path $InstallDir "yanbao-app.exe") "--version"
    if ($InstalledVersion.ExitCode -ne 0) { throw "post-install verification failed: $($InstalledVersion.Text)" }
    Write-Host "Yanbao was installed to $InstallDir"
    Write-Host "Verified: $($InstalledVersion.Text -replace '[\r\n]+', ' ')"
} catch {
    Write-Error "Yanbao installation failed: $($_.Exception.Message)"
    exit 1
} finally {
    foreach ($Path in $Staged) { Remove-Item -Force -ErrorAction SilentlyContinue $Path }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TempDir
}
