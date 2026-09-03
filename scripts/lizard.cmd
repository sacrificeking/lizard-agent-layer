@echo off
setlocal
where pwsh >nul 2>nul
if %ERRORLEVEL% equ 0 (
    pwsh -NoProfile -File "%~dp0lizard.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0lizard.ps1" %*
)
exit /b %ERRORLEVEL%
