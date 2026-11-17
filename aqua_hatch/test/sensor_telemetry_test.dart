import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/features/history.dart';

void main() {
  final sample = <String, dynamic>{
    'timestamp': '2026-10-30T09:00:02Z',
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
      expect(restored.tankTemperature, 28.125);
      expect(restored.averageTemperature, 29.625);
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
        contains('28.125,29.5,31.25,29.625,3,29.5,28.125,31.25'),
      );
    },
  );
  test(
    'Beta2 averages the three locations and retains independent readings',
    () {
      final remote = Telemetry.fromJson({...sample, 'via_relay': true});
      expect(remote.averageTemperature, 29.625);
      expect(remote.tankTemperature, 28.125);
      expect(remote.temperaturePoints.map((p) => p.celsius), [
        29.5,
        28.125,
        31.25,
      ]);
      expect(remote.temperaturePointCount, 3);
      expect(remote.temperatureControlReady, isTrue);
      final missing = Telemetry.fromJson({...sample, 'ph_status': 'stale'});
      expect(missing.phTemperature, isNull);
      expect(missing.averageTemperature, 28.8125);
      expect(missing.temperaturePointCount, 2);
      expect(missing.temperatureControlReady, isFalse);
    },
  );
  test(
    'sample ages use monotonic board age rather than phone/NTP clock skew',
    () {
      for (final source in [
        'temperature_age_ms',
        'do_temperature_age_ms',
        'ph_temperature_age_ms',
      ]) {
        final fresh = Telemetry.fromJson({...sample, source: 10000});
        expect(fresh.temperaturePointCount, 3);
        final stale = Telemetry.fromJson({...sample, source: 10001});
        expect(stale.temperaturePointCount, 2);
        expect(stale.temperatureControlReady, isFalse);
        expect(Telemetry.fromJson(stale.toJson()).temperaturePointCount, 2);
      }
    },
  );
  test(
    'a failed temperature cannot enter the mean even if another status is ok',
    () {
      for (final status in ['timeout', 'stale', 'crc_error', 'invalid_value']) {
        final t = Telemetry.fromJson({
          ...sample,
          'ph_temperature_status': status,
        });
        expect(t.temperaturePoints.last.celsius, isNull);
        expect(t.averageTemperature, 28.8125);
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
        expect(t.temperaturePoints[1].celsius, isNull);
        expect(t.averageTemperature, 30.375);
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
