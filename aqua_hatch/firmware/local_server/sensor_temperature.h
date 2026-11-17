#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include "temperature_fusion.h"

// DS18B20: externally powered, DATA pin per board profile with a 4.7k pull-up to 3.3V.
// All bus access is owned by loop(); HTTPS handlers only copy the snapshot.
namespace temperature_sensor {
void begin();
void tick();
// Returns NAN when the latest sample is invalid or stale.
float currentCelsius();
temperature_fusion::Reading temperatureReading();
void append(JsonObject telemetry);
}
