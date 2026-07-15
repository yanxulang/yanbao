@echo off
setlocal
if "%YANXU_BIN%"=="" (
  if exist "%~dp0yanxu-1.1.5.exe" (set "YANXU=%~dp0yanxu-1.1.5.exe") else (set "YANXU=yanxu")
) else (set "YANXU=%YANXU_BIN%")
if exist "%~dp0yanbao-app.exe" if exist "%~dp0yanxu-1.1.5.exe" (
  set "YANXU_BIN=%YANXU%"
  "%~dp0yanbao-app.exe" %*
) else (
  "%YANXU%" "%~dp0src\主.yx" -- %*
)
exit /b %ERRORLEVEL%
