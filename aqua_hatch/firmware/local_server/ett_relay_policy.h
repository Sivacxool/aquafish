#pragma once

#include <math.h>
#include <stdint.h>
#include "fill_policy.h"

namespace ett_relays {
constexpr uint8_t HeaterBit = 1;
constexpr uint8_t PumpBit = 3;
constexpr uint8_t FanBit = 5;
constexpr uint8_t AllOff = 0xff;

enum class Output { pump, heater, fan };
enum class Result {
  applied, requiresManual, floatOpen, noTemperature,
  heaterLimit, opposingOutput
};

class Policy {
 public:
  static constexpr uint32_t ManualMs = 300000;
  static constexpr float HysteresisC = .5f;

  void update(bool needsWater, float temperature, float target, uint32_t now) {
    if (!floatKnown_ || needsWater_ != needsWater) {
      floatKnown_ = true;
      needsWater_ = needsWater;
      floatChangedAt_ = now;
    }
    temperature_ = temperature;
    target_ = target;
    now_ = now;
    if (manual_ && now - manualStarted_ >= ManualMs) setMode(false);

    fill.sample(needsWater, now);
    if (manual_ && !needsWater && fill.armed) fill.arm(false);
    if (fill.timedOut) autoFillArmed_ = false;

    if (manual_) {
      // Cancel an active request when a guard trips. Sensor recovery by itself
      // must not re-enable a manual heater or fan.
      if (!manualHeatAllowed()) heater_ = false;
      if (!temperatureValid()) fan_ = false;
      return;
    }
    if (!temperatureValid()) {
      heater_ = fan_ = false;
      return;
    }
    heater_ = levelAllowsHeat() && temperature_ < target_ &&
              (heater_ || temperature_ < target_ - HysteresisC);
    fan_ = temperature_ > target_ &&
           (fan_ || temperature_ > target_ + HysteresisC);
  }

  void setMode(bool manual) {
    if (manual_ == manual) return;
    if (manual) {
      autoFillArmed_ = fill.armed;
      manualStarted_ = now_;
    }
    manual_ = manual;
    heater_ = fan_ = false;
    fill.arm(!manual_ && autoFillArmed_);
  }

  bool armAutoFill(bool enabled) {
    if (manual_) return false;
    autoFillArmed_ = enabled;
    fill.arm(enabled);
    return true;
  }

  Result setOutput(Output output, bool enabled) {
    if (!manual_) return Result::requiresManual;
    switch (output) {
      case Output::pump:
        if (enabled && needsWater_ == false) return Result::floatOpen;
        fill.arm(enabled);
        return Result::applied;
      case Output::heater:
        if (enabled) {
          if (!temperatureValid()) return Result::noTemperature;
          if (!levelAllowsHeat()) return Result::floatOpen;
          if (!manualHeatAllowed()) return Result::heaterLimit;
          if (fan_) return Result::opposingOutput;
        }
        heater_ = enabled;
        return Result::applied;
      case Output::fan:
        if (enabled) {
          if (!temperatureValid()) return Result::noTemperature;
          if (heater_) return Result::opposingOutput;
        }
        fan_ = enabled;
        return Result::applied;
    }
    return Result::requiresManual;
  }

  void resetAfterIoFault() {
    manual_ = false;
    autoFillArmed_ = false;
    fill.arm(false);
    heater_ = fan_ = false;
    // Require a new stable float sample before automatic heat can resume.
    floatKnown_ = false;
  }

  bool manual() const { return manual_; }
  uint32_t remainingMs(uint32_t now) const {
    const uint32_t elapsed = now - manualStarted_;
    return manual_ && elapsed < ManualMs ? ManualMs - elapsed : 0;
  }

  uint8_t portValue() const {
    uint8_t value = AllOff;
    if (fill.running) value &= ~(1u << PumpBit);
    if (heater_) value &= ~(1u << HeaterBit);
    if (fan_) value &= ~(1u << FanBit);
    return value;
  }

  FillPolicy fill;

 private:
  bool temperatureValid() const {
    return isfinite(temperature_) && temperature_ >= 0 && temperature_ <= 50 &&
           isfinite(target_) && target_ >= 20 && target_ <= 35;
  }

  bool levelAllowsHeat() const {
    return floatKnown_ && !needsWater_ &&
           now_ - floatChangedAt_ >= FillPolicy::StableStopMs;
  }

  bool manualHeatAllowed() const {
    return temperatureValid() && levelAllowsHeat() &&
           temperature_ < fminf(35.0f, target_ + 1.0f);
  }

  bool manual_ = false;
  bool autoFillArmed_ = false;
  bool heater_ = false;
  bool fan_ = false;
  bool floatKnown_ = false;
  bool needsWater_ = false;
  uint32_t floatChangedAt_ = 0;
  uint32_t manualStarted_ = 0;
  uint32_t now_ = 0;
  float temperature_ = NAN;
  float target_ = NAN;
};
}  // namespace ett_relays
