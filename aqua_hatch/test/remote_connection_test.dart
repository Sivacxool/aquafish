import 'dart:convert';

import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/esp32_repository.dart';
import 'package:aqua_hatch/core/pairing.dart';
import 'package:aqua_hatch/core/relay_origin.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'esp32_repository_test.dart' show jsonResponse, snapshot;
import 'pairing_fixture.dart';

const origin = 'https://aquahatch-relay.example.workers.dev';

void main() {
  test('relay URL is a dedicated HTTPS Workers origin', () {
    expect(parseRelayOrigin('$origin/')?.toString(), origin);
    for (final invalid in [
      'http://aquahatch-relay.example.workers.dev',
      'https://a.b.workers.dev.evil.test',
      '$origin/path',
      '$origin?token=abc',
      'https://user@aquahatch-relay.example.workers.dev',
      'https://127.0.0.1',
    ]) {
      expect(parseRelayOrigin(invalid), isNull);
    }
  });

  test(
    'paired sensor falls back to relay and resumes LAN without pairing again',
    () async {
      final pairing = PairingBundle.parse(jsonEncode(pairingFixture()));
      final config = pairing
          .config('https://192.168.1.50')
          .withRelayOrigin(origin);
      var lan = false, cloudReads = 0, postRequests = 0;
      final repo = Esp32Repository(
        config,
        pairing.token,
        pollInterval: const Duration(hours: 1),
        client: MockClient((request) async {
          if (request.method == 'POST') postRequests++;
          if (!lan) throw http.ClientException('no route to LAN');
          return jsonResponse(snapshot(device: config.deviceId));
        }),
        relayClient: MockClient((request) async {
          cloudReads++;
          expect(request.method, 'GET');
          expect(request.url.host, Uri.parse(origin).host);
          expect(request.followRedirects, isFalse);
          final writer = sha256.convert(
            utf8.encode('aquahatch relay write v1:${pairing.token}'),
          );
          final reader = sha256.convert(
            utf8.encode('aquahatch relay read v1:$writer'),
          );
          final room = sha256.convert(
            utf8.encode('aquahatch relay room v1:$reader'),
          );
          expect(request.headers['Authorization'], 'Bearer $reader');
          expect(request.url.path, '/v1/readings/$room');
          return jsonResponse({
            'age_ms': 6000,
            'snapshot': snapshot(device: config.deviceId),
          });
        }),
      );
      addTearDown(repo.dispose);
      final first = repo.telemetry.first;
      await repo.connect();
      final remote = await first;
      expect(remote.viaRelay, isTrue);
      expect(remote.hardwareReady, isFalse);
      expect(
        DateTime.now().difference(remote.at).inSeconds,
        greaterThanOrEqualTo(5),
      );
      await expectLater(
        repo.command('ping', {}),
        throwsA(isA<http.ClientException>()),
      );
      expect(postRequests, 0);
      expect(cloudReads, 1);

      lan = true;
      final next = repo.telemetry.first;
      await repo.pollNow(preferLan: true);
      expect((await next).viaRelay, isFalse);
      expect(cloudReads, 1);
    },
  );

  test(
    'camera captures through one remote job when local route is unavailable',
    () async {
      final pairing = PairingBundle.parse(
        jsonEncode(pairingFixture(kind: 'camera')),
      );
      final config = pairing
          .config('https://192.168.1.51')
          .withRelayOrigin(origin);
      final bytes = [255, 216, 31, 42, 255, 217];
      const id = 'remote-capture-test';
      var sent = 0;
      final identity = {
        'backend': 'esp32-camera',
        'protocol_version': 1,
        'device_id': config.deviceId,
        'camera_id': config.deviceId,
        'server_time_unix': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
      final camera = DirectCameraClient(
        config,
        pairing.token,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          throw http.ClientException('no route to camera LAN');
        }),
        relayClient: MockClient((request) async {
          final path = request.url.path;
          expect(
            request.headers['Authorization'],
            isNot('Bearer ${pairing.token}'),
          );
          if (request.method == 'POST') {
            sent++;
            expect(jsonDecode(request.body)['capture_id'], id);
            return jsonResponse({
              ...identity,
              'capture_id': id,
              'status': 'queued',
            }, 202);
          }
          if (path.endsWith('/image')) {
            return http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          if (path.endsWith('/$id')) {
            return jsonResponse({
              ...identity,
              'capture_id': id,
              'status': 'captured',
              'bytes': bytes.length,
              'sha256': sha256.convert(bytes).toString(),
              'received_at': DateTime.now().toUtc().toIso8601String(),
              'width': 2048,
              'height': 1536,
            });
          }
          return jsonResponse({
            ...identity,
            'configured': true,
            'online': true,
            'sensor': 'OV3660',
            'default_capture_resolution': '3mp',
          });
        }),
      );
      addTearDown(camera.close);
      final photo = await camera.capture(id);
      expect(photo.bytes, bytes);
      expect(photo.cameraId, config.deviceId);
      expect(sent, 1);
    },
  );
}
