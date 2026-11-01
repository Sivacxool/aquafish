#include "../local_server/renke_do_protocol.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main() {
  // Published manufacturer request/reply, manual V2.0 pages 9-10.
  const uint8_t documentedRequest[] = {1,3,0,0,0,6,0xc5,0xc8};
  uint8_t request[8]; renke_do::request(1, request);
  assert(memcmp(request, documentedRequest, sizeof(request)) == 0);
  uint8_t reply[] = {1,3,12,0x3f,0x6a,0xeb,0x52,0x40,0xe2,0x48,0xb0,
                     0x41,0xe5,0x85,0xc5,0xa7,0x49};
  renke_do::Reading reading;
  assert(renke_do::decode(reply, sizeof(reply), 1, reading) == renke_do::Result::ok);
  assert(fabs(reading.mgL - 7.071373f) < .00001f);
  assert(fabs(reading.saturationRatio * 100 - 91.7653f) < .001f);
  assert(fabs(reading.temperatureC - 28.690317f) < .00001f);
  for (size_t length = 0; length < sizeof(reply); length++)
    assert(renke_do::decode(reply, length, 1, reading) != renke_do::Result::ok);
  assert(renke_do::decode(reply, sizeof(reply), 2, reading) == renke_do::Result::wrong_device);
  reply[8] ^= 1;
  assert(renke_do::decode(reply, sizeof(reply), 1, reading) == renke_do::Result::crc_error);
  reply[8] ^= 1;
  // A complete CRC-valid exception must never be accepted as a sensor reading.
  uint8_t exception[] = {1,0x83,2,0xc0,0xf1};
  assert(renke_do::decode(exception, sizeof(exception), 1, reading) == renke_do::Result::exception);
  reply[7] = 0x7f; reply[8] = 0xc0; reply[9] = reply[10] = 0; // float NaN
  auto crc = renke_do::crc16(reply, 15); reply[15] = crc & 0xff; reply[16] = crc >> 8;
  assert(renke_do::decode(reply, sizeof(reply), 1, reading) == renke_do::Result::invalid_value);
  puts("PASS: manufacturer Modbus vector, float byte order, CRC, truncation, address, exception, NaN");
}
