param(
  [string]$ArduinoCli = "$env:LOCALAPPDATA\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe",
  [string]$Port = "COM3",
  [switch]$Upload
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'device_private.h'))) {
  throw 'Generate device_private.h and the matching app CA with tools/prepare_device.py first.'
}
$board = 'esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,FlashMode=qio,PartitionScheme=app3M_fat9M_16MB,CDCOnBoot=default,UploadSpeed=921600'
$binaryDirectory = Join-Path $PSScriptRoot 'build'
& $ArduinoCli compile --fqbn $board --output-dir $binaryDirectory $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'Firmware compile failed.' }
if ($Upload) {
  & $ArduinoCli upload --port $Port --fqbn $board --input-dir $binaryDirectory $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Firmware upload failed.' }
}
