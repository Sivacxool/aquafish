param(
  [string]$ArduinoCli = "$env:LOCALAPPDATA\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe",
  [string]$Port = 'COM4',
  [switch]$Upload
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'device_private.h'))) {
  throw 'Generate the camera private header and matching public app certificate first.'
}
# Verified assembly: classic ESP32-S / ESP32-CAM-MB, 4 MB flash, 4 MB PSRAM.
# This target is different from the main ESP32-S3 controller.
$cameraBoard = 'esp32:esp32:esp32cam'
$binaryDirectory = Join-Path $PSScriptRoot 'build'
& $ArduinoCli compile --fqbn $cameraBoard --output-dir $binaryDirectory $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'Camera build failed.' }
if ($Upload) {
  & $ArduinoCli upload --fqbn $cameraBoard --port $Port --input-dir $binaryDirectory $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Camera upload failed.' }
}
