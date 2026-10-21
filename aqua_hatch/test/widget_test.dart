import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/local_store.dart';

Future<void> mountApp(
  WidgetTester tester, {
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  final font = FontLoader('NotoSansThai')
    ..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'));
  await font.load();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(LocalStore(preferences)),
      ],
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: const AquaHatchApp(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  testWidgets(
    'mobile dashboard and all four routes render without layout errors',
    (tester) async {
      await mountApp(tester);
      expect(find.text('ภาพรวมเครื่องฟัก'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in ['ควบคุม', 'นับลูกปลา', 'ตั้งค่า', 'ภาพรวม']) {
        await tester.tap(find.text(label).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('desktop dashboard uses sidebar and fits without overflow', (
    tester,
  ) async {
    await mountApp(tester, size: const Size(1440, 1024));
    expect(find.text('พื้นที่ทำงาน'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('นับลูกปลา').first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets('sample count requires review and saves count provenance', (
    tester,
  ) async {
    await mountApp(tester, size: const Size(1440, 1024));
    await tester.tap(find.text('นับลูกปลา').first);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('ใช้ภาพตัวอย่าง'));
    await tester.pump();
    final analyze = find.text('ลองนับภาพตัวอย่าง');
    await tester.ensureVisible(analyze);
    await tester.tap(analyze);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('48'), findsOneWidget);
    final saveFinder = find.widgetWithText(FilledButton, 'บันทึกผลนับ');
    expect(tester.widget<FilledButton>(saveFinder).onPressed, isNull);
    final review = find.text('ตรวจสอบจำนวนในภาพแล้ว');
    await tester.ensureVisible(review);
    await tester.tap(review);
    await tester.pump();
    await tester.ensureVisible(saveFinder);
    await tester.tap(saveFinder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('บันทึกแล้ว'), findsOneWidget);
    final persisted = LocalStore(
      await SharedPreferences.getInstance(),
    ).counts.single;
    expect(persisted.count, 48);
    expect(persisted.aiCount, 48);
    expect(persisted.demo, isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
