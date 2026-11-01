import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/usb_camera.dart';

class UsbNetwork extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'actual USB receiver provides checked OV5640 frames with Wi-Fi off',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final camera = UsbCameraClient(baseUrl: 'http://127.0.0.1:8771');
        try {
          expect((await camera.status()).ready, isTrue);
          final one = await camera.capture('usb-hardware-one');
          await Future<void>.delayed(const Duration(milliseconds: 200));
          final two = await camera.capture('usb-hardware-two');
          expect(one.bytes.length, greaterThan(1000));
          expect(two.bytes.length, greaterThan(1000));
          expect(two.receivedAt.isAfter(one.receivedAt), isTrue);
        } finally {
          camera.close();
        }
      }, UsbNetwork());
    },
    skip: !const bool.fromEnvironment('USB_CAMERA_TEST')
        ? 'Requires physical USB camera'
        : false,
  );
}
