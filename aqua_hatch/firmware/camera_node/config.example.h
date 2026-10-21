#pragma once
// Copy to config.h. Values below are placeholders, NOT your board pinout.
// Arduino-ESP32 3.x. Select flash size and PSRAM mode from the exact board.
// 16 MB + OPI PSRAM applies to N16R8 boards only; it is not a generic S3 setting.
#define WIFI_SSID "replace-me"
#define WIFI_PASSWORD "replace-me"
#define MQTT_HOST "mqtt.example.com"
#define MQTT_PORT 8883
#define MQTT_USER "incubator-01-camera"
#define MQTT_PASSWORD "replace-me"
#define DEVICE_ID "incubator-01"
#define CAMERA_ID "incubator-01-camera"
#define GATEWAY_ORIGIN "https://your-gateway.example.com"
// Actual PEM root certificate for EACH endpoint. Do not use setInsecure().
static const char MQTT_ROOT_CA[] = R"PEM(REPLACE_WITH_BROKER_ROOT_CA_PEM)PEM";
static const char HTTPS_ROOT_CA[] = R"PEM(REPLACE_WITH_GATEWAY_ROOT_CA_PEM)PEM";

// Set 1 ONLY after copying the pin table from your exact board vendor schematic.
#define CAMERA_PINS_CONFIRMED 0
#define CAM_PIN_PWDN -1
#define CAM_PIN_RESET -1
#define CAM_PIN_XCLK -1
#define CAM_PIN_SIOD -1
#define CAM_PIN_SIOC -1
#define CAM_PIN_D0 -1
#define CAM_PIN_D1 -1
#define CAM_PIN_D2 -1
#define CAM_PIN_D3 -1
#define CAM_PIN_D4 -1
#define CAM_PIN_D5 -1
#define CAM_PIN_D6 -1
#define CAM_PIN_D7 -1
#define CAM_PIN_VSYNC -1
#define CAM_PIN_HREF -1
#define CAM_PIN_PCLK -1
// Start with UXGA. OV5640 supports QSXGA; verify focus/upload time before changing.
#define CAMERA_FRAME_SIZE FRAMESIZE_UXGA
