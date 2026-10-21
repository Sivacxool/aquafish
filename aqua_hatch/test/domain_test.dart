import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/demo_repository.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Last Will offline status disables fresh data immediately', () {
    final now = DateTime.now();
    expect(Telemetry(at: now, deviceOnline: false).isFresh(now), isFalse);
  });
  test('stale and future timestamps cannot be treated as fresh', () {
    final now = DateTime(2026, 10, 12, 12);
    expect(
      Telemetry(at: now.subtract(const Duration(seconds: 16))).isFresh(now),
      isFalse,
    );
    expect(
      Telemetry(at: now.add(const Duration(minutes: 1))).isFresh(now),
      isFalse,
    );
    expect(Telemetry(at: now).isFresh(now), isTrue);
  });
  test('invalid settings and non-finite values are rejected', () {
    expect(
      const DeviceSettings(temperatureTarget: double.nan).validate(),
      isNotNull,
    );
    expect(
      const DeviceSettings(phMinimum: 9, phMaximum: 8).validate(),
      isNotNull,
    );
    expect(const DeviceSettings(flowTarget: -1).validate(), isNotNull);
    expect(const DeviceSettings().validate(), isNull);
  });
  test('remote connections require TLS and safe device identifiers', () {
    expect(
      const ConnectionConfig(
        demo: false,
        baseUrl: 'http://example.com',
      ).validate(),
      isNotNull,
    );
    expect(
      const ConnectionConfig(
        demo: false,
        baseUrl: 'https://example.com',
        deviceId: '../other',
      ).validate(),
      isNotNull,
    );
    expect(
      const ConnectionConfig(
        demo: false,
        baseUrl: 'https://example.com',
      ).validate(),
      isNull,
    );
  });
  test('missing sensors are null, not valid zeros', () {
    final t = Telemetry.fromJson({
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'mode': 'auto',
      'outputs': {},
      'water_level_ok': true,
    });
    expect(t.temperature, isNull);
    expect(t.ph, isNull);
    expect(t.alerts(const DeviceSettings()), contains('อ่านค่าอุณหภูมิไม่ได้'));
  });
  test('automatic mode rejects direct output commands', () async {
    final repo = DemoRepository(const DeviceSettings());
    addTearDown(repo.dispose);
    final result = await repo.command('set_output', {
      'output': 'heater',
      'enabled': true,
    });
    expect(result.applied, isFalse);
    expect(repo.snapshot().output('heater'), isFalse);
  });
  test('heater and cooler cannot run together', () async {
    final repo = DemoRepository(const DeviceSettings());
    addTearDown(repo.dispose);
    await repo.command('set_mode', {'mode': 'manual'});
    await repo.command('set_output', {'output': 'heater', 'enabled': true});
    final result = await repo.command('set_output', {
      'output': 'cooler',
      'enabled': true,
    });
    expect(result.applied, isFalse);
    expect(repo.snapshot().output('heater'), isTrue);
    expect(repo.snapshot().output('cooler'), isFalse);
  });
  test('stopping pump disables heat and tumbling', () async {
    final repo = DemoRepository(const DeviceSettings());
    addTearDown(repo.dispose);
    await repo.command('set_mode', {'mode': 'manual'});
    await repo.command('set_output', {'output': 'heater', 'enabled': true});
    await repo.command('set_output', {'output': 'pump', 'enabled': false});
    final t = repo.snapshot();
    expect(t.output('heater'), isFalse);
    expect(t.output('tumbler'), isFalse);
    expect(t.flow, 0);
  });
  test('low water forces outputs off and rejects unsafe activation', () async {
    final repo = DemoRepository(const DeviceSettings());
    addTearDown(repo.dispose);
    await repo.command('set_mode', {'mode': 'manual'});
    repo.scenario(ph: false, water: true);
    final result = await repo.command('set_output', {
      'output': 'pump',
      'enabled': true,
    });
    expect(result.applied, isFalse);
    expect(repo.snapshot().output('pump'), isFalse);
    expect(repo.snapshot().outputs.containsKey('aerator'), isFalse);
  });
  test('manual lease expiry returns to automatic control', () {
    final repo = DemoRepository(const DeviceSettings());
    addTearDown(repo.dispose);
    repo.mode = RunMode.manual;
    repo.manualUntil = DateTime.now().subtract(const Duration(seconds: 1));
    expect(repo.snapshot().mode, RunMode.automatic);
    expect(repo.manualUntil, isNull);
  });
  test(
    'count history persists original AI count separately from correction',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final r = CountRecord(
        id: '1',
        batchId: 'b',
        batchName: 'รอบ 1',
        source: 'image.jpg',
        method: 'AI + reviewed',
        count: 47,
        aiCount: 48,
        at: DateTime.now(),
        demo: false,
      );
      await store.saveCounts([r]);
      expect(store.counts.single.count, 47);
      expect(store.counts.single.aiCount, 48);
      expect(store.counts.single.demo, isFalse);
    },
  );
}
