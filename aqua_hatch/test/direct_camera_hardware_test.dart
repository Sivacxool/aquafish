import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/paired_camera.dart';

class CameraNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ip = String.fromEnvironment('CAMERA_IP'),
      token = String.fromEnvironment('CAMERA_TOKEN'),
      sensor = String.fromEnvironment('CAMERA_SENSOR', defaultValue: 'OV5640');
  const width = int.fromEnvironment('CAMERA_WIDTH', defaultValue: 2560),
      height = int.fromEnvironment('CAMERA_HEIGHT', defaultValue: 1920);
  test(
    'actual paired TLS camera returns two fresh native-resolution JPEG captures',
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
          final status = await client.status();
          expect(status.ready, isTrue);
          expect(status.sensor, sensor);
          final one = await client.capture(createId());
          final two = await client.capture(createId());
          expect(one.bytes.length, greaterThan(1000));
          expect(two.bytes.length, greaterThan(1000));
          expect(one.id, isNot(two.id));
          expect(two.cameraId, cameraDeviceId);
          for (final photo in [one, two]) {
            expect(photo.sensor, sensor);
            expect(photo.width, width);
            expect(photo.height, height);
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
