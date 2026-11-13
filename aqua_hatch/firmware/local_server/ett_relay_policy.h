#pragma once

#include <math.h>
#include <stdint.h>

namespace ett_relays {
constexpr uint8_t HeaterBit = 1;
constexpr uint8_t PumpBit = 3;
constexpr uint8_t FanBit = 5;
constexpr uint8_t AllOff = 0xff;
constexpr uint8_t ThermalBits = (1u << HeaterBit) | (1u << FanBit);

enum class Output { pump, heater, fan };
enum class Result {
  applied, requiresManual, floatOpen, noTemperature,
  heaterLimit, opposingOutput
};

// Allow the previous mechanical relay to release before energizing the other
// one. Track successful writes so a stalled or failed write cannot skip this.
class ThermalRelayDelay {
 public:
  static constexpr uint32_t ReleaseMs = 100;

  uint8_t portValue(uint8_t requested, uint32_t now) const {
    const uint8_t thermalOn = ThermalBits & ~requested;
    if (thermalOn && lastThermal_ && thermalOn != lastThermal_ &&
        (!off_ || now - offAt_ < ReleaseMs)) {
      return requested | ThermalBits;
    }
    return requested;
  }

  void written(uint8_t outputs, uint32_t now) {
    const uint8_t thermalOn = ThermalBits & ~outputs;
    if (thermalOn) {
      lastThermal_ = thermalOn;
      off_ = false;
    } else if (!off_) {
      off_ = true;
      offAt_ = now;
    }
  }

 private:
  // A controller reset can leave the expander powered and its outputs latched.
  uint8_t lastThermal_ = ThermalBits;
  bool off_ = false;
  uint32_t offAt_ = 0;
};

class Policy {
 public:
  static constexpr uint32_t ManualMs = 300000;
  static constexpr uint32_t FloatDebounceMs = 500;
  static constexpr float HysteresisC = .5f;
  static constexpr float MaxHeaterC = 35.0f;

  void update(bool needsWater, float temperature, float target, uint32_t now) {
    if (!floatKnown_ || needsWater_ != needsWater) {
      floatKnown_ = true;
      needsWater_ = needsWater;
      floatChangedAt_ = now;
      lowStable_ = false;
    }
    if (needsWater && !lowStable_ && now - floatChangedAt_ >= FloatDebounceMs) {
      lowStable_ = true;
    }
    temperature_ = temperature;
    now_ = now;
    if (manual_ && now - manualStarted_ >= ManualMs) setMode(false);

    if (manual_) {
      if (!manualHeatAllowed()) heater_ = false;
      return;
    }
    if (!temperatureValid() || !isfinite(target) || target < 20 || target > 35) {
      heater_ = fan_ = false;
      return;
    }
    heater_ = temperature_ < target &&
              (heater_ || temperature_ < target - HysteresisC);
    fan_ = temperature_ > target &&
           (fan_ || temperature_ > target + HysteresisC);
  }

  void setMode(bool manual) {
    if (manual_ == manual) return;
    if (manual) manualStarted_ = now_;
    manual_ = manual;
    pumpPaused_ = false;
    heater_ = fan_ = false;
  }

  Result setOutput(Output output, bool enabled) {
    if (!manual_) return Result::requiresManual;
    switch (output) {
      case Output::pump:
        if (enabled && !needsWater()) return Result::floatOpen;
        pumpPaused_ = !enabled;
        return Result::applied;
      case Output::heater:
        if (enabled) {
          if (fan_) return Result::opposingOutput;
          if (!temperatureValid()) return Result::noTemperature;
          if (!manualHeatAllowed()) return Result::heaterLimit;
        }
        heater_ = enabled;
        return Result::applied;
      case Output::fan:
        if (enabled && heater_) return Result::opposingOutput;
        fan_ = enabled;
        return Result::applied;
    }
    return Result::requiresManual;
  }

  void resetAfterIoFault() {
    manual_ = false;
    pumpPaused_ = false;
    heater_ = fan_ = false;
    floatKnown_ = false;
    lowStable_ = false;
  }

  bool needsWater() const { return floatKnown_ && needsWater_; }
  bool fillEnabled() const { return !pumpPaused_; }

  uint32_t remainingMs(uint32_t now) const {
    const uint32_t elapsed = now - manualStarted_;
    return manual_ && elapsed < ManualMs ? ManualMs - elapsed : 0;
  }

  uint8_t portValue() const {
    uint8_t value = AllOff;
    if (lowStable_ && fillEnabled()) {
      value &= ~(1u << PumpBit);
    }
    if (heater_) value &= ~(1u << HeaterBit);
    if (fan_) value &= ~(1u << FanBit);
    return value;
  }

 private:
  bool temperatureValid() const {
    return isfinite(temperature_) && temperature_ >= 0 && temperature_ <= 50;
  }

  bool manualHeatAllowed() const {
    return temperatureValid() && temperature_ < MaxHeaterC;
  }

  bool manual_ = false;
  bool pumpPaused_ = false;
  bool heater_ = false;
  bool fan_ = false;
  bool floatKnown_ = false;
  bool lowStable_ = false;
  bool needsWater_ = false;
  uint32_t floatChangedAt_ = 0;
  uint32_t manualStarted_ = 0;
  uint32_t now_ = 0;
  float temperature_ = NAN;
};
}  // namespace ett_relays
