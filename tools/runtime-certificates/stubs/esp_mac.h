#pragma once
#include <cstring>
constexpr int ESP_OK=0,ESP_MAC_WIFI_STA=0;
inline unsigned char mockMac[6]={0xaa,0xbb,0xcc,0xdd,0xee,0x01};
inline int esp_read_mac(unsigned char *out,int){std::memcpy(out,mockMac,6);return ESP_OK;}
