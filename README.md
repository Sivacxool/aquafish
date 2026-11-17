# Smart Catfish System · AquaHatch 0.23.3

ระบบเครื่องฟักไข่ปลาดุกด้วยบอร์ด ET-ESP32 WROOM32UE, กล้อง Arducam B0434 และแอป Flutter สำหรับ Android/iOS

| ชุดติดตั้ง | ดาวน์โหลด |
| --- | --- |
| Android / LDPlayer | [APK Universal](https://github.com/Sivacxool/aquafish/releases/download/v0.23.3/AquaHatch-v0.23.3-Android.apk) |
| iPhone iOS 16+ | [IPA unsigned](https://github.com/Sivacxool/aquafish/releases/download/v0.23.3/AquaHatch-v0.23.3-iOS-unsigned.ipa) · [วิธีเซ็นและติดตั้ง](IOS_INSTALL_TH.md) |
| ETT WROOM32UE + B0434 | [FirstBoot ZIP](https://github.com/Sivacxool/aquafish/releases/download/v0.23.0-ett32ue.2/AquaHatch-ETT-WROOM32UE-v0.23.0-ett32ue.2-FirstBoot.zip) |

## เริ่มใช้งาน

1. ถอดไฟโหลดรีเลย์ทั้งหมด แล้วต่อ B0434 เข้าหัว 4G-EC200U ของบอร์ดหลักตาม [ผัง ETT](ETT_WROOM32UE_SETUP_TH.md#กล้อง-arducam-b0434)
2. แตก ZIP แล้วเปิด Install-ETT-WROOM32UE.cmd เลือก COM ของ ETT ชุดนี้ลงเฟิร์มแวร์และตารางพาร์ทิชันสำหรับพัก JPEG โดยเก็บ NVS เดิม
3. เปิดแอป **ตั้งค่า → สแกน QR บอร์ด ETT** ใช้ QR ของ ETT ตัวเดียว ตั้ง Wi-Fi 2.4 GHz หากเปลี่ยนเครือข่าย
4. เปิด **นับลูกปลา** ตั้งความละเอียดหรือค่ากล้องด้วยไอคอนปรับค่า กดถ่าย แล้วเลือก AI หรือแก้จุดนับด้วยมือก่อนบันทึกผล
5. เมื่อต้องใช้จากเครือข่ายอื่น เพิ่มสิทธิ์ห้องกล้องของ ETT ใน Cloudflare แล้วเปิด **ตั้งค่า → ดูจากระยะไกล** ตาม [คู่มือ](REMOTE_SETUP_TH.md)

## โครงสร้างและรุ่นเดิม

- ETT ใช้ GPIO32 สำหรับ DS18B20, RS485 TX27/RX26 สำหรับ DO และ pH, ลูกลอย GPIO13, RY0 ฮีตเตอร์, RY1 ปั๊ม และ RY2 พัดลม
- แอปสั่งกล้องและรีเลย์ผ่าน HTTPS ของ ETT บอร์ดคุมรีเลย์ตามลูกลอยและอุณหภูมิได้เอง การสั่งรีเลย์จากแอปใช้ LAN
- Arducam ถ่าย VGA หรือ 3 MP ตามคำสั่ง รองรับโหมดปกติ แสงน้อย และตั้งค่า EV ความสว่าง คอนทราสต์ ความอิ่มสี สมดุลแสงขาว ผลนับบันทึกในมือถือ
- หลังถ่ายจาก Arducam กด **บันทึกรูปลงแกลเลอรี** เพื่อเก็บ JPEG ต้นฉบับ ดูในอัลบั้ม AquaHatch บน Android หรือแอปรูปภาพบน iPhone
- หน้าภาพรวมแสดงผลนับล่าสุดของรอบฟักที่เลือก เมื่อมีจำนวนไข่ตั้งต้น อัตราฟักจะคำนวณจากจำนวนลูกปลาที่บันทึก ÷ จำนวนไข่ตั้งต้น × 100

[แอป Flutter](aqua_hatch/) · [Android](ANDROID/) · [iOS](IOS/) · [เฟิร์มแวร์](aqua_hatch/firmware/) · [เริ่มใช้งาน](START_HERE_TH.md)
