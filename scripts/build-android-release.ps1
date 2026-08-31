# Build van3 Android release APK (rider app).
# Requires android/key.properties — see android/key.properties.example
param(
    [switch]$SkipClean,
    [switch]$AllowDebugSigning
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$keyProps = Join-Path $root 'android\key.properties'
$usingDebugSigning = -not (Test-Path $keyProps)
if ($usingDebugSigning -and -not $AllowDebugSigning) {
    Write-Error @"
Missing android/key.properties — copy from android/key.properties.example before store release.
For internal QA only, rerun with -AllowDebugSigning (uses debug keystore; not for Play Store).
"@
}
if ($usingDebugSigning) {
    Write-Warning 'Building with debug signing — OK for QA sideload, NOT for Play Store upload.'
}

if (-not $SkipClean) {
    flutter pub get
}

$version = (Select-String -Path (Join-Path $root 'pubspec.yaml') -Pattern '^version:\s*(.+)$').Matches.Groups[1].Value.Trim()
$releasesDir = Join-Path $root 'releases'
if (-not (Test-Path $releasesDir)) {
    New-Item -ItemType Directory -Path $releasesDir | Out-Null
}

flutter build apk --release --no-pub -PfirebaseCrashlyticsMappingFileUploadEnabled=false
if ($LASTEXITCODE -ne 0) {
    throw 'flutter build apk --release failed'
}
$apkSrc = Join-Path $root 'build\app\outputs\flutter-apk\app-release.apk'
if (-not (Test-Path $apkSrc)) {
    throw "Missing release APK at $apkSrc"
}
$apkDst = Join-Path $releasesDir "van3-$version-release.apk"
Copy-Item $apkSrc $apkDst -Force
Write-Host "APK: $apkDst"
