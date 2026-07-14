@echo off
setlocal
if "%YANXU_BIN%"=="" (set "YANXU=yanxu") else (set "YANXU=%YANXU_BIN%")
"%YANXU%" "%~dp0src\主.yx" -- %*
exit /b %ERRORLEVEL%
