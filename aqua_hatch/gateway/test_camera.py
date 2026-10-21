"""Capture lifecycle tests use real JPEG bytes and the same HTTP router as hardware."""
import hashlib
import io
import json
import sqlite3
import os
from datetime import timedelta

import pytest
from fastapi import FastAPI, Header, HTTPException
from fastapi.testclient import TestClient
from PIL import Image

from camera_service import CameraService

os.environ.setdefault('DEV_ACCESS_TOKEN', 'test-token-that-is-never-for-production')
os.environ.setdefault('SIMULATE_DEVICE', '1')
os.environ.setdefault('AUDIT_DB', ':memory:')

APP_AUTH = {"Authorization": "Bearer app-test-token"}
BASE = "/api/v1/devices/incubator-01/camera"
TOPIC = "incubator/v1/incubator-01/camera/"


@pytest.fixture
def rig(tmp_path):
    db = sqlite3.connect(":memory:", check_same_thread=False)
    published = []

    def auth(authorization: str = Header(default="")):
        if authorization != APP_AUTH["Authorization"]:
            raise HTTPException(401)

    camera = CameraService(db, tmp_path, "incubator-01", "camera-01",
                           "https://cloud.example", published.append, auth)
    camera.receive(TOPIC + "availability", {"camera_id": "camera-01", "status": "online"})
    app = FastAPI()
    app.include_router(camera.router)
    with TestClient(app) as client:
        yield camera, client, published
    db.close()


def jpeg(color="blue"):
    result = io.BytesIO()
    Image.new("RGB", (40, 30), color).save(result, "JPEG")
    return result.getvalue()


def start(client, capture_id="capture-1"):
    return client.post(BASE + "/captures", headers=APP_AUTH, json={"capture_id": capture_id})


def upload(client, payload, data=None):
    return client.post(BASE + "/captures/" + payload["capture_id"] + "/image",
                       headers={"Authorization": "Bearer " + payload["upload_token"], "Content-Type": "image/jpeg"},
                       content=jpeg() if data is None else data)


def test_remote_capture_round_trip_and_idempotency(rig):
    camera, client, published = rig
    result = start(client)
    assert result.status_code == 202
    assert result.json()["status"] == "queued"
    assert "upload_token" not in result.text
    assert len(published) == 1
    command = published[0]
    assert command["action"] == "capture"
    assert command["camera_id"] == "camera-01"
    assert command["upload_url"] == "https://cloud.example" + BASE + "/captures/capture-1/image"
    assert start(client).status_code == 202
    assert len(published) == 1  # An HTTP retry cannot take another photo.
    assert start(client, "other-job").status_code == 409
    url = BASE + "/captures/capture-1/image"
    assert client.get(url, headers=APP_AUTH).status_code == 409
    assert upload(client, command).json()["status"] == "captured"
    assert upload(client, command).status_code == 200
    assert upload(client, command, jpeg("red")).status_code == 409
    assert client.get(url).status_code == 401
    response = client.get(url, headers=APP_AUTH)
    assert response.content == jpeg()
    assert response.headers["content-type"] == "image/jpeg"
    assert response.headers["cache-control"] == "no-store"
    job = client.get(BASE + "/captures/capture-1", headers=APP_AUTH).json()
    assert job["received_at"] is not None
    assert "token" not in json.dumps(job)
    assert camera.row("capture-1")["token_hash"] == hashlib.sha256(command["upload_token"].encode()).hexdigest()


def test_camera_auth_device_scope_and_upload_token(rig):
    _, client, published = rig
    assert client.get(BASE).status_code == 401
    assert client.post(BASE + "/captures", json={"capture_id": "x"}).status_code == 401
    assert client.get(BASE.replace("incubator-01", "other"), headers=APP_AUTH).status_code == 404
    assert start(client, "bad/../id").status_code == 422
    start(client)
    url = BASE + "/captures/capture-1/image"
    assert client.post(url, headers=APP_AUTH, content=jpeg()).status_code == 401
    assert upload(client, published[0]).status_code == 200
    # A token from one job cannot upload to a later job.
    start(client, "capture-2")
    assert client.post(BASE + "/captures/capture-2/image",
                       headers={"Authorization": "Bearer " + published[0]["upload_token"], "Content-Type": "image/jpeg"},
                       content=jpeg()).status_code == 401


def test_camera_liveness_and_timeout(rig):
    camera, client, published = rig
    camera.last_seen -= timedelta(seconds=46)
    assert client.get(BASE, headers=APP_AUTH).json()["online"] is False
    assert start(client).status_code == 409
    camera.receive(TOPIC + "availability", {"camera_id": "wrong-camera", "status": "online"})
    assert start(client).status_code == 409
    camera.receive(TOPIC + "availability", {"camera_id": "camera-01", "status": "online"})
    assert start(client).status_code == 202
    camera.db.execute("UPDATE captures SET expires=?", ((camera.now() - timedelta(seconds=1)).isoformat(),))
    camera.db.commit()
    assert upload(client, published[0]).status_code == 410
    job = client.get(BASE + "/captures/capture-1", headers=APP_AUTH).json()
    assert job["status"] == "expired"
    assert client.get(BASE + "/captures/capture-1/image", headers=APP_AUTH).status_code == 409


def test_upload_validation_and_camera_failure(rig):
    camera, client, published = rig
    start(client)
    command = published[0]
    assert upload(client, command, b"not a JPEG").status_code == 422
    assert upload(client, command, jpeg()[:-24]).status_code == 422
    camera.max_bytes = 8
    assert upload(client, command).status_code == 413
    camera.max_bytes = 8 * 1024 * 1024
    camera.receive(TOPIC + "result", {"camera_id": "camera-01", "capture_id": "capture-1",
                                    "status": "failed", "message": "camera sensor missing"})
    assert upload(client, command).status_code == 409
    assert client.get(BASE + "/captures/capture-1", headers=APP_AUTH).json()["status"] == "failed"


def test_missing_https_and_broker_failures_do_not_return_a_photo(rig):
    camera, client, _ = rig
    camera.public_url = "http://remote.example"
    assert start(client).status_code == 503
    camera.public_url = "https://cloud.example"

    def unavailable(_):
        raise ConnectionError("broker down")

    camera.publish = unavailable
    assert start(client).status_code == 503
    assert camera.job("capture-1")["status"] == "failed"


def test_integrated_router_rejects_retained_online_and_uses_saved_photo(tmp_path, monkeypatch):
    # Import here so test_gateway's environment setup applies consistently.
    import asyncio
    import main
    main.camera.available = False
    raw = json.dumps({"camera_id": main.camera.camera_id, "status": "online"})
    topic = "incubator/v1/" + main.DEVICE_ID + "/camera/availability"
    asyncio.run(main.receive_mqtt(topic, raw, retained=True))
    assert main.camera.status()["online"] is False
    asyncio.run(main.receive_mqtt(topic, raw))
    assert main.camera.status()["online"] is True
    asyncio.run(main.receive_mqtt(topic, "[]"))  # malformed payload ignored
    monkeypatch.setattr(main.camera, "directory", tmp_path)
    monkeypatch.setattr(main.camera, "public_url", "https://cloud.example")
    published = []
    monkeypatch.setattr(main.camera, "publish", published.append)
    monkeypatch.setenv("LARVAE_MODEL_PATH", "")
    headers = {"Authorization": "Bearer " + main.TOKEN}
    with TestClient(main.app) as client:
        url = "/api/v1/devices/" + main.DEVICE_ID + "/camera/captures"
        assert client.post(url, headers=headers, json={"capture_id": "integrated-photo"}).status_code == 202
        payload = published[0]
        response = client.post(url + "/integrated-photo/image", content=jpeg(),
            headers={"Authorization": "Bearer " + payload["upload_token"], "Content-Type": "image/jpeg"})
        assert response.status_code == 200
        result = client.post(url + "/integrated-photo/analyze", headers=headers)
        assert result.status_code == 503
        assert "points" not in result.json()
    main.DB.execute("DELETE FROM captures WHERE id='integrated-photo'")
    main.DB.commit()
    main.camera.available = False
