from pathlib import Path
from datetime import datetime, timezone
import json, secrets
from cryptography import x509
from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT/'work/aqua_hatch' if (ROOT/'work/aqua_hatch').exists() else ROOT/'aqua_hatch'
PRIVATE = ROOT/'work/private' if (ROOT/'work').exists() else ROOT/'private'
PRIVATE.mkdir(parents=True,exist_ok=True)
FIRMWARE = APP/'firmware/local_server'
FIRMWARE.mkdir(parents=True,exist_ok=True)
ASSETS = APP/'assets/device'
ASSETS.mkdir(parents=True,exist_ok=True)
(ROOT/'outputs').mkdir(exist_ok=True)
hostname = 'aquahatch-117c.local'
config_path = PRIVATE / 'device.json'
if config_path.exists():
    config = json.loads(config_path.read_text())
else:
    config = {'hostname': hostname, 'device_id': 'incubator-01', 'token': secrets.token_urlsafe(24)}
    config_path.write_text(json.dumps(config, indent=2))
ca_path = PRIVATE / 'device_ca.pem'
if not ca_path.exists():
    ca_key = ec.generate_private_key(ec.SECP256R1())
    ca_name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'AquaHatch device 117C private CA')])
    ca = (x509.CertificateBuilder().subject_name(ca_name).issuer_name(ca_name)
          .public_key(ca_key.public_key()).serial_number(x509.random_serial_number())
          .not_valid_before(datetime(2025, 1, 1, tzinfo=timezone.utc))
          .not_valid_after(datetime(2036, 1, 1, tzinfo=timezone.utc))
          .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
          .add_extension(x509.KeyUsage(digital_signature=True, key_encipherment=False,
              content_commitment=False,data_encipherment=False,key_agreement=False,
              key_cert_sign=True,crl_sign=True,encipher_only=None,decipher_only=None),critical=True)
          .sign(ca_key, hashes.SHA256()))
    key = ec.generate_private_key(ec.SECP256R1())
    cert = (x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, hostname)]))
            .issuer_name(ca.subject).public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(datetime(2025,1,1,tzinfo=timezone.utc))
            .not_valid_after(datetime(2035,1,1,tzinfo=timezone.utc))
            .add_extension(x509.BasicConstraints(ca=False,path_length=None),critical=True)
            .add_extension(x509.SubjectAlternativeName([x509.DNSName(hostname)]),critical=False)
            .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]),critical=False)
            .sign(ca_key, hashes.SHA256()))
    for name, data in [('device_ca.pem', ca.public_bytes(serialization.Encoding.PEM)),
          ('server.pem', cert.public_bytes(serialization.Encoding.PEM)),
          ('server-key.pem', key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.TraditionalOpenSSL,serialization.NoEncryption())),
          ('ca-key.pem', ca_key.private_bytes(serialization.Encoding.PEM,serialization.PrivateFormat.TraditionalOpenSSL,serialization.NoEncryption()))]:
        (PRIVATE/name).write_bytes(data)
header = '#pragma once\n'
for name, value in [('DEVICE_ID', config['device_id']), ('DEVICE_HOSTNAME', hostname), ('API_TOKEN', config['token'])]:
    header += 'static const char '+name+'[] = '+json.dumps(value)+';\n'
for name, filename in [('SERVER_CERT','server.pem'), ('SERVER_KEY','server-key.pem')]:
    header += 'static const char '+name+'[] = R"PEM('+ (PRIVATE/filename).read_text() + ')PEM";\n'
(FIRMWARE/'device_private.h').write_text(header)
(ASSETS/'device_ca.pem').write_bytes(ca_path.read_bytes())
(ROOT/'outputs/DEVICE_CONNECTION_PRIVATE.md').write_text(
    '# เชื่อมต่อบอร์ดตัวนี้\n\nรหัสเครื่อง: `'+config['device_id']+'`\n\nรหัสเข้าถึง: `'+config['token']+'`\n\n'
    'กรอก URL ที่หน้าตั้งค่า Wi-Fi รายงาน เช่น https://192.168.1.xxx และเลือก “ESP32 ในบ้าน” ในแอปรุ่น 0.5\n'
    'ใบรับรองในแอปใช้กับบอร์ดตัวนี้เท่านั้น อย่าเผยแพร่ไฟล์รหัสนี้\n', encoding='utf-8')
print('Prepared unique device certificate and app trust anchor; credentials remain local.')
