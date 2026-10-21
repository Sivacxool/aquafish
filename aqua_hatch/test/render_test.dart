import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/local_store.dart';

void main() {
  testWidgets('render desktop and mobile screens with Thai font', (
    tester,
  ) async {
    final key = GlobalKey();
    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final font = FontLoader('NotoSansThai')
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [
            localStoreProvider.overrideWithValue(LocalStore(preferences)),
          ],
          child: const AquaHatchApp(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));
    Future<void> capture(String name) async {
      await tester.pump();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory('artifacts/screens').create(recursive: true);
        await File(
          'artifacts/screens/$name.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('dashboard-desktop');
    await tester.tap(find.text('ควบคุมเครื่อง').first);
    await tester.pump(const Duration(milliseconds: 350));
    await capture('controls-desktop');
    await tester.tap(find.text('นับลูกปลา').first);
    await tester.pump(const Duration(milliseconds: 350));
    await capture('camera-desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await capture('camera-mobile');
    tester.view.physicalSize = const Size(1440, 1024);
    await tester.pump();
    await tester.tap(find.text('ใช้ภาพตัวอย่าง'));
    await tester.pump();
    await tester.ensureVisible(find.text('ลองนับภาพตัวอย่าง'));
    await tester.tap(find.text('ลองนับภาพตัวอย่าง'));
    await tester.pump(const Duration(seconds: 1));
    await capture('counting-desktop');
    await tester.tap(find.text('ตั้งค่า').first);
    await tester.pump(const Duration(milliseconds: 350));
    await capture('settings-desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('ภาพรวม').last);
    await tester.pump(const Duration(milliseconds: 350));
    await capture('dashboard-mobile');
    await tester.tap(find.text('นับลูกปลา').last);
    await tester.pump(const Duration(milliseconds: 350));
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflow')) {
        debugPrint(details.toString());
      }
      previousHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousHandler);
    tester.platformDispatcher.textScaleFactorTestValue = 1.4;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final label in ['ควบคุม', 'นับลูกปลา', 'ตั้งค่า']) {
      await tester.tap(find.text(label).last);
      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.takeException(), isNull, reason: label);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
