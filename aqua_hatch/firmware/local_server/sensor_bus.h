#pragma once
#include <Wire.h>
#include <freertos/semphr.h>
#include "sensor_config.h"

namespace sensor_bus {
inline SemaphoreHandle_t lock = nullptr;
inline bool ready = false;

inline bool begin() {
  if (ready) return true;
  if (lock == nullptr) lock = xSemaphoreCreateMutex();
  if (lock == nullptr) return false;
  ready = Wire.begin(PH_SDA_PIN, PH_SCL_PIN, 100000);
  if (ready) Wire.setTimeOut(20);
  return ready;
}

class Guard {
 public:
  Guard() : held_(ready && xSemaphoreTake(lock, pdMS_TO_TICKS(60)) == pdTRUE) {}
  ~Guard() { if (held_) xSemaphoreGive(lock); }
  explicit operator bool() const { return held_; }
  Guard(const Guard &) = delete;
  Guard &operator=(const Guard &) = delete;

 private:
  bool held_;
};
}
