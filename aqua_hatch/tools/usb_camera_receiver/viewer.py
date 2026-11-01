from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
import argparse,hashlib,json,threading,time
import serial
from protocol import PacketReader,ProtocolError

class Camera:
    def __init__(self,port,baud):
        self.port=serial.Serial(port=None,baudrate=baud,timeout=.15,write_timeout=3)
        self.port.dtr=False;self.port.rts=False;self.port.port=port;self.port.open()
        self.reader=PacketReader(self.port);self.request=0
        self.condition=threading.Condition();self.stop=threading.Event()
        self.photo=None;self.state={'connected':False,'com_port':port,'baud':baud,'frames':0,'fps':0,'message':'กำลังตรวจบอร์ดผ่าน USB'}
    def transaction(self,op):
        self.request=(self.request+1)&0xffffffff or 1
        self.port.write(f'{op} {self.request}\n'.encode('ascii'))
        deadline=time.monotonic()+7
        while time.monotonic()<deadline:
            packet=self.reader.read(max(.1,deadline-time.monotonic()))
            if packet['request']!=self.request:continue
            if packet['kind']==3:raise ProtocolError(packet['payload'].decode('utf-8','replace'))
            return packet
        raise TimeoutError('USB camera response ID not received')
    def run(self):
        try:
            packet=self.transaction('HELLO');assert packet['kind']==1
            info=json.loads(packet['payload'])
            if not info['camera_ready']:raise ProtocolError(f"Camera init failed: {info['camera_error']}")
            if info['wifi_mode']!=0:raise ProtocolError('This firmware has Wi-Fi enabled')
            if not info['crc_self_test']:raise ProtocolError('Firmware CRC self-test failed')
            with self.condition:self.state.update(info,connected=True,message='รับภาพผ่าน USB · Wi-Fi ปิดอยู่')
            start=time.monotonic()
            while not self.stop.is_set():
                packet=self.transaction('CAP');photo=packet['payload']
                if packet['kind']!=2 or photo[:2]!=b'\xff\xd8' or photo[-2:]!=b'\xff\xd9':raise ProtocolError('Invalid USB JPEG')
                with self.condition:
                    self.photo=photo;self.state['frames']+=1
                    self.state.update(width=packet['width'],height=packet['height'],sequence=packet['sequence'],last_frame_time=time.time())
                    self.state['fps']=round(self.state['frames']/max(time.monotonic()-start,.001),2)
                    self.condition.notify_all()
                self.stop.wait(.01)
        except Exception as error:
            with self.condition:self.state.update(connected=False,message=str(error));self.condition.notify_all()
            print('USB_CAMERA_ERROR',str(error),flush=True)
        finally:self.port.close()
    def latest(self):
        with self.condition:return dict(self.state),self.photo

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--port',default='COM4');parser.add_argument('--baud',type=int,default=921600);parser.add_argument('--http-port',type=int,default=8771)
    args=parser.parse_args();camera=Camera(args.port,args.baud)
    class Handler(BaseHTTPRequestHandler):
        def log_message(self,*args):pass
        def send(self,status,kind,data,extra=None):
            self.send_response(status);self.send_header('Content-Type',kind);self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(data)))
            for key,value in (extra or {}).items():self.send_header(key,value)
            self.end_headers();self.wfile.write(data)
        def do_GET(self):
            path=self.path.split('?')[0]
            try:
                if path=='/':return self.send(200,'text/html; charset=utf-8',(Path(__file__).parent/'index.html').read_bytes())
                if path=='/status':return self.send(200,'application/json; charset=utf-8',json.dumps(camera.latest()[0],ensure_ascii=False).encode())
                if path in ('/snapshot.jpg','/download'):
                    state,photo=camera.latest()
                    if not state['connected'] or photo is None:return self.send(503,'text/plain; charset=utf-8',state['message'].encode())
                    if time.time()-state.get('last_frame_time',0)>3:return self.send(503,'text/plain',b'USB camera image is stale')
                    headers={'X-AquaHatch-Transport':'usb-uart','X-AquaHatch-Sequence':str(state['sequence']),
                        'X-AquaHatch-Captured-At':str(state['last_frame_time']),
                        'X-AquaHatch-SHA256':hashlib.sha256(photo).hexdigest()}
                    if path=='/download':headers['Content-Disposition']='attachment; filename="AquaHatch-USB.jpg"'
                    return self.send(200,'image/jpeg',photo,headers)
                if path=='/stream':
                    self.send_response(200);self.send_header('Content-Type','multipart/x-mixed-replace; boundary=aquausb');self.send_header('Cache-Control','no-store');self.end_headers()
                    previous=0
                    while not camera.stop.is_set():
                        with camera.condition:
                            camera.condition.wait_for(lambda:camera.state['frames']!=previous or not camera.state['connected'],timeout=2)
                            state=dict(camera.state);photo=camera.photo
                        if not state['connected']:break
                        if state['frames']==previous or photo is None:continue
                        previous=state['frames']
                        header=f'\r\n--aquausb\r\nContent-Type: image/jpeg\r\nContent-Length: {len(photo)}\r\nX-Sequence: {state["sequence"]}\r\n\r\n'.encode()
                        self.wfile.write(header+photo);self.wfile.flush()
                    return
                self.send(404,'text/plain',b'Not found')
            except (BrokenPipeError,ConnectionResetError,ConnectionAbortedError):pass
    server=ThreadingHTTPServer(('127.0.0.1',args.http_port),Handler);server.daemon_threads=True
    worker=threading.Thread(target=camera.run,daemon=True);worker.start()
    print(f'USB_VIEWER http://127.0.0.1:{server.server_port}/  {args.port} @ {args.baud} baud',flush=True)
    print('Keep this program running. Ctrl+C releases the COM port. No Wi-Fi connection is used.',flush=True)
    try:server.serve_forever(poll_interval=.25)
    except KeyboardInterrupt:pass
    finally:
        camera.stop.set();server.server_close();worker.join(timeout=8)

if __name__=='__main__':main()
