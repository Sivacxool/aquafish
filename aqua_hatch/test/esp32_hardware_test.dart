import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/esp32_repository.dart';
import 'package:aqua_hatch/core/models.dart';

class HardwareHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ip = String.fromEnvironment('DEVICE_IP');
  const token = String.fromEnvironment('DEVICE_TOKEN');
  test(
    'physical ESP32 HTTPS, trusted device certificate, fresh polling and command ACK',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final config = ConnectionConfig(
          demo: false,
          localEsp32: true,
          baseUrl: 'https://$ip',
        );
        final repo = Esp32Repository(config, token);
        final data = <Telemetry>[];
        final errors = <Object>[];
        final sub = repo.telemetry.listen(data.add, onError: errors.add);
        try {
          await repo.connect();
          final pollingDeadline = DateTime.now().add(
            const Duration(seconds: 12),
          );
          while (data.length < 2 && DateTime.now().isBefore(pollingDeadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          expect(data.length, greaterThanOrEqualTo(2));
          expect(data.last.firmwareVersion, '0.6.0-local');
          expect(data.last.isFresh(DateTime.now()), isTrue);
          expect(data.last.simulated, isFalse);
          expect(data.last.hardwareReady, isFalse);
          expect(data.last.temperature, isNull);
          expect(data.last.ph, isNull);
          final result = await repo.command('ping', {});
          expect(result.applied, isTrue);
          expect(result.message, contains('ESP32-S3'));
          final camera = await repo.cameraStatus();
          expect(camera.ready, isFalse);
          await expectLater(
            repo.command('set_output', {'output': 'pump', 'enabled': true}),
            throwsStateError,
          );
          expect(errors, isEmpty);
        } finally {
          await sub.cancel();
          await repo.dispose();
        }
        final wrong = Esp32Repository(config, 'wrong-token');
        try {
          await expectLater(wrong.connect(), throwsStateError);
        } finally {
          await wrong.dispose();
        }
      }, HardwareHttpOverrides());
    },
    skip: ip.isEmpty || token.isEmpty
        ? 'Requires physical board and private device definitions'
        : false,
  );
}
