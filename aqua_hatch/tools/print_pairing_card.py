"""Create a private, printable pairing card; never include it in a public release ZIP."""
from pathlib import Path
import hashlib
import html
import json

app=Path(__file__).resolve().parent.parent
root=app.parent.parent if app.parent.name=='work' else app.parent
private=root/'work/private' if (root/'work/private').exists() else root/'private'
output=root/'outputs'; output.mkdir(exist_ok=True)
device=json.loads((private/'device.json').read_text())
code=device['token']; password=hashlib.sha256(('AquaHatch setup v1:'+code).encode()).hexdigest()[:16]
card='''<!doctype html><html lang="th"><meta charset="utf-8"><title>AquaHatch — บัตรจับคู่ส่วนตัว</title>
<style>body{font:18px/1.7 "Segoe UI",sans-serif;background:#f2f7f8;color:#16354b;margin:40px}.card{max-width:650px;margin:auto;background:white;border:2px solid #087d86;border-radius:20px;padding:32px}h1{margin:0;color:#087d86}code{display:block;font:20px/1.6 monospace;overflow-wrap:anywhere;background:#edf7f6;padding:12px;border-radius:8px}label{display:block;margin-top:20px;font-weight:bold}small{display:block;margin-top:24px;color:#526775}@media print{body{background:white;margin:0}.card{break-inside:avoid}}</style>
<div class="card"><h1>AquaHatch</h1><p>บัตรจับคู่ประจำเครื่อง — เก็บส่วนตัว</p>
<label>รหัสเครื่อง</label><code>__DEVICE__</code>
<label>รหัสจับคู่ — ใส่ในแอปครั้งแรก</label><code>__CODE__</code>
<label>Wi-Fi สำหรับตั้งค่าบอร์ด</label><code>AquaHatch-117C</code>
<label>รหัส Wi-Fi บอร์ด</label><code>__PASSWORD__</code>
<p>จ่ายไฟให้บอร์ด → แอป AquaHatch → ตั้งค่า → ตั้ง Wi-Fi ให้บอร์ด → ทำตามขั้นตอนในแอป</p>
<small>รหัสจับคู่และรหัส Wi-Fi บอร์ดเป็นคนละรหัสกับ Wi-Fi บ้าน ใช้กับบอร์ดและแอปที่จับคู่ใบรับรองไว้แล้ว พิมพ์เก็บกับเครื่องเพื่อเริ่มตั้งค่าได้โดยไม่เปิดคอม</small></div></html>'''
for key,value in [('__DEVICE__',device['device_id']),('__CODE__',code),('__PASSWORD__',password)]:
    card=card.replace(key,html.escape(value))
(output/'DEVICE_PAIRING_PRIVATE.html').write_text(card,encoding='utf-8')
print('Private pairing card created; credentials were not logged.')
