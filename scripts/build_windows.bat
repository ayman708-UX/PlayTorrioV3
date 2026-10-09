@echo off
REM Build Windows release and package full Release folder into a zip for local QA.
REM Usage: scripts\build_windows.bat [version]
REM   version  optional version string used in the zip name (default: timestamp).
REM           Use the same name as CI: PlayTorrio-Windows-x64-Portable.zip

echo Building Windows release (flutter build windows --release)...
flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
  echo Build failed with exit code %ERRORLEVEL%.
  exit /b %ERRORLEVEL%
)

set RELEASE_DIR=build\windows\x64\runner\Release
set OUTPUT_DIR=build\releases

if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"

if "%~1"=="" (
  set TIMESTAMP=%DATE:~10,4%-%DATE:~4,2%-%DATE:~7,2%_%TIME:~0,2%-%TIME:~3,2%-%TIME:~6,2%
  set TIMESTAMP=%TIMESTAMP: =0%
  set ZIP_NAME=playtorrio-windows-x64-%TIMESTAMP%.zip
) else (
  set ZIP_NAME=PlayTorrio-Windows-x64-Portable.zip
)

echo Packaging "%RELEASE_DIR%" -> "%OUTPUT_DIR%\%ZIP_NAME%" ...
powershell -Command "Compress-Archive -Path '%RELEASE_DIR%\*' -DestinationPath '%OUTPUT_DIR%\%ZIP_NAME%' -Force"
if %ERRORLEVEL% NEQ 0 (
  echo Packaging failed.
  exit /b %ERRORLEVEL%
)

echo Generating SHA-256 checksum...
powershell -Command "Get-FileHash '%OUTPUT_DIR%\%ZIP_NAME%' -Algorithm SHA256 | Select-Object -ExpandProperty Hash | Out-File -FilePath '%OUTPUT_DIR%\%ZIP_NAME%.sha256' -Encoding ascii"
if %ERRORLEVEL% NEQ 0 (
  echo Checksum generation failed.
  exit /b %ERRORLEVEL%
)

echo Done. Created: %OUTPUT_DIR%\%ZIP_NAME%
echo Checksum: %OUTPUT_DIR%\%ZIP_NAME%.sha256
exit /b 0