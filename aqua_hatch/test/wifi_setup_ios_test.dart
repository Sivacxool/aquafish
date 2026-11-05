import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:aqua_hatch/app/theme.dart';
import 'package:aqua_hatch/core/board_wifi.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/features/wifi_setup.dart';
import 'board_wifi_test.dart' show wifiResponse, wifiStatus;
import 'wifi_setup_test.dart'
    show WifiTestController, TestWifiPlatform, TestCredentials;

void main() {
  testWidgets(
    'iPhone shows the actual setup SSID and manual Wi-Fi steps',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final platform = TestWifiPlatform();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => WifiTestController(false)),
            credentialStoreProvider.overrideWithValue(const TestCredentials()),
          ],
          child: MaterialApp(
            theme: buildTheme(),
            home: WifiSetupScreen(
              platform: platform,
              clientFactory: (config, token) => BoardWifiClient(
                config,
                token,
                client: MockClient((_) async => wifiResponse(wifiStatus())),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('wifi-pairing-code')),
        'pairing',
      );
      final start = find.text('เริ่มตั้งค่า');
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      final instructions = find.text('วิธีเปลี่ยน Wi-Fi บน iPhone');
      await tester.ensureVisible(instructions);
      await tester.tap(instructions);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('การตั้งค่า > Wi-Fi'), findsOneWidget);
      expect(find.textContaining(setupNetworkName), findsWidgets);
      expect(find.textContaining('เครือข่ายเฉพาะที่'), findsOneWidget);
      expect(platform.opened, 0);
      await tester.tap(find.text('เข้าใจแล้ว'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
