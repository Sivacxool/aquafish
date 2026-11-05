import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/wifi_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('th.ac.aquahatch/wifi');
  final calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'openWifiSettings' ? null : true;
        });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'iOS uses manual network selection without Android method calls',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const platform = WifiPlatform();
      expect(platform.requiresManualWifiSelection, isTrue);
      await platform.openSettings();
      await platform.bindWifi();
      await platform.releaseWifi();
      expect(calls, isEmpty);
    },
  );

  test(
    'Android still opens and binds Wi-Fi through its native channel',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      const platform = WifiPlatform();
      expect(platform.requiresManualWifiSelection, isFalse);
      await platform.openSettings();
      await platform.bindWifi();
      await platform.releaseWifi();
      expect(calls, ['openWifiSettings', 'bindWifi', 'releaseWifi']);
    },
  );
}
