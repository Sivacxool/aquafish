# เฟิร์มแวร์ทดสอบ ETT WROOM32UE + Arducam B0434

รุ่น `0.22.1-ett32ue-b0434-test.1` ทดสอบสั่งกล้อง Mega SPI 3MP และรับไฟล์ JPG ผ่าน USB จากบอร์ด ETT ตัวหลัก ทดสอบได้โดยไม่ต้องเชื่อม Wi-Fi กับกล้อง รุ่นนี้ใช้โปรไฟล์ควบคุมและอ่านเซนเซอร์ ETT เดิม และเปิดคำสั่งกล้องสำหรับโปรแกรมทดสอบบนคอม

## ต่อสายและติดตั้ง

ถอดปลั๊กฮีตเตอร์และตัดไฟโหลดปั๊มกับพัดลมก่อนทดสอบ ปิดไฟ ETT ก่อนต่อสายกล้องเข้าหัวสีขาว `4G-EC200U BUS` โดยยึดตำแหน่งจากสกรีน `+5V / +3V3 / PWRKEY / RESET / STATUS / TX1 / RX1 / GND` ตามคู่มือ หัวนี้ต้องว่างจากแผง 4G ก่อนต่อกล้อง

| ขากล้อง | หัว 4G ของ ETT |
| --- | --- |
| VCC | ขา 2 +3.3V |
| GND | ขา 8 GND |
| SCK | ขา 7 GPIO14 / RX1 |
| MISO | ขา 5 GPIO34 / STATUS |
| MOSI | ขา 4 GPIO25 / RESET |
| CS | ขา 3 GPIO33 / PWRKEY |

เว้นขา 1 (+5V) และคงลูกลอยที่ขา 6 (GPIO13) ตามเดิม ใช้สายกล้องสั้น ๆ และตรวจแรงดันที่ขา VCC ของกล้องเทียบ GND ก่อนทดสอบ [คู่มือ ETT หน้า 3 และผังวงจรแผ่น 1–2](https://www.etteam.com/productI2C_RS485/ET-ESP/et-esp32-wroom-32ue-v1.zip) · [คู่มือต่อ Arducam Mega SPI](https://docs.arducam.com/Arduino-SPI-camera/MEGA-SPI/MEGA-Quick-Start-Guide/#hardware-connection)

1. แตก ZIP ต่อ ET‑USB USART/TTL เข้าหัวโปรแกรมเมอร์ของ ETT ใช้ไฟจากโปรแกรมเมอร์หรือไฟบอร์ดตามผัง ETT ขณะเสียบ USB พร้อมไฟบอร์ด ให้ใช้การต่อ UART ที่แยกสาย +5V ดูหัวข้อ 5 ใน [คู่มือไฟและ USB ของ ETT](ETT_WROOM32UE_SETUP_TH.md)
2. ปิด Arduino Serial Monitor เปิด `Install-ETT-B0434-Test.cmd` แล้วเลือก COM ของ ETT ต้องมี Python 3.11 ขึ้นไปและ Arduino IDE/CLI ที่ติดตั้ง Arduino‑ESP32 3.3.12 ตัวติดตั้งเขียนทับเฉพาะพื้นที่เฟิร์มแวร์และเก็บข้อมูลจับคู่กับ Wi-Fi ใน NVS
3. เปิด `tools\Test-B0434.cmd` เลือก COM เดิม กด Enter เพื่อทดสอบ 640 × 480 แล้วลอง 2048 × 1536 ถ้าได้ภาพแรก เปิด JPG จากโฟลเดอร์ `captures` ในชุดที่แตกไว้
4. ถ้าขึ้น `spi_or_sensor_timeout` ให้ปิดไฟแล้วตรวจ +3.3V, GND, SCK, MISO, MOSI และ CS หากรับภาพไม่ครบ โปรแกรมจะแจ้งสาเหตุและเก็บไฟล์เมื่อภาพผ่านการตรวจ checksum กับขนาด JPEG แล้ว

คำสั่งกล้องทดสอบอยู่บน USB ส่วนการถ่ายจากแอปและการเขียน microSD ต้องเพิ่มหลังตรวจกล้องจริง รุ่นนี้คอมไพล์สำหรับ ETT และต้องทดสอบกับฮาร์ดแวร์ก่อนต่อโหลดกลับ

## สร้างเฟิร์มแวร์และกลับรุ่นเดิม

```powershell
./aqua_hatch/firmware/local_server/Build-Device.ps1 -Profile ett32ue-b0434-test
```

กลับรุ่นใช้งานจริงด้วย [เฟิร์มแวร์ ETT รุ่น 0.22.1-ett32ue.1](https://github.com/Sivacxool/aquafish/releases/download/v0.22.1/AquaHatch-ETT-WROOM32UE-v0.22.1-ett32ue.1-FirstBoot.zip)

ไดรเวอร์ทดสอบอ้างอิง [เอกสารรีจิสเตอร์และ SPI ของ Arducam](https://cdn.arducam.com/downloads/datasheet/Arducam_MEGA_SPI_Camera_Application_Note.pdf) และ [รหัสเซนเซอร์กับโหมดความละเอียดจาก Arducam Mega SDK](https://github.com/ArduCAM/Arducam_Mega/blob/146e058b1b5e57bd0d2c64885d0642390e11b6b1/src/Arducam/ArducamCamera.c)
