# AquaHatch — iOS / Android 0.14.0

แอปเครื่องฟักไข่ปลา เชื่อม ESP32-S3 และ ESP32-CAM ผ่าน Wi-Fi บ้านโดยตรง แต่ละบอร์ดมี IP แยกกัน

| ระบบ | ดาวน์โหลดล่าสุด | คู่มือ |
| --- | --- | --- |
| iPhone / iOS | [AquaHatch 0.14.0 IPA](https://github.com/Sivacxool/aquafish/raw/refs/heads/main/IOS/AquaHatch-v0.14.0-iOS-unsigned.ipa) | [IOS](IOS/README.md) — ยังไม่เซ็น ใช้ Sideloadly |
| Android / LDPlayer | [AquaHatch 0.14.0 APK Universal](https://github.com/Sivacxool/aquafish/raw/refs/heads/main/ANDROID/AquaHatch-v0.14.0-Android-universal.apk) | [ANDROID](ANDROID/README.md) — ARM32 / ARM64 / x86_64 |

ทั้งสองระบบ 0.14.0+2015 ใช้ซอร์ส [Flutter/Dart ร่วมกัน](aqua_hatch/)
[ซอร์ส ZIP](AquaHatch-v0.14.0-source.zip) · [SHA256](SHA256SUMS.txt) · [ผลตรวจ](VERIFICATION.md)

## รุ่นนี้เพิ่มอะไร

- **เปิดบอร์ดใหม่ครั้งแรก แล้วสร้างรหัสเอง:** generic firmware ของ S3/CAM สร้าง token และ ECDSA keys แยกต่อบอร์ด เก็บใน NVS
- โปรแกรม Windows ลง firmware แล้วรับ **QR ส่วนตัวผ่าน USB** ให้แอปสแกนและตั้ง Wi-Fi ได้ รหัสไม่เปลี่ยนเมื่อรีสตาร์ตหรืออัปเดตที่ไม่ล้าง NVS
- แอปตรวจ CA/hostname ของตัวที่สแกน รองรับการเก็บบอร์ดหลายตัวเพื่อเลือกใช้ โดยแสดงบอร์ดหลักและกล้องอย่างละหนึ่งตัวขณะใช้งาน
- [ดาวน์โหลด FirstBoot package](AquaHatch-v0.14.0-FirstBoot.zip) · [คู่มือ QR](FIRST_BOOT_PAIRING_TH.md)

## สิ่งที่คงจากรุ่น 0.13.0

- **วงนับมือเล็กลง** ค่าเริ่มต้นเส้นผ่านศูนย์กลาง 4 px ปรับขนาดได้ ซูมแล้ววงคงขนาดบนหน้าจอ มีขอบสีขาวบางช่วยแยกจากภาพ
- แยก **ซูม / เพิ่มจุด / ลบจุด** เพิ่มจุดใกล้หัวปลาตัวเดิมได้โดยไม่ลบกัน โหมดลบเลือกจุดที่ใกล้ที่สุด พร้อมย้อนกลับ
- เตรียม **E-201-C + PH-4502C + ADS1115** บน S3 GPIO8/9 พร้อมหน้าสอบเทียบสองจุด บันทึกในบอร์ดและเก็บสถานะใน CSV
- ตัดอัตราไหลจากแอป การตั้งค่า ประวัติ CSV และเฟิร์มแวร์ local S3; Gateway เก่ายังเก็บฟิลด์เดิมไว้เพื่อรองรับข้อมูลย้อนหลัง
- เตรียมใบรับรอง S3 730 วันด้วย CA เดิมสำหรับ iOS ต้องลงเฟิร์มแวร์ใหม่ก่อนใช้งานจริง
- คงกล้อง **OV3660 2048×1536 พร้อมแฟลช** จากเฟิร์มแวร์ 0.12.0-camera.1 รุ่นใหม่ใช้ generic firmware 0.14.0-camera.1 และยังไม่มีการแฟลชกล้องหรือ S3 ของผู้ใช้ในรอบนี้

## ต่อ pH ตามนี้ก่อนใช้

[คู่มือ pH พร้อมผังสาย](PH_ADS1115_SETUP_TH.md): ADS1115 VDD3.3V / SDA GPIO8 / SCL GPIO9 / ADDR GND / A0 รับ PO ผ่านตัวต้านทาน 10kΩ สองตัวแบ่งครึ่งแรงดัน
PH-4502C ใช้ 5V และ GND ร่วม หัววัดเสียบ BNC ไม่ต่อหัววัดหรือ PO5V ตรงเข้า ADC
ต้องอัปโหลด S3 0.13.0-sensors.1 หนึ่งครั้ง แล้วสอบเทียบด้วยน้ำยา 7.00 หรือ6.86 และ4.00 หรือ4.01
**pH รอบนี้ตรวจด้วยซอฟต์แวร์และคอมไพล์เท่านั้น ยังไม่ได้ต่อหรือทดสอบเซนเซอร์จริงตามคำขอเจ้าของ**

## เริ่มใช้งาน

[เชื่อมต่อทีละขั้น](START_HERE_TH.md) · [คู่มือ iPhone](IOS_INSTALL_TH.md) · [สร้างสำหรับบอร์ดใหม่](REBUILD.md)
DS18B20 ใช้ GPIO4; ออกซิเจน RS485 ใช้ TX16 / DE+RE17 / RX18 ตาม [คู่มือเซนเซอร์เดิม](aqua_hatch/SENSORS_SETUP_TH.md)
ยังไม่เปิดขับรีเลย์ ปั๊ม หรือฮีตเตอร์ และยังไม่มีโมเดล AI ที่ยืนยันกับภาพลูกปลาจริง จึงใช้การตรวจนับด้วยมือกับภาพจริงได้
กล้อง OV3660 เคยรับภาพจริงสำเร็จในรุ่น 0.12.0; ผลนั้นไม่ใช่การทดสอบ pH หรือการติดตั้ง 0.13.0 บนมือถือจริง

## ผลตรวจรุ่นนี้

ทดสอบ Flutter ผ่าน100รายการ ข้าม6รายการที่ต้องใช้ฮาร์ดแวร์ Native iOS / Simulator และการตรวจใบรับรองที่สร้างโดย runtime ผ่าน [CI](https://github.com/Sivacxool/aquafish/actions/runs/42090614131)
S3/CAM generic คอมไพล์ผ่าน ทดสอบ source สร้างตัวตนจริงบนคอมกับ NVS/hardware adapters จำลอง ตรวจ QR encode/decode และ TLS loopback ผ่าน
ยังไม่ได้เปิด COM/แฟลชบอร์ดผู้ใช้ หรือสแกนด้วยกล้องมือถือจริง [รายละเอียด](VERIFICATION.md)

## โค้ดหลัก

- [สร้างตัวตนในบอร์ด](aqua_hatch/firmware/libraries/AquaIdentity/src/AquaIdentity.cpp)
- [รับ QR ในแอป](aqua_hatch/lib/features/qr_pairing.dart) / [ตรวจ payload](aqua_hatch/lib/core/pairing.dart)
- [ลงเฟิร์มแวร์และรับ QR ผ่าน USB](tools/pairing_card.py)

- [จุดนับด้วยมือ](aqua_hatch/lib/features/counting.dart)
- [สอบเทียบ pH ในแอป](aqua_hatch/lib/features/ph_calibration.dart)
- [อ่าน ADS1115 และเก็บการสอบเทียบ](aqua_hatch/firmware/local_server/sensor_ph.cpp)
- [คณิตศาสตร์สอบเทียบสองจุด](aqua_hatch/firmware/local_server/ph_calibration.h)
- [ติดต่อ S3](aqua_hatch/lib/core/esp32_repository.dart) / [รับภาพกล้อง](aqua_hatch/lib/core/direct_camera.dart)
- [เฟิร์มแวร์ S3](aqua_hatch/firmware/local_server/) / [กล้อง](aqua_hatch/firmware/camera_server/)

รหัส Wi-Fi, token จับคู่จริง, private key, กุญแจเซ็นแอป และภาพจากกล้องจริงไม่รวมในซอร์สเผยแพร่
บอร์ดใหม่ต้องสร้างเอกลักษณ์และคู่ใบรับรองส่วนตัว และบิลด์แอปกับเฟิร์มแวร์ให้ตรงกันตาม REBUILD.md

## บอร์ดใหม่สร้างรหัสเองใน 0.14.0

เฟิร์มแวร์ generic ของ S3/CAM สร้าง token และใบรับรองเองในบอร์ด และจำไว้หลังรีสตาร์ต โปรแกรมลงเฟิร์มแวร์รับ QR ผ่าน USB ให้มือถือสแกน ไม่ต้องบิลด์แอปประจำบอร์ด
[เริ่มติดตั้งและจับคู่ด้วย QR](FIRST_BOOT_PAIRING_TH.md)
