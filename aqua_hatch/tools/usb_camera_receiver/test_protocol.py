import struct,unittest,zlib
from protocol import HEADER,MAGIC,MAX_PAYLOAD,PacketReader,ProtocolError

class Port:
    def __init__(self,data,chunk=3):self.data=bytearray(data);self.chunk=chunk
    @property
    def in_waiting(self):return len(self.data)
    def read(self,size):
        size=min(size,self.chunk,len(self.data));out=bytes(self.data[:size]);del self.data[:size];return out

def packet(data=b'\xff\xd8hello\xff\xd9',request=7,crc=None):
    return HEADER.pack(MAGIC,1,2,32,request,len(data),10,320,240,zlib.crc32(data) if crc is None else crc)+data

class ProtocolTest(unittest.TestCase):
    def test_fragmented_packet_and_boot_noise_resynchronize(self):
        result=PacketReader(Port(b'boot ROM noise\r\n'+packet(),1)).read()
        self.assertEqual(result['request'],7);self.assertEqual(result['width'],320)
        self.assertEqual(result['payload'],b'\xff\xd8hello\xff\xd9')
    def test_corrupted_payload_is_rejected(self):
        with self.assertRaises(ProtocolError):PacketReader(Port(packet(crc=123))).read()
    def test_oversized_header_cannot_allocate_unbounded_memory(self):
        bad=HEADER.pack(MAGIC,1,2,32,1,MAX_PAYLOAD+1,1,320,240,0)
        self.assertEqual(PacketReader(Port(bad+packet(request=8))).read()['request'],8)
    def test_two_packets_keep_separate_request_ids(self):
        reader=PacketReader(Port(packet(request=3)+packet(request=4),65536))
        self.assertEqual(reader.read()['request'],3);self.assertEqual(reader.read()['request'],4)

if __name__=='__main__':unittest.main()
