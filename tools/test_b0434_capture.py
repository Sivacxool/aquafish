"""Request a JPEG over USB from the ETT B0434 test build."""
import argparse
import base64
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import time


DIMENSIONS = {"vga": (640, 480), "3mp": (2048, 1536)}
LIGHTING = ("normal", "low-light", "compare")
MAX_JPEG = 2 * 1024 * 1024
MAX_CHUNK = 768
ERRORS = {
    "spi_or_sensor_timeout": "กล้องไม่ตอบ SPI ตรวจ +3.3V, GND และสายสัญญาณทั้งสี่",
    "unrecognized_3mp_sensor": "รหัสเซนเซอร์ไม่ตรงกับ Arducam Mega 3MP",
    "capture_timeout": "กล้องตอบ SPI แต่ไม่แจ้งว่าถ่ายเสร็จ",
    "invalid_fifo_length": "กล้องแจ้งขนาดภาพผิดปกติ ตรวจสาย SPI และไฟเลี้ยง",
    "image_expired": "หมดเวลารับภาพจากกล้อง ให้ลองถ่ายใหม่",
}


def request(connection, op, reply_type, **details):
    message = json.dumps({"op": op, **details}).encode("ascii") + b"\n"
    connection.write(message)
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        line = connection.read_until(b"\n", 4096)
        try:
            reply = json.loads(line)
        except (ValueError, UnicodeDecodeError):
            continue
        if isinstance(reply, dict) and reply.get("type") == reply_type:
            error = reply.get("error")
            if isinstance(error, str) and error:
                raise ValueError(ERRORS.get(error, error))
            return reply
    raise TimeoutError("บอร์ดไม่ตอบคำสั่งทดสอบ B0434 ตรวจ COM และรุ่นเฟิร์มแวร์")


def jpeg_dimensions(data):
    # Read the Start of Frame marker without decoding or resizing the image.
    index = 2
    frame_markers = {0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7,
                     0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF}
    while index + 4 <= len(data) and data[index] == 0xff:
        index += 1
        while index < len(data) and data[index] == 0xff:
            index += 1
        if index + 2 >= len(data):
            break
        marker = data[index]
        index += 1
        length = int.from_bytes(data[index:index + 2], "big")
        if length < 2 or index + length > len(data):
            break
        if marker in frame_markers and length >= 8:
            h = int.from_bytes(data[index + 3:index + 5], "big")
            w = int.from_bytes(data[index + 5:index + 7], "big")
            return w, h
        if marker == 0xda:
            break
        index += length
    raise ValueError("ไม่พบข้อมูลขนาดภาพ JPEG")


def capture(connection, resolution, lighting="normal"):
    status = request(
        connection, "b0434_capture", "b0434_status",
        resolution=resolution, lighting=lighting,
    )
    if status.get("lighting", "normal") != lighting:
        raise ValueError("โหมดแสงไม่ตรงกับคำขอ ตรวจว่าอัปโหลดเฟิร์มแวร์ Test 2 แล้ว")
    deadline = time.monotonic() + 16
    while status.get("status") == "busy" and time.monotonic() < deadline:
        time.sleep(.2)
        status = request(connection, "b0434_status", "b0434_status")
    length = status.get("bytes")
    if status.get("status") != "ready" or type(length) is not int or not 4 <= length <= MAX_JPEG:
        raise ValueError("กล้องยังไม่พร้อมส่ง JPG")
    if status.get("lighting", "normal") != lighting:
        raise ValueError("กล้องตอบกลับด้วยโหมดแสงคนละแบบกับคำขอ")
    expected = DIMENSIONS[resolution]
    if (status.get("width"), status.get("height")) != expected:
        raise ValueError("กล้องส่งสถานะขนาดภาพไม่ตรงกับคำขอ")
    print(f"อ่านภาพ {lighting} {expected[0]} × {expected[1]} ({length:,} bytes)…", flush=True)
    frame = bytearray()
    while len(frame) < length:
        chunk = request(connection, "b0434_read", "b0434_chunk", offset=len(frame))
        data = base64.b64decode(chunk.get("data", ""), validate=True)
        if (chunk.get("offset") != len(frame)
                or len(data) != min(MAX_CHUNK, length - len(frame))
                or hashlib.sha256(data).hexdigest() != chunk.get("sha256")):
            raise ValueError("ข้อมูลภาพผ่าน USB ไม่ครบหรือตรวจ checksum ไม่ผ่าน")
        frame.extend(data)
    start = frame.find(b"\xff\xd8", 0, 256)
    end = frame.rfind(b"\xff\xd9")
    if start < 0 or end <= start or len(frame) - end - 2 > 256:
        raise ValueError("เฟรมจากกล้องไม่มีหัวหรือท้าย JPEG ที่สมบูรณ์")
    image = bytes(frame[start:end + 2])
    if jpeg_dimensions(image) != expected:
        raise ValueError("ขนาด JPEG ที่ได้รับจริงไม่ตรงกับที่เลือก")
    return image


def main():
    import serial

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port")
    parser.add_argument("--resolution", choices=DIMENSIONS)
    parser.add_argument("--lighting", choices=LIGHTING)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1] / "captures")
    args = parser.parse_args()
    port = (args.port or input("พอร์ต USB ของ ETT เช่น COM5: ")).strip().upper()
    if not re.fullmatch(r"COM[1-9][0-9]*", port):
        parser.error("ระบุพอร์ตเป็น COM ตามด้วยตัวเลข")
    resolution = args.resolution
    if resolution is None:
        choice = input("กด Enter สำหรับ 640×480 หรือพิมพ์ 2 สำหรับ 2048×1536: ").strip()
        resolution = "3mp" if choice == "2" else "vga"
    lighting = args.lighting
    if lighting is None:
        choice = input("แสง [Enter] ปกติ  [2] แสงน้อย  [3] ถ่ายเทียบสองแบบ: ").strip()
        if choice not in ("", "1", "2", "3"):
            parser.error("เลือกโหมดแสง 1, 2 หรือ 3")
        lighting = {"2": "low-light", "3": "compare"}.get(choice, "normal")
    modes = ("normal", "low-light") if lighting == "compare" else (lighting,)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
    try:
        with serial.Serial(port=None, baudrate=115200, timeout=.25, write_timeout=2) as connection:
            connection.dtr = False
            connection.rts = False
            connection.port = port
            connection.open()
            time.sleep(1)
            connection.reset_input_buffer()
            for mode in modes:
                image = capture(connection, resolution, mode)
                args.output.mkdir(parents=True, exist_ok=True)
                path = args.output / f"B0434_{stamp}_{resolution}_{mode}.jpg"
                with path.open("xb") as output:
                    output.write(image)
                print(f"บันทึก JPG แล้ว {path}", flush=True)
    except (OSError, ValueError, TypeError) as error:
        parser.exit(1, f"ทดสอบไม่สำเร็จ {error}\n")


if __name__ == "__main__":
    main()
