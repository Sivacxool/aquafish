param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Invoke-FlutterStep([string[]]$Arguments) {
    & $Flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Flutter step failed: $($Arguments -join ' ')" }
}
Invoke-FlutterStep -Arguments @('pub', 'get')
Invoke-FlutterStep -Arguments @('analyze')
Invoke-FlutterStep -Arguments @('test')
Invoke-FlutterStep -Arguments @('build', 'apk', '--release', '--split-per-abi')
Write-Host 'APK: build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
Write-Host 'Signed with a development key unless a release signer is configured.'
