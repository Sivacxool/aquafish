param(
  [string]$ArduinoCli = "$env:LOCALAPPDATA\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe",
  [string]$Port,
  [string]$BuildPath,
  [string]$OutputDirectory,
  [switch]$Upload
)
$ErrorActionPreference = 'Stop'
if ($Upload -and $Port -notmatch '^COM[1-9][0-9]*$') {
  throw 'Specify the camera port with -Upload -Port COMx (use its actual port).'
}

# Verified assembly: classic ESP32-S / ESP32-CAM-MB, 4 MB flash, 4 MB PSRAM.
# This target is different from the main ESP32-WROOM-DA controller.
$cameraBoard = 'esp32:esp32:esp32cam'
$binaryDirectory = if ($OutputDirectory) { $OutputDirectory } else { Join-Path $PSScriptRoot 'build' }
$buildOptions = @()
if ($BuildPath) { $buildOptions = @('--build-path', $BuildPath) }
& $ArduinoCli compile @buildOptions --libraries (Join-Path $PSScriptRoot "../libraries") --fqbn $cameraBoard --output-dir $binaryDirectory $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'Camera build failed.' }
if ($Upload) {
  & $ArduinoCli upload --fqbn $cameraBoard --port $Port --input-dir $binaryDirectory $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Camera upload failed.' }
}
