# AquaHatch 0.11.0 — ติดตั้งทดสอบบน iPhone จาก Windows

ไฟล์ **AquaHatch-v0.11.0-iOS-unsigned.ipa** เป็นแอป iOS สำหรับเครื่องจริงที่ยังไม่เซ็น ต้องเซ็นด้วย Apple ID ของเจ้าของก่อนติดตั้ง เปิดไฟล์จาก Safari เพื่อติดตั้งตรง ๆ ไม่ได้

## สิ่งที่เตรียมให้

- คำอธิบายสิทธิ์เครือข่ายเฉพาะที่สำหรับ ESP32-S3 และ ESP32-CAM
- ขั้นตอนเปลี่ยน Wi-Fi สำหรับ iPhone โดยไม่เรียกคำสั่ง Android หรือ URL ตั้งค่าที่เป็น API ส่วนตัว
- ใช้การตรวจใบรับรองประจำบอร์ดและกล้องตามเดิม ไม่ปิดการตรวจ TLS
- บิลด์อัตโนมัติบน macOS ของ GitHub Actions พร้อมตรวจแพ็กเกจ arm64 และทดสอบเปิดใน iPhone Simulator

การบิลด์สำเร็จหรือ Simulator เปิดได้ยังไม่ยืนยันว่าเซ็น ติดตั้ง และเชื่อมบอร์ดบน iPhone จริงสำเร็จ

## ติดตั้งด้วย Windows และ Apple ID ธรรมดา

1. ดาวน์โหลด IPA จากชุดส่งมอบหรือ artifact ชื่อ AquaHatch-iOS-unsigned ในหน้า Actions ของ repository
2. ติดตั้ง [Sideloadly จากเว็บไซต์ผู้พัฒนา](https://sideloadly.io/) ตามข้อกำหนด Windows ในหน้านั้น โปรแกรมระบุว่าต้องใช้ iTunes/iCloud รุ่นจากเว็บไซต์ Apple; ตรวจโปรแกรมเดิมก่อนเปลี่ยนหรือถอนการติดตั้ง
3. เสียบ iPhone ทาง USB ปลดล็อก แล้วกดเชื่อถือคอมพิวเตอร์บน iPhone
4. เปิด Sideloadly เลือก iPhone และลาก IPA เข้าไป เลือกโหมดติดตั้งด้วย Apple ID
5. เจ้าของกรอก Apple ID/รหัสผ่านและยืนยันตัวตนในโปรแกรมด้วยตนเอง ไม่ส่งรหัสผ่านหรือรหัสยืนยันผ่านแชทหรือ GitHub
6. เมื่อเซ็นและติดตั้งแล้ว ให้เชื่อถือโปรไฟล์นักพัฒนาใน การตั้งค่า > ทั่วไป > VPN และการจัดการอุปกรณ์ หากระบบร้องขอ
7. หาก iOS ขอ Developer Mode ให้เปิดใน การตั้งค่า > ความเป็นส่วนตัวและความปลอดภัย > โหมดนักพัฒนา แล้วทำตามขั้นตอนรีสตาร์ต/ยืนยันของ iPhone
8. เปิด AquaHatch และอนุญาตเครือข่ายเฉพาะที่ หากเคยปฏิเสธให้เปิดสิทธิ์ของ AquaHatch ในแอปการตั้งค่า

Apple ID ธรรมดาใช้สำหรับทดสอบส่วนตัว โปรไฟล์ฟรีมีอายุ 7 วัน จึงต้องเซ็นใหม่เป็นระยะ; ดู [ข้อจำกัด Personal Team ของ Apple](https://developer.apple.com/help/account/basics/about-your-developer-account) และ [ข้อมูล auto-refresh ของ Sideloadly](https://sideloadly.io/)

## เชื่อมบอร์ดและกล้อง

1. ให้ iPhone กับ ESP32-S3 และ ESP32-CAM อยู่ใน Wi-Fi บ้านเดียวกัน
2. ในแอปเลือกเชื่อมบอร์ด ใส่ข้อมูลจากบัตรจับคู่ของเครื่อง ไม่ใช้ข้อมูลตัวอย่างในเอกสาร
3. หากต้องตั้ง Wi-Fi ใหม่ ให้ทำตาม wizard เมื่อถึงขั้นสลับ Wi-Fi กด “วิธีเปลี่ยน Wi-Fi บน iPhone” แล้วสลับใน การตั้งค่า > Wi-Fi จากนั้นกลับมาตรวจในแอป
4. เพิ่มกล้องด้วยข้อมูลจับคู่ของกล้อง กล้องและ S3 มี IP แยกกัน
5. ทดสอบอ่านค่าเซนเซอร์และถ่ายภาพ ตรวจว่าระบุเป็นข้อมูลจริงและเวลาอัปเดตใหม่

## ส่ง TestFlight / App Store ภายหลัง

ต้องมีสมาชิก Apple Developer พร้อมสิทธิ์และข้อมูลเซ็นแอป สำหรับเส้นทางนี้ยังไม่ได้สร้าง signed IPA หรืออัปโหลด TestFlight

ข้อมูลต้นทาง: [Flutter — Build and release an iOS app](https://docs.flutter.dev/deployment/ios), [Apple — Local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [Apple — Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
