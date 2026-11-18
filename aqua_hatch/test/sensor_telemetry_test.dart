import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/features/history.dart';

void main() {
  final sample = <String, dynamic>{
    'timestamp': '2026-10-30T09:00:02Z',
    'temperature_control_source': 'two_point_average',
    'temperature_c': 28.125,
    'temperature_status': 'ok',
    'temperature_sampled_at': '2026-10-30T09:00:01Z',
    'do_mg_l': 6.78,
    'do_temperature_c': 29.5,
    'ph_temperature_c': 31.25,
    'ph_status': 'ok',
    'do_status': 'ok',
    'do_sampled_at': '2026-10-30T09:00:00Z',
    'simulated': false,
    'hardware_ready': false,
  };
  test(
    'real sensor values survive history persistence and CSV export',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      const device = ConnectionConfig(demo: false, localEsp32: true);
      await store.saveHistory(device, [Telemetry.fromJson(sample)]);
      final restored = store.history(device).single;
      expect(restored.temperature, 28.125);
      expect(restored.doTemperature, 29.5);
      expect(restored.phTemperature, 31.25);
      expect(restored.reservoirTemperaturePoint.celsius, 28.125);
      expect(restored.averageTemperature, 28.8125);
      expect(restored.dissolvedOxygen, 6.78);
      expect(
        restored.temperatureSampledAt?.toUtc().toIso8601String(),
        '2026-10-30T09:00:01.000Z',
      );
      expect(
        restored.dissolvedOxygenSampledAt?.toUtc().toIso8601String(),
        '2026-10-30T09:00:00.000Z',
      );
      expect(restored.simulated, false);
      expect(restored.hardwareReady, false);
      expect(telemetryCsv([restored]), contains('do_mg_l'));
      expect(telemetryCsv([restored]), contains('6.78,ok,ok'));
      expect(
        telemetryCsv([restored]),
        contains('29.5,31.25,28.8125,2,29.5,28.125,ok,ok'),
      );
    },
  );
  test(
    'Beta3 uses only DO and DS18B20 even if an old pH temperature is present',
    () {
      final remote = Telemetry.fromJson({...sample, 'via_relay': true});
      expect(remote.averageTemperature, 28.8125);
      expect(remote.temperaturePoints.map((p) => p.celsius), [29.5, 28.125]);
      expect(remote.temperaturePointCount, 2);
      expect(remote.temperatureControlReady, isTrue);
      final failedPh = Telemetry.fromJson({...sample, 'ph_status': 'timeout'});
      expect(failedPh.averageTemperature, 28.8125);
      expect(failedPh.temperatureControlReady, isTrue);
      final legacy = Telemetry.fromJson({
        ...sample,
        'firmware_version': '0.25.0-ett32ue.beta2',
        'temperature_control_source': 'three_point_average',
      });
      expect(legacy.needsTemperatureFirmwareUpdate, isTrue);
      expect(legacy.toJson()['temperature_control_source'], isNull);
      expect(telemetryCsv([legacy]), contains('29.5,31.25,,,,,ok,ok'));
    },
  );
  test(
    'sample ages use monotonic board age rather than phone/NTP clock skew',
    () {
      for (final source in ['temperature_age_ms', 'do_temperature_age_ms']) {
        final fresh = Telemetry.fromJson({...sample, source: 10000});
        expect(fresh.temperaturePointCount, 2);
        final stale = Telemetry.fromJson({...sample, source: 10001});
        expect(stale.temperaturePointCount, 1);
        expect(stale.temperatureControlReady, isFalse);
        expect(Telemetry.fromJson(stale.toJson()).temperaturePointCount, 1);
      }
    },
  );
  test(
    'a failed temperature cannot enter the mean even if another status is ok',
    () {
      for (final status in ['timeout', 'stale', 'crc_error', 'invalid_value']) {
        final t = Telemetry.fromJson({
          ...sample,
          'ds18b20_temperature_status': status,
          'temperature_age_ms': 100000,
        });
        expect(t.temperaturePoints.last.celsius, isNull);
        expect(t.temperaturePoints.last.readingStatus, status);
        expect(t.averageTemperature, 29.5);
      }
      for (final value in [
        null,
        -127,
        85,
        double.nan,
        double.infinity,
        '28.5',
      ]) {
        final t = Telemetry.fromJson({...sample, 'temperature_c': value});
        expect(t.reservoirTemperaturePoint.celsius, isNull);
        expect(t.averageTemperature, 29.5);
      }
      final empty = Telemetry.fromJson({
        ...sample,
        'temperature_c': null,
        'do_temperature_c': null,
        'ph_temperature_c': null,
      });
      expect(empty.averageTemperature, isNull);
      expect(empty.temperaturePointCount, 0);
      expect(
        Telemetry.fromJson({
          ...sample,
          'temperature_c': 0,
        }).temperaturePoints[1].celsius,
        0,
      );
    },
  );
  test('errors and stale sensors never display a previous numeric reading', () {
    for (final status in ['timeout', 'stale', 'crc_error', 'not_configured']) {
      final t = Telemetry.fromJson({
        ...sample,
        'do_status': status,
        'temperature_status': status,
      });
      expect(t.temperature, isNull);
      expect(t.dissolvedOxygen, isNull);
    }
    for (final invalid in [null, -1, double.infinity, '6.78']) {
      expect(
        Telemetry.fromJson({...sample, 'do_mg_l': invalid}).dissolvedOxygen,
        isNull,
      );
    }
    expect(Telemetry.fromJson({...sample, 'do_mg_l': 0}).dissolvedOxygen, 0);
  });
}
