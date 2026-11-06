param(
  [string]$ArduinoCli = "$env:LOCALAPPDATA\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe",
  [string]$Port,
  [switch]$Upload
)
$ErrorActionPreference = 'Stop'
if ($Upload -and $Port -notmatch '^COM[1-9][0-9]*$') {
  throw 'Specify the connected WROOM-DA port with -Upload -Port COM5 (use the actual port).'
}

$board = 'esp32:esp32:esp32da:FlashSize=4M,FlashMode=dio,FlashFreq=40,PartitionScheme=min_spiffs,UploadSpeed=115200'
$binaryDirectory = Join-Path $PSScriptRoot 'build'
& $ArduinoCli compile --libraries (Join-Path $PSScriptRoot "../libraries") --fqbn $board --output-dir $binaryDirectory $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'Firmware compile failed.' }
if ($Upload) {
  & $ArduinoCli upload --port $Port --fqbn $board --input-dir $binaryDirectory $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Firmware upload failed.' }
}
