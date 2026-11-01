#include "sensor_do.h"
#include "sensor_config.h"
#include "renke_do_protocol.h"
#include <time.h>

namespace oxygen_sensor {
namespace {
constexpr uint32_t PERIOD_MS = 2000, RESPONSE_MS = 1200;
HardwareSerial wire(1);
portMUX_TYPE guard = portMUX_INITIALIZER_UNLOCKED;
struct Sample {
  float mgL = NAN, temperatureC = NAN, saturationRatio = NAN;
  const char *status = DO_ENABLED ? "converting" : "not_configured";
  uint32_t acquiredMs = 0, requests = 0, successes = 0, timeouts = 0, errors = 0;
  time_t acquiredUnix = 0;
  uint16_t lastResponseBytes = 0;
} latest;
bool waiting = false;
uint32_t lastRequest = 0, startedAt = 0;
uint8_t received[32];
size_t used = 0;
void failure(const char *status) {
  portENTER_CRITICAL(&guard);
  latest.mgL = NAN; latest.temperatureC = NAN; latest.saturationRatio = NAN;
  latest.status = status;
  latest.lastResponseBytes = used;
  if (strcmp(status, "timeout") == 0) latest.timeouts++;
  else latest.errors++;
  portEXIT_CRITICAL(&guard);
  waiting = false;
}
void processReply() {
  renke_do::Reading reading;
  const auto result = renke_do::decode(received, used, DO_ADDRESS, reading);
  if (result != renke_do::Result::ok) {
    failure(result == renke_do::Result::exception ? "modbus_exception" :
            result == renke_do::Result::invalid_value ? "invalid_value" : "crc_error");
    return;
  }
  const time_t acquiredUnix = time(nullptr);
  const uint32_t acquiredMs = millis();
  portENTER_CRITICAL(&guard);
  latest.mgL = reading.mgL;
  latest.temperatureC = reading.temperatureC;
  latest.saturationRatio = reading.saturationRatio;
  latest.acquiredMs = acquiredMs; latest.acquiredUnix = acquiredUnix;
  latest.status = "ok"; latest.successes++; latest.lastResponseBytes = used;
  portEXIT_CRITICAL(&guard);
  waiting = false;
}
}
bool enabled() { return DO_ENABLED; }
void begin() {
  if (!DO_ENABLED) return;
  digitalWrite(DO_DIRECTION_PIN, LOW);
  pinMode(DO_DIRECTION_PIN, OUTPUT);
  wire.begin(DO_BAUD, SERIAL_8N1, DO_RX_PIN, DO_TX_PIN);
}
void tick() {
  if (!DO_ENABLED) return;
  uint32_t now = millis();
  if (waiting) {
    while (wire.available()) {
      if (used >= sizeof(received)) { failure("crc_error"); break; }
      received[used++] = wire.read();
    }
    if (!waiting) return;
    const size_t expected = used >= 2 && (received[1] & 0x80) ? 5 : 17;
    if (used >= expected) { processReply(); return; }
    if (now - startedAt >= RESPONSE_MS) failure("timeout");
    return;
  }
  if (now - lastRequest < PERIOD_MS) return;
  lastRequest = now;
  while (wire.available()) wire.read();
  uint8_t frame[8]; renke_do::request(DO_ADDRESS, frame);
  used = 0;
  digitalWrite(DO_DIRECTION_PIN, HIGH);
  delayMicroseconds(50);
  wire.write(frame, sizeof(frame));
  wire.flush(); // Wait for all stop bits before returning the bus to receive.
  digitalWrite(DO_DIRECTION_PIN, LOW);
  startedAt = millis(); waiting = true;
  portENTER_CRITICAL(&guard);
  latest.requests++;
  portEXIT_CRITICAL(&guard);
}
void append(JsonObject telemetry) {
  portENTER_CRITICAL(&guard);
  Sample copy = latest;
  portEXIT_CRITICAL(&guard);
  bool stale = isfinite(copy.mgL) && millis() - copy.acquiredMs > 10000;
  telemetry["do_mg_l"] = nullptr;
  telemetry["do_temperature_c"] = nullptr;
  telemetry["do_saturation_percent"] = nullptr;
  telemetry["do_sampled_at"] = nullptr;
  telemetry["do_status"] = stale ? "stale" : copy.status;
  if (isfinite(copy.mgL) && !stale) {
    telemetry["do_mg_l"] = copy.mgL;
    telemetry["do_temperature_c"] = copy.temperatureC;
    telemetry["do_saturation_percent"] = copy.saturationRatio * 100.0f;
  }
  if (copy.acquiredUnix >= 1735689600) {
    struct tm utc; gmtime_r(&copy.acquiredUnix, &utc);
    char text[32]; strftime(text, sizeof(text), "%Y-%m-%dT%H:%M:%SZ", &utc);
    telemetry["do_sampled_at"] = text;
  }
  JsonObject details = telemetry["sensors"]["dissolved_oxygen"].to<JsonObject>();
  details["model"] = "RS-LDO-N01-2-20";
  details["enabled"] = DO_ENABLED;
  details["tx_gpio"] = DO_TX_PIN; details["rx_gpio"] = DO_RX_PIN;
  details["direction_gpio"] = DO_DIRECTION_PIN;
  details["baud"] = DO_BAUD; details["address"] = DO_ADDRESS;
  details["requests"] = copy.requests; details["valid_responses"] = copy.successes;
  details["timeouts"] = copy.timeouts; details["errors"] = copy.errors;
  details["last_response_bytes"] = copy.lastResponseBytes;
}
}
