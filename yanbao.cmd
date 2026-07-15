@echo off
setlocal
if "%YANXU_BIN%"=="" (set "YANXU=yanxu") else (set "YANXU=%YANXU_BIN%")
where "%YANXU%" >nul 2>nul
if errorlevel 1 (
  echo 言包需要言序 1.1.6 或更高版本；请先安装 yanxu，或通过 YANXU_BIN 指定其路径。 1>&2
  exit /b 1
)
if exist "%~dp0yanbao-app.exe" (
  set "YANXU_BIN=%YANXU%"
  "%~dp0yanbao-app.exe" %*
) else (
  "%YANXU%" "%~dp0src\主.yx" -- %*
)
exit /b %ERRORLEVEL%
