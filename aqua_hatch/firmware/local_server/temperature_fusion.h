#pragma once
#include <stdint.h>
#include <math.h>
#include <string.h>

namespace temperature_fusion {
constexpr uint32_t StaleMs = 10000;
constexpr uint8_t Expected = 3;
// Operational water-temperature range, shared with the app. Never clamp or
// substitute a failed sample; retain the reason and omit it from the average.
struct Reading {
  float celsius = NAN;
  uint32_t sampledMs = 0;
  const char *state = "unavailable";

  const char *status(uint32_t now) const {
    if (strcmp(state, "ok") != 0) return state;
    if (now - sampledMs > StaleMs) return "stale";
    if (!isfinite(celsius) || celsius < 0 || celsius > 50) return "invalid_value";
    return "ok";
  }
  bool valid(uint32_t now) const { return strcmp(status(now), "ok") == 0; }
};

struct Summary {
  float mean = NAN;
  float maximum = NAN;
  uint8_t count = 0;
  bool complete() const { return count == Expected; }
  // Do not silently change the thermostat's measurement locations after a
  // disconnect. Partial averages are display-only until all three recover.
  float controlCelsius() const { return complete() ? mean : NAN; }
  const char *status() const {
    return complete() ? "ok" : count ? "partial" : "unavailable";
  }
};

inline Summary summarize(const Reading &jar, const Reading &fryTank,
                         const Reading &reservoir, uint32_t now) {
  Summary result;
  float sum = 0;
  const Reading readings[] = {jar, fryTank, reservoir};
  for (const Reading &reading : readings) {
    if (!reading.valid(now)) continue;
    sum += reading.celsius;
    result.maximum = result.count ? fmaxf(result.maximum, reading.celsius) : reading.celsius;
    ++result.count;
  }
  if (result.count) result.mean = sum / result.count;
  return result;
}
}
