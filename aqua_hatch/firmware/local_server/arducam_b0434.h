#pragma once

#if !defined(AQUAHATCH_ET_WROOM32UE)
#error B0434 test requires the ETT WROOM32UE profile
#endif

#include <Arduino.h>
#include <ArduinoJson.h>
#include <SPI.h>
#include <algorithm>
#include <mbedtls/sha256.h>

namespace arducam_b0434 {
constexpr int Sck = 14, Miso = 34, Mosi = 25, Cs = 33;
constexpr uint32_t MaxJpeg = 2 * 1024 * 1024;

// Arducam Mega SPI application note, register table and burst timing.
// Sensor IDs and the legacy resolution mapping follow ArduCAM/Arducam_Mega.
constexpr uint8_t FifoControl = 0x04, Reset = 0x07, DeviceAddress = 0x0a;
constexpr uint8_t Format = 0x20, Resolution = 0x21;
constexpr uint8_t BurstRead = 0x3c;
constexpr uint8_t SensorId = 0x40, SensorState = 0x44, FifoSize = 0x45;
constexpr uint8_t IdleMask = 0x03, IdleValue = 0x02, CaptureDone = 0x04;

SPIClass bus(HSPI);
enum class Phase {
  Idle, Resetting, Addressing, FormatSetting, Configuring,
  WarmingUp, Exposing, Ready, Failed,
};
Phase phase = Phase::Idle;
bool busStarted = false;
uint32_t phaseStarted = 0, lastRead = 0, total = 0, offset = 0;
uint8_t sensorId = 0;
bool highResolution = false;
enum class Lighting { normal, lowLight, manual };

struct ImageSetting {
  const char *name;
  uint8_t address;
  int8_t minimum;
  int8_t maximum;
};
constexpr ImageSetting ImageSettings[] = {
  {"ev", 0x25, -3, 3},
  {"brightness", 0x22, -4, 4},
  {"contrast", 0x23, -3, 3},
  {"saturation", 0x24, -3, 3},
  {"white_balance", 0x26, 0, 4},
};
constexpr size_t SettingCount = sizeof(ImageSettings) / sizeof(ImageSettings[0]);
constexpr size_t PresetSettingCount = 2;

struct ImageConfig {
  Lighting lighting = Lighting::normal;
  int8_t levels[SettingCount] = {};
};
ImageConfig imageConfig;
size_t nextSetting = 0;

bool parseImageConfig(const String &lighting, JsonObjectConst input, ImageConfig &config) {
  if (lighting == "normal") return true;
  if (lighting == "low-light") {
    config.lighting = Lighting::lowLight;
    config.levels[0] = 2;
    config.levels[1] = 1;
    return true;
  }
  if (lighting != "manual") return false;
  config.lighting = Lighting::manual;
  for (size_t i = 0; i < SettingCount; ++i) {
    const ImageSetting &setting = ImageSettings[i];
    const JsonVariantConst value = input[setting.name];
    if (!value.is<int>()) return false;
    const int level = value.as<int>();
    if (level < setting.minimum || level > setting.maximum) return false;
    config.levels[i] = level;
  }
  return true;
}

uint8_t registerValue(const ImageSetting &setting, int level) {
  // Arducam encodes signed levels as 0, +1, -1, +2, -2, ... .
  if (setting.minimum >= 0 || level == 0) return level;
  return level > 0 ? level * 2 - 1 : -level * 2;
}
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

void startBus() {
  if (busStarted) return;
  pinMode(Cs, OUTPUT);
  digitalWrite(Cs, HIGH);
  bus.begin(Sck, Miso, Mosi, -1);
  busStarted = true;
}

bool validSensor(uint8_t id) { return id == 0x82 || id == 0x84 || id == 0x86; }
bool probe() {
  startBus();
  return validSensor(readRegister(SensorId));
}

void begin(bool fullSize, const ImageConfig &config) {
  startBus();
  highResolution = fullSize;
  imageConfig = config;
  nextSetting = 0;
  sensorId = 0;
  total = 0;
  offset = 0;
  failure = "";
  writeRegister(Reset, 0x40);
  advance(Phase::Resetting);
}

void trigger(Phase next) {
  writeRegister(FifoControl, 0x01);  // Clear the previous capture flag.
  writeRegister(FifoControl, 0x02);  // Start a single capture.
  advance(next);
}

void tick() {
  if (phase == Phase::Ready && millis() - lastRead > 15000) {
    fail("image_expired");
  }
  if (!working()) return;
  const uint32_t elapsed = millis() - phaseStarted;
  const uint8_t state = readRegister(SensorState);
  if (phase == Phase::WarmingUp || phase == Phase::Exposing) {
    if ((state & CaptureDone) && state != 0xff) {
      if (phase == Phase::WarmingUp) {
        // Let auto exposure run on a first frame before keeping a JPEG.
        if (elapsed >= 500) trigger(Phase::Exposing);
        return;
      }
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
      if (!validSensor(sensorId)) {
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
      advance(Phase::Configuring);
      break;
    }
    case Phase::Configuring: {
      const bool manual = imageConfig.lighting == Lighting::manual;
      const size_t count = manual ? SettingCount : PresetSettingCount;
      if (nextSetting == count) {
        trigger(imageConfig.lighting == Lighting::normal ? Phase::Exposing : Phase::WarmingUp);
        break;
      }
      const ImageSetting &setting = ImageSettings[nextSetting];
      writeRegister(setting.address, registerValue(setting, imageConfig.levels[nextSetting]));
      ++nextSetting;
      advance(Phase::Configuring);  // Wait for camera idle after each write.
      break;
    }
    default:
      break;
  }
}

size_t read(uint8_t *bytes, size_t capacity) {
  if (phase != Phase::Ready || offset >= total) return 0;
  const size_t length = std::min<size_t>(capacity, total - offset);
  transact();
  bus.transfer(BurstRead);
  if (!offset) bus.transfer(0);  // The first burst has a dummy byte.
  bus.transferBytes(nullptr, bytes, length);
  endTransaction();
  offset += length;
  lastRead = millis();
  return length;
}
}
