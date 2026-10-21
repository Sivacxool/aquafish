param([string]$Flutter = 'flutter', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    # Compile every ABI included by Flutter's default release packaging.
    & $Flutter build apk --release --target-platform android-arm,android-arm64,android-x64
    if ($LASTEXITCODE -ne 0) { throw 'Android build failed' }
    & $Python tools/check_apk_abis.py build/app/outputs/flutter-apk/app-release.apk --expected armeabi-v7a arm64-v8a x86_64
    if ($LASTEXITCODE -ne 0) { throw 'APK ABI verification failed' }
} finally { Pop-Location }
