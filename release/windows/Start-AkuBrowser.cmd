@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-AkuBrowser.ps1" %*
exit /b %ERRORLEVEL%
