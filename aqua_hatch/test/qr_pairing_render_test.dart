import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
  testWidgets(
    'QR confirmation is readable on a phone and opens the scanned board setup',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fonts = FontLoader('NotoSansThai')
        ..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'));
      await fonts.load();
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: [
              localStoreProvider.overrideWithValue(store),
              appControllerProvider.overrideWith(
                () => WifiTestController(false),
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(),
              home: QrPairingScreen(
                scanCode: (_) => Future.value(jsonEncode(pairingFixture())),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('scan-device-qr')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts/qr-pairing').create(recursive: true);
        await File(
          'artifacts/qr-pairing/confirm-mobile.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      final confirm = find.byKey(const ValueKey('confirm-device-qr'));
      await tester.ensureVisible(confirm);
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('อ่านรหัสจาก QR แล้ว ไม่ต้องกรอกซ้ำ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
