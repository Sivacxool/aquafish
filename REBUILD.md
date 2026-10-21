# สร้างชุดสำหรับบอร์ดใหม่

ชุดทดสอบเดิมใช้ ESP32-S3, flash 16 MB, OPI PSRAM 8 MB และพอร์ต USB-UART
ค่าต่อไปนี้ตรงกับบอร์ดที่ทดสอบเท่านั้น ต้องตรวจรุ่นจริงก่อนใช้กับบอร์ดอื่น

## 1. เตรียมเครื่องมือ

- Python 3.11 ขึ้นไป
- Arduino CLI / Arduino IDE พร้อม Arduino-ESP32 3.3.12 และ ArduinoJson 7.4.3
- Flutter 3.44.6 / Dart 3.12.2, Android SDK และ JDK 17 ขึ้นไป

## 2. สร้างคู่ใบรับรองในเครื่อง

จาก root ของ repository:

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r tools/requirements.txt
./.venv/Scripts/python.exe tools/prepare_device.py
```

เครื่องมือสร้าง `private/`, `aqua_hatch/firmware/local_server/device_private.h`
และแทน `aqua_hatch/assets/device/device_ca.pem` ให้เป็นคู่ใหม่
ไฟล์ใน private และ device_private.h ต้องเก็บในเครื่องผู้ประกอบ
ห้ามคัดลอกใบรับรองใหม่เข้าแอปอย่างเดียวแล้วใช้คู่กับเฟิร์มแวร์เดิม

## 3. สร้างเฟิร์มแวร์

```powershell
./aqua_hatch/firmware/local_server/Build-Device.ps1
```

เมื่อยืนยันพอร์ตและมีเฉพาะ USB ต่อกับบอร์ด จึงใช้ `-Upload -Port COM3`
เปลี่ยน COM3 ให้ตรงกับเครื่องจริง การ build นี้ใช้ FlashSize=16M, PSRAM=opi,
FlashMode=qio, PartitionScheme=app3M_fat9M_16MB, CDCOnBoot=default

## 4. สร้างแอปและบัตรของคู่ใหม่

```powershell
cd aqua_hatch
flutter pub get
./tools/Build-Android.ps1 -Python ../.venv/Scripts/python.exe
../.venv/Scripts/python.exe tools/print_pairing_card.py
```

ใช้ APK ที่สร้างใหม่นี้กับเฟิร์มแวร์คู่ใหม่ และเก็บบัตรใน `outputs/` เป็นส่วนตัว
กุญแจลงนาม APK เดิมไม่เผยแพร่ จึงต้องใช้การลงนามของผู้ประกอบและจัดการการติดตั้งตามลายเซ็นของตน
ไฟล์ .bin ที่ build แล้วมีรหัสและ private key ฝังอยู่ จึงไม่รวม binary เฟิร์มแวร์ใน GitHub

## ผลที่คาดหวัง

บอร์ดเปิด Wi-Fi ตั้งค่า แอปตั้งเครือข่าย 2.4 GHz และเชื่อมตรงได้
เซนเซอร์ กล้อง และ GPIO ภายนอกยังไม่เปิดใช้ในเฟิร์มแวร์หลักรุ่นนี้
