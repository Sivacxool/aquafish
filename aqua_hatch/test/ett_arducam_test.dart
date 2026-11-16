import 'dart:convert';

import 'package:aqua_hatch/core/camera.dart';
import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/pairing.dart';
import 'package:aqua_hatch/core/remote_relay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'direct_camera_test.dart' as fixture;
import 'pairing_fixture.dart';

const origin = 'https://aquahatch-relay.example.workers.dev';

void main() {
  final pairing = PairingBundle.parse(jsonEncode(pairingFixture(kind: 's3')));
  final board = pairing.config('https://192.168.1.50');
  final cameraId = board.deviceId.replaceFirst('s3-', 'cam-');
  const settings = ArducamSettings(
    fullSize: false,
    lighting: 'manual',
    levels: {'ev': 2, 'brightness': -4, 'white_balance': 2},
  );

  for (final useRelay in [false, true]) {
    test(
      'ETT takes a manual B0434 photo over ' + (useRelay ? 'relay' : 'LAN'),
      () async {
        var posted = false;
        Future<http.Response> capture(http.Request request) async {
          expect(request.url.path, contains('/camera'));
          if (useRelay) {
            expect(request.url.path, startsWith('/v1/cameras/'));
          } else {
            expect(
              request.url.path,
              startsWith('/api/v1/devices/' + board.deviceId),
            );
            expect(request.url.host, board.identity!.hostname);
            expect(request.headers['Authorization'], 'Bearer ' + pairing.token);
          }
          final status = {
            ...fixture.status(),
            'device_id': cameraId,
            'camera_id': cameraId,
            'sensor': 'Arducam B0434',
            'autofocus_supported': false,
          };
          if (request.method == 'POST') {
            posted = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body['flash'], isFalse);
            expect(body['autofocus'], isFalse);
            expect(body['resolution'], '3mp');
            expect(body['arducam'], {
              'resolution': 'vga',
              'lighting': 'manual',
              'settings': {
                'ev': 2,
                'brightness': -4,
                'contrast': 0,
                'saturation': 0,
                'white_balance': 2,
              },
            });
            return fixture.json({
              ...fixture.job('ett-photo'),
              ...status,
              'width': 640,
              'height': 480,
            }, 202);
          }
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              fixture.jpeg,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          return fixture.json(status);
        }

        final client = DirectCameraClient(
          useRelay ? board.withRelayOrigin(origin) : board,
          pairing.token,
          controllerCamera: true,
          client: MockClient(
            useRelay
                ? (_) async => throw http.ClientException('LAN offline')
                : capture,
          ),
          relayClient: useRelay ? MockClient(capture) : null,
        );
        addTearDown(client.close);
        final image = await client.captureArducam('ett-photo', settings);
        expect(posted, isTrue);
        expect(image.cameraId, cameraId);
        expect(image.width, 640);
        expect(image.bytes, fixture.jpeg);
      },
    );
  }

  test('ETT remote camera and readings are both disabled off-site', () async {
    final disabled = <String>[];
    Future<http.Response> deny(http.Request request) async {
      expect(request.method, 'POST');
      expect(jsonDecode(request.body), {'enabled': false});
      disabled.add(request.url.pathSegments[1]);
      return fixture.json({'enabled': false});
    }

    await configureDeviceRelay(
      board.withRelayOrigin(origin),
      pairing.token,
      null,
      includeControllerCamera: true,
      relayClient: MockClient(deny),
      controllerCameraClient: MockClient(deny),
      localClientFactory: (_) async => throw StateError('LAN unavailable'),
    );
    expect(disabled, ['cameras', 'readings']);
  });
}
