import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/app/theme.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/features/connection_journey.dart';
import 'package:aqua_hatch/features/settings.dart';
import 'wifi_setup_test.dart' show WifiTestController;

void main() {
  Future<void> tap(
    WidgetTester tester,
    Finder finder, {
    bool moving = false,
  }) async {
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(finder);
    if (moving) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets(
    'offline settings starts with guided choices and hides manual fields',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = WifiTestController(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: buildTheme(),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('start-board-setup')), findsOneWidget);
      expect(find.text('ติดต่อไม่ได้'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'URL บอร์ด'), findsNothing);
      expect(
        find.widgetWithText(TextField, 'IP หรือ URL บอร์ดกล้อง'),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('connect-usb-camera')), findsNothing);
      await tap(tester, find.byKey(const ValueKey('connection-preview')));
      expect(
        find.text('ตัวอย่างขั้นตอน • ไม่เชื่อมต่อหรือเปลี่ยนค่าอุปกรณ์'),
        findsOneWidget,
      );
      for (var i = 0; i < 3; i++) {
        await tap(tester, find.text('ดูขั้นตอนถัดไป'), moving: i == 2);
      }
      expect(find.text('ตรวจยืนยันการเชื่อมต่อ'), findsOneWidget);
      expect(find.text('เชื่อมต่อสำเร็จ'), findsNothing);
      expect(
        tester.widget<ConnectionSignal>(find.byType(ConnectionSignal)).active,
        isTrue,
      );
      await tap(tester, find.text('เข้าใจแล้ว'), moving: true);
      expect(controller.configured, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets(
    'Demo 1 shows remote switches with no URL input or legacy settings pages',
    (tester) async {
      tester.view.physicalSize = const Size(320, 620);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = WifiTestController(true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: buildTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('กล้อง: IP และ USB'), findsNothing);
      expect(find.text('สอบเทียบ pH'), findsNothing);
      expect(find.text('Demo 1'), findsOneWidget);
      await tap(tester, find.text('ดูจากระยะไกล'));
      expect(find.byType(BackButton), findsOneWidget);
      expect(
        find.widgetWithText(SwitchListTile, 'ดูค่าเซนเซอร์'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SwitchListTile, 'ถ่ายภาพจากกล้อง'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'walkthrough fits small screen with large Thai text and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.6),
            ),
            child: child!,
          ),
          home: const ConnectionPreviewScreen(),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        expect(tester.takeException(), isNull);
        await tap(tester, find.text('ดูขั้นตอนถัดไป'));
      }
      // Even the activity preview settles when the OS requests reduced motion.
      expect(find.text('ตรวจยืนยันการเชื่อมต่อ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
