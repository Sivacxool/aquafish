#pragma once

#if !defined(AQUAHATCH_ET_WROOM32UE)
#error B0434 test requires the ETT WROOM32UE profile
#endif

#include <Arduino.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <algorithm>
#include <mbedtls/base64.h>
#include <mbedtls/sha256.h>

namespace b0434_test {
constexpr int Sck = 14, Miso = 34, Mosi = 25, Cs = 33;
constexpr uint32_t MaxJpeg = 2 * 1024 * 1024;
constexpr size_t ChunkSize = 768;

// Arducam Mega SPI application note, register table and burst timing.
// Sensor IDs and the legacy resolution mapping follow ArduCAM/Arducam_Mega.
constexpr uint8_t FifoControl = 0x04, Reset = 0x07, DeviceAddress = 0x0a;
constexpr uint8_t Format = 0x20, Resolution = 0x21, BurstRead = 0x3c;
constexpr uint8_t SensorId = 0x40, SensorState = 0x44, FifoSize = 0x45;
constexpr uint8_t IdleMask = 0x03, IdleValue = 0x02, CaptureDone = 0x04;

SPIClass bus(HSPI);
enum class Phase { Idle, Resetting, Addressing, FormatSetting, SizeSetting, Exposing, Ready, Failed };
Phase phase = Phase::Idle;
bool busStarted = false;
uint32_t phaseStarted = 0, lastRead = 0, total = 0, offset = 0;
uint8_t sensorId = 0;
bool highResolution = false;
const char *failure = "";

void transact() {
  bus.beginTransaction(SPISettings(1000000, MSBFIRST, SPI_MODE0));
  digitalWrite(Cs, LOW);
}

void endTransaction() {
  digitalWrite(Cs, HIGH);
  bus.endTransaction();
}

void writeRegister(uint8_t address, uint8_t value) {
  transact();
  bus.transfer(address | 0x80);
  bus.transfer(value);
  endTransaction();
}

uint8_t readRegister(uint8_t address) {
  transact();
  bus.transfer(address);
  bus.transfer(0);
  const uint8_t value = bus.transfer(0);
  endTransaction();
  return value;
}

void advance(Phase next) {
  phase = next;
  phaseStarted = millis();
}

void fail(const char *reason) {
  failure = reason;
  phase = Phase::Failed;
}

bool working() {
  return phase >= Phase::Resetting && phase <= Phase::Exposing;
}

void begin(bool fullSize) {
  if (!busStarted) {
    pinMode(Cs, OUTPUT);
    digitalWrite(Cs, HIGH);
    bus.begin(Sck, Miso, Mosi, -1);
    busStarted = true;
  }
  highResolution = fullSize;
  sensorId = 0;
  total = 0;
  offset = 0;
  failure = "";
  writeRegister(Reset, 0x40);
  advance(Phase::Resetting);
}

void tick() {
  if (phase == Phase::Ready && millis() - lastRead > 15000) {
    fail("image_expired");
  }
  if (!working()) return;
  const uint32_t elapsed = millis() - phaseStarted;
  const uint8_t state = readRegister(SensorState);
  if (phase == Phase::Exposing) {
    if ((state & CaptureDone) && state != 0xff) {
      total = readRegister(FifoSize);
      total |= uint32_t(readRegister(FifoSize + 1)) << 8;
      total |= uint32_t(readRegister(FifoSize + 2)) << 16;
      if (total < 4 || total > MaxJpeg) {
        fail("invalid_fifo_length");
        return;
      }
      lastRead = millis();
      advance(Phase::Ready);
    } else if (elapsed > 3000) {
      fail("capture_timeout");
    }
    return;
  }
  if ((state & IdleMask) != IdleValue) {
    if (elapsed > 1200) fail("spi_or_sensor_timeout");
    return;
  }
  switch (phase) {
    case Phase::Resetting:
      if (elapsed < 100) return;
      sensorId = readRegister(SensorId);
      if (sensorId != 0x82 && sensorId != 0x84 && sensorId != 0x86) {
        fail("unrecognized_3mp_sensor");
        return;
      }
      writeRegister(DeviceAddress, 0x78);
      advance(Phase::Addressing);
      break;
    case Phase::Addressing:
      writeRegister(Format, 0x01);  // JPEG
      advance(Phase::FormatSetting);
      break;
    case Phase::FormatSetting: {
      const bool legacy = sensorId != 0x86;
      const uint8_t mode = highResolution ? (legacy ? 0x08 : 0x0c) : (legacy ? 0x02 : 0x05);
      writeRegister(Resolution, mode);
      advance(Phase::SizeSetting);
      break;
    }
    case Phase::SizeSetting:
      writeRegister(FifoControl, 0x01);  // Clear the previous capture flag.
      writeRegister(FifoControl, 0x02);  // Start a single capture.
      advance(Phase::Exposing);
      break;
    default:
      break;
  }
}

void status(JsonDocument &reply) {
  reply["type"] = "b0434_status";
  reply["sensor_id"] = sensorId;
  if (working()) {
    reply["status"] = "busy";
  } else if (phase == Phase::Ready) {
    reply["status"] = "ready";
    reply["bytes"] = total;
    reply["width"] = highResolution ? 2048 : 640;
    reply["height"] = highResolution ? 1536 : 480;
  } else if (phase == Phase::Failed) {
    reply["status"] = "failed";
    reply["error"] = failure;
  } else {
    reply["status"] = "idle";
  }
}

void readChunk(uint32_t requested, JsonDocument &reply) {
  reply["type"] = "b0434_chunk";
  if (phase != Phase::Ready || requested != offset || offset >= total) {
    reply["error"] = "invalid_offset_or_inactive_capture";
    return;
  }
  uint8_t bytes[ChunkSize] = {};
  const size_t length = std::min<size_t>(ChunkSize, total - offset);
  transact();
  bus.transfer(BurstRead);
  if (!offset) bus.transfer(0);  // The dummy byte appears only on the first burst.
  bus.transfer(bytes, length);
  endTransaction();

  unsigned char encoded[ChunkSize * 4 / 3 + 1] = {};
  size_t encodedSize = 0;
  unsigned char digest[32];
  if (mbedtls_base64_encode(encoded, sizeof(encoded), &encodedSize, bytes, length) != 0 ||
      mbedtls_sha256(bytes, length, digest, 0) != 0) {
    fail("encoding_failed");
    reply["error"] = failure;
    return;
  }
  char hash[65];
  for (size_t i = 0; i < sizeof(digest); ++i) snprintf(hash + i * 2, 3, "%02x", digest[i]);
  reply["offset"] = offset;
  reply["sha256"] = String(hash);
  reply["data"] = String(reinterpret_cast<const char *>(encoded), encodedSize);
  offset += length;
  lastRead = millis();
}

bool handle(const String &op, const JsonDocument &input) {
  JsonDocument reply;
  if (op == "b0434_capture") {
    const String size = input["resolution"] | "vga";
    if (!working() && (size == "vga" || size == "3mp")) begin(size == "3mp");
    status(reply);
    if (size != "vga" && size != "3mp") reply["error"] = "unsupported_resolution";
  } else if (op == "b0434_status") {
    status(reply);
  } else if (op == "b0434_read") {
    readChunk(input["offset"] | UINT32_MAX, reply);
  } else {
    return false;
  }
  serializeJson(reply, Serial);
  Serial.println();
  return true;
}
}
