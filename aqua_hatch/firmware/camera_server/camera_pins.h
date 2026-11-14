#pragma once
// Standard ESP32-CAM (ESP32-S) camera connector profile from Espressif's
// CAMERA_MODEL_AI_THINKER. Only for this USB-only camera test assembly.
// Sensor PID and actual JPEG capture must be verified after initialization.
#define PWDN_GPIO_NUM 32
#define RESET_GPIO_NUM -1
#define XCLK_GPIO_NUM 0
#define SIOD_GPIO_NUM 26
#define SIOC_GPIO_NUM 27
#define Y9_GPIO_NUM 35
#define Y8_GPIO_NUM 34
#define Y7_GPIO_NUM 39
#define Y6_GPIO_NUM 36
#define Y5_GPIO_NUM 21
#define Y4_GPIO_NUM 19
#define Y3_GPIO_NUM 18
#define Y2_GPIO_NUM 5
#define VSYNC_GPIO_NUM 25
#define HREF_GPIO_NUM 23
#define PCLK_GPIO_NUM 22
// Standard AI Thinker flash LED. The 1-bit SD bus does not use GPIO4.
#define FLASH_GPIO_NUM 4
