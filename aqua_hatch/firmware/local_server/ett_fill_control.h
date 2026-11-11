#pragma once
#include <atomic>
#include <driver/gpio.h>
#include "fill_policy.h"
#include "sensor_bus.h"

namespace fill_control {
constexpr uint8_t ExpanderAddress = 0x38;
constexpr uint8_t FloatMask = 1 << 0;
constexpr uint8_t PumpRelayMask = 1 << 1;
constexpr auto PumpPermitPin = GPIO_NUM_25;

FillPolicy policy;
SemaphoreHandle_t policyLock = nullptr;
std::atomic<bool> ready{false};
bool relayRequested = false;

bool writePumpRelay(bool enabled) {
  Wire.beginTransmission(ExpanderAddress);
  // All input bits stay high in the output latch. RY1–RY3 stay off.
  Wire.write(enabled ? uint8_t(0xff & ~PumpRelayMask) : uint8_t(0xff));
  return Wire.endTransmission() == 0;
}

void stopOnFault() {
  gpio_set_level(PumpPermitPin, 0);
  policy.arm(false);
  policy.sample(false, millis());
  ready = false;
}

void service(void *) {
  for (;;) {
    xSemaphoreTake(policyLock, portMAX_DELAY);
    {
      sensor_bus::Guard bus;
      if (!bus) {
        stopOnFault();
      } else {
        if (!ready && writePumpRelay(false)) {
          relayRequested = false;
          ready = true;
        }
        if (ready) {
          if (Wire.requestFrom(ExpanderAddress, uint8_t(1)) != 1) {
            stopOnFault();
          } else {
            const int ports = Wire.read();
            if (ports < 0) {
              stopOnFault();
            } else {
              policy.sample((ports & FloatMask) == 0, millis());
              if (!policy.running) gpio_set_level(PumpPermitPin, 0);
              if (relayRequested != policy.running) {
                if (writePumpRelay(policy.running)) {
                  relayRequested = policy.running;
                } else {
                  stopOnFault();
                }
              }
              if (ready && policy.running) gpio_set_level(PumpPermitPin, 1);
            }
          }
        }
      }
    }
    xSemaphoreGive(policyLock);
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void begin() {
  // An external pull-down holds the independent low-side driver off at reset.
  if (gpio_set_level(PumpPermitPin, 0) != ESP_OK ||
      gpio_set_direction(PumpPermitPin, GPIO_MODE_INPUT_OUTPUT) != ESP_OK ||
      !sensor_bus::begin()) return;
  policyLock = xSemaphoreCreateMutex();
  if (policyLock != nullptr) {
    xTaskCreate(service, "aqua-fill", 3072, nullptr, 3, nullptr);
  }
}

bool setArmed(bool enabled) {
  if (policyLock == nullptr) return false;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  if (ready) policy.arm(enabled);
  if (!enabled) gpio_set_level(PumpPermitPin, 0);
  const bool accepted = ready;
  xSemaphoreGive(policyLock);
  return accepted;
}

void append(JsonObject telemetry, bool diagnostics = false) {
  if (policyLock == nullptr) return;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  const bool available = ready;
  const FillPolicy current = policy;
  const int permit = gpio_get_level(PumpPermitPin);
  const bool relayCommandedOn = relayRequested;
  xSemaphoreGive(policyLock);

  if (!available && !diagnostics) return;
  JsonObject fill = telemetry["fill"].to<JsonObject>();
  fill["armed"] = current.armed;
  fill["requested"] = current.requested;
  fill["running"] = current.running && permit != 0;
  fill["timed_out"] = current.timedOut;
  fill["limit_seconds"] = FillPolicy::LimitMs / 1000;
  if (diagnostics) {
    fill["io_ready"] = available;
    fill["relay_commanded_on"] = relayCommandedOn;
    if (available) fill["float_level"] = current.requested ? 0 : 1;
    fill["float_pcf_bit"] = 0;
    fill["relay_pcf_bit"] = 1;
    fill["pcf_address"] = ExpanderAddress;
    fill["pump_permit_gpio"] = PumpPermitPin;
    fill["pump_permit_level"] = permit;
  }
}
}
