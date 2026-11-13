#pragma once

#include <atomic>
#include "ett_relay_policy.h"
#include "sensor_bus.h"
#include "sensor_temperature.h"

namespace fill_control {
constexpr uint8_t ExpanderAddress = 0x38;
constexpr int FloatPin = 13;
constexpr uint32_t RelayRefreshMs = 250;

ett_relays::Policy policy;
SemaphoreHandle_t policyLock = nullptr;
std::atomic<bool> ready{false};
std::atomic<float> temperatureTarget{NAN};
uint8_t lastOutputs = ett_relays::AllOff;
uint32_t lastWriteAt = 0;

bool relayOn(uint8_t bit) {
  return (lastOutputs & (1u << bit)) == 0;
}

bool writeRelays(uint8_t outputs) {
  sensor_bus::Guard bus;
  if (!bus) return false;
  Wire.beginTransmission(ExpanderAddress);
  Wire.write(outputs);
  if (Wire.endTransmission() != 0) return false;
  lastOutputs = outputs;
  lastWriteAt = millis();
  return true;
}

void updatePolicy(uint32_t now) {
  policy.update(digitalRead(FloatPin) == LOW,
                temperature_sensor::currentCelsius(), temperatureTarget.load(), now);
}

bool applyOutputs() {
  const uint8_t outputs = policy.portValue();
  if (outputs == lastOutputs && millis() - lastWriteAt < RelayRefreshMs) return true;
  if (writeRelays(outputs)) return true;
  ready = false;
  policy.resetAfterIoFault();
  return false;
}

void service(void *) {
  for (;;) {
    xSemaphoreTake(policyLock, portMAX_DELAY);
    if (!ready) {
      ready = writeRelays(ett_relays::AllOff);
    } else {
      updatePolicy(millis());
      applyOutputs();
    }
    xSemaphoreGive(policyLock);
    vTaskDelay(pdMS_TO_TICKS(10));
  }
}

void begin() {
  pinMode(FloatPin, INPUT_PULLUP);
  if (!sensor_bus::begin()) return;
  policyLock = xSemaphoreCreateMutex();
  if (policyLock != nullptr) {
    xTaskCreate(service, "aqua-relays", 3072, nullptr, 3, nullptr);
  }
}

void setTemperatureTarget(float target) {
  temperatureTarget = target >= 20.0f && target <= 35.0f ? target : NAN;
}

enum class CommandStatus { applied, ioFault, rejected };

CommandStatus setArmed(bool enabled) {
  if (policyLock == nullptr) return CommandStatus::ioFault;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  bool available = ready;
  bool accepted = false;
  if (available) {
    const uint32_t now = millis();
    updatePolicy(now);
    accepted = policy.armAutoFill(enabled);
    if (accepted) updatePolicy(now);
    available = applyOutputs();
  }
  xSemaphoreGive(policyLock);
  if (!available) return CommandStatus::ioFault;
  return accepted ? CommandStatus::applied : CommandStatus::rejected;
}

CommandStatus setMode(bool manual) {
  if (policyLock == nullptr) return CommandStatus::ioFault;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  bool accepted = false;
  if (ready) {
    const uint32_t now = millis();
    updatePolicy(now);
    policy.setMode(manual);
    updatePolicy(now);
    accepted = applyOutputs();
  }
  xSemaphoreGive(policyLock);
  return accepted ? CommandStatus::applied : CommandStatus::ioFault;
}

CommandStatus setOutput(ett_relays::Output output, bool enabled, ett_relays::Result &reason) {
  if (policyLock == nullptr) return CommandStatus::ioFault;
  xSemaphoreTake(policyLock, portMAX_DELAY);
  bool available = ready;
  if (available) {
    const uint32_t now = millis();
    updatePolicy(now);
    reason = policy.setOutput(output, enabled);
    updatePolicy(now);
    available = applyOutputs();
  }
  xSemaphoreGive(policyLock);
  if (!available) return CommandStatus::ioFault;
  return reason == ett_relays::Result::applied ? CommandStatus::applied : CommandStatus::rejected;
}

const char *outputError(ett_relays::Output output, ett_relays::Result reason) {
  switch (reason) {
    case ett_relays::Result::requiresManual:
      return "เข้าโหมด Manual ก่อน หรือเวลา 5 นาทีหมดแล้ว";
    case ett_relays::Result::floatOpen:
      return output == ett_relays::Output::pump
        ? "ลูกลอยสั่งหยุดเติมน้ำ จึงเปิดปั๊มไม่ได้"
        : "รอระดับน้ำถึงจุดเติมและสัญญาณลูกลอยนิ่งก่อนเปิดฮีตเตอร์";
    case ett_relays::Result::noTemperature:
      return "รอค่าอุณหภูมิที่ใช้ได้จาก DS18B20";
    case ett_relays::Result::heaterLimit:
      return "อุณหภูมิถึงขีดจำกัดของฮีตเตอร์ในโหมด Manual";
    case ett_relays::Result::opposingOutput:
      return "ปิดฮีตเตอร์หรือพัดลมที่กำลังทำงานก่อน";
    default:
      return "บอร์ดปฏิเสธคำสั่ง";
  }
}

void append(JsonObject telemetry, bool diagnostics = false) {
  const bool locked = policyLock != nullptr;
  if (locked) xSemaphoreTake(policyLock, portMAX_DELAY);
  const bool available = locked && ready;
  const FillPolicy current = policy.fill;
  const uint32_t remaining = available ? policy.remainingMs(millis()) : 0;
  const bool pumpOn = available && relayOn(ett_relays::PumpBit);
  const bool heaterOn = available && relayOn(ett_relays::HeaterBit);
  const bool fanOn = available && relayOn(ett_relays::FanBit);
  if (locked) xSemaphoreGive(policyLock);

  telemetry["hardware_ready"] = available;
  telemetry["mode"] = remaining > 0 ? "manual" : "auto";
  JsonObject controls = telemetry["ett_control"].to<JsonObject>();
  controls["io_ready"] = available;
  controls["manual_remaining_ms"] = remaining;
  if (available) controls["fan_commanded_on"] = fanOn;
  JsonObject outputs = telemetry["outputs"].to<JsonObject>();
  if (available) {
    outputs["pump"] = pumpOn;
    outputs["heater"] = heaterOn;
    outputs["cooler"] = fanOn;
  }
  JsonObject heater = telemetry["heater"].to<JsonObject>();
  heater["io_ready"] = available;
  heater["relay_commanded_on"] = nullptr;
  if (available) heater["relay_commanded_on"] = heaterOn;

  if (!available && !diagnostics) return;
  JsonObject fill = telemetry["fill"].to<JsonObject>();
  fill["armed"] = current.armed;
  fill["requested"] = current.requested;
  fill["running"] = pumpOn;
  fill["timed_out"] = current.timedOut;
  fill["limit_seconds"] = FillPolicy::LimitMs / 1000;
  if (diagnostics) {
    fill["io_ready"] = available;
    fill["relay_commanded_on"] = pumpOn;
    if (available) fill["float_level"] = current.requested ? LOW : HIGH;
    fill["float_gpio"] = FloatPin;
    fill["relay_pcf_bit"] = ett_relays::PumpBit;
    fill["pcf_address"] = ExpanderAddress;
    heater["relay_pcf_bit"] = ett_relays::HeaterBit;
    controls["fan_relay_pcf_bit"] = ett_relays::FanBit;
  }
}
}
