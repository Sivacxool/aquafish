#pragma once
#include <Arduino.h>
#include <ArduinoJson.h>
#include "temperature_fusion.h"
namespace ph_sensor {
#if defined(AQUAHATCH_ET_WROOM32UE)
// Shared RS485 poller calls these after validating the response frame.
void recordModbusReply(const uint8_t *registers);
void recordModbusFailure(const char *status);
#else
void begin();
void tick();
#endif
void append(JsonObject telemetry);
temperature_fusion::Reading temperatureReading();
bool calibrate(float bufferPh,bool startNew,String &message);
}
