# สร้าง AquaHatch 0.12.0 สำหรับบอร์ดใหม่

ชุดฮาร์ดแวร์ที่เคยทดสอบ: ESP32-S3 flash 16 MB / OPI PSRAM 8 MB และ AI Thinker ESP32-CAM + OV3660 แยกบอร์ด (เคยทดสอบ OV5640 ในรุ่นก่อน)
ตรวจรุ่นและผังขาจริงก่อนใช้กับบอร์ดอื่น

## เครื่องมือ

- Python 3.11 ขึ้นไป
- Arduino CLI / IDE พร้อม Arduino-ESP32 3.3.12
- ArduinoJson 7.4.3, DallasTemperature 4.0.6, OneWire 2.3.8
- Flutter 3.44.6 / Dart 3.12.2, Android SDK และ JDK 17 ขึ้นไป

## สร้างเอกลักษณ์ส่วนตัวและคู่ใบรับรอง

จาก root ของ repository:

```powershell
python -m venv .venv
./.venv/Scripts/python.exe -m pip install -r tools/requirements.txt
./.venv/Scripts/python.exe tools/prepare_device.py
./.venv/Scripts/python.exe tools/prepare_camera.py
```

เครื่องมือแรกสร้างเอกลักษณ์ของ S3, public CA ของแอป และโฟลเดอร์ outputs
เครื่องมือที่สองสร้างเอกลักษณ์ของกล้อง, public CA ของกล้อง, ข้อมูล public identity ใน Dart และบัตรกล้อง
ไฟล์ `private/`, `device_private.h` และบัตรจับคู่ใน outputs ต้องเก็บเป็นส่วนตัว
ต้องใช้เฟิร์มแวร์กับแอปที่สร้างจากเอกลักษณ์ชุดเดียวกัน

## สร้างเฟิร์มแวร์

```powershell
./aqua_hatch/firmware/local_server/Build-Device.ps1
./aqua_hatch/firmware/camera_server/Build-Camera.ps1
```

ตรวจพอร์ตจริงและวงจรที่ต่ออยู่ก่อนใช้ตัวเลือก Upload ตามพารามิเตอร์ในสคริปต์
S3 ใช้ FlashSize=16M, PSRAM=opi, FlashMode=qio, PartitionScheme=app3M_fat9M_16MB, CDCOnBoot=default
กล้องใช้บอร์ด AI Thinker ESP32-CAM ตาม Build-Camera.ps1
DS18B20 ใช้ GPIO4; DO ใช้ TX16 / DE17 / RX18 ตาม [คู่มือสาย](aqua_hatch/SENSORS_SETUP_TH.md)
รุ่นนี้อ่านเซนเซอร์ แต่ยังไม่เปิดการขับรีเลย์/ปั๊ม/ฮีตเตอร์

## สร้างแอปและบัตร S3

```powershell
cd aqua_hatch
flutter pub get
./tools/Build-Android.ps1 -Python ../.venv/Scripts/python.exe
../.venv/Scripts/python.exe tools/print_pairing_card.py
```

APK Universal มี ARM32/ARM64/x86_64 ต้องรักษากุญแจลงนามของผู้ประกอบเพื่ออัปเดตทับได้ในอนาคต
กุญแจลงนามเดิมและ binary เฟิร์มแวร์ที่มี private key ฝังอยู่ไม่เผยแพร่ใน GitHub
วิธีบิลด์นี้ใช้ source เดียวกับชุดส่งมอบ 0.12.0 แต่บอร์ดใหม่และการสลับ SoftAP ของมือถือแต่ละรุ่นยังต้องทดสอบจริง

## iOS และการต่ออายุใบรับรอง

โค้ดแอปใช้ร่วมกันใน aqua_hatch; ชุดติดตั้งแยกที่ IOS/ และ ANDROID/
[วิธีบิลด์ iOS บน macOS และติดตั้งจาก Windows](IOS_INSTALL_TH.md)

ใบรับรองเซิร์ฟเวอร์ที่เครื่องมือสร้างใหม่มีอายุ 730 วัน เก็บ ca-key.pem เป็นส่วนตัวเพื่อเซ็นใบรับรองต่ออายุโดยไม่เปลี่ยน CA ในแอป
เมื่อต่ออายุ ใช้ข้อมูล private/ เดิมก่อนสั่ง:

```powershell
./.venv/Scripts/python.exe tools/prepare_camera.py --renew-certificate
# สำหรับ S3 ให้ใช้ tools/prepare_device.py --renew-certificate แยกต่างหาก
```

ใบรับรองเก่า 10 ปีจะถูกปฏิเสธโดย Apple หากไม่มี CA signing key เดิม การต่ออายุต้องเปลี่ยน CA ด้วย และบิลด์แอปทั้ง iOS/Android กับเฟิร์มแวร์ให้ตรงกัน
อย่ารันเครื่องมือบนโฟลเดอร์ private/ ว่างเพื่ออัปเดตบอร์ดที่จับคู่แล้ว เพราะจะสร้าง token ใหม่
