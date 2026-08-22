@echo off
REM Run playtorrio.exe and capture stdout/stderr to playtorrio-console.log
REM Usage: scripts\run_windows.bat <path-to-release-folder>
if "%1"=="" (
  set RELEASE_DIR=build\windows\x64\runner\Release
) else (
  set RELEASE_DIR=%~1
)
if not exist "%RELEASE_DIR%\playtorrio.exe" (
  echo playtorrio.exe not found in %RELEASE_DIR%
  exit /b 1
)
echo Running playtorrio.exe from %RELEASE_DIR%
pushd "%RELEASE_DIR%"
:: Run and capture output to log (PowerShell redirection to capture console output from GUI apps)
powershell -Command "Start-Process -FilePath '.\\playtorrio.exe' -RedirectStandardOutput 'playtorrio-console.log' -RedirectStandardError 'playtorrio-console.log' -NoNewWindow -Wait"
if %ERRORLEVEL% NEQ 0 (
  echo Application exited with code %ERRORLEVEL%
) else (
  echo Application exited normally. Log: %RELEASE_DIR%\\playtorrio-console.log
)
popd
exit /b 0
