"""Single-device development gateway. Production auth/queue/HA are separate work."""
import asyncio
import base64
import hashlib
import io
import json
import math
import os
import re
import secrets
import sqlite3
import tempfile
from contextlib import asynccontextmanager, suppress
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from camera_service import CameraService

DEVICE_ID = os.getenv("DEVICE_ID", "incubator-01")
TOKEN = os.getenv("DEV_ACCESS_TOKEN", "")
SIMULATE = os.getenv("SIMULATE_DEVICE", "0") == "1"
ORIGINS = [v.strip() for v in os.getenv("ALLOWED_ORIGINS", "http://localhost:8787,http://127.0.0.1:8787").split(",") if v.strip()]
ROOT = Path(__file__).resolve().parent
DB_PATH = os.getenv("AUDIT_DB", str(ROOT / "data" / "gateway.sqlite"))
if DB_PATH != ":memory:":
    Path(DB_PATH).parent.mkdir(parents=True, exist_ok=True)
DB = sqlite3.connect(DB_PATH, check_same_thread=False)
DB.execute("CREATE TABLE IF NOT EXISTS commands(id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, ack TEXT)")
DB.execute("CREATE TABLE IF NOT EXISTS samples(device TEXT NOT NULL, simulated INTEGER NOT NULL, minute INTEGER NOT NULL, payload TEXT NOT NULL, PRIMARY KEY(device,simulated,minute))")
DB.commit()

class Settings(BaseModel):
    model_config = ConfigDict(extra="forbid", allow_inf_nan=False)
    temperature_target: float = Field(default=28, ge=20, le=35)
    ph_minimum: float = Field(default=6.5, ge=0, le=14)
    ph_maximum: float = Field(default=8.5, ge=0, le=14)
    flow_target: float = Field(default=2.4, gt=0, le=50)
    @model_validator(mode="after")
    def ordered_ph(self):
        if self.ph_minimum >= self.ph_maximum:
            raise ValueError("pH minimum must be below maximum")
        return self

class Telemetry(BaseModel):
    model_config = ConfigDict(allow_inf_nan=False)
    schema_version: int = 1
    timestamp: datetime
    temperature_c: float | None = None
    ph: float | None = Field(default=None, ge=0, le=14)
    ph_calibrated: bool = False
    ph_calibrated_at: datetime | None = None
    wifi_rssi: int | None = Field(default=None, ge=-127, le=0)
    firmware_version: str | None = Field(default=None, max_length=80)
    flow_l_min: float | None = None
    water_level_ok: bool | None = None
    device_online: bool = True
    mode: Literal["auto", "manual"] = "auto"
    outputs: dict[str, bool] = Field(default_factory=dict)
    manual_until: datetime | None = None
    simulated: bool = False
    @field_validator("timestamp", "manual_until", "ph_calibrated_at")
    @classmethod
    def aware(cls, value):
        if value is not None and value.tzinfo is None:
            raise ValueError("timestamp must include timezone")
        return value

class Command(BaseModel):
    model_config = ConfigDict(extra="forbid")
    command_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,80}$")
    action: Literal["set_mode", "set_output", "set_config"]
    payload: dict
    expires_at: datetime
    @field_validator("expires_at")
    @classmethod
    def aware(cls, value):
        if value.tzinfo is None:
            raise ValueError("expires_at must include timezone")
        return value

settings = Settings()
current: Telemetry | None = None
sockets: set[WebSocket] = set()
loop: asyncio.AbstractEventLoop | None = None
mqtt_client = None
last_sequence: tuple[str, int] | None = None
ai_slot = asyncio.Semaphore(1)
model_instance = None
security = HTTPBearer(auto_error=False)

def utcnow():
    return datetime.now(timezone.utc)

def require_auth(credentials: HTTPAuthorizationCredentials | None = Depends(security)):
    if not TOKEN or credentials is None or not secrets.compare_digest(credentials.credentials, TOKEN):
        raise HTTPException(401, "รหัสเข้าถึงไม่ถูกต้อง")

def check_device(device_id):
    if device_id != DEVICE_ID:
        raise HTTPException(404, "ไม่พบเครื่องที่มีสิทธิ์เข้าถึง")

def snapshot():
    return {"device_id": DEVICE_ID, "config": settings.model_dump(), "telemetry": current.model_dump(mode="json") if current else None, "camera": camera.status()}

async def broadcast(message):
    async def send(ws):
        try:
            await asyncio.wait_for(ws.send_json(message), 2)
        except Exception:
            sockets.discard(ws)
    await asyncio.gather(*(send(ws) for ws in tuple(sockets)))

def record_history():
    if current is not None and current.device_online and abs((utcnow() - current.timestamp).total_seconds()) <= 15:
        minute = int(current.timestamp.timestamp() // 60)
        DB.execute("INSERT OR IGNORE INTO samples(device,simulated,minute,payload) VALUES(?,?,?,?)", (DEVICE_ID, int(current.simulated), minute, current.model_dump_json()))
        DB.execute("DELETE FROM samples WHERE minute < ?", (int(utcnow().timestamp() // 60) - 7 * 24 * 60,))
        DB.commit()

async def publish_snapshot():
    record_history()
    await broadcast({"type": "telemetry", "data": snapshot()})

async def receive_ack(data):
    command_id = data.get("command_id")
    if not isinstance(command_id, str) or data.get("status") not in {"applied", "rejected", "expired"}:
        return
    if DB.execute("SELECT id FROM commands WHERE id=?", (command_id,)).fetchone() is None:
        return
    safe = {"command_id": command_id, "status": data["status"], "message": str(data.get("message", "เครื่องตอบกลับแล้ว"))[:200]}
    DB.execute("UPDATE commands SET ack=? WHERE id=?", (json.dumps(safe, ensure_ascii=False), command_id))
    DB.commit()
    await broadcast({"type": "ack", "data": safe})

async def receive_mqtt(topic, raw, retained=False):
    global current, settings, last_sequence
    try:
        data = json.loads(raw)
        if not isinstance(data, dict):
            return
        if topic.startswith("incubator/v1/" + DEVICE_ID + "/camera/"):
            # Await a live heartbeat after restart; retained online may be stale.
            if retained and topic.endswith('/availability') and data.get('status') == 'online':
                return
            camera.receive(topic, data)
        elif topic.endswith("/ack"):
            await receive_ack(data)
        elif topic.endswith("/availability"):
            if current is not None and data.get("status") == "offline":
                current = current.model_copy(update={"device_online": False})
                await publish_snapshot()
        elif topic.endswith("/telemetry") or topic.endswith("/state"):
            value = data.get("telemetry", data)
            boot_id, seq = value.get("boot_id"), value.get("seq")
            if isinstance(boot_id, str) and isinstance(seq, int):
                if last_sequence is not None and boot_id == last_sequence[0] and seq <= last_sequence[1]:
                    return
            reading = Telemetry.model_validate(value)
            if reading.timestamp > utcnow() + timedelta(seconds=5):
                return
            if current is not None and reading.timestamp < current.timestamp:
                return
            # The MQTT path always represents hardware, never simulation.
            current = reading.model_copy(update={"simulated": False})
            if "config" in data:
                settings = Settings.model_validate(data["config"])
            if isinstance(boot_id, str) and isinstance(seq, int):
                last_sequence = (boot_id, seq)
            await publish_snapshot()
    except (ValueError, TypeError, KeyError):
        return

def start_mqtt():
    import paho.mqtt.client as mqtt
    global mqtt_client
    host = os.getenv("MQTT_HOST", "")
    if not host:
        raise RuntimeError("Set MQTT_HOST for hardware or SIMULATE_DEVICE=1 for a labelled simulator")
    mqtt_client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id="aqua-gateway-" + DEVICE_ID, protocol=mqtt.MQTTv5)
    username = os.getenv("MQTT_USERNAME")
    if username:
        mqtt_client.username_pw_set(username, os.getenv("MQTT_PASSWORD"))
    secure = os.getenv("MQTT_TLS", "1") == "1"
    if not secure and host not in {"localhost", "127.0.0.1", "::1", "broker"}:
        raise RuntimeError("Remote MQTT requires TLS")
    if secure:
        mqtt_client.tls_set(ca_certs=os.getenv("MQTT_CA_FILE"), certfile=os.getenv("MQTT_CERT_FILE"), keyfile=os.getenv("MQTT_KEY_FILE"))
    prefix = "incubator/v1/" + DEVICE_ID
    def on_connect(client, userdata, flags, reason_code, properties):
        if reason_code == 0:
            client.subscribe([(prefix + suffix, 1) for suffix in ["/telemetry", "/state", "/ack", "/availability", "/camera/availability", "/camera/result"]])
    def on_message(client, userdata, message):
        if loop is not None and len(message.payload) <= 64 * 1024:
            asyncio.run_coroutine_threadsafe(receive_mqtt(message.topic, message.payload, message.retain), loop)
    mqtt_client.on_connect = on_connect
    mqtt_client.on_message = on_message
    mqtt_client.connect_async(host, int(os.getenv("MQTT_PORT", "8883" if secure else "1883")), 30)
    mqtt_client.loop_start()

async def simulation_loop():
    global current
    tick = 0
    while True:
        tick += 1
        now = utcnow()
        outputs = dict(current.outputs) if current else {"pump": True, "heater": False, "cooler": False, "tumbler": True}
        mode = current.mode if current else "auto"
        until = current.manual_until if current else None
        if until and now >= until:
            mode, until = "auto", None
        if mode == "auto":
            outputs.update(pump=True, heater=False, cooler=False, tumbler=True)
        current = Telemetry(timestamp=now, temperature_c=settings.temperature_target + .15 * math.sin(tick / 4), ph=7.2, ph_calibrated=True, firmware_version="gateway-sim-0.2", flow_l_min=settings.flow_target if outputs["pump"] else 0, water_level_ok=True, mode=mode, outputs=outputs, manual_until=until, simulated=True)
        await publish_snapshot()
        await asyncio.sleep(2)

async def apply_simulated(command):
    global current, settings
    await asyncio.sleep(.12)
    status, message = "applied", "เครื่องจำลองที่ Gateway ยืนยันแล้ว"
    if command.expires_at <= utcnow():
        status, message = "expired", "คำสั่งหมดอายุ"
    elif current is None:
        status, message = "rejected", "เครื่องยังไม่พร้อม"
    elif command.action == "set_mode":
        manual = command.payload["mode"] == "manual"
        outputs = dict(current.outputs)
        if not manual:
            wet = current.water_level_ok is True
            outputs.update(pump=wet, tumbler=wet, heater=False, cooler=False)
        current = current.model_copy(update={"mode": "manual" if manual else "auto", "manual_until": utcnow() + timedelta(seconds=300) if manual else None, "outputs": outputs})
    elif command.action == "set_config":
        settings = Settings.model_validate(command.payload)
    else:
        output, enabled = command.payload["output"], command.payload["enabled"]
        if current.mode != "manual":
            status, message = "rejected", "เลือกโหมดควบคุมเองก่อน"
        elif enabled and current.water_level_ok is not True:
            status, message = "rejected", "ระดับน้ำไม่พร้อม"
        elif enabled and output in {"heater", "cooler", "tumbler"} and (not current.outputs.get("pump") or current.flow_l_min is None or current.flow_l_min < .1):
            status, message = "rejected", "ต้องมีการไหลของน้ำก่อน"
        elif enabled and ((output == "heater" and current.outputs.get("cooler")) or (output == "cooler" and current.outputs.get("heater"))):
            status, message = "rejected", "เปิดฮีตเตอร์และระบบทำความเย็นพร้อมกันไม่ได้"
        else:
            outputs = dict(current.outputs)
            outputs[output] = enabled
            if output == "pump" and not enabled:
                outputs.update(heater=False, cooler=False, tumbler=False)
            current = current.model_copy(update={"outputs": outputs, "flow_l_min": settings.flow_target if outputs["pump"] else 0})
    if current:
        current = current.model_copy(update={"timestamp": utcnow()})
    await publish_snapshot()
    await receive_ack({"command_id": command.command_id, "status": status, "message": message})

@asynccontextmanager
async def lifespan(app):
    global loop
    if len(TOKEN) < 16 or not re.fullmatch(r"[a-zA-Z0-9_-]{1,64}", DEVICE_ID):
        raise RuntimeError("DEV_ACCESS_TOKEN must have at least 16 characters; DEVICE_ID must be valid")
    loop = asyncio.get_running_loop()
    simulation_task = asyncio.create_task(simulation_loop()) if SIMULATE else None
    if not SIMULATE:
        start_mqtt()
    try:
        yield
    finally:
        if simulation_task:
            simulation_task.cancel()
            with suppress(asyncio.CancelledError):
                await simulation_task
        if mqtt_client:
            mqtt_client.disconnect()
            mqtt_client.loop_stop()
        for ws in tuple(sockets):
            with suppress(Exception):
                await ws.close()
        sockets.clear()

app = FastAPI(title="Aqua Hatch Development Gateway", version="0.4.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=ORIGINS, allow_credentials=False, allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"])

def publish_capture(payload):
    if mqtt_client is None or not mqtt_client.is_connected():
        raise RuntimeError("MQTT is disconnected")
    import paho.mqtt.client as mqtt
    properties = mqtt.Properties(mqtt.PacketTypes.PUBLISH)
    properties.MessageExpiryInterval = camera.timeout_seconds
    result = mqtt_client.publish("incubator/v1/" + DEVICE_ID + "/camera/command", json.dumps(payload), qos=1, retain=False, properties=properties)
    if result.rc != 0:
        raise RuntimeError("MQTT publish failed")

camera = CameraService(DB, ROOT / "data" / "captures", DEVICE_ID,
                       os.getenv("CAMERA_ID", DEVICE_ID + "-camera"),
                       os.getenv("CAMERA_PUBLIC_BASE_URL", ""), publish_capture, require_auth)
app.include_router(camera.router)

@app.get("/health")
def health():
    return {"status": "ok", "simulated": SIMULATE}

@app.get("/api/v1/devices/{device_id}", dependencies=[Depends(require_auth)])
def get_device(device_id: str):
    check_device(device_id)
    return snapshot()

@app.get("/api/v1/devices/{device_id}/history", dependencies=[Depends(require_auth)])
def history(device_id: str, limit: int = 1440):
    check_device(device_id)
    if limit < 1 or limit > 10080:
        raise HTTPException(422, "limit must be between 1 and 10080")
    rows = DB.execute("SELECT payload FROM samples WHERE device=? AND simulated=? ORDER BY minute DESC LIMIT ?", (device_id, int(SIMULATE), limit)).fetchall()
    return {"items": [json.loads(row[0]) for row in reversed(rows)], "retention_days": 7, "sample_interval_seconds": 60}

@app.post("/api/v1/devices/{device_id}/commands", status_code=202, dependencies=[Depends(require_auth)])
async def command(device_id: str, value: Command):
    check_device(device_id)
    now = utcnow()
    if value.expires_at <= now or value.expires_at > now + timedelta(seconds=30):
        raise HTTPException(422, "คำสั่งหมดอายุ หรือกำหนดอายุนานเกินไป")
    payload = value.payload
    if value.action == "set_mode":
        if set(payload) - {"mode", "duration_seconds"} or payload.get("mode") not in {"auto", "manual"} or payload.get("duration_seconds", 300) != 300:
            raise HTTPException(422, "รูปแบบคำสั่งเปลี่ยนโหมดไม่ถูกต้อง")
    elif value.action == "set_output":
        if set(payload) != {"output", "enabled"} or payload["output"] not in {"pump", "heater", "cooler", "tumbler"} or type(payload["enabled"]) is not bool:
            raise HTTPException(422, "รูปแบบคำสั่งอุปกรณ์ไม่ถูกต้อง")
    else:
        try:
            if set(payload) != {"temperature_target", "ph_minimum", "ph_maximum", "flow_target"}:
                raise ValueError("incomplete config")
            Settings.model_validate(payload)
        except ValueError:
            raise HTTPException(422, "ค่าตั้งเครื่องไม่ถูกต้อง") from None
    fingerprint = hashlib.sha256(json.dumps({"action": value.action, "payload": payload}, sort_keys=True).encode()).hexdigest()
    existing = DB.execute("SELECT fingerprint,ack FROM commands WHERE id=?", (value.command_id,)).fetchone()
    if existing:
        if existing[0] != fingerprint:
            raise HTTPException(409, "รหัสคำสั่งเดิมถูกใช้กับข้อมูลคนละชุด")
        if existing[1]:
            asyncio.create_task(broadcast({"type": "ack", "data": json.loads(existing[1])}))
        return {"command_id": value.command_id, "status": "accepted"}
    if current is None or not current.device_online or (now - current.timestamp).total_seconds() > 15:
        raise HTTPException(409, "ข้อมูลเครื่องไม่เป็นปัจจุบัน")
    if not SIMULATE and (mqtt_client is None or not mqtt_client.is_connected()):
        raise HTTPException(503, "Gateway ยังไม่เชื่อมต่อ MQTT Broker")
    DB.execute("INSERT INTO commands(id,fingerprint) VALUES(?,?)", (value.command_id, fingerprint))
    DB.commit()
    if SIMULATE:
        asyncio.create_task(apply_simulated(value))
    else:
        import paho.mqtt.client as mqtt
        properties = mqtt.Properties(mqtt.PacketTypes.PUBLISH)
        properties.MessageExpiryInterval = max(1, math.ceil((value.expires_at - utcnow()).total_seconds()))
        result = mqtt_client.publish("incubator/v1/" + DEVICE_ID + "/command", value.model_dump_json(), qos=1, retain=False, properties=properties)
        if result.rc != 0:
            DB.execute("DELETE FROM commands WHERE id=?", (value.command_id,)); DB.commit()
            raise HTTPException(503, "ส่งคำสั่งไปยัง Broker ไม่สำเร็จ")
    return {"command_id": value.command_id, "status": "accepted"}

@app.websocket("/api/v1/devices/{device_id}/stream")
async def stream(websocket: WebSocket, device_id: str):
    origin = websocket.headers.get("origin")
    if device_id != DEVICE_ID or (origin is not None and origin not in ORIGINS):
        await websocket.close(code=1008)
        return
    await websocket.accept()
    try:
        auth = await asyncio.wait_for(websocket.receive_json(), 5)
        if auth.get("type") != "auth" or not isinstance(auth.get("token"), str) or not TOKEN or not secrets.compare_digest(auth["token"], TOKEN):
            await websocket.close(code=1008)
            return
        sockets.add(websocket)
        await websocket.send_json({"type": "telemetry", "data": snapshot()})
        while True:
            await websocket.receive_text()
    except (WebSocketDisconnect, asyncio.TimeoutError, ValueError, RuntimeError):
        pass
    finally:
        sockets.discard(websocket)

@app.post("/api/v1/devices/{device_id}/counts/analyze", dependencies=[Depends(require_auth)])
async def analyze(device_id: str, file: UploadFile = File(...), kind: Literal["image", "video"] = Form("image")):
    check_device(device_id)
    data = await file.read(50 * 1024 * 1024 + 1)
    return await analyze_data(data, kind)

@app.post("/api/v1/devices/{device_id}/camera/captures/{capture_id}/analyze", dependencies=[Depends(require_auth)])
async def analyze_capture(device_id: str, capture_id: str):
    check_device(device_id)
    return await analyze_data(camera.image(capture_id), "image")

async def analyze_data(data, kind):
    weights = os.getenv("LARVAE_MODEL_PATH", "")
    if not weights or not Path(weights).is_file():
        raise HTTPException(503, "ยังไม่ได้ติดตั้งโมเดลนับลูกปลาที่ฝึกแล้ว กรุณานับด้วยมือ")
    if ai_slot.locked():
        raise HTTPException(429, "AI กำลังทำงาน กรุณาลองอีกครั้ง")
    if len(data) > 50 * 1024 * 1024:
        raise HTTPException(413, "ไฟล์มีขนาดเกิน 50 MB")
    if not data:
        raise HTTPException(422, "ไฟล์ว่าง")
    async with ai_slot:
        try:
            return await asyncio.to_thread(run_inference, data, kind, weights)
        except ImportError:
            raise HTTPException(503, "ยังไม่ได้ติดตั้ง dependencies ของ AI") from None
        except ValueError as error:
            raise HTTPException(422, str(error)) from None
        except Exception:
            raise HTTPException(503, "ประมวลผล AI ไม่สำเร็จ กรุณาตรวจโมเดลหรือใช้การนับด้วยมือ") from None

def run_inference(data, kind, weights):
    from PIL import Image, ImageOps
    from ultralytics import YOLO
    global model_instance
    if kind == "image":
        image = Image.open(io.BytesIO(data))
        if image.width * image.height > 25_000_000:
            raise ValueError("ภาพใหญ่เกิน 25 ล้านพิกเซล")
        image = ImageOps.exif_transpose(image).convert("RGB")
    else:
        import cv2
        import numpy as np
        with tempfile.NamedTemporaryFile(suffix=".mp4", delete=False, dir=ROOT / "data") as temp:
            temp.write(data); filename = temp.name
        capture = cv2.VideoCapture(filename)
        try:
            fps = capture.get(cv2.CAP_PROP_FPS); frames = capture.get(cv2.CAP_PROP_FRAME_COUNT)
            if fps <= 0 or frames <= 0 or frames / fps > 60:
                raise ValueError("เลือกคลิปที่อ่านได้ และยาวไม่เกิน 60 วินาที")
            best, score = None, -1
            for index in np.linspace(0, frames - 1, min(30, int(frames)), dtype=int):
                capture.set(cv2.CAP_PROP_POS_FRAMES, int(index)); ok, frame = capture.read()
                if ok:
                    sharpness = cv2.Laplacian(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), cv2.CV_64F).var()
                    if sharpness > score:
                        best, score = frame, sharpness
            if best is None:
                raise ValueError("อ่านเฟรมจากคลิปไม่ได้")
            image = Image.fromarray(cv2.cvtColor(best, cv2.COLOR_BGR2RGB))
        finally:
            capture.release(); Path(filename).unlink(missing_ok=True)
    if model_instance is None:
        model_instance = YOLO(weights)
    expected = os.getenv("LARVAE_CLASS_NAME", "larva")
    class_ids = [int(key) for key, name in model_instance.names.items() if name == expected]
    if len(class_ids) != 1:
        raise ValueError("โมเดลต้องมีคลาสลูกปลาที่ตรงกับ LARVAE_CLASS_NAME")
    result = model_instance.predict(image, classes=class_ids, conf=.25, verbose=False)[0]
    width, height = image.size
    points = [{"x": float((box[0] + box[2]) / 2 / width), "y": float((box[1] + box[3]) / 2 / height)} for box in result.boxes.xyxy.cpu().tolist()]
    output = io.BytesIO(); image.save(output, format="JPEG", quality=95)
    return {"points": points, "model_version": Path(weights).stem, "frame_base64": base64.b64encode(output.getvalue()).decode(), "count_semantics": "visible_in_selected_frame"}
