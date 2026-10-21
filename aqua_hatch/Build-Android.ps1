param([string]$Flutter = 'flutter', [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'tools/Build-Android.ps1') -Flutter $Flutter -Python $Python
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
