# ผลตรวจ AquaHatch 0.3.1

เครื่องมือ: Flutter 3.44.6 / Dart 3.12.2 / Android SDK 36 / NDK 28.2.13676358

## สาเหตุและการแก้บั๊ก

ทำซ้ำอาการที่ตั้งค่า → เครื่องและการเชื่อมต่อ → เครื่องจริง พบข้อผิดพลาด `type 'bool' is not a subtype of type 'double?' in type cast` ใน ScrollPosition.restoreScrollOffset ช่องกรอกคืนค่าสถานะจาก PageStorage ที่ชนกับสถานะ bool ของ ExpansionTile จึงเกิดพื้นที่ ErrorWidget สีเทาใน release

แก้โดยให้เนื้อหาหมวดมี PageStorageBucket แยกจากสถานะพับ/เปิด และให้ช่องกรอกเชื่อมต่อมี PageStorageKey ของตนเอง regression tests สองขนาดจอล้มเหลวก่อนแก้และผ่านหลังแก้

## ตรวจผ่าน

- flutter analyze --no-pub: No issues found
- flutter test --no-pub: 28 passed, 1 skipped เมื่อไม่เปิด Gateway
- เปิด FastAPI Gateway ที่ 127.0.0.1:8000 ด้วย SIMULATE_DEVICE=1 และ token ชั่วคราว แล้วรันชุดทดสอบอีกครั้งพร้อม TEST_GATEWAY_TOKEN: 29 passed, 0 skipped
- Live Gateway test รับ telemetry ผ่าน HTTP/WebSocket, ตรวจข้อมูลใหม่และป้ายจำลอง, เข้า manual/กลับ auto, รับ ACK คำสั่ง และปฏิเสธคำสั่งที่ไม่ผ่าน interlock
- flutter build web --release --no-web-resources-cdn --no-wasm-dry-run --no-pub: สำเร็จ
- flutter build apk --release --target-platform android-arm64 --split-per-abi --no-pub: สำเร็จ
- git diff --check: ผ่าน

ชุดทดสอบรวมการกรอก URL/รหัสเครื่อง/รหัสเข้าถึงที่ 390×844 และ 1440×1024 พร้อมข้อกำหนด freshness, TLS/device identifier, pH, interlock, manual lease, persistence, ที่มาของผลนับ และ regression tests จากรุ่น 0.3.0

## ตรวจหน้าเว็บด้วยภาพจริง

เปิดเว็บ release ของซอร์สเดียวกับ APK ที่ 390×844 และ 1440×1024 เข้าโหมดเครื่องจริงในหน้าตั้งค่า ช่อง URL รหัสเครื่อง และรหัสเข้าถึงแสดงตามขนาดปกติ ไม่มีพื้นที่สีเทาหรือข้อผิดพลาดใน browser console ภาพอยู่ที่ screens/connection-mobile-fixed.png และ screens/connection-desktop-fixed.png

## คู่มือ ESP32

- เอกสาร PDF ภาษาไทย 10 หน้า พร้อม Markdown สำหรับคัดลอกคำสั่ง
- ตรวจเทียบขั้นตอนกับ Gateway, LiveRepository, MQTT protocol และนโยบายเครือข่าย Android ใน source
- ทดสอบ Gateway health endpoint และการเชื่อมต่อ authenticated HTTP/WebSocket กับเครื่องจำลองแล้ว
- render PDF เป็นภาพและตรวจครบ 10 หน้า ภาษาไทยและกล่องคำสั่งไม่ล้นหน้า
- แหล่งอ้างอิงทางการอยู่ท้ายคู่มือ: Espressif, Mosquitto, Android และ Uvicorn

## ตรวจไฟล์ APK และ source

- apksigner verify: ผ่าน
- certificate SHA-256 ตรงกับ APK 0.2 เดิม: f6df9948344bc96c8db247aeb7f8fc6ffefdf1f172e25fc67bd23736eac39fbd
- package: th.ac.aquahatch.aqua_hatch
- versionName: 0.3.1, versionCode: 2004 (Flutter ABI split code)
- native-code: arm64-v8a, minSdk: 24
- source zip ไม่รวม private keystore, token ทดสอบ, build หรือ cache และตรวจ ZIP integrity แล้ว

ข้อมูล package/version/certificate รองรับการอัปเดตทับ APK เดิม แต่ยังไม่ได้ทดสอบติดตั้งจริงบนโทรศัพท์

## ขอบเขตที่ยังไม่ได้ยืนยัน

- ไม่มี Android เชื่อมต่อ จึงยังไม่ได้ทดสอบติดตั้ง/อัปเดตจริง กล้อง ตัวเลือกรูป/วิดีโอ permission, TalkBack และ lifecycle บนมือถือ
- ยังไม่มี ESP32/เซนเซอร์/รีเลย์จริง จึงยังไม่ได้ทดสอบ MQTT กับฮาร์ดแวร์ ผังสาย GPIO หรือความปลอดภัยของวงจร ไม่มี firmware พร้อมแฟลชรวมมาในชุดนี้
- ไม่ได้ตรวจความแม่นยำของ AI หรือระบบฟักจริง
- Push ตอนปิดแอป, QR และค้นหาเครื่องอัตโนมัติยังไม่ได้เพิ่ม
- APK ใช้ development signing certificate เดียวกับรุ่นเดิม ยังไม่ใช่ release signing สำหรับเผยแพร่บน Google Play
