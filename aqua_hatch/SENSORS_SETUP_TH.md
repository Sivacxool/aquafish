# ชุดเซนเซอร์ AquaHatch 0.9.0 — 30 ตุลาคม 2026

ชุดปัจจุบัน: ESP32-S3 COM3 อ่านเซนเซอร์และให้บริการ HTTPS ส่วน AI Thinker ESP32-CAM COM5 ให้บริการภาพแยกกัน ทั้งสองบอร์ดใช้ Wi-Fi บ้านเดียวกับมือถือ แต่มี IP คนละหมายเลข แอปติดต่อบอร์ดแต่ละตัวโดยตรง คอมใช้สำหรับอัปโหลด/ตรวจบันทึกเท่านั้น

## เปิดใช้ชุดที่ตั้งค่าแล้ว

1. เปิด Aqua Hatch ใน LDPlayer → ภาพรวม จะแสดงอุณหภูมิจาก DS18B20 และ DO จากหัววัด RS485 โดยอัปเดตประมาณทุก 2 วินาที
2. S3 ใช้ `https://192.168.1.156`, device ID `incubator-01`; กล้องใช้ `https://192.168.1.55`, camera ID `camera-7c60` ค่าเหล่านี้เป็น IP ที่ตรวจพบในรอบทดสอบ เราเตอร์อาจแจก IP ใหม่ได้
3. ไป “นับลูกปลา” → “ถ่ายภาพจากกล้องในเครื่อง” ภาพมาจาก ESP32-CAM ผ่าน Wi-Fi มีแฟลชเฉพาะขณะถ่าย รุ่นไดรเวอร์นี้ส่งได้สูงสุดจริง 2560×1920 (ประมาณ 4.9 ล้านพิกเซล), JPEG quality 10; ภาพยังต้องอาศัยโฟกัสเลนส์และแสงที่เหมาะสม
4. หลังอัปโหลดแล้ว สาย USB ใช้จ่ายไฟได้ ไม่ต้องเปิด Serial Monitor หรือโปรแกรม Gateway บนคอม และต้องให้อุปกรณ์กับมือถือ/LDPlayerอยู่ LAN เดียวกัน
5. ประวัติคุณภาพน้ำเก็บในแอปและคัดลอก CSV ได้; S3 รุ่นนี้ยังไม่เก็บประวัติย้อนหลังขณะปิดแอป

รหัสจับคู่เก็บในแอปที่ตั้งค่าแล้วและไฟล์ส่วนตัวของเครื่อง ไม่รวมใน ZIP source หรือ APK สาธารณะ การติดตั้งใหม่บนโทรศัพท์ต้องตั้ง URL/device ID และรหัสจับคู่ของบอร์ดทั้งสองตัวในหน้า “ตั้งค่า”

หาก DO แสดง 0.00 แอปจะแสดงคำเตือนให้ตรวจหัววัดและสภาพน้ำ โดยยังเก็บค่าที่หัววัดส่งมาตามจริง การสื่อสารสำเร็จยังไม่ยืนยันความแม่นยำของ DO: ต้องถอดปลอกยางภายนอก แช่หัววัดอย่างถูกต้อง รอให้ค่านิ่ง และตรวจเทียบ/สอบเทียบตามคู่มือ ค่าที่ตรวจได้หลังรีสตาร์ทในรอบทดสอบนี้ประมาณ 31.44°C จาก DS18B20 และ DO 6.80 mg/L

## สายที่ผู้ใช้ยืนยัน

| สัญญาณ | การต่อ ESP32-S3 |
|---|---|
| DS18B20 DATA | GPIO4, pull-up 4.7kΩ ไป 3.3V |
| DS18B20 GND | GND ร่วมกับ S3 |
| RS485 DI | GPIO16 / UART TX |
| RS485 DE และ /RE ต่อรวมกัน | GPIO17 / สลับส่ง-รับ |
| RS485 RO | GPIO18 / UART RX, ระดับสัญญาณต้องไม่เกิน 3.3V |
| โมดูล RS485 VCC | ผู้ใช้ยืนยันว่าต่อ 3.3V |
| หัววัด RS-LDO-N01-2-20 | ไฟเลี้ยง 12V แยกจาก GPIO; A/B ไป A/B ของโมดูล RS485 |

หัววัด DO ต้องใช้ไฟเลี้ยง 12V ตามชุดจริง ไม่ใช่ไฟจาก GPIO ตัว MAX485 ของแท้ระบุไฟเลี้ยง 5V; หากโมดูลที่ใช้ 3.3V สื่อสารไม่เสถียร ให้ใช้ transceiver 3.3V เช่น MAX3485 หรือวงจรลดระดับ RO ที่เหมาะสมก่อนใช้ MAX485 5V ห้ามเอา RO 5V เข้าขา S3 ตรง ๆ

## เฟิร์มแวร์

- `firmware/local_server/local_server.ino`: HTTPS, Wi-Fi provisioning และ snapshot
- `sensor_temperature.cpp`: DS18B20 แบบจ่ายไฟภายนอก, ไม่รองรับ parasite power, เริ่ม conversion แล้วอ่านภายหลังโดยไม่ค้างรอ 750 ms
- `sensor_do.cpp`: RS485 แบบ half duplex, read-only Modbus function 03, ตรวจ address, จำนวนไบต์ และ CRC16 ทุกคำตอบ
- `renke_do_protocol.h`: registers 0..5 เป็น float32 big endian: saturation ratio, DO mg/L และอุณหภูมิในหัววัด ตามคู่มือ Renke RS-LDO-N01 ตระกูลเดียวกัน ต้องตรวจคำตอบจริงก่อนสรุปความเข้ากันได้
- `sensor_config.h`: TX16, DE17, RX18, factory baud 4800 / 8N1 / slave address 1
- ไม่มีคำสั่งเขียน calibration, salinity หรือ address ลงหัววัดโดยอัตโนมัติ

ไลบรารี Arduino: ArduinoJson 7.4.3, DallasTemperature 4.0.6, OneWire 2.3.8; Arduino-ESP32 3.3.12

## ข้อมูลที่ส่งเข้าแอป

`GET /api/v1/devices/{device_id}` ใช้ HTTPS พร้อม CA เฉพาะเครื่องและ bearer token แอป poll ประมาณทุก 2 วินาที

ใน `telemetry` มี `temperature_c`, `do_mg_l`, `temperature_status`, `do_status`, `temperature_sampled_at`, `do_sampled_at` ค่าใดที่อ่านไม่ได้หรือเก่าเกิน 10 วินาทีเป็น null สถานะอาจเป็น `ok`, `not_found`, `crc_error`, `timeout`, `invalid_value` หรือ `stale` จึงไม่แสดงค่าสมมติเป็นค่าจริง

อุณหภูมิหลักในแอปมาจาก DS18B20 เท่านั้น อุณหภูมิชดเชยภายในหัววัด DO แยกเป็น `do_temperature_c` ไม่ใช้แทนเมื่อ DS18B20 เสีย แอปบันทึก DO และเวลาที่วัดลงประวัติในเครื่อง/CSV ด้วย

อ่านค่าเซนเซอร์ได้ไม่เท่ากับเปิดโหลดได้ `hardware_control` และ `hardware_ready` ยังคง false เพราะยังไม่ได้กำหนดวงจรรีเลย์/ปั๊ม/ฮีตเตอร์

## แหล่งข้อมูล

- [หน้าสินค้าที่ผู้ใช้ระบุจาก ModuleMore](https://www.modulemore.com/product/2627/do-sensor-rs485-fluorescence-freshwater)
- [คู่มือ Renke RS-LDO-N01 V2.0 ของผู้ผลิต เผยแพร่ผ่านผู้จำหน่าย หน้า 8–10](https://robu.in/wp-content/uploads/2024/06/18-RS-LDO-N01-1-Dissolved-Oxygen-Transmitter-Instruction-Manual-1.pdf)
- [MAX485: Analog Devices](https://www.analog.com/en/products/max485.html)
- [ESP GPIO voltage tolerance: Espressif](https://docs.espressif.com/projects/esp-faq/en/latest/hardware-related/hardware-design.html#what-is-the-voltage-tolerance-of-gpios-of-esp-chips)
- [DS18B20 datasheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ds18b20.pdf)

ผลทดสอบกับฮาร์ดแวร์ต้องอ้างอิงรายงาน verification ของรุ่นนี้ การคอมไพล์หรือเฟรมตัวอย่างในคู่มือยังไม่ยืนยันว่าหัววัดจริงเชื่อมต่อสำเร็จ
