import os
os.environ["DEV_ACCESS_TOKEN"] = "test-token-that-is-never-for-production"
os.environ["SIMULATE_DEVICE"] = "1"
os.environ["AUDIT_DB"] = ":memory:"
from datetime import timedelta
from fastapi.testclient import TestClient
import main

HEADERS = {"Authorization": "Bearer " + main.TOKEN}
def make_command(id="test-command", action="set_mode", payload=None):
    return {"command_id": id, "action": action, "payload": payload or {"mode": "manual", "duration_seconds": 300}, "expires_at": (main.utcnow() + timedelta(seconds=10)).isoformat()}

def test_auth_and_device_isolation():
    with TestClient(main.app) as client:
        assert client.get("/api/v1/devices/incubator-01").status_code == 401
        assert client.get("/api/v1/devices/other", headers=HEADERS).status_code == 404
        data = client.get("/api/v1/devices/incubator-01", headers=HEADERS).json()
        assert data["telemetry"]["simulated"] is True

def test_expired_and_invalid_commands():
    with TestClient(main.app) as client:
        expired = make_command("expired")
        expired["expires_at"] = (main.utcnow() - timedelta(seconds=1)).isoformat()
        assert client.post("/api/v1/devices/incubator-01/commands", headers=HEADERS, json=expired).status_code == 422
        invalid = make_command("invalid", "set_output", {"output": "heater", "enabled": "false"})
        assert client.post("/api/v1/devices/incubator-01/commands", headers=HEADERS, json=invalid).status_code == 422

def test_ws_ack_and_duplicate_ids():
    with TestClient(main.app) as client, client.websocket_connect("/api/v1/devices/incubator-01/stream") as ws:
        ws.send_json({"type": "auth", "token": main.TOKEN})
        assert ws.receive_json()["type"] == "telemetry"
        cmd = make_command("dedupe")
        assert client.post("/api/v1/devices/incubator-01/commands", headers=HEADERS, json=cmd).status_code == 202
        message = ws.receive_json()
        while message["type"] != "ack":
            message = ws.receive_json()
        assert message["data"]["status"] == "applied"
        assert client.post("/api/v1/devices/incubator-01/commands", headers=HEADERS, json=cmd).status_code == 202
        conflicting = make_command("dedupe", "set_mode", {"mode": "auto"})
        assert client.post("/api/v1/devices/incubator-01/commands", headers=HEADERS, json=conflicting).status_code == 409

def test_ai_unavailable_never_returns_a_fabricated_count():
    with TestClient(main.app) as client:
        response = client.post("/api/v1/devices/incubator-01/counts/analyze", headers=HEADERS, files={"file": ("photo.jpg", b"not-a-model")}, data={"kind": "image"})
        assert response.status_code == 503
        assert "points" not in response.json()

def test_ws_rejects_unknown_origin():
    from starlette.websockets import WebSocketDisconnect
    import pytest
    with TestClient(main.app) as client:
        with pytest.raises(WebSocketDisconnect):
            with client.websocket_connect("/api/v1/devices/incubator-01/stream", headers={"origin": "https://untrusted.example"}):
                pass

def test_pump_stop_disables_heater():
    with TestClient(main.app) as client, client.websocket_connect("/api/v1/devices/incubator-01/stream") as ws:
        ws.send_json({"type": "auth", "token": main.TOKEN}); ws.receive_json()
        for cmd in [make_command("safety-mode"), make_command("safety-heat", "set_output", {"output": "heater", "enabled": True}), make_command("safety-stop", "set_output", {"output": "pump", "enabled": False})]:
            assert client.post("/api/v1/devices/incubator-01/commands", headers=HEADERS, json=cmd).status_code == 202
            message = ws.receive_json()
            while message["type"] != "ack":
                message = ws.receive_json()
            assert message["data"]["status"] == "applied"
        outputs = client.get("/api/v1/devices/incubator-01", headers=HEADERS).json()["telemetry"]["outputs"]
        assert outputs["heater"] is False and outputs["pump"] is False


def test_ph_contract_and_removed_output():
    with TestClient(main.app) as client:
        data = client.get('/api/v1/devices/incubator-01', headers=HEADERS).json()
        assert 0 <= data['telemetry']['ph'] <= 14
        assert data['telemetry']['ph_calibrated'] is True
        assert 'aerator' not in data['telemetry']['outputs']
        cmd = make_command('removed-output', 'set_output', {'output': 'aerator', 'enabled': True})
        assert client.post('/api/v1/devices/incubator-01/commands', headers=HEADERS, json=cmd).status_code == 422
        for low, high in [(8, 7), (-1, 7), (7, 15), (7, 7)]:
            cmd = make_command('invalid-ph', 'set_config', {'temperature_target': 28, 'ph_minimum': low, 'ph_maximum': high, 'flow_target': 2.4})
            assert client.post('/api/v1/devices/incubator-01/commands', headers=HEADERS, json=cmd).status_code == 422
        cmd = make_command('old-contract', 'set_config', {'temperature_target': 28, 'oxygen_minimum': 5, 'flow_target': 2.4})
        assert client.post('/api/v1/devices/incubator-01/commands', headers=HEADERS, json=cmd).status_code == 422


def test_history_is_authenticated_scoped_and_deduplicated():
    with TestClient(main.app) as client:
        url = '/api/v1/devices/incubator-01/history'
        assert client.get(url).status_code == 401
        assert client.get('/api/v1/devices/other/history', headers=HEADERS).status_code == 404
        assert client.get(url + '?limit=10081', headers=HEADERS).status_code == 422
        data = client.get(url, headers=HEADERS).json()
        assert data['retention_days'] == 7
        assert data['items']
        assert all(t['simulated'] for t in data['items'])
        minutes = [int(main.datetime.fromisoformat(t['timestamp'].replace('Z', '+00:00')).timestamp() // 60) for t in data['items']]
        assert len(minutes) == len(set(minutes))


def test_ph_full_config_round_trip_ack():
    with TestClient(main.app) as client, client.websocket_connect('/api/v1/devices/incubator-01/stream') as ws:
        ws.send_json({'type': 'auth', 'token': main.TOKEN}); ws.receive_json()
        cmd = make_command('valid-ph', 'set_config', {'temperature_target': 28, 'ph_minimum': 6.8, 'ph_maximum': 8.2, 'flow_target': 2.4})
        assert client.post('/api/v1/devices/incubator-01/commands', headers=HEADERS, json=cmd).status_code == 202
        result = ws.receive_json()
        while result['type'] != 'ack':
            result = ws.receive_json()
        assert result['data']['status'] == 'applied'
        config = client.get('/api/v1/devices/incubator-01', headers=HEADERS).json()['config']
        assert config['ph_minimum'] == 6.8 and config['ph_maximum'] == 8.2


def test_null_sensors_are_not_coerced_to_safe_values():
    reading = main.Telemetry(timestamp=main.utcnow())
    assert reading.ph is None
    assert reading.water_level_ok is None
    assert reading.ph_calibrated is False
