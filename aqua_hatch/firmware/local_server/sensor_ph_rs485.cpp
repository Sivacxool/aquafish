#if defined(AQUAHATCH_ET_WROOM32UE)
#include "sensor_ph.h"
#include "sensor_config.h"
#include <math.h>
#include <time.h>

namespace ph_sensor {
namespace {
constexpr uint32_t StaleMs = 10000;
portMUX_TYPE guard = portMUX_INITIALIZER_UNLOCKED;
struct Sample {
  float ph = NAN;
  float temperatureC = NAN;
  uint32_t acquiredMs = 0;
  time_t acquiredUnix = 0;
  const char *status = "converting";
} latest;

uint16_t word(const uint8_t *bytes) {
  return (uint16_t(bytes[0]) << 8) | bytes[1];
}
}

void recordModbusReply(const uint8_t *registers) {
  const float ph = word(registers + 2) / 10.0f;
  if (ph > 14.0f) {
    recordModbusFailure("ph_out_of_range");
    return;
  }
  const float temperature = int16_t(word(registers)) / 10.0f;
  const Sample sample{ph, temperature >= -20.0f && temperature <= 80.0f ? temperature : NAN,
                      millis(), time(nullptr), "ok"};
  portENTER_CRITICAL(&guard);
  latest = sample;
  portEXIT_CRITICAL(&guard);
}

void recordModbusFailure(const char *status) {
  portENTER_CRITICAL(&guard);
  latest = Sample{};
  latest.status = status;
  portEXIT_CRITICAL(&guard);
}

bool calibrate(float, bool, String &message) {
  message = "สอบเทียบที่กล่องหัววัด pH RS485 ตามคู่มือของหัววัด";
  return false;
}

void append(JsonObject telemetry) {
  portENTER_CRITICAL(&guard);
  const Sample sample = latest;
  portEXIT_CRITICAL(&guard);
  const bool stale = isfinite(sample.ph) && millis() - sample.acquiredMs > StaleMs;
  telemetry["ph"] = nullptr;
  telemetry["ph_source"] = "rs485";
  telemetry["ph_temperature_c"] = nullptr;
  telemetry["ph_sampled_at"] = nullptr;
  telemetry["ph_status"] = stale ? "stale" : sample.status;
  if (isfinite(sample.ph) && !stale) {
    telemetry["ph"] = sample.ph;
    if (isfinite(sample.temperatureC)) telemetry["ph_temperature_c"] = sample.temperatureC;
  }
  if (sample.acquiredUnix >= 1735689600) {
    struct tm utc;
    gmtime_r(&sample.acquiredUnix, &utc);
    char text[32];
    strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &utc);
    telemetry["ph_sampled_at"] = text;
  }
  JsonObject sensor = telemetry["sensors"]["ph"].to<JsonObject>();
  sensor["model"] = "MI-Water-PH-T";
  sensor["protocol"] = "Modbus RTU";
  sensor["address"] = PH_RS485_ADDRESS;
  sensor["baud"] = PH_RS485_BAUD;
  sensor["uart"] = DO_UART;
}
}
#endif
