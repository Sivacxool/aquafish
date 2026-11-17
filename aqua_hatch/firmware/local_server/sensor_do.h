#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include "temperature_fusion.h"
namespace oxygen_sensor {
void begin();
void tick();
void append(JsonObject telemetry);
bool enabled();
temperature_fusion::Reading temperatureReading();
}
