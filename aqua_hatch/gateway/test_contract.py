"""Offline tests: do not open sockets or start the MQTT adapter."""
import os
os.environ['AUDIT_DB'] = ':memory:'
os.environ['SIMULATE_DEVICE'] = '1'
os.environ['DEV_ACCESS_TOKEN'] = 'offline-test-token-00000000'
from datetime import timedelta
import pytest
from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials
from pydantic import ValidationError
import main


def test_ph_settings_reject_bad_ranges():
    for low, high in [(-1, 8), (7, 15), (8, 7), (7, 7), (float('nan'), 8)]:
        with pytest.raises(ValidationError):
            main.Settings(ph_minimum=low, ph_maximum=high)
    assert main.Settings(ph_minimum=6.8, ph_maximum=8.2).ph_maximum == 8.2


def test_old_oxygen_config_is_rejected():
    with pytest.raises(ValidationError):
        main.Settings(oxygen_minimum=5)


def test_sensor_uncertainty_is_preserved():
    t = main.Telemetry(timestamp=main.utcnow())
    assert t.ph is None and t.water_level_ok is None and not t.ph_calibrated
    for ph in [-1, 15, float('nan')]:
        with pytest.raises(ValidationError):
            main.Telemetry(timestamp=main.utcnow(), ph=ph)


def test_auth_and_device_scope():
    for credential in [None, HTTPAuthorizationCredentials(scheme='Bearer', credentials='wrong')]:
        with pytest.raises(HTTPException) as error:
            main.require_auth(credential)
        assert error.value.status_code == 401
    main.require_auth(HTTPAuthorizationCredentials(scheme='Bearer', credentials=main.TOKEN))
    with pytest.raises(HTTPException):
        main.check_device('another-device')


def test_history_survives_memory_reset_and_deduplicates_minutes():
    main.DB.execute('DELETE FROM samples'); main.DB.commit()
    main.current = main.Telemetry(timestamp=main.utcnow(), ph=7.2, ph_calibrated=True, simulated=True)
    main.record_history(); main.record_history()
    main.current = None
    items = main.history(main.DEVICE_ID)['items']
    assert len(items) == 1 and items[0]['ph'] == 7.2 and items[0]['simulated'] is True


def test_history_excludes_stale_and_hardware_samples_in_simulation_mode():
    main.DB.execute('DELETE FROM samples'); main.DB.commit()
    main.current = main.Telemetry(timestamp=main.utcnow() - timedelta(seconds=20), ph=7, simulated=True)
    main.record_history()
    assert main.history(main.DEVICE_ID)['items'] == []
    main.current = main.Telemetry(timestamp=main.utcnow(), ph=7, simulated=False)
    main.record_history()
    assert main.history(main.DEVICE_ID)['items'] == []
    main.current = None
