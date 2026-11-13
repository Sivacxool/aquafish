#include <cassert>
#include <cstdint>
#include "../aqua_hatch/firmware/local_server/ett_relay_policy.h"

using ett_relays::Output;
using ett_relays::Policy;
using ett_relays::Result;

static constexpr uint8_t Off = 0xff;
static constexpr uint8_t Heater = 0xfd;
static constexpr uint8_t Pump = 0xf7;
static constexpr uint8_t Fan = 0xdf;

void automaticTemperature() {
  Policy policy;
  policy.update(false, 27.0f, 28, 0);
  assert(policy.portValue() == Off);
  policy.update(false, 27.0f, 28, 1999);
  assert(policy.portValue() == Off);
  policy.update(false, 27.5f, 28, 2000);
  assert(policy.portValue() == Off);
  policy.update(false, 27.4f, 28, 2010);
  assert(policy.portValue() == Heater);
  policy.update(false, 27.9f, 28, 2020);
  assert(policy.portValue() == Heater);
  policy.update(false, 28.0f, 28, 2030);
  assert(policy.portValue() == Off);
  policy.update(false, 28.5f, 28, 2040);
  assert(policy.portValue() == Off);
  policy.update(false, 28.6f, 28, 2050);
  assert(policy.portValue() == Fan);
  policy.update(false, 28.1f, 28, 2060);
  assert(policy.portValue() == Fan);
  policy.update(false, 28.0f, 28, 2070);
  assert(policy.portValue() == Off);
  policy.update(false, 29, 28, 2080);
  assert(policy.portValue() == Fan);
  policy.update(false, 26, 28, 2090);
  assert(policy.portValue() == Heater);
  policy.update(true, 26, 28, 2100);
  assert(policy.portValue() == Off);
  policy.update(true, 29, 28, 2110);
  assert(policy.portValue() == Fan);
  policy.update(true, NAN, 28, 2120);
  assert(policy.portValue() == Off);
}

void manualTemperature() {
  Policy policy;
  policy.update(false, 27, 28, 0);
  policy.update(false, 27, 28, 2000);
  assert(policy.setOutput(Output::fan, true) == Result::requiresManual);
  policy.setMode(true);
  assert(policy.portValue() == Off);
  assert(policy.remainingMs(2000) == Policy::ManualMs);
  assert(policy.setOutput(Output::heater, true) == Result::applied);
  assert(policy.portValue() == Heater);
  assert(policy.setOutput(Output::fan, true) == Result::opposingOutput);
  policy.update(false, 29, 28, 2010);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::heater, true) == Result::heaterLimit);
  assert(policy.setOutput(Output::fan, true) == Result::applied);
  assert(policy.portValue() == Fan);
  policy.update(false, NAN, 28, 2020);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::fan, true) == Result::noTemperature);
  policy.update(false, 27, 28, 2030);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::heater, true) == Result::applied);
  policy.update(true, 27, 28, 2040);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::heater, true) == Result::floatOpen);
  assert(policy.setOutput(Output::heater, false) == Result::applied);
  policy.update(false, 27, 28, 2050);
  policy.update(false, 27, 28, 4050);
  assert(policy.portValue() == Off);
  policy.resetAfterIoFault();
  assert(!policy.manual() && policy.portValue() == Off);
  policy.update(false, 27, 28, 4060);
  assert(policy.portValue() == Off);
  policy.update(false, 27, 28, 6060);
  assert(policy.portValue() == Heater);
}

void manualFill() {
  Policy policy;
  policy.update(true, 28, 28, 0);
  policy.setMode(true);
  assert(!policy.armAutoFill(true));
  assert(policy.setOutput(Output::pump, true) == Result::applied);
  policy.update(true, 28, 28, 499);
  assert(policy.portValue() == Off);
  policy.update(true, 28, 28, 500);
  assert(policy.portValue() == Pump);
  policy.update(false, 28, 28, 510);
  assert(policy.portValue() == Off && !policy.fill.armed);
  assert(policy.setOutput(Output::pump, true) == Result::floatOpen);
  policy.update(true, 28, 28, 520);
  policy.update(true, 28, 28, 1020);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::pump, true) == Result::applied);
  policy.update(true, 28, 28, 1020);
  assert(policy.portValue() == Pump);
  policy.update(true, 28, 28, 61020);
  assert(policy.portValue() == Off && policy.fill.timedOut);
  policy.update(true, 28, 28, Policy::ManualMs);
  assert(!policy.manual() && !policy.fill.armed);
}

void manualExpiry() {
  Policy policy;
  constexpr uint32_t Start = UINT32_MAX - 1000;
  policy.update(false, 29, 28, Start);
  assert(policy.armAutoFill(true));
  assert(policy.portValue() == Fan);
  policy.setMode(true);
  assert(policy.portValue() == Off && !policy.fill.armed);
  policy.update(false, 29, 28, Start + 10000);
  policy.setMode(true);
  assert(policy.remainingMs(Start + 10000) == Policy::ManualMs - 10000);
  policy.update(false, 29, 28, Start + Policy::ManualMs - 1);
  assert(policy.manual() && policy.portValue() == Off);
  policy.update(false, 29, 28, Start + Policy::ManualMs);
  assert(!policy.manual() && policy.portValue() == Fan && policy.fill.armed);
  policy.resetAfterIoFault();
  assert(!policy.fill.armed && policy.portValue() == Off);
}

int main() {
  automaticTemperature();
  manualTemperature();
  manualFill();
  manualExpiry();
}
