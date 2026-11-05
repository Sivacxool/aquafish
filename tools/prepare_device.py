from pathlib import Path
import argparse
from device_certificates import ensure_certificates
import json, secrets

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
parser=argparse.ArgumentParser()
parser.add_argument('--renew-certificate', action='store_true')
args=parser.parse_args()
ensure_certificates(PRIVATE, 'device_ca.pem', 'AquaHatch device 117C private CA',
                    hostname, renew=args.renew_certificate)
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
