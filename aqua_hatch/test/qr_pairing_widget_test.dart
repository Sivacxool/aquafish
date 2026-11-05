import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/app/theme.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/features/qr_pairing.dart';
import 'pairing_fixture.dart';
import 'wifi_setup_test.dart' show WifiTestController;

void main() {
  Future<void> mount(
    WidgetTester tester,
    String raw, {
    String? expectedKind,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          appControllerProvider.overrideWith(() => WifiTestController(false)),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: QrPairingScreen(
            expectedKind: expectedKind,
            scanCode: (_) => Future.value(raw),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets(
    'scan shows public device identity for confirmation, never the token',
    (tester) async {
      final payload = pairingFixture();
      await mount(tester, jsonEncode(payload));
      await tester.tap(find.byKey(const ValueKey('scan-device-qr')));
      await tester.pumpAndSettle();
      expect(find.textContaining('s3-aabbccddee01'), findsOneWidget);
      expect(find.textContaining('AquaHatch-S3-DDEE01'), findsOneWidget);
      expect(find.textContaining(payload['token'] as String), findsNothing);
      expect(find.byKey(const ValueKey('confirm-device-qr')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('wrong device QR is rejected before starting Wi-Fi setup', (
    tester,
  ) async {
    await mount(
      tester,
      jsonEncode(pairingFixture(kind: 'camera')),
      expectedKind: 's3',
    );
    await tester.tap(find.byKey(const ValueKey('scan-device-qr')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('qr-pairing-error')), findsOneWidget);
    expect(find.byKey(const ValueKey('confirm-device-qr')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
