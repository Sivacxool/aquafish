import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/ui.dart';
import 'package:aqua_hatch/features/history.dart';
import 'widget_test.dart' show mountApp;
import 'counting_fixture.dart';

Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

Future<void> sampleWorkspace(WidgetTester tester) async {
  await tester.tap(find.text('นับลูกปลา').last);
  await tester.pump(const Duration(milliseconds: 350));
  await openFixtureWorkspace(tester);
}

class _OnlineSettingsController extends AppController {
  @override
  AppState build() {
    final now = DateTime.now();
    return AppState(
      connection: const ConnectionConfig(demo: false, localEsp32: true),
      settings: const DeviceSettings(),
      now: now,
      connected: true,
      telemetry: Telemetry(at: now),
    );
  }
}

class _WaterReadingsController extends AppController {
  _WaterReadingsController({this.hasDoTemperature = true});

  final bool hasDoTemperature;

  @override
  AppState build() {
    final now = DateTime.now();
    return AppState(
      connection: const ConnectionConfig(demo: false, localEsp32: true),
      settings: const DeviceSettings(),
      now: now,
      connected: true,
      history: [
        Telemetry(
          at: now.subtract(const Duration(minutes: 2)),
          dissolvedOxygen: 5.24,
        ),
        Telemetry(
          at: now.subtract(const Duration(minutes: 1)),
          dissolvedOxygen: 5.64,
        ),
      ],
      telemetry: Telemetry(
        at: now,
        temperature: 26,
        doTemperature: hasDoTemperature ? 30 : null,
        phTemperature: 28,
        averagedTemperatureControl: true,
      ),
    );
  }
}

void main() {
  testWidgets(
    'DO opens the oxygen trend and local history has no server download',
    (tester) async {
      await mountApp(tester, controller: () => _WaterReadingsController());
      await tester.tap(find.byKey(const ValueKey('dissolved-oxygen-card')));
      await tester.pumpAndSettle();
      final trend = tester.widget<TrendChart>(find.byType(TrendChart));
      expect(trend.trend, WaterTrend.dissolvedOxygen);
      expect(trend.history.map(trend.trend.read), [5.24, 5.64]);
      final history = find.text('ประวัติคุณภาพน้ำ');
      await tester.ensureVisible(history);
      await tester.tap(history);
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('โหลดจากเซิร์ฟเวอร์'), findsNothing);
      await closeApp(tester);
    },
  );

  test(
    'DO trend allows zero and skips missing, stale, and invalid readings',
    () {
      final now = DateTime.now();
      final read = WaterTrend.dissolvedOxygen.read;
      expect(read(Telemetry(at: now, dissolvedOxygen: 0)), 0);
      expect(
        read(
          Telemetry(
            at: now,
            dissolvedOxygen: 6,
            dissolvedOxygenStatus: 'stale',
          ),
        ),
        isNull,
      );
      expect(read(Telemetry(at: now, dissolvedOxygen: double.nan)), isNull);
      expect(read(Telemetry(at: now)), isNull);
    },
  );

  testWidgets('nearby fry heads can be added separately and erased precisely', (
    tester,
  ) async {
    await mountApp(tester);
    await sampleWorkspace(tester);
    await tester.tap(find.text('เพิ่มจุด'));
    await tester.pump();
    final image = find.byKey(const ValueKey('count-review-image'));
    final rect = tester.getRect(image);
    final first = rect.topLeft + Offset(rect.width * .5, rect.height * .98);
    final second = first + const Offset(6, 0);
    await tester.tapAt(first);
    await tester.pump();
    await tester.tapAt(second);
    await tester.pump();
    expect(find.text('50'), findsOneWidget);
    await tester.tap(find.text('ลบจุด'));
    await tester.pump();
    await tester.tapAt(second);
    await tester.pump();
    expect(find.text('49'), findsOneWidget);
    await tester.tapAt(second);
    await tester.pump();
    expect(find.text('49'), findsOneWidget);
    final slider = find.byKey(const ValueKey('count-marker-size'));
    await tester.drag(slider, const Offset(-120, 0));
    await tester.pump();
    expect(find.text('49'), findsOneWidget);
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
      await tester.tap(find.text('ลบจุด'));
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

  testWidgets('all five water readings fit above navigation at 390x844', (
    tester,
  ) async {
    await mountApp(tester);
    final navTop = tester.getRect(find.byType(NavigationBar)).top;
    for (final label in [
      'อุณหภูมิเฉลี่ย',
      'ออกซิเจน · DO',
      'ความเป็นกรด–ด่าง',
      'ระดับน้ำ',
    ]) {
      expect(
        tester.getRect(find.text(label)).bottom,
        lessThan(navTop),
        reason: label,
      );
    }
    await closeApp(tester);
  });

  testWidgets('Beta2 average opens all three locations on narrow phones', (
    tester,
  ) async {
    await mountApp(
      tester,
      size: const Size(320, 740),
      textScale: 1.3,
      controller: _WaterReadingsController.new,
    );
    expect(find.text('28.0 °C', findRichText: true), findsOneWidget);
    expect(find.text('3/3 จุด'), findsOneWidget);
    expect(find.text('เป้าหมายอุณหภูมิในน้ำ 28.0 °C'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('temperature-average-card')));
    await tester.pumpAndSettle();
    for (final label in ['แมคโดนัลด์จาร์', 'ถังพักลูกปลา', 'ถังพักน้ำ']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('30.0 °C', findRichText: true), findsOneWidget);
    expect(find.text('26.0 °C', findRichText: true), findsOneWidget);
    expect(find.text('DS18B20'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(find.text('อุณหภูมิแต่ละจุด'), findsNothing);
    await closeApp(tester);
  });

  testWidgets(
    'missing jar probe shows a partial average and unavailable location',
    (tester) async {
      await mountApp(
        tester,
        controller: () => _WaterReadingsController(hasDoTemperature: false),
      );
      expect(find.text('27.0 °C', findRichText: true), findsOneWidget);
      expect(find.text('2/3 จุด'), findsOneWidget);
      expect(find.text('รออีก 1 จุด · Auto พัก'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('temperature-average-card')));
      await tester.pumpAndSettle();
      expect(find.text('26.0 °C', findRichText: true), findsOneWidget);
      expect(find.text('30.0 °C', findRichText: true), findsNothing);
      expect(find.text('ถังพักน้ำ'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await closeApp(tester);
    },
  );

  testWidgets(
    'phone review keeps image, editing controls and save together; edits require review again',
    (tester) async {
      await mountApp(tester);
      await sampleWorkspace(tester);
      expect(find.text('48'), findsOneWidget);
      final image = find.byKey(const ValueKey('count-review-image'));
      final edit = find.text('เพิ่มจุด');
      final review = find.text('ตรวจสอบจำนวนในภาพแล้ว');
      final save = find.widgetWithText(FilledButton, 'บันทึกผลนับ');
      final navTop = tester.getRect(find.byType(NavigationBar)).top;
      expect(tester.getRect(image).bottom, lessThan(navTop));
      expect(tester.getRect(edit).bottom, lessThan(navTop));
      expect(tester.getRect(save).bottom, lessThanOrEqualTo(navTop));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.tap(review);
      await tester.pump();
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
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
    'settings detail retains draft while scrolling and validates inverted pH',
    (tester) async {
      await mountApp(tester, controller: _OnlineSettingsController.new);
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
      await tester.ensureVisible(maxPh);
      await tester.pump();
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
