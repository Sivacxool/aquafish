# ต่อฮาร์ดแวร์บอร์ดหลัก

สำหรับ ET-ESP32 WROOM 32UE V1 ให้ใช้ [ผังสาย ETT](../../ETT_WROOM32UE_SETUP_TH.md)

ESP32-WROOM-DA ต่อ DS18B20 DATA ที่ GPIO4, RS485 TX/DE/RX ที่ GPIO16/17/18 และ ADS1115 SDA/SCL ที่ GPIO21/22

ดูวงจรไฟเลี้ยงใน [คู่มือเซนเซอร์](../SENSORS_SETUP_TH.md) และ [คู่มือ pH](../../PH_ADS1115_SETUP_TH.md)
เลือกเฟิร์มแวร์ `local_server` สำหรับบอร์ดหลัก ส่วนกล้อง AI Thinker ใช้ `camera_server`
