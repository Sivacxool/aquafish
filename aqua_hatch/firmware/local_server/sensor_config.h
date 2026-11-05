#pragma once
// Confirmed wiring 2026-10-30: ESP32-S3 only; do not copy to ESP32-CAM.
constexpr int DO_TX_PIN = 16;    // MAX485 DI
constexpr int DO_DIRECTION_PIN = 17; // MAX485 DE and /RE joined
constexpr int DO_RX_PIN = 18;    // MAX485 RO, MUST be <=3.3V logic
constexpr uint32_t DO_BAUD = 4800; // Manufacturer factory default, 8N1
constexpr uint8_t DO_ADDRESS = 1;
// User confirmed transceiver VCC=3.3V and direct RO->GPIO18 on 2026-10-30.
// A genuine MAX485 is specified for 5V; if unreliable, use a 3.3V MAX3485
// or a 5V transceiver with a proper RO level converter. Never drive GPIO at 5V.
constexpr bool DO_ENABLED = true;
// ADS1115 VDD=3.3V, ADDR=GND (0x48). PH-4502C PO MUST pass through
// 10k to A0 and another 10k from A0 to GND. PH board V+=5V, all GND joined.
constexpr int PH_SDA_PIN=8;
constexpr int PH_SCL_PIN=9;
constexpr uint8_t PH_ADS_ADDRESS=0x48;
