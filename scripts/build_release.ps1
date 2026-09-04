# ──────────────────────────────────────────────────────────────────────────────
#  PlayTorrioV3 — Local Release Checksum Helper
#  Generates a SHA256SUMS file for all release artifacts in a directory,
#  mirroring what the CI workflow (.github/workflows/build.yml) does before
#  publishing a GitHub release. Use this to verify local builds before
#  pushing a release tag.
#
#  Usage:
#    powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1
#    powershell -ExecutionPolicy Bypass -File scripts\build_release.ps1 -Dir build\releases
# ──────────────────────────────────────────────────────────────────────────────
param(
    [string]$Dir = "build\releases"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $Dir)) {
    Write-Error "Directory not found: $Dir"
    exit 1
}

$extensions = @("*.exe", "*.zip", "*.apk", "*.AppImage", "*.tar.gz", "*.dmg", "*.ipa")
$files = Get-ChildItem -Path $Dir -File | Where-Object {
    $name = $_.Name
    $extensions | Where-Object { $name -like $_ }
}

if ($files.Count -eq 0) {
    Write-Error "No release artifacts found in $Dir"
    exit 1
}

$lines = foreach ($file in $files) {
    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToLower()
    "$hash  $($file.Name)"
}

$outPath = Join-Path $Dir "SHA256SUMS"
$lines | Out-File -FilePath $outPath -Encoding ascii
Write-Host "Generated $outPath with $($files.Count) checksums:"
$lines | ForEach-Object { Write-Host "  $_" }
exit 0