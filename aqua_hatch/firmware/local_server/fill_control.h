#pragma once
#include <driver/gpio.h>
#include "fill_policy.h"

namespace fill_control {
constexpr auto LevelPin = GPIO_NUM_27;
constexpr auto RelayDriverPin = GPIO_NUM_25;
FillPolicy policy;
portMUX_TYPE lock = portMUX_INITIALIZER_UNLOCKED;
bool ready = false;

void sampleLocked() {
  policy.sample(gpio_get_level(LevelPin) == 0, millis());
  gpio_set_level(RelayDriverPin, policy.running ? 1 : 0);
}

void service(void *) {
  for (;;) {
    portENTER_CRITICAL(&lock);
    sampleLocked();
    portEXIT_CRITICAL(&lock);
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void begin() {
  // An external pull-down on the relay driver holds it off during reset.
  if (gpio_set_level(RelayDriverPin, 0) != ESP_OK ||
      gpio_set_direction(RelayDriverPin, GPIO_MODE_INPUT_OUTPUT) != ESP_OK ||
      gpio_set_direction(LevelPin, GPIO_MODE_INPUT) != ESP_OK ||
      gpio_set_pull_mode(LevelPin, GPIO_PULLUP_ONLY) != ESP_OK) return;
  ready = xTaskCreate(service, "aqua-fill", 2048, nullptr, 3, nullptr) == pdPASS;
}

bool setArmed(bool enabled) {
  if (!ready) return false;
  portENTER_CRITICAL(&lock);
  policy.arm(enabled);
  sampleLocked();
  portEXIT_CRITICAL(&lock);
  return true;
}

void append(JsonObject telemetry, bool diagnostics = false) {
  if (!ready) return;
  portENTER_CRITICAL(&lock);
  const FillPolicy current = policy;
  const int level = gpio_get_level(LevelPin);
  const int output = gpio_get_level(RelayDriverPin);
  portEXIT_CRITICAL(&lock);

  JsonObject fill = telemetry["fill"].to<JsonObject>();
  fill["armed"] = current.armed;
  fill["requested"] = current.requested;
  fill["running"] = current.running;
  fill["timed_out"] = current.timedOut;
  fill["limit_seconds"] = FillPolicy::LimitMs / 1000;
  if (diagnostics) {
    fill["float_gpio"] = LevelPin;
    fill["float_level"] = level;
    fill["relay_gpio"] = RelayDriverPin;
    fill["relay_drive_level"] = output;
  }
}
}
