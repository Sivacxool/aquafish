#pragma once
#include <cmath>

// Voltages are measured at ADS1115 A0 AFTER the 10k/10k divider.
// Calibrating here also accounts for the actual divider resistor ratio.
namespace ph_math {
inline bool inputValid(float v) { return std::isfinite(v) && v>=0.02f && v<=2.80f; }
inline bool neutralReference(float ph) { return std::fabs(ph-7.00f)<0.001f || std::fabs(ph-6.86f)<0.001f; }
inline bool acidReference(float ph) { return std::fabs(ph-4.00f)<0.001f || std::fabs(ph-4.01f)<0.001f; }
struct Calibration {
  float neutralVoltage=NAN,acidVoltage=NAN,neutralPh=7.00f,acidPh=4.00f;
  bool valid() const {
    return inputValid(neutralVoltage) && inputValid(acidVoltage) &&
      neutralReference(neutralPh) && acidReference(acidPh) &&
      std::fabs(neutralVoltage-acidVoltage)>=0.06f;
  }
  float value(float voltage) const {
    if(!valid() || !inputValid(voltage))return NAN;
    const float ph=neutralPh+(voltage-neutralVoltage)*(acidPh-neutralPh)/(acidVoltage-neutralVoltage);
    return std::isfinite(ph) && ph>=0.0f && ph<=14.0f?ph:NAN;
  }
};
}
