#pragma once
#include "ett_relay_policy.h"

namespace ett_relays {
class BootSound {
 public:
  static constexpr uint32_t CountdownMs = 3000;
  static constexpr uint32_t PumpPulseMs = 40;
  static constexpr uint32_t WifiPulseMs = 35;
  static constexpr uint32_t WifiSpacingMs = 100;

  uint8_t portValue(uint8_t requested, bool fillWanted, uint32_t now) {
    constexpr uint8_t pumpMask = 1u << PumpBit;
    if (phase_ == Phase::finished) return requested;
    if (!fillWanted) {
      cancelPump();
      return requested | pumpMask;
    }
    if (phase_ == Phase::waiting && (requested & pumpMask) == 0) {
      phase_ = Phase::countdown;
      pumpStartedAt_ = now;
    }
    if (phase_ == Phase::countdown && now - pumpStartedAt_ >= CountdownMs) {
      phase_ = Phase::finished;
      return requested;
    }
    return requested | pumpMask;
  }

  void cancelPump() { phase_ = Phase::finished; }

  void wifiConnected() { wifiPending_ = true; }

  bool buzzerOn(uint32_t now) {
    if (phase_ == Phase::countdown) {
      if (wifiPlaying_) {
        wifiPlaying_ = false;
        wifiPending_ = true;
      }
      const uint32_t elapsed = now - pumpStartedAt_;
      return elapsed < CountdownMs && elapsed % 1000 < PumpPulseMs;
    }
    if (!wifiPlaying_) {
      if (!wifiPending_) return false;
      wifiPending_ = false;
      wifiPlaying_ = true;
      wifiStartedAt_ = now;
    }
    const uint32_t elapsed = now - wifiStartedAt_;
    if (elapsed >= WifiSpacingMs + WifiPulseMs) {
      wifiPlaying_ = false;
      return false;
    }
    return elapsed < WifiPulseMs || elapsed >= WifiSpacingMs;
  }

 private:
  enum class Phase { waiting, countdown, finished };
  Phase phase_ = Phase::waiting;
  uint32_t pumpStartedAt_ = 0;
  uint32_t wifiStartedAt_ = 0;
  bool wifiPending_ = false;
  bool wifiPlaying_ = false;
};
}  // namespace ett_relays
