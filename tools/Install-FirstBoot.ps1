param(
  [Parameter(Mandatory=$true)][ValidateSet('s3','camera')][string]$Kind,
  [string]$Port,
  [switch]$ReadOnly
)
$ErrorActionPreference='Stop'
$bundleRoot=Split-Path -Parent $PSScriptRoot
if (!$Port) { $Port=Read-Host 'พอร์ตของบอร์ด เช่น COM3 (ต่อทีละบอร์ด และปิด Serial Monitor)' }
if ($Port -notmatch '^COM[1-9][0-9]*$') { throw 'พอร์ตต้องเป็น COM ตามด้วยตัวเลข เช่น COM3' }
$pythonCandidate=Join-Path $env:USERPROFILE '.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if (Test-Path -LiteralPath $pythonCandidate) { $pythonExe=$pythonCandidate }
elseif (Get-Command python -ErrorAction SilentlyContinue) { $pythonExe=(Get-Command python).Source }
else { throw 'ติดตั้ง Python 3.11 ขึ้นไปก่อน แล้วเปิดไฟล์นี้ใหม่' }
$venvPath=Join-Path $bundleRoot '.venv-pairing'
$venvPython=Join-Path $venvPath 'Scripts\python.exe'
if (!(Test-Path -LiteralPath $venvPython)) {
  & $pythonExe -m venv $venvPath
  if ($LASTEXITCODE -ne 0) { throw 'เตรียม Python ไม่สำเร็จ' }
}
& $venvPython -m pip install -r (Join-Path $PSScriptRoot 'pairing-requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'เตรียมโปรแกรมรับ QR ไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองใหม่' }
$pairArgs=@('-X','utf8',(Join-Path $PSScriptRoot 'pairing_card.py'),'--kind',$Kind,'--port',$Port)
if ($ReadOnly) { $pairArgs+='--read-only' }
& $venvPython @pairArgs
if ($LASTEXITCODE -ne 0) { throw 'ติดตั้งหรืออ่านบัตร QR ไม่สำเร็จ' }
