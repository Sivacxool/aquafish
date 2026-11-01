import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/paired_camera.dart';

class CameraNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ip = String.fromEnvironment('CAMERA_IP'),
      token = String.fromEnvironment('CAMERA_TOKEN');
  test(
    'actual paired TLS camera returns two fresh OV5640 JPEG captures',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final client = DirectCameraClient(
          ConnectionConfig(
            demo: false,
            localEsp32: true,
            baseUrl: 'https://$ip',
            deviceId: cameraDeviceId,
          ),
          token,
        );
        try {
          expect((await client.status()).ready, isTrue);
          final one = await client.capture(createId());
          final two = await client.capture(createId());
          expect(one.bytes.length, greaterThan(1000));
          expect(two.bytes.length, greaterThan(1000));
          expect(one.id, isNot(two.id));
          expect(two.cameraId, cameraDeviceId);
          for (final photo in [one, two]) {
            expect(photo.width, 2560);
            expect(photo.height, 1920);
            expect(photo.flashUsed, isTrue);
          }
        } finally {
          client.close();
        }
      }, CameraNetwork());
    },
    skip: ip.isEmpty || token.isEmpty
        ? 'Requires paired physical camera'
        : false,
  );
}
