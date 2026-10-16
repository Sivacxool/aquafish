# AquaHatch 0.3.1

ชุดแก้บั๊กช่อง URL สีเทาในหน้าตั้งค่า พร้อมคู่มือเชื่อม App–Gateway–ESP32 ภาษาไทย

## ไฟล์

- AquaHatch-v0.3.1-Android-arm64.apk: แอป Android arm64 รุ่น 0.3.1 ใช้ certificate เดียวกับ APK 0.2 เดิม
- AquaHatch-v0.3.1-source.zip: Flutter app, Gateway, MQTT protocol, tests และคู่มือ Markdown ไม่รวม private signing key
- AquaHatch-ESP32-Guide-TH.pdf: คู่มือ 10 หน้า อ่านตามลำดับ เริ่มช่วง A หน้า 2–5 ได้แม้ยังไม่มี ESP32
- AquaHatch-ESP32-Guide-TH.md: เนื้อหาคู่มือพร้อมคำสั่งที่คัดลอกได้
- VERIFICATION.md: ผลตรวจและข้อจำกัด
- screens/: ภาพหน้าฟอร์มหลังแก้จากเว็บ release ที่ใช้ source เดียวกับ APK
- SHA256SUMS.txt: ค่า SHA-256 สำหรับตรวจไฟล์ส่งมอบ

## เริ่มใช้งาน

1. ติดตั้ง APK 0.3.1 บน Android arm64 ข้อมูล package และลายเซ็นตรงกับรุ่นเดิม แต่ยังไม่ได้ตรวจการอัปเดตจริงบนโทรศัพท์
2. เปิดคู่มือ PDF ช่วง A เพื่อรัน Gateway เครื่องจำลองบนคอมพิวเตอร์ แล้วเชื่อมมือถือผ่าน USB
3. ในแอปเลือกเครื่องจริงเพื่อใช้ Gateway adapter แม้ Gateway จะกำลังจำลอง ESP32 อยู่ ข้อมูลยังต้องแสดงป้ายจำลอง
4. เมื่อทราบรุ่นบอร์ด เซนเซอร์ และรีเลย์แล้ว จึงพัฒนา firmware และผังสายตามอุปกรณ์จริง ชุดนี้ยังไม่มี firmware พร้อมแฟลช

ทดสอบผ่าน 29 เคส รวม HTTP/WebSocket กับ Gateway เครื่องจำลอง ยังไม่ได้ต่อ ESP32 หรือทดสอบ APK บนโทรศัพท์จริง
