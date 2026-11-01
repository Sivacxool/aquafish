#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>

// DS18B20: externally powered, DATA GPIO4 with external 4.7k pull-up to 3.3V.
// All bus access is owned by loop(); HTTPS handlers only copy the snapshot.
namespace temperature_sensor {
void begin();
void tick();
void append(JsonObject telemetry);
}
