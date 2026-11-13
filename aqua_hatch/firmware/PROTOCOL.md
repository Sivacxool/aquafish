# สัญญาการสื่อสาร ESP32 สำหรับ Aqua Hatch 0.2

> เอกสารนี้เป็นสถาปัตยกรรม MQTT/Gateway รุ่นเดิม ชุด WROOM-DA และเซนเซอร์ปัจจุบันใช้ HTTPS โดยตรง ดู `../SENSORS_SETUP_TH.md` และ `local_server/local_server.ino`

ยังไม่กำหนด GPIO หรือรุ่นเซนเซอร์ เอกสารนี้เป็นสัญญาที่ต้องนำไป implement ใน Firmware หลังตรวจวงจรจริง ไม่ใช่ Firmware พร้อม flash

## Transport และ Topic

MQTT 5 ผ่าน TLS ใช้ credential เฉพาะเครื่อง และ ACL จำกัดตาม device_id

| Topic | ผู้ส่ง | QoS | Retain |
|---|---|---|---|
| incubator/v1/{device_id}/telemetry | ESP32 | 0 | false |
| incubator/v1/{device_id}/state | ESP32 | 1 | true |
| incubator/v1/{device_id}/availability | ESP32 / Last Will | 1 | true |
| incubator/v1/{device_id}/command | Gateway | 1 | false |
| incubator/v1/{device_id}/ack | ESP32 | 1 | false |

## Telemetry

ส่งประมาณทุก 2–5 วินาที เวลาเป็น ISO 8601 พร้อม timezone ค่าเซนเซอร์ที่อ่านไม่ได้ต้องเป็น null

~~~json
{
  "schema_version": 1,
  "boot_id": "boot-unique-id",
  "seq": 123,
  "timestamp": "2026-10-12T10:00:00Z",
  "temperature_c": 28.1,
  "ph": 7.2,
  "ph_calibrated": true,
  "ph_calibrated_at": "2026-10-12T09:00:00Z",
  "wifi_rssi": -54,
  "firmware_version": "0.2.0",
  "flow_l_min": 2.4,
  "water_level_ok": true,
  "device_online": true,
  "mode": "auto",
  "manual_until": null,
  "outputs": {
    "pump": true,
    "heater": false,
    "cooler": false,
    "tumbler": true
  }
}
~~~

state เป็น object ที่มี telemetry ข้างต้นและ config:

~~~json
{
  "telemetry": { "...": "ตามตัวอย่าง telemetry" },
  "config": {
    "temperature_target": 28,
    "ph_minimum": 6.5,
    "ph_maximum": 8.5,
    "flow_target": 2.4
  }
}
~~~

ค่าตัวอย่างนี้สำหรับซอฟต์แวร์ ต้องกำหนดค่าจริงตามชนิดปลาและกระบวนการเพาะฟัก

Last Will ใช้ {"status":"offline"} และส่ง {"status":"online"} เมื่อเชื่อมต่อสำเร็จ

## คำสั่งและ ACK

~~~json
{
  "command_id": "unique-command-id",
  "action": "set_output",
  "payload": {"output":"pump","enabled":true},
  "expires_at": "2026-10-12T10:00:10Z"
}
~~~

- set_mode: payload.mode = auto หรือ manual; duration_seconds = 300
- set_output: output = pump/heater/cooler/tumbler และ enabled เป็น boolean
- set_config: ต้องส่ง temperature_target, ph_minimum, ph_maximum, flow_target ครบทั้ง 4 ค่า โดย 0 ≤ ph_minimum < ph_maximum ≤ 14

~~~json
{"command_id":"unique-command-id","status":"applied","message":"เครื่องยืนยันแล้ว"}
~~~

status เป็น applied, rejected หรือ expired เท่านั้น ส่ง applied หลังตรวจเงื่อนไขและตั้งสถานะเอาต์พุตสำเร็จ MQTT PUBACK ของ Broker ไม่ใช่ ACK ของเครื่อง

Firmware ต้องตรวจวันหมดอายุและ command_id ซ้ำเอง มีเวลาที่เชื่อถือได้ก่อนรับคำสั่ง remote ใช้คำสั่งตั้งสถานะ ไม่ใช้ toggle เพื่อให้ retry ปลอดภัย

## หน้าที่ที่ต้องอยู่ในเครื่อง

- อ่านเซนเซอร์และควบคุม Auto โดยไม่พึ่งมือถือหรืออินเทอร์เน็ต
- Manual เป็น lease 300 วินาที ตรวจด้วยเวลา monotonic และกลับ Auto เมื่อครบ
- ป้องกันฮีตเตอร์ทำงานเมื่อระดับน้ำต่ำหรือไม่มีการไหล
- ป้องกันเปิด heater และ cooler พร้อมกัน และตัดอุปกรณ์ที่ต้องใช้น้ำเมื่อ dry-run
- กำหนด fail state แยกแต่ละอุปกรณ์จากวงจรจริง พร้อมวงจรตัดความร้อนอิสระ
- ตรวจ active-high/active-low ของรีเลย์และสถานะ GPIO ตอน boot ก่อนต่อโหลด
- สถานะ outputs คือเอาต์พุตควบคุม ไม่ยืนยันว่าอุปกรณ์จริงหมุนหรือทำงาน ต้องมี feedback จากเซนเซอร์
- Calibration pH/อุณหภูมิ/flow ต้องใช้คู่มือและวิธีของเซนเซอร์รุ่นจริง
- แยก loop ควบคุมออกจาก MQTT callback; ตรวจคำสั่งผ่าน queue

ก่อนต่อเครื่อง ต้องทราบรุ่นบอร์ด รายการเซนเซอร์ แรงดันโหลด รีเลย์ และกลไกหมุนเวียนไข่ก่อน

## pH และข้อมูลที่อ่านไม่ได้

ระบบนี้ไม่มีระบบเติมออกซิเจน และไม่มีรีเลย์จ่ายสารปรับ pH ค่า pH เป็นการเฝ้าดูและแจ้งเตือนเท่านั้น
ส่ง `ph=null` เมื่ออ่านไม่ได้/เกินช่วง 0–14 ห้ามส่ง 0 แทนข้อผิดพลาด ส่ง `ph_calibrated=false` จนกว่าจะสอบเทียบหัววัดจริงแล้ว
`ph_calibrated_at` เป็นเวลาสอบเทียบจริง ไม่ใช่เวลาอ่านค่า ต้องเก็บไว้ข้ามการรีบูต หากไม่ทราบให้ส่ง null
`water_level_ok=null` หมายถึงอ่านเซนเซอร์ไม่ได้ ต่างจาก false ที่หมายถึงน้ำต่ำ; ทั้งสองกรณีต้องห้ามเปิดอุปกรณ์ที่ต้องใช้น้ำ
การสอบเทียบวงจร ADC กับการสอบเทียบหัววัด pH เป็นคนละขั้นตอน ต้องดำเนินการตามฮาร์ดแวร์ที่เลือก

## รีเลย์ ETT WROOM32UE ผ่าน HTTPS ในเครือข่ายภายใน

เฟิร์มแวร์ ETT 0.22.1-ett32ue.1 ประกาศ `capabilities.ett_manual_control=true` และส่ง `telemetry.ett_control` ที่มี `io_ready`, `manual_remaining_ms` และ `fan_commanded_on` ค่าหลังสุดมีเมื่อบัสรีเลย์พร้อม ค่า `manual_remaining_ms` นับจากนาฬิกาบอร์ด รายงาน 0 ในโหมดอัตโนมัติ ค่า `telemetry.fill.limit_seconds=null` ระบุว่าปั๊มเดินตามลูกลอยโดยไม่มีตัวจับเวลาตัด 60 วินาที

ส่งคำสั่งที่ `POST /api/v1/devices/{device_id}/commands` ด้วย Bearer token, `command_id` และ `expires_at_unix` เป็นวินาทีตามนาฬิกาบอร์ด

| action | payload | ผล |
| --- | --- | --- |
| `set_mode` | `{"mode":"manual","duration_seconds":300}` | เข้า Manual 5 นาที ปั๊มเดินตามลูกลอยต่อ ฮีตเตอร์และพัดลมเริ่มจากปิด การขอ Manual ซ้ำในช่วงเดิมไม่ต่อเวลา |
| `set_mode` | `{"mode":"auto"}` | กลับสู่อัตโนมัติ |
| `set_output` | `{"output":"cooler","enabled":true}` | เปิดพัดลม RY2 ใน Manual ใช้ `heater` สำหรับ RY0 และ `pump` เพื่อพักหรือเดินปั๊ม RY1 ตามลูกลอย |
| `set_config` | `{"temperature_target":28,"ph_minimum":6.5,"ph_maximum":8.5}` | ตั้งอุณหภูมิเป้าหมายและช่วงแจ้งเตือน pH |

คำสั่งที่ใช้ได้ส่ง ACK พร้อม `snapshot` ล่าสุด การปฏิเสธจากโหมดหรือเงื่อนไขเซนเซอร์ใช้ HTTP 409 วงจรรีเลย์ไม่พร้อมใช้ HTTP 503 บริการดูจากนอกบ้านส่งสถานะโดยอ่านอย่างเดียว

## การเก็บประวัติ

Gateway เก็บหนึ่งจุดต่อนาทีใน SQLite สูงสุด 7 วัน แยกเครื่องจริง/จำลอง เรียก `GET /api/v1/devices/{device_id}/history?limit=1440` ด้วย Bearer token
แอปเก็บสำเนาสูงสุด 1,440 จุดต่อการเชื่อมต่อ อ่านขณะออฟไลน์ได้ แต่ข้อมูลย้อนหลังจะไม่ใช้ปลดล็อกปุ่มควบคุม
