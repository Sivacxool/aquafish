# AquaHatch 0.15.0 สำหรับ ESP32-WROOM-DA

AquaHatch อ่านอุณหภูมิ DO และ pH จาก ESP32-WROOM-DA และรับภาพจาก AI Thinker ESP32-CAM ผ่าน Wi-Fi บ้าน แต่ละบอร์ดมี IP และ QR จับคู่ของตัวเอง

| ชุดติดตั้ง | ดาวน์โหลด |
| --- | --- |
| เฟิร์มแวร์และตัวติดตั้ง Windows | [FirstBoot ZIP](AquaHatch-v0.15.0-FirstBoot.zip) |
| Android / LDPlayer | [APK Universal](https://github.com/Sivacxool/aquafish/raw/refs/heads/main/ANDROID/AquaHatch-v0.15.0-Android-universal.apk) |
| iPhone | [IPA สำหรับ Sideloadly](https://github.com/Sivacxool/aquafish/raw/refs/heads/main/IOS/AquaHatch-v0.15.0-iOS-unsigned.ipa) |
| ซอร์ส | [Source ZIP](AquaHatch-v0.15.0-source.zip) |

## สายเซนเซอร์บนบอร์ดหลัก

| อุปกรณ์ | สายสัญญาณ | GPIO |
| --- | --- | --- |
| DS18B20 | DATA | 4 |
| RS485 ของหัววัด DO | DI / TX | 16 |
| RS485 ของหัววัด DO | DE + /RE | 17 |
| RS485 ของหัววัด DO | RO / RX | 18 |
| ADS1115 ของหัววัด pH | SDA | **21** |
| ADS1115 ของหัววัด pH | SCL | **22** |

ย้ายเฉพาะ SDA และ SCL จากผัง S3 เดิม GPIO8/9 ของ ESP32 รุ่นคลาสสิกใช้กับ Flash ชุดนี้เลือกโปรไฟล์ Arduino **ESP32-WROOM-DA Module** และตั้ง Flash **4 MB** ตามบอร์ดที่อ่านได้บน COM5 พอร์ตอาจเปลี่ยนตามเครื่อง

อ่านวงจรไฟเลี้ยงและระดับสัญญาณใน [คู่มือเซนเซอร์](aqua_hatch/SENSORS_SETUP_TH.md) และ [คู่มือ pH](PH_ADS1115_SETUP_TH.md) หลังย้ายหัววัด pH ไปบอร์ดใหม่ให้สอบเทียบสองจุดอีกครั้ง เพราะค่าที่บันทึกบนบอร์ดเดิมอยู่ใน NVS ของบอร์ดเดิม

## ติดตั้ง

1. แตก FirstBoot ZIP ต่อ WROOM-DA ผ่าน USB แล้วเปิด `Install-WROOM-DA.cmd` เลือก COM ของบอร์ดหลัก
2. โปรแกรมเปิดบัตร QR ส่วนตัวบนคอม เปิด AquaHatch → **ตั้งค่า → บอร์ดใหม่? สแกน QR เพื่อจับคู่**
3. เลือก Wi-Fi 2.4 GHz ของบ้านตามขั้นตอนในแอป แล้วเปิดภาพรวมตรวจค่าเซนเซอร์

เฟิร์มแวร์สร้าง token และใบรับรองต่อบอร์ด เก็บไว้ใน NVS และรับบัตรผ่าน USB รูปแบบ QR ใช้กับ AquaHatch 0.14.0 ขึ้นไป รุ่น 0.15.0 ปรับหน้าจอและคำแนะนำให้ตรงกับบอร์ดหลักรุ่นนี้ บอร์ดกล้องใช้ไฟล์ `Install-CAM.cmd` และพอร์ตของกล้องเอง

[คู่มือ QR](FIRST_BOOT_PAIRING_TH.md) · [เริ่มใช้งาน](START_HERE_TH.md) · [คู่มือ iPhone](IOS_INSTALL_TH.md) · [วิธีคอมไพล์](REBUILD.md) · [ผลทดสอบ](VERIFICATION.md) · [SHA256](SHA256SUMS.txt)

## โค้ดหลัก

- [เฟิร์มแวร์บอร์ดหลัก](aqua_hatch/firmware/local_server/) และ [ผังขาในซอร์ส](aqua_hatch/firmware/local_server/sensor_config.h)
- [รับข้อมูล ESP32](aqua_hatch/lib/core/esp32_repository.dart) และ [รับภาพกล้อง](aqua_hatch/lib/core/direct_camera.dart)
- [จับคู่ด้วย QR](aqua_hatch/lib/features/qr_pairing.dart) และ [ตัวติดตั้ง USB](tools/pairing_card.py)
- [อ่านและสอบเทียบ pH](aqua_hatch/firmware/local_server/sensor_ph.cpp) และ [หน้านับลูกปลา](aqua_hatch/lib/features/counting.dart)

ชุดแจกจ่ายเป็นเฟิร์มแวร์เปล่าสำหรับบอร์ดแต่ละชนิด เก็บบัตร QR และไฟล์สำรอง Flash เป็นส่วนตัว
