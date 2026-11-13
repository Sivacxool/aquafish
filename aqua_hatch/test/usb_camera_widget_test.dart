import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:aqua_hatch/core/camera.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/usb_camera.dart';
import 'package:aqua_hatch/features/counting.dart';
import 'camera_widget_test.dart' as fixture;

class UsbController extends fixture.CameraController {
  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(),
    usbCameraEnabled: true,
    settings: const DeviceSettings(),
    now: DateTime.now(),
  );
}

class PreviewCamera extends UsbCameraClient {
  final input = StreamController<DeviceCapture>();
  @override
  Stream<DeviceCapture> frames() => input.stream;
  @override
  void close() {
    unawaited(input.close());
    super.close();
  }
}

void main() {
  testWidgets(
    'USB preview freezes its displayed frame without main-board connection',
    (tester) async {
      await initializeDateFormatting('th');
      tester.view.physicalSize = const Size(1440, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = UsbController();
      final preview = PreviewCamera();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(() => controller),
            usbCameraFactoryProvider.overrideWithValue(() => preview),
          ],
          child: const MaterialApp(home: Scaffold(body: CountingScreen())),
        ),
      );
      await tester.pump();
      await tester.pump();
      preview.input.add(fixture.captured());
      await tester.pump();
      final button = find.byKey(const ValueKey('device-capture-button'));
      expect(tester.widget<OutlinedButton>(button).onPressed, isNotNull);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      for (
        var i = 0;
        i < 50 && find.text('ภาพจากกล้องในเครื่อง').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(controller.captures, 0);
      expect(find.text('ภาพจากกล้องในเครื่อง'), findsOneWidget);
      expect(find.text('นับด้วยมือ'), findsOneWidget);
      expect(find.byKey(const ValueKey('usb-resume-preview')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
