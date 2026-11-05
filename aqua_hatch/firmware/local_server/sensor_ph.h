#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
namespace ph_sensor {
void begin();
void tick();
void append(JsonObject telemetry);
bool calibrate(float bufferPh,bool startNew,String &message);
}
