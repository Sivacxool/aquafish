#pragma once
#include "temperature_fusion.h"
#include "sensor_temperature.h"
#include "sensor_do.h"
#include "sensor_ph.h"

namespace water_temperature {
inline temperature_fusion::Summary current() {
  const auto jar = oxygen_sensor::temperatureReading();
  const auto fry = temperature_sensor::temperatureReading();
  const auto reservoir = ph_sensor::temperatureReading();
  return temperature_fusion::summarize(jar, fry, reservoir, millis());
}

inline void append(JsonObject telemetry) {
  const auto jar = oxygen_sensor::temperatureReading();
  const auto fry = temperature_sensor::temperatureReading();
  const auto reservoir = ph_sensor::temperatureReading();
  const uint32_t now = millis();
  const auto summary = temperature_fusion::summarize(jar, fry, reservoir, now);
  telemetry["water_temperature_c"] = nullptr;
  if (summary.count) telemetry["water_temperature_c"] = summary.mean;
  telemetry["water_temperature_status"] = summary.status();
  telemetry["water_temperature_count"] = summary.count;
  telemetry["water_temperature_expected"] = temperature_fusion::Expected;
  telemetry["temperature_control_ready"] = summary.complete();
  telemetry["temperature_control_source"] = "three_point_average";
  telemetry["ds18b20_temperature_status"] = fry.status(now);
  telemetry["do_temperature_status"] = jar.status(now);
  telemetry["ph_temperature_status"] = reservoir.status(now);
  telemetry["temperature_age_ms"] = now - fry.sampledMs;
  telemetry["do_temperature_age_ms"] = now - jar.sampledMs;
  telemetry["ph_temperature_age_ms"] = now - reservoir.sampledMs;
  // Use the same snapshot for all temperatures and their average. JSON sensor
  // appenders may have run just before a new sample arrived on another task.
  telemetry["temperature_c"] = nullptr;
  telemetry["do_temperature_c"] = nullptr;
  telemetry["ph_temperature_c"] = nullptr;
  if (fry.valid(now)) telemetry["temperature_c"] = fry.celsius;
  if (jar.valid(now)) telemetry["do_temperature_c"] = jar.celsius;
  if (reservoir.valid(now)) telemetry["ph_temperature_c"] = reservoir.celsius;
  telemetry["sensors"]["temperature"]["location"] = "fry_tank";
  telemetry["sensors"]["dissolved_oxygen"]["location"] = "mcdonald_jar";
  telemetry["sensors"]["ph"]["location"] = "reservoir";
}
}
