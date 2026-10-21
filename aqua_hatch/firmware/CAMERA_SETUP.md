# สั่งกล้องในเครื่องจากแอป — Aqua Hatch 0.4.0

แอปมีปุ่ม **ถ่ายภาพจากกล้องในเครื่อง** ในหน้า “นับลูกปลา” กดแล้วสร้างงานถ่ายภาพหนึ่งงาน รอ JPEG จาก ESP32-S3 CAM แล้วแสดงภาพพร้อมเวลาที่เซิร์ฟเวอร์รับ หลังจากนั้นกด “วิเคราะห์ด้วย AI” เพื่อใช้ภาพเดียวกันบนคลาวด์ ตรวจแก้จุดนับ แล้วบันทึกเข้ารอบฟักได้

กล้องมือถือ/เลือกภาพ/เลือกคลิปอยู่ใน “นำเข้าภาพอื่น (ทางเลือก)” ภาพตัวอย่างเป็นการจำลอง ต้องเลือกเอง ไม่ได้ใช้แทนภาพจากเครื่องจริง

## สิ่งที่ต้องตั้งค่าก่อนใช้กล้องจริง

1. อัปเดต Gateway เป็นโค้ดในชุด 0.4.0 และติดตั้ง `gateway/requirements.txt` บนเซิร์ฟเวอร์ของเจ้าของเครื่อง ใช้ HTTPS ที่มีใบรับรองถูกต้อง และ MQTT Broker ที่รองรับ TLS
2. ตั้งค่า environment ของ Gateway (ไฟล์ `.env.example` เป็นตัวอย่าง ไม่ได้ถูกโหลดเอง ต้องใช้ environment ของบริการ หรือ `uvicorn --env-file` พร้อม python-dotenv):

   ```dotenv
   DEVICE_ID=incubator-01
   CAMERA_ID=incubator-01-camera
   CAMERA_PUBLIC_BASE_URL=https://your-gateway.example.com
   DEV_ACCESS_TOKEN=<รหัสแอปแบบสุ่ม>
   SIMULATE_DEVICE=0
   MQTT_HOST=<ชื่อ broker>
   MQTT_PORT=8883
   MQTT_TLS=1
   MQTT_USERNAME=<บัญชี gateway>
   MQTT_PASSWORD=<รหัส gateway>
   ```

   `CAMERA_PUBLIC_BASE_URL` คือ URL หลักที่บอร์ดเข้าถึงได้ ไม่ใช่ `localhost`, URL ของ bucket หรือ URL ที่ลงท้าย `/api/v1` ตั้ง reverse proxy ให้ยอมรับ JPEG สูงสุด 8 MB และไม่เขียน Authorization ลง log ใช้ Gateway หนึ่ง process/worker ต่อเครื่องตามข้อจำกัดของระบบเดิม

3. ฝั่งบอร์ดกล้องมี reference sketch ใน `camera_node/camera_node.ino` และ `config.example.h` คัดลอกเป็น `config.h` กรอก Wi‑Fi, MQTT, ID, URL และ root CA ของ broker/HTTPS แยกกัน เปิด PSRAM ตามบอร์ดจริง สเก็ตช์หยุด compile จนยืนยัน pin map เพื่อป้องกันการเดาขาจากชื่อ “S3 WROOM” ที่มีหลายบอร์ด
4. ต้องใช้ pin map จากผู้ผลิตของบอร์ดตัวจริงและคอนเนกเตอร์ OV5640 ตัวนั้น ชื่อ N16R8 หรือภาพหน้าร้านอย่างเดียวไม่พอระบุ GPIO ทุกขา ชุดนี้คอมไพล์ source ผ่านกับ Arduino-ESP32 3.3.12, PubSubClient 2.8.0 และ ArduinoJson 7.4.3 โดยใช้ config ทดสอบเพื่อตรวจ API เท่านั้น ยัง **ไม่ได้ flash หรือทดสอบกับบอร์ดจริง** ต้องกรอก pin map/ขนาด flash/ชนิด PSRAM ตามบอร์ดจริงแล้วตรวจ compile อีกครั้ง ผล compile ทดสอบไม่ยืนยัน GPIO
5. ในแอปไป “ตั้งค่า” เลือกเครื่องจริง ใส่ URL Gateway, DEVICE_ID และรหัสแอป เมื่อสถานะ “กล้องในเครื่อง” เป็น “พร้อมถ่าย” จึงกดถ่ายได้ บอร์ดหลักไม่จำเป็นต้องออนไลน์เพื่อรับภาพ แต่ต้องออนไลน์และส่ง telemetry ใหม่จึงควบคุมปั๊ม/ฮีตเตอร์ได้

อย่าใส่ DEV_ACCESS_TOKEN ของแอปลงในกล้อง บอร์ดได้รับเพียง token อัปโหลดเฉพาะงาน อายุ 90 วินาที ภาพเก็บส่วนตัวบน Gateway ตามนโยบาย 7 วัน/200 งาน โดยตรวจล้างเมื่อเรียกสถานะหรืองานใหม่ ไม่ใช่ public bucket ต้องให้ volume ข้อมูลคงอยู่หลัง restart และมีโควตาพื้นที่อย่างน้อยประมาณ 1.6 GB หากใช้ภาพขนาดสูงสุดทุกงาน

## MQTT ของบอร์ดกล้อง

| Topic (แทน incubator-01 ด้วยรหัสจริง) | ผู้ส่ง → ผู้รับ | รูปแบบ |
| --- | --- | --- |
| `incubator/v1/incubator-01/camera/command` | Gateway → กล้อง | QoS 1, retain=false |
| `incubator/v1/incubator-01/camera/availability` | กล้อง → Gateway | heartbeat ทุก 15 วินาที, retained; LWT=offline |
| `incubator/v1/incubator-01/camera/result` | กล้อง → Gateway | แจ้ง failed; ความสำเร็จยืนยันจาก HTTP upload |

ตั้ง ACL ของบัญชีกล้องให้ subscribe เฉพาะ camera/command ของเครื่องตัวเอง และ publish เฉพาะ camera/availability กับ camera/result ห้าม subscribe wildcard ของทุกเครื่อง บัญชี Gateway publish/subscribe เฉพาะเครื่องที่ดูแล ตัวอย่าง sketch ใช้ MQTT 3.1.1 รับ QoS 1 และ publish สถานะ QoS 0 พร้อม heartbeat; LWT QoS 1 การยืนยันรับภาพใช้ HTTP ไม่พึ่งข้อความ QoS 0

Availability:

```json
{"camera_id":"incubator-01-camera","status":"online"}
```

Gateway รอ live heartbeat หลังเริ่มบริการใหม่ ไม่ถือ retained online เก่าว่าออนไลน์ ถ้าไม่มี heartbeat เกิน 45 วินาทีจะแสดงออฟไลน์

คำสั่งถ่าย:

```json
{
  "schema_version":1,
  "action":"capture",
  "camera_id":"incubator-01-camera",
  "capture_id":"unique-request-id",
  "expires_at":"2026-10-19T15:01:30+00:00",
  "expires_at_unix":1792422090,
  "upload_url":"https://your-gateway.example.com/api/v1/devices/incubator-01/camera/captures/unique-request-id/image",
  "upload_token":"<เฉพาะงานนี้>",
  "max_bytes":8388608
}
```

ค่าตัวอย่างเวลาใช้แสดงรูปแบบเท่านั้น บอร์ดต้อง sync เวลา NTP, ปฏิเสธงานหมดอายุ/ผิด camera_id, ตรวจ URL ให้ตรง Gateway ที่ตั้งไว้ และกัน capture_id ซ้ำ ข้อความ MQTT ที่ส่งซ้ำต้องไม่ถ่ายอีกรอบ Reference sketch จำ ID ล่าสุด 8 งานใน NVS และ retry อัปโหลดด้วย JPEG เดิมเท่านั้น

อัปโหลด `POST upload_url` ด้วย `Content-Type: image/jpeg`, `Authorization: Bearer <upload_token>` และ body เป็น JPEG binary โดยตรง ไม่มี multipart Gateway ตรวจว่าเป็น JPEG ที่อ่านได้ ขนาดไม่เกิน 8 MB/25 ล้านพิกเซล และยังไม่หมดเวลา การส่ง JPEG เดิมซ้ำตอบ 200 แต่ส่งภาพอื่นทับ ID เดิมตอบ 409

หากถ่าย/อัปโหลดไม่ได้ publish:

```json
{"camera_id":"incubator-01-camera","capture_id":"unique-request-id","status":"failed","message":"Upload failed"}
```

หากบอร์ดรีบูตระหว่างงาน อาจต้องรอให้งานหมดอายุแล้วกดถ่ายใหม่ แอปไม่ส่งคำสั่งถ่ายซ้ำอัตโนมัติเมื่อ HTTP ไม่แน่นอน เพื่อไม่สร้างภาพคนละจังหวะโดยผู้ใช้ไม่รู้

## HTTP ที่แอปใช้ (Bearer token ของแอป)

| Method / path ต่อจาก `/api/v1/devices/{device_id}` | หน้าที่ |
| --- | --- |
| GET `/camera` | สถานะกล้องอิสระจากบอร์ดควบคุม |
| POST `/camera/captures` | body `{"capture_id":"..."}`; ตอบ 202 พร้อมงานเดิมเมื่อใช้ ID เดิม |
| GET `/camera/captures/{id}` | queued / captured / failed / expired |
| GET `/camera/captures/{id}/image` | รับ JPEG แบบ private, no-store |
| POST `/camera/captures/{id}/analyze` | นับภาพที่รับแล้วบนคลาวด์ ไม่ต้องอัปโหลดซ้ำจากมือถือ |

`received_at` คือเวลาเซิร์ฟเวอร์รับภาพ ไม่ใช่เวลาของเซนเซอร์ ใช้ ID ตรงคำสั่งเพื่อกันภาพสลับงาน และล้างภาพบนหน้าจอทันทีเมื่อเปลี่ยนเครื่อง/เซิร์ฟเวอร์หรือเริ่มถ่ายใหม่

AI ต้องตั้ง `LARVAE_MODEL_PATH` เป็น weights ที่ฝึกกับลูกปลาจริง และคลาสตาม `LARVAE_CLASS_NAME` ไม่มี weights ดังกล่าวในชุดนี้ หากยังไม่ตั้งจะได้ HTTP 503 ภาพยังเปิดตรวจและนับจุดด้วยมือได้ ไม่มีการสร้างจำนวนปลาปลอม

## ตรวจรับกับเครื่องจริง

- กล้องต้องเห็นถาดครบ โฟกัสถึงลูกปลา แสงคงที่ ลดเงาสะท้อน/หยดน้ำบนเลนส์ ทดสอบ JPEG จริงที่ UXGA ก่อน แล้วเลือก QSXGA หาก OV5640 และเวลาส่งภาพรองรับ
- เปิดแอปจากเครือข่ายอื่น กดถ่าย เปลี่ยนวัตถุในถาด แล้วถ่ายใหม่ ตรวจว่า ID และภาพใหม่ตรงกัน
- ถอดไฟกล้อง/ตัด Wi‑Fi ต้องแสดงออฟไลน์หรือหมดเวลา โดยไม่ใช้ภาพเดิมแทน บอร์ดหลักต้องควบคุมต่อได้
- กดซ้ำ/เครือข่ายสะดุด/รีบูตกล้องระหว่างงาน ต้องไม่ส่งภาพไปผิดเครื่อง ไม่อัปโหลดภาพซ้ำคนละภาพใน ID เดียว
- ทดสอบโมเดลกับภาพจากกล้องและการติดตั้งจริง แยกชุดตรวจวัดความแม่นยำออกจากชุดฝึกก่อนใช้ผลนับในการทำงานจริง
