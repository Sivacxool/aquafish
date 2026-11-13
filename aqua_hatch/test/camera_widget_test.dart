import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:aqua_hatch/core/camera.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/fish_head_analyzer.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/repository.dart';
import 'package:aqua_hatch/features/counting.dart';

class CameraController extends AppController {
  int captures = 0;
  String? analyzedId;
  final photo = Completer<DeviceCapture>();

  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(
      demo: false,
      baseUrl: 'https://cloud.example',
    ),
    settings: const DeviceSettings(),
    now: DateTime.now(),
  );

  @override
  Future<DeviceCameraStatus> cameraStatus() async => const DeviceCameraStatus(
    cameraId: 'camera-01',
    configured: true,
    online: true,
    message: 'กล้องพร้อมถ่ายภาพ',
  );

  @override
  Future<DeviceCapture> captureFromDevice(
    String requestId, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async {
    captures++;
    onProgress?.call('รอกล้องส่งภาพ…');
    return photo.future;
  }

  @override
  Future<AnalysisResult> analyzeDeviceCapture(String captureId) async {
    analyzedId = captureId;
    return const AnalysisResult([CountPoint(.5, .5)], 'test-camera-model');
  }

  void switchMachine() => state = state.copyWith(
    connection: const ConnectionConfig(
      demo: false,
      baseUrl: 'https://other.example',
      deviceId: 'other-device',
    ),
  );
}

class Ov3660Controller extends CameraController {
  @override
  AppState build() => super.build().copyWith(
    cameraConnection: const ConnectionConfig(
      demo: false,
      localEsp32: true,
      baseUrl: 'https://192.168.1.55',
      deviceId: 'camera-7c60',
    ),
  );

  @override
  Future<DeviceCameraStatus> cameraStatus() async => const DeviceCameraStatus(
    cameraId: 'camera-7c60',
    configured: true,
    online: true,
    message: 'กล้องพร้อมถ่ายภาพ',
    sensor: 'OV3660',
    captureWidth: 2048,
    captureHeight: 1536,
    autofocusSupported: false,
  );
}

DeviceCapture captured() => DeviceCapture(
  id: 'capture-from-machine',
  cameraId: 'camera-01',
  receivedAt: DateTime.now(),
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAABAAAAAKCAIAAAAy3EnLAAAAGklEQVR4nGNkYPjPQApgIkk1w6gG4gDtgxUA+jYBEw7VJ9EAAAAASUVORK5CYII=',
  ),
);

Future<void> mount(
  WidgetTester tester,
  CameraController controller, {
  FishHeadAnalyzer? localAnalyzer,
}) async {
  await initializeDateFormatting('th');
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appControllerProvider.overrideWith(() => controller),
        fishHeadAnalyzerProvider.overrideWithValue(localAnalyzer),
      ],
      child: const MaterialApp(home: Scaffold(body: CountingScreen())),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets(
    'OV3660 photo can use local AI and its head markers can be corrected',
    (tester) async {
      final controller = Ov3660Controller();
      final capture = captured();
      var calls = 0;
      await mount(
        tester,
        controller,
        localAnalyzer: (bytes) async {
          expect(bytes, same(capture.bytes));
          calls++;
          return const AnalysisResult([CountPoint(.25, .25)], 'fishfry-test');
        },
      );
      expect(find.text('OV3660 · 2048 × 1536 พิกเซล'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('device-capture-button')));
      await tester.pump();
      controller.photo.complete(capture);
      final wait = Stopwatch()..start();
      while (find.text('ภาพจากกล้องในเครื่อง').evaluate().isEmpty &&
          wait.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(find.text('ภาพจากกล้องในเครื่อง'), findsOneWidget);
      final ai = find.widgetWithText(FilledButton, 'วิเคราะห์ด้วย AI');
      await tester.ensureVisible(ai);
      await tester.tap(ai);
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.text('AI ก่อนแก้ 1 ตัว · ตรวจแก้ได้'), findsOneWidget);
      final add = find.text('เพิ่มจุด');
      await tester.ensureVisible(add);
      await tester.tap(add);
      await tester.pump();
      final image = find.byKey(const ValueKey('count-review-image'));
      await tester.ensureVisible(image);
      await tester.tap(image);
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(controller.analyzedId, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'embedded camera is primary, works without main telemetry, and analyzes captured ID',
    (tester) async {
      final controller = CameraController();
      await mount(tester, controller);
      expect(find.text('ภาพตัวอย่างจำลอง'), findsNothing);
      final captureButton = find.byKey(const ValueKey('device-capture-button'));
      expect(tester.widget<OutlinedButton>(captureButton).onPressed, isNotNull);
      await tester.ensureVisible(captureButton);
      await tester.tap(captureButton);
      await tester.pump();
      expect(controller.captures, 1);
      expect(tester.widget<OutlinedButton>(captureButton).onPressed, isNull);
      controller.photo.complete(captured());
      // Native image decoding needs real event-loop time. Wait for the visible
      // result instead of assuming it finishes within a fixed 150 ms under load.
      final decoding = Stopwatch()..start();
      while (find.text('ภาพจากกล้องในเครื่อง').evaluate().isEmpty &&
          decoding.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        find.text('ภาพจากกล้องในเครื่อง'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join('\n'),
      );
      final aiButton = find.widgetWithText(FilledButton, 'วิเคราะห์ด้วย AI');
      await tester.ensureVisible(aiButton);
      await tester.tap(aiButton);
      await tester.pump();
      expect(controller.analyzedId, 'capture-from-machine');
      expect(find.text('1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a photo returning after switching machines is discarded', (
    tester,
  ) async {
    final controller = CameraController();
    await mount(tester, controller);
    await tester.tap(find.byKey(const ValueKey('device-capture-button')));
    await tester.pump();
    controller.switchMachine();
    await tester.pump();
    await tester.runAsync(() async {
      controller.photo.complete(captured());
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pump();
    expect(find.text('ภาพจากกล้องในเครื่อง'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
