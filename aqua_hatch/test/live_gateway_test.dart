import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/live_repository.dart';

void main() {
  const token = String.fromEnvironment('TEST_GATEWAY_TOKEN');
  test(
    'real HTTP camera round trip returns a new private JPEG and no fake AI result',
    () async {
      final repository = LiveRepository(
        const ConnectionConfig(demo: false, baseUrl: 'http://127.0.0.1:8000'),
        token,
      );
      addTearDown(repository.dispose);
      final camera = await repository.cameraStatus();
      expect(camera.ready, isTrue);
      final first = await repository.capture(createId());
      final second = await repository.capture(createId());
      expect(first.id, isNot(second.id));
      expect(first.cameraId, 'incubator-01-camera');
      expect(first.bytes.take(2), [255, 216]);
      expect(first.bytes.length, greaterThan(1000));
      expect(second.bytes, isNot(orderedEquals(first.bytes)));
      await expectLater(repository.analyzeCapture(first.id), throwsStateError);
    },
    skip: token.isEmpty
        ? 'Optional integration: start loopback Gateway with a software camera fixture'
        : false,
  );
  test(
    'real HTTP and WebSocket adapter receives telemetry and device ACK',
    () async {
      final repository = LiveRepository(
        const ConnectionConfig(demo: false, baseUrl: 'http://127.0.0.1:8000'),
        token,
      );
      final readings = <Telemetry>[];
      final errors = <Object>[];
      final subscription = repository.telemetry.listen(
        readings.add,
        onError: errors.add,
      );
      addTearDown(() => subscription.cancel());
      addTearDown(repository.dispose);
      await repository.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(readings, isNotEmpty);
      expect(readings.last.simulated, isTrue);
      expect(readings.last.isFresh(DateTime.now()), isTrue);
      final mode = await repository.command('set_mode', {
        'mode': 'manual',
        'duration_seconds': 300,
      });
      expect(mode.applied, isTrue);
      final stop = await repository.command('set_output', {
        'output': 'pump',
        'enabled': false,
      });
      expect(stop.applied, isTrue);
      final unsafe = await repository.command('set_output', {
        'output': 'heater',
        'enabled': true,
      });
      expect(unsafe.applied, isFalse);
      final automatic = await repository.command('set_mode', {
        'mode': 'auto',
        'duration_seconds': 300,
      });
      expect(automatic.applied, isTrue);
      await expectLater(
        repository.analyze(Uint8List.fromList([1, 2, 3]), 'photo.jpg', false),
        throwsStateError,
      );
      expect(errors, isEmpty);
    },
    skip: token.isEmpty
        ? 'Optional integration: start Gateway and pass --dart-define=TEST_GATEWAY_TOKEN'
        : false,
  );
}
