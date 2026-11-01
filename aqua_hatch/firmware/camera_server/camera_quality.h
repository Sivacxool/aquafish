#pragma once
#include "esp_camera.h"

struct AquaFocusResult {
  bool requested=false, firmwareReady=false, focused=false;
  uint8_t raw=0;
  uint32_t initMs=0, searchMs=0;
  const char *status="not_requested";
};
AquaFocusResult aquaPrepareFocus(sensor_t *sensor, bool requested);
void aquaRunFocus(sensor_t *sensor, AquaFocusResult &result);
