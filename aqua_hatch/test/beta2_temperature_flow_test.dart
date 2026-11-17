import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'widget_test.dart' show mountApp;

class _TemperatureController extends AppController {
  Telemetry snapshot({String jarStatus = 'ok', double fry = 28}) =>
      Telemetry.fromJson({
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'firmware_version': '0.25.0-ett32ue.beta2',
        'temperature_control_source': 'three_point_average',
        'temperature_c': fry,
        'temperature_status': 'ok',
        'do_temperature_c': 27,
        'do_status': 'ok',
        'do_temperature_status': jarStatus,
        'ph_temperature_c': 29,
        'ph_status': 'ok',
        'ph_source': 'rs485',
        'ph_temperature_status': 'ok',
        'temperature_age_ms': 100,
        'do_temperature_age_ms': 200,
        'ph_temperature_age_ms': 300,
        'do_mg_l': 6.2,
        'ph': 7.1,
        'water_level_ok': true,
      });
  @override
  AppState build() {
    final sample = snapshot();
    return AppState(
      connection: const ConnectionConfig(demo: false, localEsp32: true),
      settings: const DeviceSettings(),
      now: sample.at,
      connected: true,
      telemetry: sample,
    );
  }

  void deliver({String jarStatus = 'ok', double fry = 28}) {
    final sample = snapshot(jarStatus: jarStatus, fry: fry);
    state = state.copyWith(telemetry: sample, now: sample.at);
  }
}

Future<void> capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('artifacts/screens/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets(
    'three-location sheet receives updates while open and excludes a lost probe',
    (tester) async {
      final controller = _TemperatureController();
      final key = GlobalKey();
      await mountApp(tester, controller: () => controller, captureKey: key);
      await tester.pumpAndSettle();
      expect(find.text('28.0 °C', findRichText: true), findsOneWidget);
      await capture(tester, key, 'beta2-temperature-overview');
      await tester.tap(find.byKey(const ValueKey('temperature-average-card')));
      await tester.pumpAndSettle();
      expect(find.text('แมคโดนัลด์จาร์'), findsOneWidget);
      expect(find.text('ถังพักลูกปลา'), findsOneWidget);
      expect(find.text('ถังพักน้ำ'), findsOneWidget);
      await capture(tester, key, 'beta2-temperature-locations');
      controller.deliver(fry: 30);
      await tester.pumpAndSettle();
      expect(find.text('30.0 °C'), findsOneWidget);
      expect(find.text('เฉลี่ย 28.7 °C · 3/3 จุด'), findsOneWidget);
      controller.deliver(jarStatus: 'timeout', fry: 30);
      await tester.pumpAndSettle();
      expect(find.text('27.0 °C'), findsNothing);
      expect(find.text('เฉลี่ย 29.5 °C · 2/3 จุด'), findsOneWidget);
      expect(
        find.text('รอข้อมูลครบ 3 จุดเพื่อควบคุมอุณหภูมิอัตโนมัติ'),
        findsOneWidget,
      );
      await capture(tester, key, 'beta2-temperature-partial');
      await tester.tap(find.byTooltip('ปิด'));
      await tester.pumpAndSettle();
      expect(find.text('29.5 °C', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
