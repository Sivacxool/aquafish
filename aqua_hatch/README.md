# AquaHatch 0.6.0

Flutter Android + เฟิร์มแวร์ ESP32-S3 0.6.0-local สำหรับตั้ง Wi-Fi และเชื่อมตรงผ่าน HTTPS

เริ่มจาก [คู่มือใช้งาน](../START_HERE_TH.md), [ผลตรวจล่าสุด](../VERIFICATION.md),
[การสร้างคู่สำหรับบอร์ดใหม่](../REBUILD.md) และ [API ตั้ง Wi-Fi](firmware/local_server/WIFI_SETUP.md)

## เฟิร์มแวร์หลัก

`firmware/local_server/local_server.ino` เป็นโค้ดที่ทดสอบกับ ESP32-S3 จริง
อ่านสถานะ สแกนและตั้ง Wi-Fi รับ ping และบันทึกค่าตั้งได้
ยังไม่อ่านเซนเซอร์ ไม่ขับ GPIO ภายนอก และยังไม่รับภาพ OV5640

## แอป Android

ใช้ Flutter 3.44.6 / Dart 3.12.2

```powershell
flutter pub get
flutter analyze
flutter test --concurrency=2
./tools/Build-Android.ps1
```

Universal APK ต้องมี libapp.so และ libflutter.so ครบ armeabi-v7a, arm64-v8a และ x86_64
เครื่องมือ Build-Android.ps1 จะตรวจ ABI หลัง build
กุญแจลงนามแอปเดิมไม่อยู่ใน GitHub การสร้าง APK ด้วยกุญแจใหม่จะอัปเดตทับแอปที่ลงนามเดิมไม่ได้

## ทางเลือก Gateway และกล้อง

`gateway/` และ `firmware/camera_node/` เป็นทางเลือกเมื่อจัดเตรียมบริการและฮาร์ดแวร์เพิ่มเติม
อ่าน [สถานะกล้อง](../AquaHatch-Camera-Start-TH.md) และ [CAMERA_SETUP.md](firmware/CAMERA_SETUP.md)
ก่อนใช้งาน ค่า CAMERA_PINS_CONFIRMED ในตัวอย่างยังเป็น 0
การมีไฟล์กล้องอยู่ในซอร์สไม่ได้หมายความว่า APK โหมดเชื่อมตรงเปิดใช้กล้องแล้ว

ไม่มีโมเดล AI ลูกปลาที่ฝึกและยืนยันแล้ว ไม่มีข้อมูลเซนเซอร์จำลองแสดงแทนค่าจริงในโหมดบอร์ดจริง
