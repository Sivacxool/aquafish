# AquaHatch 0.19.0

AquaHatch อ่านอุณหภูมิ DO และ pH จากบอร์ดควบคุม ET-ESP32 WROOM 32UE V1 สั่งเติมน้ำ และรับภาพจากกล้อง AI Thinker ESP32-CAM + OV3660 เพื่อใช้ AI นับลูกปลาในแอป

| ชุดติดตั้ง | ดาวน์โหลด |
| --- | --- |
| Android / LDPlayer | [APK Universal](https://github.com/Sivacxool/aquafish/releases/download/v0.19.0/AquaHatch-v0.19.0-FishFryAI-Android.apk) |
| iPhone (iOS 16 ขึ้นไป) | [IPA สำหรับ Sideloadly](https://github.com/Sivacxool/aquafish/releases/download/v0.19.0/AquaHatch-v0.19.0-FishFryAI-iOS-unsigned.ipa) · [วิธีติดตั้ง](IOS_INSTALL_TH.md) |
| บอร์ดควบคุม ETT | [FirstBoot 0.19.0-ett32ue.2](https://github.com/Sivacxool/aquafish/releases/download/v0.19.0/AquaHatch-ETT-WROOM32UE-v0.19.0-ett32ue.2.zip) · [คู่มือต่อสาย](ETT_WROOM32UE_SETUP_TH.md) |
| กล้อง ESP32-CAM | [FirstBoot สำหรับกล้อง](https://github.com/Sivacxool/aquafish/releases/download/v0.19.0/AquaHatch-ESP32-CAM-FirstBoot.zip) · [คู่มือกล้อง](AquaHatch-Camera-Start-TH.md) |

## เริ่มใช้งาน

1. แตกไฟล์ FirstBoot ของ ETT แล้วเปิด `Install-ETT-WROOM32UE.cmd` เลือก COM ของโปรแกรมเมอร์บอร์ดควบคุม ใช้ผังใน [คู่มือ ETT](ETT_WROOM32UE_SETUP_TH.md) สำหรับ DS18B20, DO, ADS1115, ลูกลอย และปั๊ม
2. เปิด AquaHatch → **ตั้งค่า → สแกน QR เพื่อเพิ่มอุปกรณ์** สแกนบัตรที่โปรแกรมเปิดขึ้น แล้วตั้ง Wi-Fi 2.4 GHz ให้บอร์ด
3. หากติดตั้งกล้องใหม่ ให้แตกชุด ESP32-CAM เปิด `Install-CAM.cmd` ที่ COM ของกล้อง แล้วสแกนบัตร QR ของกล้องแยกในแอป
4. ไปที่ **นับลูกปลา** เพื่อถ่ายจากกล้องหรือเลือกภาพ แล้วกด **วิเคราะห์ด้วย AI** ตรวจแก้จุดก่อนบันทึก

บอร์ดควบคุมและกล้องใช้ Wi-Fi เดียวกันได้ แต่ละตัวมี IP และ QR ของตัวเอง [คู่มือจับคู่](FIRST_BOOT_PAIRING_TH.md) · [การเชื่อมต่อ 4 ขั้น](START_HERE_TH.md) · [ดูจากนอกบ้าน](REMOTE_SETUP_TH.md)

## ซอร์สโค้ด

- [แอป Flutter](aqua_hatch/) · [เชื่อมต่อบอร์ดหลัก](aqua_hatch/lib/core/esp32_repository.dart) · [รับภาพกล้อง](aqua_hatch/lib/core/direct_camera.dart)
- [เฟิร์มแวร์บอร์ดควบคุม](aqua_hatch/firmware/local_server/) · [เฟิร์มแวร์กล้อง](aqua_hatch/firmware/camera_server/) · [วิธีคอมไพล์](REBUILD.md)
- [รายละเอียดรุ่น](https://github.com/Sivacxool/aquafish/releases/tag/v0.19.0) · [SHA256](SHA256SUMS.txt)
