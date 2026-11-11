#include "../aqua_hatch/firmware/local_server/ph_filter.h"
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
  ph_filter::Window filter;
  const float recorded[] = {
    1.7944f, 2.4549f, 1.7168f, 2.6632f, 1.4820f,
    2.7126f, 1.8099f, 2.4921f, 2.2127f, -3.0000f,
  };
  for (unsigned i = 0; i < filter.Size; ++i) filter.add(recorded[i % 10]);
  assert(std::isnan(filter.voltage()));

  filter.reset();
  for (unsigned i = 0; i < filter.Size - 1; ++i) filter.add(1.250f);
  assert(std::isnan(filter.voltage()));
  filter.add(-3.0f);
  assert(std::fabs(filter.voltage() - 1.250f) < .001f);

  filter.reset();
  for (unsigned i = 0; i < filter.Size; ++i) {
    if (i % 4 == 0) {
      filter.add(i == 0 ? -3.0f : 2.5f);
    } else {
      filter.add(1.250f + static_cast<float>(i % 3) * .001f);
    }
  }
  const float stable = filter.voltage();
  assert(std::fabs(stable - 1.251f) < .002f);
  cal.neutralPh=7.0f;cal.acidPh=4.0f;
  assert(std::fabs(cal.value(stable) - 7.0f) < .04f);

  // A true sustained change invalidates the old cluster and is accepted later.
  filter.reset();
  for (unsigned i = 0; i < filter.Size; ++i) filter.add(1.250f);
  for (unsigned i = 0; i < 3; ++i) filter.add(1.500f);
  assert(std::isnan(filter.voltage()));
  for (unsigned i = 0; i < 12; ++i) filter.add(1.500f);
  assert(std::fabs(filter.voltage() - 1.500f) < .001f);
  filter.reset();
  assert(std::isnan(filter.voltage()));

  std::cout << "pH calibration, corrupted samples, robust cluster, and step-change checks passed\n";
}
