"""Loopback HTTP integration fixture. Does not emulate MQTT or ESP32 hardware."""
import argparse
import asyncio
from contextlib import asynccontextmanager, suppress
import io
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--config-file', required=True, type=Path,
                    help='Write an ephemeral TEST_GATEWAY_TOKEN for flutter test')
args = parser.parse_args()
args.config_file.parent.mkdir(parents=True, exist_ok=True)
token = secrets.token_urlsafe(32)
args.config_file.write_text(json.dumps({'TEST_GATEWAY_TOKEN': token}), encoding='utf-8')
os.environ.update(DEV_ACCESS_TOKEN=token, DEVICE_ID='incubator-01', SIMULATE_DEVICE='1',
                  AUDIT_DB=':memory:', CAMERA_PUBLIC_BASE_URL='http://localhost:8000',
                  ALLOWED_ORIGINS='http://localhost:8794,http://127.0.0.1:8794,http://localhost:8787,http://127.0.0.1:8787')
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import main
import httpx
import uvicorn
from PIL import Image, ImageDraw

storage = tempfile.TemporaryDirectory(prefix='aquahatch-software-camera-')
main.camera.directory = Path(storage.name)
sequence = 0
real_status = main.camera.status


def fixture_status():
    value = real_status()
    if value['online']:
        value['message'] = 'กล้องจำลองสำหรับทดสอบซอฟต์แวร์'
    return value


main.camera.status = fixture_status


async def upload_fixture(payload):
    global sequence
    await asyncio.sleep(.6)
    sequence += 1
    image = Image.new('RGB', (960, 640), '#e8f3f5')
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((60, 90, 900, 560), radius=40, fill='#afdae1', outline='#216579', width=5)
    for index in range(12):
        x, y = 140 + index % 4 * 200, 180 + index // 4 * 140
        draw.ellipse((x, y, x + 34, y + 13), fill='#215569')
        draw.line((x + 30, y + 7, x + 50, y + 18), fill='#215569', width=4)
    draw.text((70, 30), f'SOFTWARE CAMERA TEST / FRAME {sequence}', fill='#123f50', font_size=30)
    draw.text((70, 592), 'SYNTHETIC FIXTURE - NO PHYSICAL CAMERA CONNECTED', fill='#123f50', font_size=22)
    jpeg = io.BytesIO()
    image.save(jpeg, 'JPEG', quality=90)
    async with httpx.AsyncClient() as client:
        response = await client.post(payload['upload_url'], content=jpeg.getvalue(),
            headers={'Authorization': 'Bearer ' + payload['upload_token'], 'Content-Type': 'image/jpeg'})
        response.raise_for_status()


pending = set()


def fixture_publish(payload):
    task = asyncio.create_task(upload_fixture(payload))
    pending.add(task)
    task.add_done_callback(pending.discard)


main.camera.publish = fixture_publish
real_lifespan = main.app.router.lifespan_context


@asynccontextmanager
async def fixture_lifespan(app):
    async with real_lifespan(app):
        async def heartbeat():
            while True:
                main.camera.receive('incubator/v1/incubator-01/camera/availability',
                    {'camera_id': 'incubator-01-camera', 'status': 'online'})
                await asyncio.sleep(5)
        task = asyncio.create_task(heartbeat())
        try:
            yield
        finally:
            for active in [task, *pending]:
                active.cancel()
                with suppress(asyncio.CancelledError):
                    await active
            storage.cleanup()


main.app.router.lifespan_context = fixture_lifespan
print('Software camera fixture: loopback only, no physical camera or MQTT.', flush=True)
uvicorn.run(main.app, host='127.0.0.1', port=8000, log_level='warning')
