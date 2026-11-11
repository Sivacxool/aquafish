#include "sensor_temperature.h"
#include "sensor_config.h"
#include <OneWire.h>
#include <DallasTemperature.h>
#include <math.h>
#include <time.h>

namespace temperature_sensor {
namespace {
constexpr uint8_t DATA_PIN = TEMPERATURE_DATA_PIN;
constexpr uint32_t CONVERSION_MS = 800, SAMPLE_MS = 2000, RESCAN_MS = 5000;
OneWire bus(DATA_PIN);
DallasTemperature sensor(&bus);
DeviceAddress address;
bool found = false, converting = false;
uint32_t conversionStarted = 0, lastAttempt = 0, lastScan = 0;
portMUX_TYPE guard = portMUX_INITIALIZER_UNLOCKED;
struct Sample {
  float value = NAN;
  uint32_t acquiredMs = 0;
  time_t acquiredUnix = 0;
  const char *status = "not_found";
  uint8_t detected = 0;
} latest;

void fail(const char *status, uint8_t detected) {
  portENTER_CRITICAL(&guard);
  latest.value = NAN;
  latest.status = status;
  latest.detected = detected;
  portEXIT_CRITICAL(&guard);
}
void discover() {
  lastScan = millis();
  sensor.begin();
  found = false;
  uint8_t count = sensor.getDeviceCount();
  if (count != 1) {
    fail(count > 1 ? "multiple_sensors" : "not_found", count);
    return;
  }
  if (!sensor.getAddress(address, 0) || address[0] != 0x28) {
    fail("not_found", count);
    return;
  }
  if (sensor.isParasitePowerMode()) {
    fail("unsupported_power", count);
    return;
  }
  sensor.setAutoSaveScratchPad(false); // Avoid writing sensor EEPROM on reconnect.
  if (!sensor.setResolution(address, 12)) {
    fail("crc_error", count);
    return;
  }
  sensor.setWaitForConversion(false);
  found = true;
  fail("converting", count);
}
}
void begin() { discover(); }
void tick() {
  const uint32_t now = millis();
  if (!found) {
    if (now - lastScan >= RESCAN_MS) discover();
    return;
  }
  if (converting) {
    if (now - conversionStarted < CONVERSION_MS) return;
    converting = false;
    // DallasTemperature verifies scratchpad CRC and returns -127 on bus failure.
    float value = sensor.getTempC(address);
    if (!isfinite(value) || value == DEVICE_DISCONNECTED_C || value < -55 || value > 125) {
      fail("crc_error", 1);
      found = false;
      return;
    }
    const time_t acquiredUnix = time(nullptr);
    const uint32_t acquiredMs = millis();
    portENTER_CRITICAL(&guard);
    latest.value = value;
    latest.acquiredMs = acquiredMs;
    latest.acquiredUnix = acquiredUnix;
    latest.status = "ok";
    latest.detected = 1;
    portEXIT_CRITICAL(&guard);
  }
  if (now - lastAttempt >= SAMPLE_MS) {
    lastAttempt = now;
    if (!sensor.requestTemperaturesByAddress(address).result) {
      fail("crc_error", 1);
      found = false;
      return;
    }
    conversionStarted = millis();
    converting = true;
  }
}
void append(JsonObject telemetry) {
  portENTER_CRITICAL(&guard);
  Sample copy = latest;
  portEXIT_CRITICAL(&guard);
  const bool stale = isfinite(copy.value) && millis() - copy.acquiredMs > 10000;
  telemetry["temperature_c"] = nullptr;
  if (isfinite(copy.value) && !stale) telemetry["temperature_c"] = copy.value;
  telemetry["temperature_status"] = stale ? "stale" : copy.status;
  telemetry["temperature_sampled_at"] = nullptr;
  if (copy.acquiredUnix >= 1735689600) {
    struct tm utc;
    gmtime_r(&copy.acquiredUnix, &utc);
    char text[32];
    strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &utc);
    telemetry["temperature_sampled_at"] = text;
  }
  telemetry["sensors"]["temperature"]["model"] = "DS18B20";
  telemetry["sensors"]["temperature"]["gpio"] = DATA_PIN;
  telemetry["sensors"]["temperature"]["detected"] = copy.detected;
}
}
