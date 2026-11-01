from pathlib import Path
from datetime import datetime, timezone
import hashlib, html, json, secrets
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT=Path(__file__).resolve().parent.parent
APP=ROOT/'work/aqua_hatch' if (ROOT/'work/aqua_hatch').exists() else ROOT/'aqua_hatch'
PRIVATE=ROOT/'work/private/camera' if (ROOT/'work').exists() else ROOT/'private/camera'
PRIVATE.mkdir(parents=True,exist_ok=True)
firmware=APP/'firmware/camera_server'; firmware.mkdir(exist_ok=True)
identity=PRIVATE/'identity.json'
if not identity.exists():
    identity.write_text(json.dumps({'hostname':'aquahatch-camera-7c60.local','device_id':'camera-7c60',
      'ap_ssid':'AquaHatch-CAM-7C60','token':secrets.token_urlsafe(24)},indent=2))
device=json.loads(identity.read_text())
if not (PRIVATE/'server.pem').exists():
    ca_key=ec.generate_private_key(ec.SECP256R1()); key=ec.generate_private_key(ec.SECP256R1())
    ca_name=x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,'AquaHatch camera 7C60 private CA')])
    ca=(x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name).public_key(ca_key.public_key())
        .serial_number(x509.random_serial_number()).not_valid_before(datetime(2025,1,1,tzinfo=timezone.utc))
        .not_valid_after(datetime(2036,1,1,tzinfo=timezone.utc)).add_extension(x509.BasicConstraints(ca=True,path_length=0),True)
        .sign(ca_key,hashes.SHA256()))
    cert=(x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME,device['hostname'])]))
        .issuer_name(ca_name).public_key(key.public_key()).serial_number(x509.random_serial_number())
        .not_valid_before(datetime(2025,1,1,tzinfo=timezone.utc)).not_valid_after(datetime(2035,1,1,tzinfo=timezone.utc))
        .add_extension(x509.BasicConstraints(ca=False,path_length=None),True)
        .add_extension(x509.SubjectAlternativeName([x509.DNSName(device['hostname'])]),False)
        .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),False).sign(ca_key,hashes.SHA256()))
    for name, value in [('camera_ca.pem',ca.public_bytes(serialization.Encoding.PEM)),('server.pem',cert.public_bytes(serialization.Encoding.PEM)),
       ('server-key.pem',key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.TraditionalOpenSSL,serialization.NoEncryption()))]:
        (PRIVATE/name).write_bytes(value)
header='#pragma once\n'
for name,value in [('DEVICE_ID',device['device_id']),('DEVICE_HOSTNAME',device['hostname']),('API_TOKEN',device['token'])]:
    header+='static const char '+name+'[] = '+json.dumps(value)+';\n'
for name,filename in [('SERVER_CERT','server.pem'),('SERVER_KEY','server-key.pem')]:
    header+='static const char '+name+'[] = R"PEM('+(PRIVATE/filename).read_text()+')PEM";\n'
(firmware/'device_private.h').write_text(header)
(APP/'assets/device/camera_ca.pem').write_bytes((PRIVATE/'camera_ca.pem').read_bytes())
(APP/'lib/core/paired_camera.dart').write_text(
    "// Public identity only. The bearer token is never embedded in the app.\n"
    f"const cameraTlsHostname = '{device['hostname']}';\n"
    f"const cameraDeviceId = '{device['device_id']}';\n"
    f"const cameraSetupNetworkName = '{device['ap_ssid']}';\n"
    "const cameraCaAsset = 'assets/device/camera_ca.pem';\n")
wifi=(firmware/'wifi_setup.h').read_text(encoding='utf-8')
start=wifi.index('String apName=')
end=wifi.index(';',start)+1
wifi=wifi[:start]+'String apName='+json.dumps(device['ap_ssid'])+';'+wifi[end:]
(firmware/'wifi_setup.h').write_text(wifi,encoding='utf-8')
password=hashlib.sha256(('AquaHatch setup v1:'+device['token']).encode()).hexdigest()[:16]
card=f'''<!doctype html><meta charset="utf-8"><title>บัตรจับคู่กล้อง AquaHatch</title><style>body{{font:20px/1.7 sans-serif;max-width:700px;margin:40px auto;color:#153c4a}}code{{display:block;background:#edf7f6;padding:12px;overflow-wrap:anywhere}}h1{{color:#087d86}}</style>
<h1>บัตรกล้อง — เก็บเป็นส่วนตัว</h1><p>รหัสกล้อง</p><code>{html.escape(device['device_id'])}</code>
<p>รหัสจับคู่กล้อง</p><code>{html.escape(device['token'])}</code><p>Wi-Fi ตั้งค่ากล้อง</p><code>{device['ap_ssid']}</code><p>รหัส Wi-Fi กล้อง</p><code>{password}</code>
<p>ใช้แอป AquaHatch → ตั้งค่า → ตั้ง Wi-Fi ให้กล้อง รหัสนี้แยกจากบอร์ดควบคุมหลัก</p>'''
(ROOT/'outputs/CAMERA_PAIRING_PRIVATE.html').write_text(card,encoding='utf-8')
print('Prepared separate camera certificate and public app identity. Private pairing remains local.')
