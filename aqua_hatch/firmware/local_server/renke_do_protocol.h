#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <math.h>

// Renke RS-LDO-N01 family: read registers 0..5, function 03, big-endian float32.
// Manufacturer manual V2.0 section 2.4. Never writes calibration or settings.
namespace renke_do {
enum class Result { ok, length_error, crc_error, wrong_device, exception, invalid_value };
struct Reading { float saturationRatio, mgL, temperatureC; };
inline uint16_t crc16(const uint8_t *data, size_t length) {
  uint16_t crc = 0xffff;
  for (size_t i = 0; i < length; ++i) {
    crc ^= data[i];
    for (uint8_t bit = 0; bit < 8; ++bit)
      crc = (crc & 1) ? (crc >> 1) ^ 0xa001 : crc >> 1;
  }
  return crc;
}
inline void request(uint8_t address, uint8_t (&frame)[8]) {
  frame[0] = address; frame[1] = 3; frame[2] = 0; frame[3] = 0;
  frame[4] = 0; frame[5] = 6;
  uint16_t crc = crc16(frame, 6);
  frame[6] = crc & 0xff; frame[7] = crc >> 8;
}
inline float bigFloat(const uint8_t *bytes) {
  uint32_t bits = (uint32_t(bytes[0]) << 24) | (uint32_t(bytes[1]) << 16) |
                  (uint32_t(bytes[2]) << 8) | uint32_t(bytes[3]);
  float value;
  static_assert(sizeof(value) == sizeof(bits), "Requires IEEE754 float32");
  memcpy(&value, &bits, sizeof(value));
  return value;
}
inline Result decode(const uint8_t *frame, size_t length, uint8_t address, Reading &reading) {
  if (length != 17 && length != 5) return Result::length_error;
  uint16_t actual = crc16(frame, length - 2);
  if (frame[length - 2] != (actual & 0xff) || frame[length - 1] != (actual >> 8))
    return Result::crc_error;
  if (frame[0] != address) return Result::wrong_device;
  if (length == 5 && frame[1] == 0x83) return Result::exception;
  if (length != 17 || frame[1] != 3 || frame[2] != 12) return Result::length_error;
  Reading decoded{bigFloat(frame + 3), bigFloat(frame + 7), bigFloat(frame + 11)};
  // Keep the received numeric values available for diagnostics even if invalid.
  reading = decoded;
  if (!isfinite(decoded.saturationRatio) || !isfinite(decoded.mgL) ||
      !isfinite(decoded.temperatureC) || decoded.mgL < 0 || decoded.mgL > 20 ||
      decoded.saturationRatio < 0 || decoded.saturationRatio > 2.1f ||
      decoded.temperatureC < -20 || decoded.temperatureC > 85)
    return Result::invalid_value;
  return Result::ok;
}
}
