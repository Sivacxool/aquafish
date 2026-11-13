#include <cassert>
#include <cstdint>
#include "../aqua_hatch/firmware/local_server/ett_relay_policy.h"

using ett_relays::Output;
using ett_relays::Policy;
using ett_relays::Result;
using ett_relays::ThermalRelayDelay;

static constexpr uint8_t Off = 0xff;
static constexpr uint8_t Heater = 0xfd;
static constexpr uint8_t Pump = 0xf7;
static constexpr uint8_t Fan = 0xdf;

void automaticFill() {
  Policy policy;
  policy.update(true, NAN, 28, 0);
  assert(policy.portValue() == Off);
  policy.update(true, NAN, 28, 499);
  assert(policy.portValue() == Off);
  policy.update(true, NAN, 28, 500);
  assert(policy.portValue() == Pump);
  policy.update(true, NAN, 28, 60500);
  assert(policy.portValue() == Pump);
  policy.update(true, NAN, 28, 3600500);
  assert(policy.portValue() == Pump);
  policy.update(false, NAN, 28, 3600510);
  assert(policy.portValue() == Off);
  policy.update(true, NAN, 28, 3600520);
  policy.update(true, NAN, 28, 3601019);
  assert(policy.portValue() == Off);
  policy.update(true, NAN, 28, 3601020);
  assert(policy.portValue() == Pump);
}

void fillClockRollover() {
  Policy policy;
  policy.update(true, NAN, 28, 500);
  policy.update(true, NAN, 28, 1000);
  assert(policy.portValue() == Pump);
  policy.update(true, NAN, 28, UINT32_MAX);
  policy.update(true, NAN, 28, 501);
  assert(policy.portValue() == Pump);
}

void automaticTemperature() {
  Policy policy;
  policy.update(true, 27.5f, 28, 0);
  assert(policy.portValue() == Off);
  policy.update(true, 27.4f, 28, 10);
  assert(policy.portValue() == Heater);
  policy.update(true, 27.9f, 28, 500);
  assert(policy.portValue() == (Heater & Pump));
  policy.update(false, 27.9f, 28, 510);
  assert(policy.portValue() == Heater);
  policy.update(false, 28.0f, 28, 520);
  assert(policy.portValue() == Off);
  policy.update(false, 28.5f, 28, 530);
  assert(policy.portValue() == Off);
  policy.update(false, 28.6f, 28, 540);
  assert(policy.portValue() == Fan);
  policy.update(true, 28.1f, 28, 550);
  assert(policy.portValue() == Fan);
  policy.update(true, 28.0f, 28, 1050);
  assert(policy.portValue() == Pump);
  policy.update(true, NAN, 28, 1060);
  assert(policy.portValue() == Pump);
}

void manualTemperature() {
  Policy policy;
  policy.update(true, 31, 28, 0);
  assert(policy.setOutput(Output::fan, true) == Result::requiresManual);
  policy.setMode(true);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::heater, true) == Result::applied);
  assert(policy.portValue() == Heater);
  assert(policy.setOutput(Output::fan, true) == Result::opposingOutput);
  policy.update(false, 32, 28, 50);
  assert(policy.portValue() == Heater);
  policy.update(false, 35, 28, 60);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::heater, true) == Result::heaterLimit);
  policy.update(false, NAN, 28, 70);
  assert(policy.setOutput(Output::heater, true) == Result::noTemperature);
  assert(policy.setOutput(Output::fan, true) == Result::applied);
  assert(policy.portValue() == Fan);
  policy.update(true, NAN, 28, 80);
  assert(policy.portValue() == Fan);
  policy.update(false, 30, 28, 90);
  assert(policy.setOutput(Output::heater, true) == Result::opposingOutput);
  assert(policy.setOutput(Output::fan, false) == Result::applied);
  assert(policy.setOutput(Output::heater, true) == Result::applied);
  policy.update(false, NAN, 28, 100);
  assert(policy.portValue() == Off);
  policy.update(false, 30, 28, 110);
  assert(policy.portValue() == Off);
}

void manualFillAndExpiry() {
  Policy policy;
  constexpr uint32_t Start = UINT32_MAX - 1000;
  policy.update(true, 28, 28, Start - 500);
  policy.update(true, 28, 28, Start);
  assert(policy.portValue() == Pump);
  policy.setMode(true);
  assert(policy.remainingMs(Start) == Policy::ManualMs);
  assert(policy.portValue() == Pump);
  assert(policy.setOutput(Output::pump, false) == Result::applied);
  assert(!policy.fillEnabled() && policy.portValue() == Off);
  assert(policy.setOutput(Output::pump, true) == Result::applied);
  assert(policy.portValue() == Pump);
  policy.update(true, 28, 28, Start + 61000);
  assert(policy.portValue() == Pump);
  policy.setMode(true);
  assert(policy.remainingMs(Start + 61000) == Policy::ManualMs - 61000);
  policy.update(false, 28, 28, Start + 61010);
  assert(policy.portValue() == Off);
  assert(policy.setOutput(Output::pump, true) == Result::floatOpen);
  policy.update(true, 28, 28, Start + 62000);
  policy.update(true, 28, 28, Start + 62500);
  assert(policy.portValue() == Pump);
  assert(policy.setOutput(Output::pump, false) == Result::applied);
  policy.update(false, 28, 28, Start + 62600);
  policy.update(true, 28, 28, Start + 62700);
  policy.update(true, 28, 28, Start + Policy::ManualMs - 1);
  assert(policy.portValue() == Off);
  policy.update(true, 28, 28, Start + Policy::ManualMs);
  assert(policy.remainingMs(Start + Policy::ManualMs) == 0);
  assert(policy.portValue() == Pump);
  policy.resetAfterIoFault();
  assert(policy.portValue() == Off);
  policy.update(true, 28, 28, Start + Policy::ManualMs + 1);
  assert(policy.portValue() == Off);
}

void thermalChangeover() {
  ThermalRelayDelay delay;
  constexpr uint32_t Start = UINT32_MAX - 10;
  assert(delay.portValue(Heater & Pump, Start - 100) == Pump);
  delay.written(Pump, Start - 100);
  assert(delay.portValue(Heater & Pump, Start - 1) == Pump);
  assert(delay.portValue(Heater & Pump, Start) == (Heater & Pump));
  delay.written(Heater & Pump, Start);
  assert(delay.portValue(Fan & Pump, Start + 1) == Pump);
  assert(delay.portValue(Fan & Pump, Start + 110) == Pump);
  delay.written(Pump, Start + 120);
  assert(delay.portValue(Fan & Pump, Start + 219) == Pump);
  delay.written(Pump, Start + 219);
  assert(delay.portValue(Fan & Pump, Start + 220) == (Fan & Pump));
  delay.written(Fan & Pump, Start + 220);
  assert(delay.portValue(Heater, Start + 221) == Off);
  delay.written(Off, Start + 221);
  assert(delay.portValue(Heater, Start + 321) == Heater);
  delay = {};
  delay.written(Off, Start + 322);
  assert(delay.portValue(Fan, Start + 421) == Off);
  assert(delay.portValue(Fan, Start + 422) == Fan);
}

int main() {
  automaticFill();
  fillClockRollover();
  automaticTemperature();
  manualTemperature();
  manualFillAndExpiry();
  thermalChangeover();
}
