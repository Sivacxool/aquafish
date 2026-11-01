"""Length-delimited JPEG packets over the CAM-MB USB-UART bridge."""
import struct,time,zlib

MAGIC=b'AQCAM01!'
HEADER=struct.Struct('<8sBBHIIIHHI')
MAX_PAYLOAD=512*1024

class ProtocolError(RuntimeError):pass

class PacketReader:
    def __init__(self,port):self.port=port;self.buffer=bytearray()
    def read(self,timeout=6):
        deadline=time.monotonic()+timeout
        while time.monotonic()<deadline:
            index=self.buffer.find(MAGIC)
            if index<0:
                self.buffer=self.buffer[-(len(MAGIC)-1):]
            elif index>0:
                del self.buffer[:index]
            if self.buffer.startswith(MAGIC) and len(self.buffer)>=HEADER.size:
                magic,version,kind,header_size,request,size,sequence,width,height,crc=HEADER.unpack(self.buffer[:HEADER.size])
                if version!=1 or header_size!=HEADER.size or kind not in (1,2,3) or size>MAX_PAYLOAD:
                    del self.buffer[0];continue
                total=HEADER.size+size
                if len(self.buffer)>=total:
                    payload=bytes(self.buffer[HEADER.size:total]);del self.buffer[:total]
                    if zlib.crc32(payload)!=crc:raise ProtocolError('USB frame CRC mismatch')
                    return dict(kind=kind,request=request,sequence=sequence,width=width,height=height,payload=payload)
            chunk=self.port.read(min(max(self.port.in_waiting,1),65536))
            if chunk:self.buffer.extend(chunk)
        raise TimeoutError('No complete USB camera packet received')
