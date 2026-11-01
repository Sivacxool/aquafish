import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/usb_camera.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final jpeg = [255, 216, 1, 2, 3, 255, 217];
Map<String, dynamic> status({int wifi = 0}) => {
  'transport': 'usb-uart',
  'wifi_mode': wifi,
  'connected': true,
  'camera_ready': true,
  'last_frame_time': DateTime.now().millisecondsSinceEpoch / 1000,
};
http.Response photo({String? digest, double? seconds}) => http.Response.bytes(
  jpeg,
  200,
  headers: {
    'content-type': 'image/jpeg',
    'x-aquahatch-transport': 'usb-uart',
    'x-aquahatch-sequence': '1',
    'x-aquahatch-captured-at':
        '${seconds ?? DateTime.now().millisecondsSinceEpoch / 1000}',
    'x-aquahatch-sha256': digest ?? sha256.convert(jpeg).toString(),
  },
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'USB client accepts checked fresh JPEG and rejects stale/corrupt images',
    () async {
      final good = UsbCameraClient(client: MockClient((_) async => photo()));
      addTearDown(good.close);
      expect((await good.capture('one')).bytes, jpeg);
      for (final response in [photo(digest: 'bad'), photo(seconds: 1)]) {
        final camera = UsbCameraClient(
          client: MockClient((_) async => response),
        );
        await expectLater(camera.capture('bad'), throwsStateError);
        camera.close();
      }
    },
  );
  test('USB client rejects radio-enabled endpoint and redirects', () async {
    final camera = UsbCameraClient(
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        return http.Response(jsonEncode(status(wifi: 1)), 200);
      }),
    );
    addTearDown(camera.close);
    await expectLater(camera.status(), throwsStateError);
    final redirect = UsbCameraClient(
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://example.com'},
        ),
      ),
    );
    addTearDown(redirect.close);
    await expectLater(redirect.capture('redirect'), throwsStateError);
    expect(
      () => UsbCameraClient(baseUrl: 'http://example.com:8771'),
      throwsArgumentError,
    );
  });
  test(
    'USB mode persists independently of main board and paired Wi-Fi camera',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          usbCameraFactoryProvider.overrideWithValue(
            () => UsbCameraClient(
              client: MockClient(
                (_) async => http.Response(jsonEncode(status()), 200),
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final original = container
          .read(appControllerProvider)
          .connection
          .toJson();
      final controller = container.read(appControllerProvider.notifier);
      expect(await controller.configureUsbCamera(true), isNull);
      expect(store.usbCameraEnabled, isTrue);
      expect(
        container.read(appControllerProvider).connection.toJson(),
        original,
      );
      expect((await controller.cameraStatus()).ready, isTrue);
      expect(await controller.configureUsbCamera(false), isNull);
      expect(store.usbCameraEnabled, isFalse);
    },
  );
}
