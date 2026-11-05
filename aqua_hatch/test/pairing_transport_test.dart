import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/pairing.dart';
import 'package:aqua_hatch/core/board_wifi.dart';
import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/esp32_repository.dart';
import 'pairing_fixture.dart';
import 'esp32_repository_test.dart' as legacy;

void main() {
  test('S3 requests use scanned device hostname, API ID and secret', () async {
    final bundle = PairingBundle.parse(jsonEncode(pairingFixture()));
    final repository = Esp32Repository(
      bundle.config('https://192.168.1.80'),
      bundle.token,
      client: MockClient((request) async {
        expect(request.url.host, bundle.identity.hostname);
        expect(request.url.path, '/api/v1/devices/${bundle.identity.deviceId}');
        expect(request.headers['Authorization'], 'Bearer ${bundle.token}');
        return http.Response(
          jsonEncode(legacy.snapshot(device: bundle.identity.deviceId)),
          200,
        );
      }),
    );
    addTearDown(repository.dispose);
    await repository.connect();
  });
  test(
    'camera status validates the scanned camera ID instead of fixed legacy ID',
    () async {
      final bundle = PairingBundle.parse(
        jsonEncode(pairingFixture(kind: 'camera')),
      );
      final camera = DirectCameraClient(
        bundle.config('https://192.168.1.81'),
        bundle.token,
        client: MockClient((request) async {
          expect(request.url.host, bundle.identity.hostname);
          expect(
            request.url.path,
            '/api/v1/devices/${bundle.identity.deviceId}/camera',
          );
          return http.Response(
            jsonEncode({
              'backend': 'esp32-camera',
              'device_id': bundle.identity.deviceId,
              'camera_id': bundle.identity.deviceId,
              'online': true,
              'configured': true,
              'message': 'ready',
              'sensor': 'OV3660',
            }),
            200,
          );
        }),
      );
      addTearDown(camera.close);
      expect((await camera.status()).ready, isTrue);
    },
  );
  test(
    'Wi-Fi setup uses the scanned identity and rejects a response from another board',
    () async {
      final bundle = PairingBundle.parse(jsonEncode(pairingFixture()));
      final client = BoardWifiClient(
        bundle.config('https://192.168.4.1'),
        bundle.token,
        client: MockClient((request) async {
          expect(request.url.host, bundle.identity.hostname);
          return http.Response(
            jsonEncode({
              'backend': 'esp32-local',
              'provisioning_version': 1,
              'device_id': 'other-board',
              'networks': [],
            }),
            200,
          );
        }),
      );
      addTearDown(client.close);
      expect(client.status(), throwsStateError);
    },
  );
}
