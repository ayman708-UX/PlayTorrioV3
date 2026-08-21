@echo off
REM Build Windows release and package full Release folder into a zip for local QA.
REM Usage: scripts\build_windows.bat

echo Building Windows release (flutter build windows --release)...
flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
  echo Build failed with exit code %ERRORLEVEL%.
  exit /b %ERRORLEVEL%
)

set RELEASE_DIR=build\windows\x64\runner\Release
set OUTPUT_DIR=build\releases

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

set TIMESTAMP=%DATE:~10,4%-%DATE:~4,2%-%DATE:~7,2%_%TIME:~0,2%-%TIME:~3,2%-%TIME:~6,2%
set TIMESTAMP=%TIMESTAMP: =0%
set ZIP_NAME=playtorrio-windows-x64-%TIMESTAMP%.zip

echo Packaging "%RELEASE_DIR%" -> "%OUTPUT_DIR%\%ZIP_NAME%" ...
powershell -Command "Compress-Archive -Path '%RELEASE_DIR%\*' -DestinationPath '%OUTPUT_DIR%\%ZIP_NAME%' -Force"
if %ERRORLEVEL% NEQ 0 (
  echo Packaging failed.
  exit /b %ERRORLEVEL%
)

echo Done. Created: %OUTPUT_DIR%\%ZIP_NAME%
exit /b 0
