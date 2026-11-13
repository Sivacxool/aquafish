#pragma once
#if defined(AQUAHATCH_ET_WROOM32UE)
constexpr int DO_UART = 2;
constexpr int DO_TX_PIN = 27;
constexpr int DO_RX_PIN = 26;
constexpr int DO_DIRECTION_PIN = -1; // MAX13487E onboard AutoDirection.
constexpr int TEMPERATURE_DATA_PIN = 32; // IO32 solder pad beside the ESP32-WROOM-32UE module.
constexpr char BOARD_PROFILE[] = "et-esp32-wroom32ue-v1";
constexpr bool PH_RS485_ENABLED = true;
constexpr uint32_t PH_RS485_BAUD = 9600;
constexpr uint8_t PH_RS485_ADDRESS = 1;
#else
constexpr int DO_UART = 1;
constexpr int TEMPERATURE_DATA_PIN = 4;
constexpr char BOARD_PROFILE[] = "esp32-wroom-da";
constexpr bool PH_RS485_ENABLED = false;
constexpr uint32_t PH_RS485_BAUD = 0;
constexpr uint8_t PH_RS485_ADDRESS = 0;
constexpr int DO_TX_PIN = 16;    // MAX485 DI
constexpr int DO_DIRECTION_PIN = 17; // MAX485 DE and /RE joined
constexpr int DO_RX_PIN = 18;    // MAX485 RO, MUST be <=3.3V logic
#endif
constexpr uint32_t DO_BAUD = 4800; // Manufacturer factory default, 8N1
constexpr uint8_t DO_ADDRESS = 1;
// User confirmed transceiver VCC=3.3V and direct RO->GPIO18 on 2026-10-30.
// A genuine MAX485 is specified for 5V; if unreliable, use a 3.3V MAX3485
// or a 5V transceiver with a proper RO level converter. Never drive GPIO at 5V.
constexpr bool DO_ENABLED = true;
// On WROOM-DA: ADS1115 VDD=3.3V, ADDR=GND (0x48). PH-4502C PO MUST pass through
// 10k to A0 and another 10k from A0 to GND. PH board V+=5V, all GND joined.
// Classic ESP32 GPIO6–11 are reserved for SPI flash.
constexpr int PH_SDA_PIN = 21;
constexpr int PH_SCL_PIN = 22;
#if !defined(CONFIG_IDF_TARGET_ESP32)
#error "AquaHatch main controller requires a classic ESP32."
#elif defined(AQUAHATCH_ET_WROOM32UE) && !defined(ARDUINO_ESP32_DEV)
#error "Select ESP32 Dev Module for the ET-ESP32 WROOM 32UE V1."
#elif !defined(AQUAHATCH_ET_WROOM32UE) && !defined(ARDUINO_ESP32_WROOM_DA)
#error "Select ESP32-WROOM-DA Module or use the ett32ue build profile."
#endif
static_assert(PH_SDA_PIN >= 12 && PH_SCL_PIN >= 12,
              "Keep I2C away from the ESP32 flash pins.");
constexpr uint8_t PH_ADS_ADDRESS=0x48;
