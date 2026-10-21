import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'opening Wi-Fi setup during bootstrap pauses polling until the wizard exits',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [
          localStoreProvider.overrideWithValue(LocalStore(preferences)),
        ],
      );
      addTearDown(container.dispose);
    final subscription = container.listen(appControllerProvider, (_, _) {});
      addTearDown(subscription.close);
      final controller = container.read(appControllerProvider.notifier);
      await controller.pauseForWifiSetup();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(appControllerProvider).connected, isFalse);
      expect(container.read(appControllerProvider).telemetry, isNull);
      await controller.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(container.read(appControllerProvider).connected, isTrue);
    },
  );
}
