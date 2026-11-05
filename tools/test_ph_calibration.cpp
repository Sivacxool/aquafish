#include "../aqua_hatch/firmware/local_server/ph_calibration.h"
#include <cassert>
#include <iostream>
#include <limits>

int main() {
  ph_math::Calibration cal;
  assert(!cal.valid() && std::isnan(cal.value(1.25f)));
  cal.neutralVoltage=1.25f;cal.acidVoltage=1.50f;
  assert(cal.valid());
  assert(std::fabs(cal.value(1.25f)-7.0f)<0.001f);
  assert(std::fabs(cal.value(1.50f)-4.0f)<0.001f);
  assert(std::fabs(cal.value(1.375f)-5.5f)<0.001f);
  assert(std::isnan(cal.value(0.01f)) && std::isnan(cal.value(3.3f)));
  assert(std::isnan(cal.value(std::numeric_limits<float>::quiet_NaN())));
  assert(std::isnan(cal.value(2.7f))); // No silently clamped bogus pH.
  cal.acidVoltage=1.26f;assert(!cal.valid()); // Same buffer twice rejected.
  cal.acidVoltage=1.50f;cal.neutralPh=6.86f;cal.acidPh=4.01f;
  assert(cal.valid());assert(std::fabs(cal.value(1.375f)-5.435f)<0.001f);
  cal.neutralPh=8;assert(!cal.valid());
  cal.neutralPh=7;cal.acidPh=3;assert(!cal.valid());
  std::cout << "pH two-point calibration, buffer references, rails and invalid-input checks passed\n";
}
