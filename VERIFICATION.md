# ผลตรวจ AquaHatch 0.14.0 — First boot / QR pairing

## รหัสเฉพาะตัว

รัน AquaIdentity.cpp ตัวเดียวกับที่คอมไพล์ลง firmware บนคอม โดยใช้ NVS / MAC / RNG adapters จำลอง:
first boot สร้างตัวตนใหม่, อีกบอร์ดได้ token/CA ต่างกัน, reboot ใช้ตัวตนเดิมโดยไม่เขียนใหม่, บันทึกผิดพลาดไม่ออก QR พร้อมใช้งาน, ข้อมูลเสียหายหยุด, ต่ออายุ leaf โดย CA/token เดิมผ่าน
ผลนี้ตรวจ logic ของ source กับ storage จำลอง ไม่ใช่การยืนยัน NVS บนชิปจริง

## Crypto และแอป

- Mbed TLS3.6.6 รัน AquaCertificates.cpp จริง สร้าง ECDSA CA / leaf แยก key ตรวจ chain/SAN และปฏิเสธ root/hostname/key ผิดผ่าน
- QR ที่ render จาก payload ของ runtime test ถอดด้วย QR decoder กลับมาตรงกันครบ ไม่ได้เปิด serial port
- Dart TLS ใช้ CA จาก runtime QR กับ HTTPS server บน loopback ผ่าน อีก CA หรือ hostname ผิดถูกปฏิเสธก่อน HTTP ที่มีรหัส
- Flutter ตรวจ QR malformed / wrong role / identity mismatch / external URLs / persistence / stable credential keys และหน้ารับ QR โดยไม่แสดง token ผ่าน
- Firmware S3 และ CAM generic คอมไพล์ด้วย Arduino-ESP32 3.3.12 ผ่าน

## ขอบเขต

ไม่ได้เปิดพอร์ตหรือแฟลชบอร์ดผู้ใช้ ไม่ได้ทดสอบ first boot/NVS กับชิปจริง และไม่ได้ทดสอบการสแกนด้วยกล้อง iPhone/Android จริงในรอบนี้
ขั้น QR scanner ของมือถือจะต้องอนุญาตกล้อง มีทางวาง payload สำหรับ LDPlayer/เครื่องไม่มีกล้อง
ยังไม่เปิดขับโหลดและยังไม่มีโมเดล AI นับลูกปลาที่ตรวจความแม่นยำกับชุดจริง
ผลแพ็กเกจและ native iOS อ้างอิงรายงาน release หลัง CI ผ่าน ไม่ใช้ compile หรือ Simulator แทนผลเชื่อมฮาร์ดแวร์จริง

ผลฮาร์ดแวร์ OV3660 เดิมและรายงาน 0.12.0/0.13.0 เก็บไว้ใน verification ตามรุ่น ไม่ใช่ผลทดสอบ generic firmware รุ่นนี้

## ชุดติดตั้งที่ตรวจแล้ว

Native iOS arm64 / iPhoneOS 0.14.0+2015 และการเปิด Simulator ผ่าน [CI](https://github.com/Sivacxool/aquafish/actions/runs/42090614131) จาก source แอป `0838ba8ee890313cb3a42120be95931015aa7967`
เฟิร์มแวร์คอมไพล์จาก `160961e331ead7d73a594642465c07fb0b505535` ซึ่งเพิ่มการหยุดเมื่อ Wi-Fi เปิดไม่สำเร็จก่อนสร้างกุญแจ โดย source แอปและไลบรารีตัวตนตรงกับชุดที่ CI ตรวจแล้ว
Flutterผ่าน100รายการ ข้าม6 hardware tests ตรวจ Android ครบ3ABI และลายเซ็นเดิมผ่าน
[รายงานรุ่นนี้](verification/v0.14.0/release.json) · [FirstBoot](verification/v0.14.0/firstboot-verification.json) · [iOS](verification/v0.14.0/ios-ipa.json) · [Android](verification/v0.14.0/android-apk.json)
