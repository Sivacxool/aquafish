#pragma once
#include <atomic>
#include <math.h>
#include "fill_policy.h"
#include "sensor_bus.h"
#include "sensor_temperature.h"

namespace fill_control {
constexpr uint8_t ExpanderAddress = 0x38;
constexpr uint8_t HeaterRelayBit = 1;
constexpr uint8_t PumpRelayBit = 3;
constexpr uint8_t AllRelaysOff = 0xff;
constexpr int FloatPin = 13;
constexpr float HeaterHysteresisC = 0.5f;
constexpr uint32_t RelayRefreshMs = 250;

FillPolicy policy;
SemaphoreHandle_t policyLock = nullptr;
std::atomic<bool> ready{false};
std::atomic<float> temperatureTarget{NAN};
uint8_t lastOutputs = AllRelaysOff;
uint32_t lastWriteAt = 0;

bool relayOn(uint8_t bit) {
  return (lastOutputs & (1 << bit)) == 0;
}

bool writeRelays(uint8_t outputs) {
  sensor_bus::Guard bus;
  if (!bus) return false;
  Wire.beginTransmission(ExpanderAddress);
  Wire.write(outputs);
  if (Wire.endTransmission() != 0) return false;
  lastOutputs = outputs;
  lastWriteAt = millis();
  return true;
}

void stopOnFault() {
  ready = false;
  policy.arm(false);
}

void service(void *) {
  for (;;) {
    xSemaphoreTake(policyLock, portMAX_DELAY);
    const uint32_t now = millis();
    policy.sample(digitalRead(FloatPin) == LOW, now);
    if (!ready) {
      ready = writeRelays(AllRelaysOff);
    } else {
      const float temperature = temperature_sensor::currentCelsius();
      const float target = temperatureTarget.load();
      const bool heaterOn = temperature >= 0.0f && temperature <= 50.0f &&
          temperature < target &&
          (relayOn(HeaterRelayBit) || temperature < target - HeaterHysteresisC);
      // Keep unused relays off and the PCF8574A input latches high.
      uint8_t outputs = AllRelaysOff;
      if (heaterOn) outputs &= ~(1 << HeaterRelayBit);
      if (policy.running) outputs &= ~(1 << PumpRelayBit);
      if (outputs != lastOutputs || now - lastWriteAt >= RelayRefreshMs) {
        if (!writeRelays(outputs)) stopOnFault();
      }
    }
    xSemaphoreGive(policyLock);
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void begin() {
  pinMode(FloatPin, INPUT_PULLUP);
  if (!sensor_bus::begin()) return;
  policyLock = xSemaphoreCreateMutex();
  if (policyLock != nullptr) {
    xTaskCreate(service, "aqua-relays", 3072, nullptr, 3, nullptr);
  }
}

void setTemperatureTarget(float target) {
  temperatureTarget = target >= 20.0f && target <= 35.0f ? target : NAN;
}

bool setArmed(bool enabled) {
  if (policyLock == nullptr) return false;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  if (ready) {
    policy.arm(enabled);
    if (!enabled && relayOn(PumpRelayBit)) {
      if (!writeRelays(lastOutputs | (1 << PumpRelayBit))) stopOnFault();
    }
  }
  const bool accepted = ready;
  xSemaphoreGive(policyLock);
  return accepted;
}

void append(JsonObject telemetry, bool diagnostics = false) {
  if (policyLock == nullptr) return;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  const bool available = ready;
  const FillPolicy current = policy;
  const bool pumpOn = available && relayOn(PumpRelayBit);
  const bool heaterOn = available && relayOn(HeaterRelayBit);
  xSemaphoreGive(policyLock);

  JsonObject heater = telemetry["heater"].to<JsonObject>();
  heater["io_ready"] = available;
  heater["relay_commanded_on"] = nullptr;
  if (available) heater["relay_commanded_on"] = heaterOn;
  if (diagnostics) heater["relay_pcf_bit"] = HeaterRelayBit;

  if (!available && !diagnostics) return;
  JsonObject fill = telemetry["fill"].to<JsonObject>();
  fill["armed"] = current.armed;
  fill["requested"] = current.requested;
  fill["running"] = pumpOn;
  fill["timed_out"] = current.timedOut;
  fill["limit_seconds"] = FillPolicy::LimitMs / 1000;
  if (diagnostics) {
    fill["io_ready"] = available;
    fill["relay_commanded_on"] = pumpOn;
    if (available) fill["float_level"] = current.requested ? LOW : HIGH;
    fill["float_gpio"] = FloatPin;
    fill["relay_pcf_bit"] = PumpRelayBit;
    fill["pcf_address"] = ExpanderAddress;
  }
}
}
