# ผลตรวจ AquaHatch 0.4.0 — 20 ตุลาคม 2026

## การรวมงาน

ใช้ source 0.3.1 จากแชทนี้เป็นฐาน รวม camera service/repository/firmware sketch จาก source ที่อ้างในแชทแชร์ แล้วผสานหน้าตรวจนับแบบ workspace และฟอร์ม PageStorage ที่แก้แล้ว ไม่มีการแก้ synced project ต้นทาง

## ตรวจผ่าน

- Flutter 3.44.6 / Dart 3.12.2: analyze --no-pub ไม่มีปัญหา
- Flutter tests ไม่มี Gateway: 33 passed, 2 skipped
- Flutter tests กับ loopback FastAPI และ software camera fixture: 35 passed, 0 skipped
- Gateway pytest: 22 passed มี Starlette TestClient deprecation warning 1 รายการ ไม่ใช่ test failure
- build web release สำเร็จ
- build APK release arm64 สำเร็จ
- โค้ดกล้อง Arduino-ESP32 3.3.12 / PubSubClient 2.8.0 / ArduinoJson 7.4.3 คอมไพล์ผ่านเป้าหมาย esp32:esp32:esp32s3 (OPI PSRAM / 16 MB / huge_app สำหรับ compile fixture เท่านั้น) ขนาด sketch 1,084,134 bytes, global variables 58,336 bytes
- source diff whitespace check ของ lib/Gateway ผ่าน

การคอมไพล์กล้องใช้สำเนา source กับ config ทดสอบภายนอกโครงการ เปิด guard เพื่อทดสอบ C++/driver API เท่านั้น ค่า GPIO ยังไม่กำหนด ไม่มีการแฟลชและไม่ส่ง binary ทดสอบให้ผู้ใช้ `config.example.h` ใน ZIP ยังตั้ง CAMERA_PINS_CONFIRMED=0 ตามเดิม

## พฤติกรรมที่ตรวจ

- หน้ากล้องเป็นทางหลัก ไม่มีภาพตัวอย่างเปิดแทนภาพจริงโดยอัตโนมัติ
- รับ JPEG ของรหัสคำขอเดียวกัน ภาพหลังเปลี่ยนเครื่องถูกทิ้ง และไม่มีผล AI ปลอมเมื่อไม่มีโมเดล
- การทดสอบ HTTP integration สั่ง 2 งาน รับ JPEG ที่ต่างกันผ่าน network จริงบน loopback และตรวจการวิเคราะห์ที่ไม่มี weights ว่าล้มเหลวอย่างถูกต้อง
- LiveRepository รับ telemetry และ ACK ผ่าน HTTP/WebSocket กับเครื่องจำลอง ตรวจ manual/auto และ interlock
- Gateway ตรวจสิทธิ์อ่านภาพ/token อัปโหลดเฉพาะงาน, JPEG เสีย/เกินขนาด, งานหมดอายุ, duplicate, stale heartbeat, broker failure และส่งวิเคราะห์ภาพที่เก็บแล้ว
- แบบทดสอบ UI ครอบคลุม 320×568, 390×844, 844×390 และตัวอักษร 140% รวมฟอร์ม URL สองขนาดจอและการตรวจแก้จุดหลังซูม

## ทดลองเว็บด้วยการกดจริง

เปิดเว็บ release ของ source เดียวกับ APK ใน in-app browser:

1. เข้าเครื่องจริงในตั้งค่า กรอกรหัสทดสอบ เชื่อม loopback Gateway สำเร็จ ไม่มีพื้นที่สีเทาในฟอร์ม
2. สถานะกล้องพร้อมถ่าย กดถ่าย รับ JPEG ทดสอบพร้อมเวลา กด AI แล้วได้ข้อความยังไม่มีโมเดล โดยคงภาพไว้
3. เปิดนับด้วยมือ เพิ่มจุดหนึ่งจุด เริ่มรอบชื่อ “ทดสอบระบบกล้อง — ข้อมูลจำลอง” ยืนยันแล้วบันทึก ขึ้น “บันทึกแล้ว”
4. ตรวจหน้ากล้องและ Dashboard ที่จอมือถือ 390×844 และหน้าคอม ขนาด viewport คืนค่าหลังตรวจ

ภาพใน screens/camera-received-* และ camera-manual-saved-mobile.png เป็นภาพ synthetic จาก software fixture ไม่ได้มาจาก OV5640 จริง ไม่ใช้จำนวนจุดทดสอบเป็นหลักฐานความแม่นยำการนับ

## ตรวจ APK

- apksigner verify ผ่าน certificate SHA-256 ตรงกับ APK เดิม: f6df9948344bc96c8db247aeb7f8fc6ffefdf1f172e25fc67bd23736eac39fbd
- package th.ac.aquahatch.aqua_hatch, versionName 0.4.0, versionCode 2005
- arm64-v8a, minSdk 24, targetSdk 36
- ZIP integrity ผ่าน และตรวจไม่รวม keystore/config.h/token ทดสอบ/cache/build

## ยังไม่ได้ยืนยัน

- ไม่ได้ติดตั้ง/อัปเดต APK หรือใช้กล้องมือถือ permission/lifecycle/TalkBack บน Android จริง
- ไม่มีบอร์ด ESP32-S3 หรือ OV5640 เชื่อมต่อ จึงยังไม่ยืนยัน GPIO/PSRAM/สายแพ/การถ่ายจริง/TLS ของบอร์ด/โหลดวงจรจริง
- software camera fixture แทน publish callback เท่านั้น ไม่ได้นับเป็นผลทดสอบ MQTT Broker จริงหรือเส้นทาง MQTT ไปกลับกับบอร์ด
- ยังไม่มีโมเดลลูกปลาที่ฝึกแล้ว/ผลวัดความแม่นยำ ไม่มีเฟิร์มแวร์ควบคุมปั๊ม/ฮีตเตอร์ที่ยืนยันกับอุปกรณ์ของผู้ใช้
- ไม่มีวิดีโอสดต่อเนื่อง Push ตอนปิดแอป และ production auth/deployment ระบบหลายผู้ใช้
