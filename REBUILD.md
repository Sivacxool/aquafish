# สร้าง AquaHatch 0.16.0 และ generic firmware

รุ่นนี้ WROOM-DA/CAM สร้างตัวตนและ private keys ในบอร์ดตอนเปิดครั้งแรก ไม่ต้องสร้าง device_private.h หรือบิลด์แอปประจำบอร์ด
อ่าน [คู่มือติดตั้งและจับคู่ด้วย QR](FIRST_BOOT_PAIRING_TH.md) ก่อนใช้งาน

## เครื่องมือ

- Arduino CLI / IDE พร้อม Arduino-ESP32 3.3.12
- ArduinoJson7.4.3, DallasTemperature4.0.6, OneWire2.3.8
- Flutter3.44.6 / Dart3.12.2, Android SDK, JDK17ขึ้นไป
- iOS build ใช้ macOS/Xcode หรือ GitHub Actions ใน repository

## เฟิร์มแวร์

```powershell
./aqua_hatch/firmware/local_server/Build-Device.ps1
./aqua_hatch/firmware/camera_server/Build-Camera.ps1
```

สคริปต์รวม `firmware/libraries/AquaIdentity` ให้อัตโนมัติ
บอร์ดหลักใช้ ESP32-WROOM-DA Module, Flash 4 MB, DIO 40 MHz, Minimal SPIFFS และ Upload Speed 115200 ส่วนกล้องใช้ AI Thinker ESP32-CAM
เพิ่ม `-Upload -Port COM5` เมื่อพอร์ตของบอร์ดหลักเป็น COM5 เลือกหมายเลขจริงของบอร์ดแต่ละตัว
เพื่อรับบัตร QR หลังลง ใช้ FirstBoot package หรือตัวอ่าน `tools/pairing_card.py --kind wroom-da --port COM5 --read-only`
อย่าสั่งล้าง NVS เพื่ออัปเดตรุ่นปกติ เพราะการล้างทำให้ CA/token เปลี่ยนและต้องสแกนใหม่

## แอป

```powershell
cd aqua_hatch
flutter pub get --enforce-lockfile
flutter analyze
flutter test --concurrency=2
./tools/Build-Android.ps1
```

APK Universal รวม ARM32 / ARM64 / x86_64 ต้องใช้กุญแจลงนามเดิมเพื่ออัปเดตทับ
CA ที่อยู่ใน assets เป็น fallback ของบอร์ดรุ่นเก่าเท่านั้น บอร์ด generic ใหม่ใช้ CA จาก QR ที่ผู้ใช้สแกน
ไม่รันเครื่องมือ `prepare_device.py` หรือ `prepare_camera.py` ของระบบเก่าเพื่อแทนที่ trust anchor เมื่อสร้าง generic firmware

## ตรวจโค้ดสร้างตัวตนบนคอม

ใช้ CMake / C++17, Mbed TLS3.6.6 และ ArduinoJson7.4.3 ตามขั้นตอนใน `.github/workflows/ios.yml`
`tools/runtime-certificates` สร้างโปรแกรมตรวจ crypto และโปรแกรมรัน AquaIdentity.cpp ตัวจริงกับ NVS/hardware adapters จำลอง
หลังสร้าง fixture ใน `aqua_hatch/build/runtime-private` ชุด Flutter จะตรวจ TLS จริงบน loopback กับ CA จาก QR โดยไม่ติดต่อบอร์ดผู้ใช้
หากไม่มี fixture ชุด TLS4รายการจะข้าม ส่วน hardware tests เดิมข้ามเมื่อไม่ได้ระบุอุปกรณ์จริง
macOS CI ตรวจ chain/hostname ด้วย Apple trust policy และตรวจ native IPA / Simulator ด้วย
