"""Authenticated MQTT capture jobs; camera uploads never receive the app token."""
import hashlib
import io
import re
import secrets
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field


class CaptureRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    capture_id: str = Field(pattern=r"^[a-zA-Z0-9_-]{1,80}$")


class CameraService:
    timeout_seconds = 90
    max_bytes = 8 * 1024 * 1024

    def __init__(self, db, directory, device_id, camera_id, public_url, publish, auth):
        self.db, self.directory = db, Path(directory)
        self.device_id, self.camera_id = device_id, camera_id
        self.public_url, self.publish = public_url.rstrip("/"), publish
        self.last_seen = None
        self.available = False
        self.db.execute("""CREATE TABLE IF NOT EXISTS captures(
            id TEXT PRIMARY KEY, camera TEXT NOT NULL, created TEXT NOT NULL,
            expires TEXT NOT NULL, status TEXT NOT NULL, token_hash TEXT NOT NULL,
            received TEXT, digest TEXT, error TEXT)""")
        self.db.commit()
        self.router = APIRouter(prefix="/api/v1/devices/{device_id}/camera")
        r = self.router

        @r.get("", dependencies=[Depends(auth)])
        async def status(device_id: str):
            self.check_device(device_id)
            self.cleanup()
            return self.status()

        @r.post("/captures", status_code=202, dependencies=[Depends(auth)])
        async def create(device_id: str, value: CaptureRequest):
            self.check_device(device_id)
            return self.create(value.capture_id)

        @r.get("/captures/{capture_id}", dependencies=[Depends(auth)])
        async def job(device_id: str, capture_id: str):
            self.check_device(device_id)
            return self.job(capture_id)

        @r.get("/captures/{capture_id}/image", dependencies=[Depends(auth)])
        async def image(device_id: str, capture_id: str):
            self.check_device(device_id)
            return Response(self.image(capture_id), media_type="image/jpeg",
                            headers={"Cache-Control": "no-store"})

        @r.post("/captures/{capture_id}/image")
        async def upload(device_id: str, capture_id: str, request: Request):
            self.check_device(device_id)
            row = self.row(capture_id)
            token = request.headers.get("authorization", "").removeprefix("Bearer ")
            if not token or not secrets.compare_digest(hashlib.sha256(token.encode()).hexdigest(), row["token_hash"]):
                raise HTTPException(401, "รหัสอัปโหลดไม่ถูกต้อง")
            if datetime.fromisoformat(row["expires"]) <= self.now():
                self.job(capture_id)
                raise HTTPException(410, "คำสั่งถ่ายภาพหมดอายุ")
            if row["status"] not in {"queued", "captured"}:
                raise HTTPException(409, "งานถ่ายภาพสิ้นสุดแล้ว")
            if request.headers.get("content-type", "").split(";")[0].strip() != "image/jpeg":
                raise HTTPException(415, "กล้องต้องส่งภาพ JPEG")
            chunks, size = [], 0
            async for chunk in request.stream():
                size += len(chunk)
                if size > self.max_bytes:
                    raise HTTPException(413, "ภาพจากกล้องต้องไม่เกิน 8 MB")
                chunks.append(chunk)
            data = b"".join(chunks)
            try:
                with Image.open(io.BytesIO(data)) as img:
                    if img.format != "JPEG" or img.width * img.height > 25_000_000:
                        raise ValueError()
                    img.load()
            except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError):
                raise HTTPException(422, "ไฟล์จากกล้องไม่ใช่ภาพ JPEG ที่อ่านได้") from None
            # The stream may have crossed its deadline, or a camera failure arrived.
            row = self.row(capture_id)
            if datetime.fromisoformat(row["expires"]) <= self.now():
                self.job(capture_id)
                raise HTTPException(410, "คำสั่งถ่ายภาพหมดอายุ")
            digest = hashlib.sha256(data).hexdigest()
            if row["status"] == "captured":
                if row["digest"] != digest:
                    raise HTTPException(409, "ไม่สามารถเขียนทับภาพของคำสั่งเดิม")
                return self.job(capture_id)
            if row["status"] != "queued":
                raise HTTPException(409, "งานถ่ายภาพสิ้นสุดแล้ว")
            self.directory.mkdir(parents=True, exist_ok=True)
            path = self.path(capture_id)
            temp = path.with_suffix(".tmp")
            temp.write_bytes(data)
            temp.replace(path)
            self.db.execute("UPDATE captures SET status='captured',received=?,digest=? WHERE id=?",
                            (self.now().isoformat(), digest, capture_id))
            self.db.commit()
            return self.job(capture_id)

    @staticmethod
    def now():
        return datetime.now(timezone.utc)

    def check_device(self, device_id):
        if device_id != self.device_id:
            raise HTTPException(404, "ไม่พบเครื่องที่มีสิทธิ์เข้าถึง")

    def row(self, capture_id):
        if not re.fullmatch(r"[a-zA-Z0-9_-]{1,80}", capture_id):
            raise HTTPException(404, "ไม่พบคำสั่งถ่ายภาพ")
        cursor = self.db.execute("SELECT * FROM captures WHERE id=?", (capture_id,))
        values = cursor.fetchone()
        if values is None:
            raise HTTPException(404, "ไม่พบคำสั่งถ่ายภาพ")
        return dict(zip((c[0] for c in cursor.description), values))

    def path(self, capture_id):
        return self.directory / (capture_id + ".jpg")

    def cleanup(self):
        now = self.now()
        self.db.execute("UPDATE captures SET status='expired',error=? WHERE status='queued' AND expires<=?",
                        ("กล้องยังไม่ส่งภาพกลับภายในเวลาที่กำหนด", now.isoformat()))
        # Bound private disk storage: retain seven days, at most 200 capture jobs.
        expired = self.db.execute("SELECT id FROM captures WHERE created<? OR id IN (SELECT id FROM captures ORDER BY created DESC LIMIT -1 OFFSET 200)",
                                  ((now - timedelta(days=7)).isoformat(),)).fetchall()
        for (capture_id,) in expired:
            self.path(capture_id).unlink(missing_ok=True)
            self.db.execute("DELETE FROM captures WHERE id=?", (capture_id,))
        self.db.commit()

    def status(self):
        configured = bool(self.public_url)
        online = self.available and self.last_seen is not None and (self.now() - self.last_seen).total_seconds() <= 45
        return {"camera_id": self.camera_id, "configured": configured, "online": online,
                "last_seen": self.last_seen.isoformat() if self.last_seen else None,
                "message": ("กล้องพร้อมถ่ายภาพ" if online else "กล้องยังไม่เชื่อมต่อ") if configured else "ยังไม่ได้ตั้งค่ากล้องที่เซิร์ฟเวอร์"}

    def job(self, capture_id):
        self.cleanup()
        row = self.row(capture_id)
        return {"capture_id": row["id"], "camera_id": row["camera"], "status": row["status"],
                "requested_at": row["created"], "expires_at": row["expires"],
                "received_at": row["received"], "message": row["error"]}

    def create(self, capture_id):
        self.cleanup()
        if self.db.execute("SELECT 1 FROM captures WHERE id=?", (capture_id,)).fetchone():
            return self.job(capture_id)
        parsed = urlparse(self.public_url)
        if (parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1", "::1"})) or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
            raise HTTPException(503, "ตั้งค่า CAMERA_PUBLIC_BASE_URL เป็น HTTPS ที่กล้องเข้าถึงได้ก่อน")
        if not self.status()["online"]:
            raise HTTPException(409, "กล้องออฟไลน์ ตรวจไฟเลี้ยงและ Wi-Fi ของบอร์ดกล้อง")
        if self.db.execute("SELECT 1 FROM captures WHERE status='queued'").fetchone():
            raise HTTPException(409, "กล้องกำลังถ่ายภาพ รอคำสั่งเดิมเสร็จก่อน")
        now = self.now()
        expires = now + timedelta(seconds=self.timeout_seconds)
        upload_token = secrets.token_urlsafe(32)
        self.db.execute("INSERT INTO captures(id,camera,created,expires,status,token_hash) VALUES(?,?,?,?,?,?)",
                        (capture_id, self.camera_id, now.isoformat(), expires.isoformat(), "queued", hashlib.sha256(upload_token.encode()).hexdigest()))
        self.db.commit()
        payload = {"schema_version": 1, "action": "capture", "camera_id": self.camera_id,
                   "capture_id": capture_id, "expires_at": expires.isoformat(), "expires_at_unix": int(expires.timestamp()),
                   "upload_url": self.public_url + f"/api/v1/devices/{self.device_id}/camera/captures/{capture_id}/image",
                   "upload_token": upload_token, "max_bytes": self.max_bytes}
        try:
            self.publish(payload)
        except Exception:
            self.db.execute("UPDATE captures SET status='failed',error=? WHERE id=?", ("ส่งคำสั่งถึงกล้องไม่สำเร็จ", capture_id))
            self.db.commit()
            raise HTTPException(503, "ส่งคำสั่งถึงกล้องไม่สำเร็จ ตรวจ MQTT Broker") from None
        return self.job(capture_id)

    def receive(self, topic, data):
        if data.get("camera_id") != self.camera_id:
            return
        if topic.endswith("/availability") and data.get("status") in {"online", "offline"}:
            self.available = data["status"] == "online"
            self.last_seen = self.now()
        elif topic.endswith("/result") and data.get("status") == "failed":
            capture_id = data.get("capture_id")
            self.db.execute("UPDATE captures SET status='failed',error=? WHERE id=? AND status='queued'",
                            (str(data.get("message", "กล้องถ่ายภาพไม่สำเร็จ"))[:200], capture_id))
            self.db.commit()

    def image(self, capture_id):
        if self.job(capture_id)["status"] != "captured":
            raise HTTPException(409, "ยังไม่ได้รับภาพจากกล้อง")
        try:
            return self.path(capture_id).read_bytes()
        except FileNotFoundError:
            raise HTTPException(410, "ภาพหมดอายุหรือไม่อยู่ในพื้นที่จัดเก็บแล้ว") from None
