param(
  [string]$ArduinoCli = "$env:LOCALAPPDATA\Programs\Arduino IDE\resources\app\lib\backend\resources\arduino-cli.exe",
  [string]$Port,
  [ValidateSet('wroom-da','ett32ue','ett32ue-b0434-test')][string]$Profile = 'wroom-da',
  [string]$BuildPath,
  [string]$OutputDirectory,
  [switch]$Upload
)
$ErrorActionPreference = 'Stop'
if ($Upload -and $Port -notmatch '^COM[1-9][0-9]*$') {
  throw 'Specify the connected controller port with -Upload -Port COM5 (use the actual port).'
}

$options = 'FlashSize=4M,FlashMode=dio,FlashFreq=40,PartitionScheme=min_spiffs,UploadSpeed=115200'
$board = "esp32:esp32:esp32da:$options"
$profileFlags = @()
if ($Profile -like 'ett32ue*') {
  $board = "esp32:esp32:esp32:$options"
  $defines = '-DAQUAHATCH_ET_WROOM32UE=1'
  if ($Profile -eq 'ett32ue-b0434-test') { $defines += ' -DAQUAHATCH_B0434_TEST=1' }
  $profileFlags = @('--build-property', "compiler.cpp.extra_flags=$defines")
}
$buildOptions = @()
if ($BuildPath) { $buildOptions = @('--build-path', $BuildPath) }
if (!$OutputDirectory) {
  $folder = if ($Profile -like 'ett32ue*') { "build/$Profile" } else { 'build' }
  $OutputDirectory = Join-Path $PSScriptRoot $folder
}
& $ArduinoCli compile @profileFlags @buildOptions --libraries (Join-Path $PSScriptRoot "../libraries") --fqbn $board --output-dir $OutputDirectory $PSScriptRoot
if ($LASTEXITCODE -ne 0) { throw 'Firmware compile failed.' }
if ($Upload) {
  & $ArduinoCli upload --port $Port --fqbn $board --input-dir $OutputDirectory $PSScriptRoot
  if ($LASTEXITCODE -ne 0) { throw 'Firmware upload failed.' }
}
