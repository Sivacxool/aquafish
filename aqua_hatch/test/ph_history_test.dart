import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/features/history.dart';

void main() {
  test('pH is unitless, bounded, and requires calibration', () {
    for (final s in [
      const DeviceSettings(phMinimum: 9, phMaximum: 8),
      const DeviceSettings(phMinimum: -1),
      const DeviceSettings(phMaximum: 15),
      const DeviceSettings(phMaximum: double.nan),
    ]) {
      expect(s.validate(), isNotNull);
    }
    final now = DateTime.now();
    expect(
      Telemetry(at: now, ph: 7).alerts(const DeviceSettings()),
      contains('เซนเซอร์ pH ยังไม่ยืนยันการสอบเทียบ'),
    );
    for (final ph in [5.0, 10.0]) {
      expect(
        Telemetry(
          at: now,
          ph: ph,
          phCalibrated: true,
        ).alerts(const DeviceSettings()),
        contains('pH อยู่นอกช่วงที่ตั้งไว้'),
      );
    }
    final decoded = Telemetry.fromJson({
      'timestamp': now.toIso8601String(),
      'ph': 99,
    });
    expect(decoded.ph, isNull);
    expect(decoded.waterLevelOk, isNull);
  });
  test('persist history and acknowledgement with device isolation', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    const demo = ConnectionConfig();
    const real = ConnectionConfig(demo: false, baseUrl: 'https://example.com');
    final t = Telemetry(
      at: DateTime.now(),
      ph: 7.2,
      phCalibrated: true,
      simulated: true,
    );
    await store.saveHistory(demo, [t]);
    await store.saveEvents(demo, [
      DeviceEvent('pH สูง', warning: true).acknowledge(),
    ]);
    expect(store.history(demo).single.ph, 7.2);
    expect(store.history(real), isEmpty);
    expect(store.events(demo).single.acknowledged, isTrue);
    expect(store.events(real), isEmpty);
    expect(telemetryCsv(store.history(demo)), contains('ph_calibrated'));
    expect(telemetryCsv(store.history(demo)), contains('7.2,true'));
  });
  test(
    'connection label never presents simulation or stale data as a real online device',
    () {
      final now = DateTime.now();
      AppState state(Telemetry t) => AppState(
        connection: const ConnectionConfig(demo: false),
        settings: const DeviceSettings(),
        now: now,
        telemetry: t,
        connected: true,
      );
      expect(
        state(Telemetry(at: now, simulated: true)).connectionLabel,
        'เซิร์ฟเวอร์ส่งข้อมูลจำลอง',
      );
      expect(
        state(Telemetry(at: now, deviceOnline: false)).connectionLabel,
        'เครื่องออฟไลน์',
      );
      expect(
        state(Telemetry(at: now.subtract(const Duration(seconds: 20)))).fresh,
        isFalse,
      );
      expect(state(Telemetry(at: now)).connectionLabel, 'เชื่อมต่อเครื่องแล้ว');
    },
  );
}
