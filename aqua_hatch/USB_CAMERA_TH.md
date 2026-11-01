# AquaHatch 0.8 — กล้อง USB ใน LDPlayer

เส้นทางจริง: OV5640 → ESP32-S บน ESP32-CAM-MB → สาย USB → ตัวรับภาพ Windows → แอป AquaHatch ใน LDPlayer

เฟิร์มแวร์นี้ปิด Wi-Fi และไม่ต้องใส่ชื่อเครือข่ายหรือรหัส ตัวรับภาพเปิดเฉพาะ 127.0.0.1:8771 บน Windows ส่วนแอปเข้าถึงผ่าน 172.16.1.2 ซึ่งเป็นช่องทาง host-loopback ภายใน LDPlayer ตัวที่ตรวจจริง ไม่ใช่ IP กล้องจากเราเตอร์

## ใช้บนคอมเครื่องนี้

1. เสียบ ESP32-CAM-MB ด้วย USB และปิด Serial Monitor ใน Arduino IDE
2. เปิด Start-AquaHatch-USB.cmd ค้างไว้ ถ้าตัวรับภาพเปิดอยู่แล้ว ไม่ต้องเปิดซ้ำ
3. ติดตั้ง AquaHatch-v0.8.0-Android-universal.apk ทับแอปเดิมใน LDPlayer
4. ในแอปเข้า ตั้งค่า → กล้องในเครื่อง → เชื่อมกล้อง USB
5. ไป กล้องและนับลูกปลา จะเห็นภาพสด กด “หยุดภาพนี้เพื่อนับ” เพื่อใช้ภาพที่กำลังแสดง แล้วกด “นับด้วยมือ”
6. กด “กลับไปดูภาพสด USB” เมื่อต้องการดูภาพต่อ

หลังถอดบอร์ดแล้วเสียบใหม่ ให้ปิดและเปิดตัวรับภาพ USB ใหม่ ถ้าตัวรับภาพที่เปิดเบื้องหลังค้างอยู่ ให้ใช้ Stop-AquaHatch-USB.cmd ก่อนเริ่มใหม่

## เฟิร์มแวร์

ไฟล์ firmware/AquaHatchUsbCamera/AquaHatchUsbCamera.ino ใช้เป้าหมาย esp32:esp32:esp32cam สำหรับ ESP32-S / AI Thinker ESP32-CAM ที่ตรวจจริง ไม่ใช่ ESP32-S3 ตัวควบคุมหลัก ใช้ขากล้องเดิมและ PSRAM; เริ่มที่ 320×240 JPEG และ UART 921600 baud

เมื่อใช้งาน USB ช่อง Serial เป็นข้อมูลภาพไบนารี จึงไม่ได้ใช้ Serial Monitor ดูข้อความทั่วไปพร้อมกัน ตัวรับภาพถามข้อมูลผ่าน HELLO และรับ JPEG ผ่าน CAP โดยใช้ request ID, ความยาวข้อมูล และ CRC32 ไม่ปะปนข้อความกับภาพ

## ตัวรับภาพบนคอมอื่น

ต้องมี Python และ pyserial ตาม viewer/requirements.txt จากนั้นใช้:

```text
python -m pip install -r viewer/requirements.txt
python viewer/viewer.py --port COM4 --http-port 8771
```

ปรับ COM4 ให้ตรงพอร์ตจริง หาก LDPlayer เครื่องอื่นใช้ host-loopback คนละที่ ต้องตั้งค่าที่อยู่ใน lib/core/usb_camera.dart และขอบเขต cleartext ใน Android ให้ตรงก่อน ไม่เปิดบริการรับภาพออก LAN

## ขอบเขต

- นี่คือ USB–Serial พร้อมโปรแกรมรับภาพ ไม่ใช่กล้อง UVC ที่ Windows Camera มองเห็นทันที
- ใช้แอป Android ใน LDPlayer บนคอมที่ต่อบอร์ดอยู่ ยังไม่ใช่การต่อ Android มือถือด้วยสาย OTG
- Wi-Fi ของบอร์ดกล้องปิดอยู่ การเชื่อมเซนเซอร์/ตัวควบคุมหลัก ESP32-S3 เป็นคนละส่วน
- ใช้ภาพ USB นับด้วยมือได้ ยังไม่มีผลยืนยันโมเดล AI ลูกปลา และการเปลี่ยนวิธีส่งไม่ได้ยืนยันว่าแก้เลนส์เบลอแล้ว
- รักษาการจับคู่กล้อง Wi-Fi เดิมไว้ แต่จะใช้ได้เมื่อเปลี่ยนเฟิร์มแวร์บอร์ดกลับเป็นแบบ Wi-Fi และเลือกโหมด Wi-Fi ในแอป
- source ZIP ไม่รวมภาพห้องจริง รหัส Wi-Fi, TLS private key, pairing token หรือ signing key
