import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/paired_camera.dart';

const config = ConnectionConfig(
  demo: false,
  localEsp32: true,
  baseUrl: 'https://192.168.1.51',
  deviceId: cameraDeviceId,
);
final jpeg = [0xff, 0xd8, 1, 2, 3, 0xff, 0xd9];
Map<String, dynamic> status() => {
  'backend': 'esp32-camera',
  'device_id': cameraDeviceId,
  'camera_id': cameraDeviceId,
  'configured': true,
  'online': true,
  'message': 'ready',
  'server_time_unix': 1800000000,
};
Map<String, dynamic> job(String id) => {
  ...status(),
  'capture_id': id,
  'status': 'captured',
  'received_at': '2026-10-27T01:00:00Z',
  'bytes': jpeg.length,
  'sha256': sha256.convert(jpeg).toString(),
};
http.Response json(Object data, [int code = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), code);
void main() {
  test(
    'capture selects native resolution and focus support for each sensor',
    () async {
      for (final spec in [
        ('OV3660', '3mp', false, 2048, 1536),
        ('OV5640', '5mp', true, 2560, 1920),
        ('OV2640', 'uxga', false, 1600, 1200),
      ]) {
        final camera = DirectCameraClient(
          config,
          'camera-secret',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/image')) {
              return http.Response.bytes(
                jpeg,
                200,
                headers: {'content-type': 'image/jpeg'},
              );
            }
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map;
              expect(body['resolution'], spec.$2);
              expect(body['autofocus'], spec.$3);
              expect(body['flash'], isTrue);
              return json({
                ...job(body['capture_id'] as String),
                'sensor': spec.$1,
                'width': spec.$4,
                'height': spec.$5,
                'flash_used': true,
              }, 202);
            }
            return json({
              ...status(),
              'sensor': spec.$1,
              'default_capture_width': spec.$4,
              'default_capture_height': spec.$5,
              'autofocus_supported': spec.$3,
            });
          }),
        );
        addTearDown(camera.close);
        final photo = await camera.capture('native-sensor-photo');
        expect(photo.sensor, spec.$1);
        expect(photo.width, spec.$4);
        expect(photo.height, spec.$5);
        expect(photo.flashUsed, isTrue);
      }
    },
  );

  test(
    'reads reuse TLS and retry a transient transport failure once',
    () async {
      var attempts = 0;
      final camera = DirectCameraClient(
        config,
        'secret',
        client: MockClient((request) async {
          expect(request.persistentConnection, isTrue);
          attempts++;
          if (attempts == 1) throw http.ClientException('connection lost');
          return json(status());
        }),
      );
      addTearDown(camera.close);
      expect((await camera.status()).ready, isTrue);
      expect(attempts, 2);
    },
  );

  test(
    'transport retry is bounded and does not hide a persistent outage',
    () async {
      var attempts = 0;
      final camera = DirectCameraClient(
        config,
        'secret',
        client: MockClient((_) async {
          attempts++;
          throw TimeoutException('offline');
        }),
      );
      addTearDown(camera.close);
      await expectLater(camera.status(), throwsA(isA<TimeoutException>()));
      expect(attempts, 2);
    },
  );

  test(
    'status polling waits for the previous response body and recovers after an error',
    () async {
      final started = <int>[];
      final finishFirst = Completer<http.Response>();
      final camera = DirectCameraClient(
        config,
        'secret',
        client: MockClient((request) async {
          started.add(started.length + 1);
          if (started.length == 1) return finishFirst.future;
          if (started.length == 2) return json({'detail': 'denied'}, 401);
          return json(status());
        }),
      );
      addTearDown(camera.close);
      final first = camera.status();
      final second = camera.status();
      final secondError = expectLater(second, throwsStateError);
      final third = camera.status();
      await Future<void>.delayed(Duration.zero);
      expect(started, [1]);
      finishFirst.complete(json(status()));
      expect((await first).ready, isTrue);
      await secondError;
      expect((await third).ready, isTrue);
      expect(started, [1, 2, 3]);
    },
  );

  test(
    'camera uses separate identity, validates JPEG and expires commands using board clock',
    () async {
      final paths = <String>[];
      final camera = DirectCameraClient(
        config,
        'camera-secret',
        client: MockClient((request) async {
          paths.add(request.url.path);
          expect(request.url.host, cameraTlsHostname);
          expect(request.headers['Authorization'], 'Bearer camera-secret');
          expect(request.followRedirects, isFalse);
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              jpeg,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          if (request.method == 'POST') {
            final data = jsonDecode(request.body) as Map;
            expect(data['expires_at_unix'], 1800000030);
            expect(data['flash'], isTrue);
            expect(data['resolution'], '5mp');
            expect(data['jpeg_quality'], 10);
            return json(job(data['capture_id'] as String), 202);
          }
          return json(status());
        }),
      );
      addTearDown(camera.close);
      final photo = await camera.capture('capture-one');
      expect(photo.bytes, jpeg);
      expect(photo.cameraId, cameraDeviceId);
      expect(paths.last, endsWith('/capture-one/image'));
    },
  );
  test(
    'lost POST acknowledgement queries same capture ID without another exposure',
    () async {
      var posts = 0;
      final camera = DirectCameraClient(
        config,
        'secret',
        client: MockClient((request) async {
          if (request.method == 'POST') {
            posts++;
            throw TimeoutException('ack lost');
          }
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              jpeg,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return json(
            request.url.path.endsWith('/captures/one') ? job('one') : status(),
          );
        }),
      );
      addTearDown(camera.close);
      expect((await camera.capture('one')).id, 'one');
      expect(posts, 1);
    },
  );
  test(
    'wrong camera, failed capture and corrupted JPEG never become successful photos',
    () async {
      for (final mode in [
        'identity',
        'id',
        'digest',
        'failed',
        'unauthorized',
      ]) {
        final camera = DirectCameraClient(
          config,
          'secret',
          client: MockClient((request) async {
            if (mode == 'unauthorized') return json({'detail': 'denied'}, 401);
            if (request.url.path.endsWith('/image')) {
              return http.Response.bytes(
                jpeg,
                200,
                headers: {'content-type': 'image/jpeg'},
              );
            }
            if (request.method == 'POST') {
              return json({
                ...job('one'),
                if (mode == 'id') 'capture_id': 'other',
                if (mode == 'digest') 'sha256': 'bad',
                if (mode == 'failed') 'status': 'failed',
              }, 202);
            }
            return json({
              ...status(),
              if (mode == 'identity') 'device_id': 'wrong-board',
            });
          }),
        );
        await expectLater(camera.capture('one'), throwsStateError);
        camera.close();
      }
    },
  );
  test('cancelled capture does not send a command', () async {
    var sent = 0;
    final camera = DirectCameraClient(
      config,
      'secret',
      client: MockClient((_) async {
        sent++;
        return json(status());
      }),
    );
    await expectLater(
      camera.capture('one', cancelled: () => true),
      throwsStateError,
    );
    expect(sent, 0);
    camera.close();
  });
}
