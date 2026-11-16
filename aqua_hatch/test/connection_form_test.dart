import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'widget_test.dart' show mountApp;

void main() {
  for (final size in [const Size(1440, 1024), const Size(390, 844)]) {
    testWidgets('real connection fields render and accept input at $size', (
      tester,
    ) async {
      await mountApp(tester, size: size);
      await tester.tap(find.text('ตั้งค่า').last);
      await tester.pumpAndSettle();
      final group = find.text('ตั้งค่าบอร์ดขั้นสูง');
      await tester.ensureVisible(group);
      await tester.pump();
      //       await tester.tap(group);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      for (final label in [
        'URL บอร์ด',
        'รหัสเครื่อง',
        'รหัสเข้าถึงเซิร์ฟเวอร์',
      ]) {
        final field = find.widgetWithText(TextField, label);
        expect(field, findsOneWidget);
        expect(tester.getSize(field).height, lessThan(150));
        await tester.ensureVisible(field);
        await tester.pump();
        await tester.enterText(
          field,
          label == 'URL บอร์ด' ? 'https://192.168.1.50' : 'test-value',
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
}
