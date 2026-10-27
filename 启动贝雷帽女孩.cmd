@echo off
chcp 65001 >nul
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\Install-And-Run.ps1"
if errorlevel 1 (
  echo.
  echo 启动未完成，请查看上面的提示。请先完整解压 ZIP，再双击此文件。
  pause
  exit /b 1
)
exit /b 0

