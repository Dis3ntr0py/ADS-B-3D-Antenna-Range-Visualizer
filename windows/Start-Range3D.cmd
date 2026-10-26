@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Range3D.ps1" %*
if errorlevel 1 (
  echo.
  echo Range3D collector stopped with an error. See the message above.
  pause
)
endlocal
