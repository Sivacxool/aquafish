#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
namespace oxygen_sensor {
void begin();
void tick();
void append(JsonObject telemetry);
bool enabled();
}
