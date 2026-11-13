# Smart Catfish System · AquaHatch 0.21.0

รุ่นทดลองดีไซน์ใหม่บนสาขา `codex/aquahatch-redesign` แยกจากรุ่นหลัก ใช้ Flutter ชุดเดียวสำหรับ Android/iOS และคงข้อมูลจับคู่เดิมเมื่ออัปเดตทับ

| ชุดติดตั้ง | ดาวน์โหลด |
| --- | --- |
| Android / LDPlayer | [APK Universal](https://github.com/Sivacxool/aquafish/releases/download/v0.21.0-preview/AquaHatch-v0.21.0-Redesign-Android.apk) |
| iPhone iOS 16+ | [IPA unsigned](https://github.com/Sivacxool/aquafish/releases/download/v0.21.0-preview/AquaHatch-v0.21.0-Redesign-iOS-unsigned.ipa) · [วิธีเซ็นและติดตั้ง](IOS_INSTALL_TH.md) |
| บอร์ด ETT WROOM32UE | [FirstBoot 0.21.0-ett32ue.1](https://github.com/Sivacxool/aquafish/releases/download/v0.21.0-preview/AquaHatch-ETT-WROOM32UE-v0.21.0-ett32ue.1-FirstBoot.zip) |
| ESP32-CAM + OV3660 | [FirstBoot 0.21.0-camera.1](https://github.com/Sivacxool/aquafish/releases/download/v0.21.0-preview/AquaHatch-ESP32-CAM-v0.21.0-camera.1-FirstBoot.zip) |

## สิ่งที่เปลี่ยน

- หน้าภาพรวมอ่านอุณหภูมิ DO, pH และระดับน้ำในแผงเดียว หน้ากล้องมีชัตเตอร์หลัก หน้าตั้งค่ามีสแกน QR เป็นจุดเริ่มต้น
- พื้นเรียบ สีเน้นเดียว ไอคอน Phosphor และลำดับตัวอักษรชัดเจน มีภาพเคลื่อนไหวตอนเปิดแอปและขณะรอคำสั่ง รองรับ Reduce Motion
- รับข้อมูลเฟิร์มแวร์ `.5`: pH RS485 และสถานะฮีตเตอร์ RY0 ปรับอุณหภูมิเป้าหมายด้วย `set_config` ไม่ส่งคำสั่งเปิดฮีตเตอร์ที่บอร์ดไม่รองรับ
- ชื่อ Wi-Fi ตั้งค่าใหม่ `Smart Catfish System-B-XXXXXX` สำหรับบอร์ด และ `Smart Catfish System-C-XXXXXX` สำหรับกล้อง แต่ละตัวใช้ท้าย MAC ของตนเอง
- รหัสจับคู่ CA และชื่อ TLS เดิมยังใช้ได้ เมื่ออัปเกรดโดยไม่ล้าง NVS แอปยังอ่าน QR ของเฟิร์มแวร์รุ่นเดิมได้

## เริ่มใช้งาน

1. อ่าน [ผังต่อ ETT](ETT_WROOM32UE_SETUP_TH.md) และถอดโหลดก่อนอัปเดต แฟลชด้วย `Install-ETT-WROOM32UE.cmd` ใน ZIP ของบอร์ด หรือ `Install-CAM.cmd` สำหรับกล้อง เลือก COM ของอุปกรณ์ที่ต่อจริง
2. เปิด **ตั้งค่า → สแกน QR เพื่อเพิ่มอุปกรณ์** สแกนบัตรของแต่ละตัว แล้วตั้ง Wi-Fi 2.4 GHz ตามขั้นตอน
3. บอร์ดและกล้องใช้ Wi-Fi เดียวกันได้ แต่มี IP และ QR แยกกัน บอร์ดที่อัปเดตจาก QR เก่าใช้ตัวเลือก **อัปเดตเฟิร์มแวร์แล้ว? ใช้ชื่อ Wi-Fi ใหม่** ในหน้าตั้ง Wi-Fi หรืออ่านบัตร QR ใหม่ด้วย Read-QR
4. ตรวจค่าบอร์ดใน **ภาพรวม** แล้วไป **นับลูกปลา** เพื่อถ่ายภาพ วิเคราะห์ และแก้จุดนับก่อนบันทึก

ชุด ETT นี้สืบทอดผัง `.5`: DS18B20 GPIO32, RS485 TX27/RX26, ลูกลอย GPIO13, RY0 ฮีตเตอร์ และ RY1 ปั๊ม หัว pH RS485 MI-Water-PH-T แทน PH-4502C/ADS1115 ในโปรไฟล์ ETT เท่านั้น คำสั่งปั๊มและฮีตเตอร์ยังจำกัดเครือข่ายภายในตามระบบเดิม การดูข้อมูล/รับภาพจากนอกบ้านใช้ Cloudflare ที่ตั้งไว้

การตรวจซอฟต์แวร์และไฟล์ build ไม่แทนการยืนยันกับบอร์ด/เซนเซอร์จริง รุ่นนี้ยังไม่ได้แฟลชหรือทดสอบโหลดจริงในรอบ redesign

## ซอร์สและเอกสาร

[แอป Flutter](aqua_hatch/) · [Android](ANDROID/) · [iOS](IOS/) · [เฟิร์มแวร์](aqua_hatch/firmware/) · [วิธี build](REBUILD.md)

[แนวทางออกแบบและที่มาของ skill](DESIGN_021.md) · [จับคู่ QR](FIRST_BOOT_PAIRING_TH.md) · [ดูจากนอกบ้าน](REMOTE_SETUP_TH.md)
