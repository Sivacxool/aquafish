#pragma once
#include <stdint.h>

class FillPolicy {
 public:
  static constexpr uint32_t StartDelayMs = 500;
  static constexpr uint32_t StableStopMs = 2000;
  static constexpr uint32_t LimitMs = 60000;

  void arm(bool enabled) {
    if (armed == enabled) return;
    armed = enabled;
    running = false;
    timedOut = false;
    cycleActive = false;
  }

  void sample(bool needsWater, uint32_t now) {
    if (requested != needsWater) {
      requested = needsWater;
      changedAt = now;
    }
    if (!armed) return;

    if (!requested) {
      running = false;
      if (now - changedAt >= StableStopMs) cycleActive = false;
      return;
    }
    if (cycleActive && now - cycleStartedAt >= LimitMs) {
      arm(false);
      timedOut = true;
      return;
    }
    if (now - changedAt < StartDelayMs) return;
    if (!cycleActive) {
      cycleActive = true;
      cycleStartedAt = now;
    }
    running = true;
  }

  bool armed = false;
  bool requested = false;
  bool running = false;
  bool timedOut = false;

 private:
  bool cycleActive = false;
  uint32_t changedAt = 0;
  uint32_t cycleStartedAt = 0;
};
