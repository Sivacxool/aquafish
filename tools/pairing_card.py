"""Flash generic firmware, then retrieve the board-generated pairing card over USB.

Never generate a token/key on the PC, erase NVS, discover network devices, or log
the returned secret. Nothing touches a serial port unless main() is invoked.
"""
from pathlib import Path
import argparse,base64,hashlib,html,io,json,os,re,subprocess,time,webbrowser

ROOT=Path(__file__).resolve().parent.parent
FQBN={'s3':'esp32:esp32:esp32s3:FlashSize=16M,PSRAM=opi,FlashMode=qio,PartitionScheme=app3M_fat9M_16MB,CDCOnBoot=default,UploadSpeed=921600','camera':'esp32:esp32:esp32cam'}

def validate(payload,expected_kind=None):
    if not isinstance(payload,dict) or set(payload)!={'format','version','kind','id','host','ssid','token','ca'}:
        raise ValueError('Unexpected pairing format from board')
    if payload['format']!='aquahatch-pairing' or type(payload['version']) is not int or payload['version']!=1:
        raise ValueError('Unsupported pairing version')
    kind=payload['kind']
    if kind not in FQBN or expected_kind is not None and kind!=expected_kind:raise ValueError('Board type does not match selected firmware')
    prefix='s3' if kind=='s3' else 'cam'
    if not isinstance(payload['id'],str) or not re.fullmatch(prefix+r'-[0-9a-f]{12}',payload['id']):raise ValueError('Invalid board identity')
    if payload['host']!='aquahatch-'+payload['id']+'.local':raise ValueError('Unexpected TLS hostname')
    ssid='AquaHatch-'+('S3' if kind=='s3' else 'CAM')+'-'+payload['id'][-6:].upper()
    if payload['ssid']!=ssid:raise ValueError('Unexpected setup network')
    if not isinstance(payload['token'],str) or not re.fullmatch(r'[0-9a-f]{64}',payload['token']):raise ValueError('Invalid pairing secret')
    ca=payload['ca']
    if not isinstance(ca,str) or not 200<=len(ca)<=2048 or not re.fullmatch(r'[A-Za-z0-9_-]+',ca):raise ValueError('Invalid pairing CA')
    raw=base64.b64decode(ca+'='*((-len(ca))%4),altchars=b'-_',validate=True)
    if len(raw)<150 or raw[0]!=0x30:raise ValueError('Missing X.509 certificate')
    return payload

def render_card(payload,directory):
    import qrcode
    from qrcode.image.svg import SvgPathImage
    validate(payload)
    directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
    raw=json.dumps(payload,separators=(',',':'),ensure_ascii=True)
    qr=qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_M,box_size=8,border=4)
    qr.add_data(raw);qr.make(fit=True);buffer=io.BytesIO();qr.make_image(image_factory=SvgPathImage).save(buffer)
    svg=buffer.getvalue().decode();svg=svg[svg.index('<svg'):]
    password=hashlib.sha256(('AquaHatch setup v1:'+payload['token']).encode()).hexdigest()[:16]
    ca=base64.urlsafe_b64decode(payload['ca']+'='*((-len(payload['ca']))%4))
    fingerprint=hashlib.sha256(ca).hexdigest()
    title='บอร์ดหลัก ESP32-S3' if payload['kind']=='s3' else 'กล้อง ESP32-CAM'
    text=f'''<!doctype html><html lang="th"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>AquaHatch — บัตรส่วนตัว {html.escape(payload['id'])}</title>
<style>body{{font:16px/1.7 system-ui,sans-serif;background:#f2f6f3;color:#163b2c;margin:0;padding:24px}}main{{max-width:760px;margin:auto;background:white;padding:32px;border-radius:24px}}h1{{margin:0;font-size:28px}}.qr{{max-width:560px;margin:24px auto}}.qr svg{{width:100%;height:auto;display:block}}code,textarea{{display:block;overflow-wrap:anywhere;background:#edf4ee;padding:12px;border-radius:8px}}textarea{{width:100%;box-sizing:border-box;min-height:96px}}button{{font:inherit;padding:12px 16px;min-height:44px;background:#345740;color:white;border:0;border-radius:12px;cursor:pointer}}.notice{{background:#fff5dc;padding:16px;border-radius:12px}}label{{display:block;margin:20px 0 8px;font-weight:600}}small{{color:#52695a}}@media print{{body{{background:white;padding:0}}main{{padding:16px}}button,.screen-only{{display:none}}.qr{{max-width:110mm}}}}</style>
<main><h1>AquaHatch · {title}</h1><p>รหัสอุปกรณ์: <strong>{html.escape(payload['id'])}</strong></p>
<p class="notice">บัตรนี้มีรหัสควบคุมอุปกรณ์ เก็บเป็นส่วนตัว ไม่อัปโหลด GitHub หรือส่งในพื้นที่สาธารณะ</p>
<div class="qr">{svg}</div><p>ใน AquaHatch 0.14.0 ขึ้นไป เปิด ตั้งค่า → บอร์ดใหม่? สแกน QR เพื่อจับคู่</p>
<label>Wi-Fi ตั้งค่าของอุปกรณ์</label><code>{html.escape(payload['ssid'])}</code><label>รหัส Wi-Fi อุปกรณ์</label><code>{password}</code>
<label>ใบรับรองเฉพาะตัว</label><small>{fingerprint}</small>
<details class="screen-only"><summary>ข้อมูล QR สำหรับคัดลอกเข้า LDPlayer</summary><textarea id="payload" readonly spellcheck="false">{html.escape(raw)}</textarea><button onclick="copyPayload()">คัดลอกข้อมูล QR ทั้งหมด</button><p id="copy-status" role="status"></p></details>
<p>บอร์ดเป็นผู้สร้างรหัสและเก็บไว้ใน NVS เอง รหัสเดิมใช้ต่อหลังรีสตาร์ตและอัปเดตเฟิร์มแวร์ที่ไม่ล้าง NVS ได้</p>
<button class="screen-only" onclick="window.print()">พิมพ์บัตร</button></main><script>async function copyPayload(){{const el=document.getElementById('payload');try{{await navigator.clipboard.writeText(el.value)}}catch(e){{el.select();document.execCommand('copy')}}document.getElementById('copy-status').textContent='คัดลอกแล้ว วางในช่องข้อมูล QR ของแอปได้เลย'}};</script></html>'''
    path=directory/('AquaHatch-'+payload['id']+'-PAIRING_PRIVATE.html')
    path.write_text(text,encoding='utf-8');return path

def read_pairing(port,kind,timeout=60):
    import serial
    connection=serial.Serial(port=None,baudrate=115200,timeout=.25,write_timeout=2)
    connection.dtr=False;connection.rts=False;connection.port=port
    deadline=time.monotonic()+timeout;last_sent=0;buffer=bytearray()
    try:
        connection.open()
        while time.monotonic()<deadline:
            if time.monotonic()-last_sent>=1:
                connection.write((json.dumps({'op':'pairing','time_unix':int(time.time())})+'\n').encode());last_sent=time.monotonic()
            data=connection.read(2048)
            if not data:continue
            buffer.extend(data)
            if len(buffer)>32768:buffer.clear()
            while b'\n' in buffer:
                line,_,rest=buffer.partition(b'\n');buffer=bytearray(rest)
                try:response=json.loads(line)
                except (ValueError,UnicodeDecodeError):continue
                if not isinstance(response,dict):continue
                if response.get('type')=='pairing':return validate(response.get('payload'),kind)
        raise TimeoutError('Board did not return a pairing card. Close Serial Monitor, check the port and reset the board.')
    finally:connection.close()

def flash(port,kind,arduino_cli,images):
    folder='local_server' if kind=='s3' else 'camera_server'
    images=Path(images)
    required=[images/f'{folder}.ino{suffix}.bin' for suffix in ['', '.bootloader','.partitions']]
    if not all(path.is_file() for path in required):raise FileNotFoundError('Generic firmware files are missing. Use the complete FirstBoot package.')
    manifest=images.parent/'SHA256SUMS.json'
    if not manifest.is_file():raise FileNotFoundError('Firmware checksum manifest is missing')
    expected=json.loads(manifest.read_text(encoding='utf-8'))
    for file in required:
        relative=file.relative_to(images.parent).as_posix()
        if hashlib.sha256(file.read_bytes()).hexdigest()!=expected.get(relative):raise ValueError('Firmware checksum mismatch')
    subprocess.run([str(arduino_cli),'upload','--fqbn',FQBN[kind],'--port',port,'--input-dir',str(images),str(ROOT/'aqua_hatch/firmware'/folder)],check=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--kind',choices=FQBN,required=True);parser.add_argument('--port',required=True)
    parser.add_argument('--read-only',action='store_true',help='Retrieve the existing QR without flashing or changing identity')
    parser.add_argument('--arduino-cli',default=str(Path(os.environ.get('LOCALAPPDATA',''))/'Programs/Arduino IDE/resources/app/lib/backend/resources/arduino-cli.exe'))
    parser.add_argument('--images',type=Path);parser.add_argument('--output',type=Path,default=ROOT/'outputs/private-pairing')
    parser.add_argument('--no-open',action='store_true');args=parser.parse_args()
    if not re.fullmatch(r'COM[1-9][0-9]*',args.port,re.IGNORECASE):parser.error('Use a Windows COM port such as COM3')
    try:
        if not args.read_only:
            print('กำลังลงเฟิร์มแวร์ โดยไม่สั่งล้าง NVS…',flush=True)
            flash(args.port,args.kind,Path(args.arduino_cli),args.images or ROOT/'firmware-images'/args.kind)
        print('รอบอร์ดเตรียมรหัสเฉพาะตัว แล้วรับบัตรผ่าน USB…',flush=True)
        payload=read_pairing(args.port,args.kind)
        card=render_card(payload,args.output)
        print('บัตรจับคู่ส่วนตัวพร้อมแล้ว: '+str(card),flush=True)
        if not args.no_open:webbrowser.open(card.resolve().as_uri())
    except (OSError,ValueError,TimeoutError,subprocess.CalledProcessError) as error:
        # Do not dump serial content or an exception containing a payload.
        print('ทำรายการไม่สำเร็จ ตรวจพอร์ต USB รุ่นบอร์ด และปิด Serial Monitor แล้วลองใหม่',flush=True)
        raise SystemExit(1) from None

if __name__=='__main__':main()
