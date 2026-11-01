import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/credentials.dart';
import 'package:aqua_hatch/core/direct_camera.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/core/models.dart';
import 'direct_camera_test.dart' as fixture;

class CameraCredentials extends CredentialStore {
  final saved = <String, String>{};
  @override
  Future<String> read(ConnectionConfig config) async =>
      saved[key(config)] ?? 'camera-secret';
  @override
  Future<void> save(ConnectionConfig config, String token) async {
    saved[key(config)] = token;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'camera pairs independently and persists without replacing the main ESP32 URL',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final credentials = CameraCredentials();
      DirectCameraClient make(ConnectionConfig config, String token) =>
          DirectCameraClient(
            config,
            token,
            client: MockClient((_) async => fixture.json(fixture.status())),
          );
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          credentialStoreProvider.overrideWithValue(credentials),
          directCameraFactoryProvider.overrideWithValue(make),
        ],
      );
      addTearDown(container.dispose);
      final original = container
          .read(appControllerProvider)
          .connection
          .toJson();
      final app = container.read(appControllerProvider.notifier);
      expect(
        await app.configureCamera(fixture.config, 'camera-secret'),
        isNull,
      );
      expect(
        container.read(appControllerProvider).connection.toJson(),
        original,
      );
      expect(store.cameraConnection?.baseUrl, fixture.config.baseUrl);
      expect((await app.cameraStatus()).ready, isTrue);
      expect(
        jsonEncode(store.cameraConnection?.toJson()),
        isNot(contains('camera-secret')),
      );
    },
  );
}
