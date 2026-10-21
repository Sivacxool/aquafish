import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';

class SetupController extends AppController {
  @override
  AppState build() {
    final now = DateTime.now();
    return AppState(
      connection: const ConnectionConfig(
        demo: false,
        localEsp32: true,
        baseUrl: 'https://192.168.1.50',
      ),
      settings: const DeviceSettings(),
      now: now,
      connected: true,
      telemetry: Telemetry(
        at: now,
        firmwareVersion: '0.5.0-local',
        hardwareReady: false,
        hardwareMessage:
            'บอร์ดเชื่อมต่อแล้ว ยังไม่ได้ติดตั้งเซนเซอร์และตั้งค่าขาควบคุม',
      ),
    );
  }
}

void main() {
  testWidgets(
    'online unconfigured board shows missing hardware and disables physical modes',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appControllerProvider.overrideWith(SetupController.new)],
          child: const AquaHatchApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('บอร์ดออนไลน์ · รอติดตั้งอุปกรณ์'), findsOneWidget);
      await tester.tap(find.text('ควบคุม').last);
      await tester.pumpAndSettle();
      expect(find.text('รอติดตั้งอุปกรณ์'), findsOneWidget);
      expect(find.text('ยังไม่ติดตั้ง / ยังไม่ยืนยันวงจร'), findsNWidgets(4));
      await tester.tap(find.text('ควบคุมเอง').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('ตั้งค่า').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('เครื่องและการเชื่อมต่อ'));
      await tester.tap(find.text('เครื่องและการเชื่อมต่อ'));
      await tester.pumpAndSettle();
      expect(find.text('ESP32 ในบ้าน'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'URL บอร์ด'), findsOneWidget);
      expect(find.text('ทดสอบบอร์ด'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
