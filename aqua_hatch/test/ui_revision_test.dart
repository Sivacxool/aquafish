import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/models.dart';
import 'widget_test.dart' show mountApp;

Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> sampleWorkspace(WidgetTester tester) async {
  await tester.tap(find.text('นับลูกปลา').last);
  await tester.pump(const Duration(milliseconds: 350));
  final sample = find.text('ใช้ภาพตัวอย่าง');
  await tester.ensureVisible(sample);
  await tester.tap(sample);
  await tester.pump();
  final analyze = find.text('ลองนับภาพตัวอย่าง');
  await tester.ensureVisible(analyze);
  await tester.tap(analyze);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('manual mode shows remaining lease and can return to automatic', (
    tester,
  ) async {
    await mountApp(tester);
    await tester.tap(find.text('ควบคุม').last);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.tap(find.text('ควบคุมเอง').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เริ่มควบคุม'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('กลับสู่อัตโนมัติใน'), findsOneWidget);
    final auto = find.text('กลับอัตโนมัติ');
    await tester.ensureVisible(auto);
    await tester.pump();
    await tester.tap(auto);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.textContaining('กลับสู่อัตโนมัติใน'), findsNothing);
    await closeApp(tester);
  });

  testWidgets(
    'editing a known point after zoom removes the point under the tap',
    (tester) async {
      await mountApp(tester);
      await sampleWorkspace(tester);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      viewer.transformationController!.value = Matrix4.diagonal3Values(2, 2, 1);
      await tester.pump();
      await tester.tap(find.text('เพิ่ม/ลบจุด'));
      await tester.pump();
      final image = find.byKey(const ValueKey('count-review-image'));
      final size = tester.getSize(image);
      final point = samplePoints.first;
      await tester.tapAt(
        tester.getTopLeft(image) +
            Offset(point.x * size.width * 2, point.y * size.height * 2),
      );
      await tester.pump();
      expect(find.text('47'), findsOneWidget);
      await closeApp(tester);
    },
  );

  testWidgets('all four water readings fit above navigation at 390x844', (
    tester,
  ) async {
    await mountApp(tester);
    final navTop = tester.getRect(find.byType(NavigationBar)).top;
    for (final label in ['อุณหภูมิน้ำ', 'ค่า pH', 'อัตราการไหล', 'ระดับน้ำ']) {
      expect(
        tester.getRect(find.text(label)).bottom,
        lessThan(navTop),
        reason: label,
      );
    }
    await closeApp(tester);
  });

  testWidgets(
    'phone review keeps image, editing controls and save together; edits require review again',
    (tester) async {
      await mountApp(tester);
      await sampleWorkspace(tester);
      expect(find.text('48'), findsOneWidget);
      final image = find.byKey(const ValueKey('count-review-image'));
      final edit = find.text('เพิ่ม/ลบจุด');
      final review = find.text('ตรวจสอบจำนวนในภาพแล้ว');
      final save = find.widgetWithText(FilledButton, 'บันทึกผลนับ');
      final navTop = tester.getRect(find.byType(NavigationBar)).top;
      expect(tester.getRect(image).bottom, lessThan(navTop));
      expect(tester.getRect(edit).bottom, lessThan(navTop));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(navTop));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(review);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(edit);
      await tester.pump();
      final imageRect = tester.getRect(image);
      await tester.tapAt(
        imageRect.topLeft +
            Offset(imageRect.width * .5, imageRect.height * .98),
      );
      await tester.pump();
      expect(find.text('49'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(find.byTooltip('ย้อนกลับ'));
      await tester.pump();
      expect(find.text('48'), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await closeApp(tester);
    },
  );

  testWidgets(
    'settings groups retain typed values and validate inverted pH at the field',
    (tester) async {
      await mountApp(tester);
      await tester.tap(find.text('ตั้งค่า').last);
      await tester.pump(const Duration(milliseconds: 350));
      final controlGroup = find.text('ค่าควบคุม');
      await tester.ensureVisible(controlGroup);
      await tester.pump();
      await tester.tap(controlGroup);
      await tester.pumpAndSettle();
      final maxPh = find.widgetWithText(TextFormField, 'pH สูงสุด');
      await tester.ensureVisible(maxPh);
      await tester.enterText(maxPh, '6.0');
      final send = find.text('ส่งค่าตั้งไปยังเครื่อง');
      await tester.ensureVisible(send);
      await tester.pump();
      await tester.tap(send);
      await tester.pump();
      expect(find.text('ต้องมากกว่า pH ต่ำสุด'), findsOneWidget);
      await tester.ensureVisible(controlGroup);
      await tester.pump();
      await tester.tap(controlGroup);
      await tester.pumpAndSettle();
      await tester.tap(controlGroup);
      await tester.pumpAndSettle();
      expect(tester.widget<TextFormField>(maxPh).controller!.text, '6.0');
      await closeApp(tester);
    },
  );

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(844, 390),
  ]) {
    testWidgets(
      'navigation and count workspace fit ${size.width}x${size.height} at 1.4 text scale',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await mountApp(tester, size: size, textScale: 1.4);
        for (final label in ['ควบคุม', 'ตั้งค่า', 'นับลูกปลา']) {
          await tester.tap(find.text(label).last);
          await tester.pump(const Duration(milliseconds: 350));
          expect(tester.takeException(), isNull, reason: label);
        }
        await sampleWorkspace(tester);
        expect(tester.takeException(), isNull);
        final save = find.widgetWithText(FilledButton, 'บันทึกผลนับ');
        expect(
          tester.getRect(save).bottom,
          lessThanOrEqualTo(tester.getRect(find.byType(NavigationBar)).top),
        );
        await closeApp(tester);
      },
    );
  }
}
