$ErrorActionPreference = "Stop"

$Repository = if ($env:YANBAO_REPOSITORY) { $env:YANBAO_REPOSITORY } else { "YanXuLang/yanbao" }
$Version = if ($env:YANBAO_VERSION) { $env:YANBAO_VERSION } else { "latest" }
$InstallDir = if ($env:YANBAO_INSTALL_DIR) { $env:YANBAO_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "Programs\Yanbao\bin" }
$Yanxu = if ($env:YANXU_BIN) { $env:YANXU_BIN } else { "yanxu" }
if (-not (Get-Command $Yanxu -ErrorAction SilentlyContinue)) {
    throw "言包安装失败：需要先安装言序 1.1.6 或更高版本（yanxu），也可通过 YANXU_BIN 指定其路径"
}
$env:YANXU_BIN = $Yanxu
try {
    $InstallDir = [System.IO.Path]::GetFullPath($InstallDir)
} catch {
    throw "言包安装失败：安装目录无效：$($_.Exception.Message)"
}

$Architecture = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($Architecture) {
    "X64" { $Target = "x86_64-pc-windows-msvc" }
    "Arm64" { $Target = "aarch64-pc-windows-msvc" }
    default { throw "言包安装失败：暂不支持处理器架构 $Architecture" }
}

$Headers = @{}
if ($env:YANBAO_GITHUB_TOKEN) { $Headers.Authorization = "Bearer $($env:YANBAO_GITHUB_TOKEN)" }
$Asset = "yanbao-$Target.zip"
$ChecksumAsset = "yanbao-$Target.sha256"
if ($Version -eq "latest") {
    try {
        $ApiHeaders = @{
            Accept = "application/vnd.github+json"
            "X-GitHub-Api-Version" = "2022-11-28"
        }
        if ($env:YANBAO_GITHUB_TOKEN) { $ApiHeaders.Authorization = "Bearer $($env:YANBAO_GITHUB_TOKEN)" }
        $Release = Invoke-RestMethod -Headers $ApiHeaders -Uri "https://api.github.com/repos/$Repository/releases/latest"
        if (-not $Release.tag_name) { throw "仓库尚未发布可安装版本" }
        $Tag = $Release.tag_name
        $VersionLabel = "最新版 $Tag"
    } catch {
        throw "言包安装失败：无法查询最新发行版：$($_.Exception.Message)"
    }
} else {
    $Tag = if ($Version.StartsWith("v")) { $Version } else { "v$Version" }
    $VersionLabel = $Tag
}
$BaseUrl = "https://github.com/$Repository/releases/download/$Tag"
$ReleaseVersion = if ($Tag.StartsWith("v")) { $Tag.Substring(1) } else { $Tag }

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("yanbao-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $TempDir | Out-Null
$Staged = @()

try {
    Write-Host "正在安装言包 $VersionLabel（$Target）…"
    $ArchivePath = Join-Path $TempDir $Asset
    $ChecksumPath = Join-Path $TempDir $ChecksumAsset
    Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri "$BaseUrl/$Asset" -OutFile $ArchivePath
    Invoke-WebRequest -UseBasicParsing -Headers $Headers -Uri "$BaseUrl/$ChecksumAsset" -OutFile $ChecksumPath

    $Expected = ((Get-Content $ChecksumPath -Raw).Trim() -split "\s+")[0]
    if ($Expected -notmatch "^[0-9A-Fa-f]{64}$") { throw "SHA-256 校验文件格式无效" }
    $Expected = $Expected.ToLowerInvariant()
    $Actual = (Get-FileHash -Algorithm SHA256 $ArchivePath).Hash.ToLowerInvariant()
    if ($Expected -ne $Actual) { throw "SHA-256 校验不一致" }

    $Expanded = Join-Path $TempDir "expanded"
    Expand-Archive -Path $ArchivePath -DestinationPath $Expanded
    $Required = @("yanbao.cmd", "yanbao.ps1", "yanbao-app.exe")
    foreach ($Name in $Required) {
        if (-not (Test-Path (Join-Path $Expanded $Name))) { throw "发行包缺少 $Name" }
    }

    $VersionOutput = @(& (Join-Path $Expanded "yanbao.cmd") --version 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "发行包不能使用本机言序运行：$($VersionOutput -join [Environment]::NewLine)" }
    if ($VersionOutput -notcontains "言包 $ReleaseVersion") { throw "发行包版本不是言包 $ReleaseVersion" }
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
        Write-Host "已把 $InstallDir 加入用户 PATH；新终端会自动生效。"
    }
    if (@($env:Path -split ";") -notcontains $InstallDir) { $env:Path = "$env:Path;$InstallDir" }
    $InstalledVersion = @(& (Join-Path $InstallDir "yanbao.cmd") --version 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "安装后验证失败：$($InstalledVersion -join [Environment]::NewLine)" }
    Write-Host "言包已安装到 $InstallDir"
    Write-Host "已验证：$($InstalledVersion -join ' ')"
} catch {
    Write-Error "言包安装失败：$($_.Exception.Message)"
    exit 1
} finally {
    foreach ($Path in $Staged) { Remove-Item -Force -ErrorAction SilentlyContinue $Path }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TempDir
}
