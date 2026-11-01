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
