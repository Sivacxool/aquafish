#include "sensor_do.h"
#include "sensor_config.h"
#include "sensor_ph.h"
#include "renke_do_protocol.h"
#include <time.h>

namespace oxygen_sensor {
namespace {
constexpr uint32_t PERIOD_MS = PH_RS485_ENABLED ? 1000 : 2000;
constexpr uint32_t RESPONSE_MS = 1200, BUS_GAP_MS = 30;
constexpr uint8_t DO_REGISTERS = 6, PH_REGISTERS = 3;
HardwareSerial wire(DO_UART);
portMUX_TYPE guard = portMUX_INITIALIZER_UNLOCKED;
struct Sample {
  float mgL = NAN, temperatureC = NAN, saturationRatio = NAN;
  const char *status = DO_ENABLED ? "converting" : "not_configured";
  uint32_t acquiredMs = 0, requests = 0, successes = 0, timeouts = 0, errors = 0;
  time_t acquiredUnix = 0;
  uint16_t lastResponseBytes = 0;
} latest;
bool waiting = false;
bool readingPh = false;
bool nextPh = !DO_ENABLED;
uint32_t lastRequest = 0, startedAt = 0, finishedAt = 0;
uint32_t busBaud = DO_ENABLED ? DO_BAUD : PH_RS485_BAUD;
uint8_t received[32];
uint8_t requestFrame[8];
size_t used = 0;
void finish() {
  waiting = false;
  finishedAt = millis();
}
void failure(const char *status) {
#if defined(AQUAHATCH_ET_WROOM32UE)
  if (readingPh) {
    ph_sensor::recordModbusFailure(status);
    finish();
    return;
  }
#endif
  portENTER_CRITICAL(&guard);
  latest.mgL = NAN; latest.temperatureC = NAN; latest.saturationRatio = NAN;
  latest.status = status;
  latest.lastResponseBytes = used;
  if (strcmp(status, "timeout") == 0) latest.timeouts++;
  else latest.errors++;
  portEXIT_CRITICAL(&guard);
  finish();
}
void processReply() {
#if defined(AQUAHATCH_ET_WROOM32UE)
  if (readingPh) {
    const uint16_t crc = renke_do::crc16(received, used - 2);
    const uint16_t receivedCrc = received[used - 2] | (uint16_t(received[used - 1]) << 8);
    if (crc != receivedCrc) {
      failure("crc_error");
    } else if (received[0] != PH_RS485_ADDRESS) {
      failure("wrong_device");
    } else if (used == 5 && received[1] == 0x83) {
      failure("modbus_exception");
    } else if (used != 5 + 2 * PH_REGISTERS || received[1] != 3 ||
               received[2] != 2 * PH_REGISTERS) {
      failure("invalid_response");
    } else {
      ph_sensor::recordModbusReply(received + 3);
      finish();
    }
    return;
  }
#endif
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
  finish();
}
}
bool enabled() { return DO_ENABLED; }
void begin() {
  if (!DO_ENABLED && !PH_RS485_ENABLED) return;
  if constexpr (DO_DIRECTION_PIN >= 0) {
    digitalWrite(DO_DIRECTION_PIN, LOW);
    pinMode(DO_DIRECTION_PIN, OUTPUT);
  }
  wire.begin(busBaud, SERIAL_8N1, DO_RX_PIN, DO_TX_PIN);
}
void tick() {
  if (!DO_ENABLED && !PH_RS485_ENABLED) return;
  uint32_t now = millis();
  if (waiting) {
    while (wire.available()) {
      if (used >= sizeof(received)) { failure("crc_error"); break; }
      received[used++] = wire.read();
    }
    if (!waiting) return;
    if constexpr (DO_DIRECTION_PIN < 0) {
      // The on-board transceiver can echo our request before the reply.
      if (used >= sizeof(requestFrame) &&
          memcmp(received, requestFrame, sizeof(requestFrame)) == 0) {
        used -= sizeof(requestFrame);
        memmove(received, received + sizeof(requestFrame), used);
      }
    }
    const size_t expected = used >= 2 && (received[1] & 0x80)
        ? 5 : 5 + 2 * (readingPh ? PH_REGISTERS : DO_REGISTERS);
    if (used >= expected) { processReply(); return; }
    if (now - startedAt >= RESPONSE_MS) failure("timeout");
    return;
  }
  if (now - lastRequest < PERIOD_MS || now - finishedAt < BUS_GAP_MS) return;
  lastRequest = now;
  readingPh = PH_RS485_ENABLED && nextPh;
  if constexpr (PH_RS485_ENABLED && DO_ENABLED) nextPh = !nextPh;
  const uint32_t baud = readingPh ? PH_RS485_BAUD : DO_BAUD;
  if (baud != busBaud) {
    wire.updateBaudRate(baud);
    busBaud = baud;
  }
  while (wire.available()) wire.read();
  renke_do::request(readingPh ? PH_RS485_ADDRESS : DO_ADDRESS, requestFrame,
                    readingPh ? PH_REGISTERS : DO_REGISTERS);
  used = 0;
  if constexpr (DO_DIRECTION_PIN >= 0) {
    digitalWrite(DO_DIRECTION_PIN, HIGH);
    delayMicroseconds(50);
  }
  wire.write(requestFrame, sizeof(requestFrame));
  wire.flush(true);
  if constexpr (DO_DIRECTION_PIN >= 0) {
    digitalWrite(DO_DIRECTION_PIN, LOW);
  }
  startedAt = millis(); waiting = true;
  if (!readingPh) {
    portENTER_CRITICAL(&guard);
    latest.requests++;
    portEXIT_CRITICAL(&guard);
  }
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
  if constexpr (DO_DIRECTION_PIN >= 0) {
    details["direction_gpio"] = DO_DIRECTION_PIN;
  } else {
    details["direction_gpio"] = nullptr;
    details["auto_direction"] = true;
  }
  details["uart"] = DO_UART;
  details["baud"] = DO_BAUD; details["address"] = DO_ADDRESS;
  details["requests"] = copy.requests; details["valid_responses"] = copy.successes;
  details["timeouts"] = copy.timeouts; details["errors"] = copy.errors;
  details["last_response_bytes"] = copy.lastResponseBytes;
}
}
