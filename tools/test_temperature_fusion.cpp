#include <cassert>
#include <cmath>
#include <cstring>
#include <initializer_list>
#include "../aqua_hatch/firmware/local_server/temperature_fusion.h"
#include "../aqua_hatch/firmware/local_server/ett_relay_policy.h"

using temperature_fusion::Reading;
using temperature_fusion::summarize;
int main() {
  const Reading jar{27, 100, "ok"}, reservoir{33, 300, "ok"};
  const auto all = summarize(jar, reservoir, 500);
  assert(all.count == 2 && all.complete() && all.mean == 30 && all.maximum == 33);
  assert(all.controlCelsius() == 30 && strcmp(all.status(), "ok") == 0);
  for (const Reading bad : {Reading{NAN, 300, "ok"}, Reading{85, 300, "ok"},
       Reading{-127, 300, "ok"}, Reading{INFINITY, 300, "ok"},
       Reading{33, 300, "timeout"}, Reading{33, 300, "crc_error"},
       Reading{33, 0, "ok"}}) {
    const auto partial = summarize(Reading{27, 10100, "ok"}, bad, 10100);
    assert(partial.count == 1 && partial.mean == 27);
    assert(!partial.complete() && isnan(partial.controlCelsius()));
    assert(strcmp(partial.status(), "partial") == 0);
  }
  const auto absent = summarize({}, {}, 0);
  assert(absent.count == 0 && isnan(absent.mean) && isnan(absent.maximum));
  assert(Reading({0, 0, "ok"}).valid(10000));
  assert(!Reading({0, 0, "ok"}).valid(10001));
  assert(Reading({50, UINT32_MAX - 100, "ok"}).valid(100));
  assert(!Reading({50, UINT32_MAX - 100, "ok"}).valid(10000));

  ett_relays::Policy policy;
  const auto cold = summarize({25, 0, "ok"}, {29, 0, "ok"}, 0);
  policy.update(true, cold.controlCelsius(), 28, 0, cold.maximum);
  assert((policy.portValue() & (1u << ett_relays::HeaterBit)) == 0);
  const auto incomplete = summarize({25, 0, "ok"}, {}, 500);
  policy.update(true, incomplete.controlCelsius(), 28, 500, incomplete.maximum); // Missing one location: thermal OFF; pump still runs.
  assert(policy.portValue() == uint8_t(0xff & ~(1u << ett_relays::PumpBit)));
  policy.update(false, 27, 28, 600, 35); // The average cannot hide an overheated location.
  assert(policy.portValue() == 0xff);
  policy.setMode(true);
  assert(policy.setOutput(ett_relays::Output::heater, true) == ett_relays::Result::heaterLimit);
  policy.update(false, NAN, 28, 610, 29);
  assert(policy.setOutput(ett_relays::Output::heater, true) == ett_relays::Result::noTemperature);
  assert(policy.setOutput(ett_relays::Output::fan, true) == ett_relays::Result::applied);
}
