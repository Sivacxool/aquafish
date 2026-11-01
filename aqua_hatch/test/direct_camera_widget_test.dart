import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'camera_widget_test.dart' as camera_fixture;
import 'direct_camera_test.dart' as network_fixture;

class IndependentCamera extends camera_fixture.CameraController {
  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(),
    cameraConnection: network_fixture.config,
    settings: const DeviceSettings(),
    now: DateTime.now(),
  );
}

void main() {
  testWidgets(
    'direct camera capture button works even when main controller is in demo or offline',
    (tester) async {
      final app = IndependentCamera();
      await camera_fixture.mount(tester, app);
      expect(find.text('พร้อมถ่าย'), findsOneWidget);
      expect(find.text('โหมดทดลอง'), findsNothing);
      final button = find.widgetWithText(
        FilledButton,
        'ถ่ายภาพจากกล้องในเครื่อง',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(app.captures, 1);
      app.photo.complete(camera_fixture.captured());
      final watch = Stopwatch()..start();
      while (find.text('ภาพจากกล้องในเครื่อง').evaluate().isEmpty &&
          watch.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('ภาพจากกล้องในเครื่อง'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
