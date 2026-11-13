import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/esp32_repository.dart';
import 'package:aqua_hatch/core/models.dart';

const config = ConnectionConfig(
  demo: false,
  localEsp32: true,
  baseUrl: 'https://192.168.1.50',
);
Map<String, dynamic> snapshot({String device = 'incubator-01'}) => {
  'device_id': device,
  'backend': 'esp32-local',
  'protocol_version': 1,
  'capabilities': {'hardware_control': false},
  'config': const DeviceSettings().toJson(),
  'telemetry': {
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'temperature_c': null,
    'ph': null,
    'flow_l_min': null,
    'water_level_ok': null,
    'device_online': true,
    'simulated': false,
    'hardware_ready': false,
    'firmware_version': '0.5.0-local',
    'outputs': {},
  },
};
http.Response jsonResponse(Object value, [int code = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(value)), code);

void main() {
  test('local mode only accepts HTTPS private IPv4 on standard port', () {
    expect(config.validate(), isNull);
    for (final url in [
      'http://192.168.1.50',
      'https://example.com',
      'https://8.8.8.8',
      'https://127.0.0.1',
      'https://192.168.1.50:444',
      'https://192.168.1.50/path',
      'https://user@192.168.1.50',
      'https://192.168.1.50?q=1',
      'https://192.168.001.50',
    ]) {
      expect(
        ConnectionConfig(
          demo: false,
          localEsp32: true,
          baseUrl: url,
        ).validate(),
        isNotNull,
        reason: url,
      );
    }
    expect(ConnectionConfig.fromJson(config.toJson()).localEsp32, isTrue);
    expect(ConnectionConfig.fromJson({'demo': false}).localEsp32, isFalse);
    expect(
      const ConnectionConfig(
        demo: false,
        baseUrl: 'http://192.168.1.50',
      ).validate(),
      isNotNull,
    );
  });
  test(
    'board telemetry preserves missing sensors and disables physical control',
    () async {
      final repo = Esp32Repository(
        config,
        'secret',
        client: MockClient((request) async {
          expect(request.url.host, 'aquahatch-117c.local');
          expect(request.url.scheme, 'https');
          expect(request.headers['Authorization'], 'Bearer secret');
          expect(request.headers['X-AquaHatch-Time'], isNotEmpty);
          expect(request.followRedirects, isFalse);
          return jsonResponse(snapshot());
        }),
      );
      addTearDown(repo.dispose);
      final first = repo.telemetry.first;
      await repo.connect();
      final t = await first;
      expect(t.temperature, isNull);
      expect(t.ph, isNull);
      expect(t.waterLevelOk, isNull);
      expect(t.simulated, isFalse);
      expect(t.hardwareReady, isFalse);
      expect(t.deviceOnline, isTrue);
      expect(t.isFresh(DateTime.now()), isTrue);
    },
  );

  test('ETT command acknowledgement wins over an older LAN poll', () async {
    Map<String, dynamic> relaySnapshot({
      bool manual = false,
      int remaining = 0,
      bool capable = true,
    }) {
      final data = snapshot();
      data['capabilities'] = {
        'hardware_control': capable,
        'ett_manual_control': capable,
        'pump_fill': true,
      };
      (data['telemetry'] as Map<String, Object?>).addAll({
        'mode': manual ? 'manual' : 'auto',
        'hardware_ready': true,
        'fill': {
          'armed': true,
          'requested': true,
          'running': true,
          'timed_out': false,
          'limit_seconds': capable ? null : 60,
        },
        'ett_control': {
          'io_ready': true,
          'manual_remaining_ms': remaining,
          'fan_commanded_on': true,
        },
      });
      return data;
    }

    final oldPoll = Completer<http.Response>();
    final oldPollStarted = Completer<void>();
    var getCount = 0;
    var capable = true;
    final repo = Esp32Repository(
      config,
      'secret',
      pollInterval: const Duration(days: 1),
      client: MockClient((request) async {
        if (request.method == 'GET') {
          if (++getCount == 2) {
            oldPollStarted.complete();
            return oldPoll.future;
          }
          return jsonResponse(relaySnapshot(capable: capable));
        }
        final body = jsonDecode(request.body) as Map;
        expect(body['action'], 'set_mode');
        expect(body['payload'], {'mode': 'manual', 'duration_seconds': 300});
        return jsonResponse({
          'command_id': body['command_id'],
          'status': 'applied',
          'snapshot': relaySnapshot(manual: true, remaining: 299000),
        });
      }),
    );
    addTearDown(repo.dispose);
    final readings = <Telemetry>[];
    final subscription = repo.telemetry.listen(readings.add);
    addTearDown(subscription.cancel);
    await repo.connect();
    final poll = repo.pollNow();
    await oldPollStarted.future;
    final manual = repo.telemetry.firstWhere((t) => t.mode == RunMode.manual);
    final result = await repo.command('set_mode', {
      'mode': 'manual',
      'duration_seconds': 300,
    });
    expect(result.applied, isTrue);
    final reading = await manual;
    expect(reading.ettControl?.fanCommandedOn, isTrue);
    expect(reading.hardwareReady, isTrue);
    expect(reading.fill?.running, isTrue);
    expect(reading.fill?.limitSeconds, isNull);
    expect(Telemetry.fromJson(reading.toJson()).fill?.running, isTrue);
    expect(reading.manualUntil!.difference(reading.at).inSeconds, 299);
    oldPoll.complete(jsonResponse(relaySnapshot()));
    await poll;
    expect(readings.last.mode, RunMode.manual);

    capable = false;
    final legacy = repo.telemetry.first;
    await repo.pollNow();
    final oldReading = await legacy;
    expect(oldReading.ettControl, isNull);
    expect(oldReading.fill?.limitSeconds, 60);
    expect(readings.last.hardwareReady, isFalse);
  });

  test('commands require matching ACK and carry expiry', () async {
    var wrong = false;
    final repo = Esp32Repository(
      config,
      'secret',
      client: MockClient((request) async {
        if (request.method == 'GET') return jsonResponse(snapshot());
        final body = jsonDecode(request.body) as Map;
        expect(body['action'], 'ping');
        expect(
          body['expires_at_unix'],
          greaterThan(DateTime.now().millisecondsSinceEpoch ~/ 1000),
        );
        return jsonResponse({
          'command_id': wrong ? 'wrong' : body['command_id'],
          'status': 'applied',
          'message': 'ตอบแล้ว',
        });
      }),
    );
    addTearDown(repo.dispose);
    expect((await repo.command('ping', {})).applied, isTrue);
    wrong = true;
    await expectLater(repo.command('ping', {}), throwsStateError);
  });
  test(
    'phone clock skew does not expire commands or mark a fresh poll stale',
    () async {
      for (final offset in [-120, 120]) {
        final boardTime = DateTime.now().toUtc().add(Duration(seconds: offset));
        final repo = Esp32Repository(
          config,
          'secret',
          client: MockClient((request) async {
            if (request.method == 'GET') {
              final data = snapshot();
              (data['telemetry'] as Map)['timestamp'] = boardTime
                  .toIso8601String();
              return jsonResponse(data);
            }
            final body = jsonDecode(request.body) as Map;
            expect(
              body['expires_at_unix'],
              boardTime.millisecondsSinceEpoch ~/ 1000 + 10,
            );
            return jsonResponse({
              'command_id': body['command_id'],
              'status': 'applied',
            });
          }),
        );
        final first = repo.telemetry.first;
        await repo.connect();
        expect((await first).isFresh(DateTime.now()), isTrue);
        expect((await repo.command('ping', {})).applied, isTrue);
        await repo.dispose();
      }
    },
  );
  test(
    'wrong board, unauthorized and malformed responses fail closed',
    () async {
      for (final response in [
        jsonResponse(snapshot(device: 'other')),
        jsonResponse({'detail': 'รหัสไม่ถูกต้อง'}, 401),
        http.Response('broken', 200),
        jsonResponse({...snapshot(), 'backend': 'unexpected'}),
      ]) {
        final repo = Esp32Repository(
          config,
          'secret',
          client: MockClient((_) async => response),
        );
        await expectLater(repo.connect(), throwsStateError);
        await repo.dispose();
      }
    },
  );
  test(
    'initial connection failure recovers without reopening the app',
    () async {
      var offline = true;
      var requests = 0;
      final repo = Esp32Repository(
        config,
        'secret',
        pollInterval: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          requests++;
          if (offline) throw http.ClientException('board still joining Wi-Fi');
          return jsonResponse(snapshot());
        }),
      );
      final recovered = repo.telemetry.first;
      await expectLater(repo.connect(), throwsA(isA<http.ClientException>()));
      offline = false;
      expect(
        (await recovered.timeout(const Duration(seconds: 2))).deviceOnline,
        isTrue,
      );
      await repo.dispose();
      final stoppedAt = requests;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(requests, stoppedAt);
    },
  );
  test(
    'polling reports disconnect and recovers with fresh board data',
    () async {
      var offline = false;
      final repo = Esp32Repository(
        config,
        'secret',
        pollInterval: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          if (offline) throw http.ClientException('offline');
          return jsonResponse(snapshot());
        }),
      );
      final errors = <Object>[];
      final readings = <Telemetry>[];
      final sub = repo.telemetry.listen(readings.add, onError: errors.add);
      await repo.connect();
      offline = true;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(errors, isNotEmpty);
      final count = readings.length;
      offline = false;
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(readings.length, greaterThan(count));
      await sub.cancel();
      await repo.dispose();
    },
  );
}
