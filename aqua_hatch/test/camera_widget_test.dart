import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
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

class _ArducamController extends CameraController {
  @override
  AppState build() => super.build().copyWith(
    telemetry: Telemetry(at: DateTime.now(), embeddedCamera: true),
  );
}

class _GalleryPicker extends ImagePickerPlatform {
  XFile photo = XFile.fromData(captured().bytes, name: 'gallery.png');

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => photo;

  @override
  Future<XFile?> getVideo({
    required ImageSource source,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
    Duration? maxDuration,
  }) async => XFile.fromData(await photo.readAsBytes(), path: 'sample.mp4');
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
    'One model analyzes Arducam captures, gallery photos, and local clip frames',
    (tester) async {
      final controller = _ArducamController();
      final originalPicker = ImagePickerPlatform.instance;
      final picker = _GalleryPicker();
      ImagePickerPlatform.instance = picker;
      addTearDown(() => ImagePickerPlatform.instance = originalPicker);
      final capture = (await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(2048, 1536);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return DeviceCapture(
          id: 'field-sample',
          cameraId: 'cam-test',
          receivedAt: DateTime.now(),
          bytes: png!.buffer.asUint8List(),
          width: 2048,
          height: 1536,
          sensor: 'Arducam B0434',
        );
      }))!;
      final galleryFrame = captured().bytes;
      final imageSizes = <int>[];
      const channel = MethodChannel('th.ac.aquahatch/video_frame');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'read');
        expect(call.arguments, 'sample.mp4');
        return galleryFrame;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await mount(
        tester,
        controller,
        localAnalyzer: (bytes) async {
          imageSizes.add(bytes.length);
          return const AnalysisResult([
            CountPoint(.42, .34),
          ], fieldFishHeadModelId);
        },
      );

      Future<void> waitForPhoto(String source) async {
        final wait = Stopwatch()..start();
        while (find.text(source).evaluate().isEmpty &&
            wait.elapsed < const Duration(seconds: 5)) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(find.text(source), findsOneWidget);
      }

      Future<void> analyzePhoto() async {
        final analyze = find.widgetWithText(FilledButton, 'วิเคราะห์ด้วย AI');
        await tester.ensureVisible(analyze);
        await tester.tap(analyze);
        await tester.pumpAndSettle();
        expect(find.text('AI ก่อนแก้ 1 ตัว · ตรวจแก้ได้'), findsOneWidget);
      }

      Future<void> pickGalleryPhoto() async {
        final gallery = find.text('เลือกภาพ');
        await tester.ensureVisible(gallery);
        await tester.tap(gallery);
        await tester.pump();
        await waitForPhoto('ภาพที่เลือก');
      }

      await tester.tap(find.byKey(const ValueKey('device-capture-button')));
      await tester.pump();
      controller.photo.complete(capture);
      await waitForPhoto('ภาพจากกล้องในเครื่อง');
      await analyzePhoto();

      await tester.tap(find.text('เลือกภาพ'));
      await tester.pumpAndSettle();
      await pickGalleryPhoto();
      expect(find.byKey(const ValueKey('count-photo-model')), findsNothing);
      await analyzePhoto();

      await tester.tap(find.text('เลือกภาพ'));
      await tester.pumpAndSettle();
      final sources = find.text('แหล่งภาพอื่น');
      await tester.ensureVisible(sources);
      await tester.tap(sources);
      await tester.pumpAndSettle();
      final video = find.text('เลือกคลิป');
      await tester.ensureVisible(video);
      await tester.tap(video);
      await tester.pump();
      await waitForPhoto('ภาพที่เลือก');
      await analyzePhoto();

      expect(imageSizes, [
        capture.bytes.length,
        galleryFrame.length,
        galleryFrame.length,
      ]);
      expect(controller.analyzedId, isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

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

  testWidgets('camera works without main telemetry and uses the local model', (
    tester,
  ) async {
    final controller = CameraController();
    await mount(
      tester,
      controller,
      localAnalyzer: (bytes) async {
        expect(bytes, captured().bytes);
        return const AnalysisResult([CountPoint(.5, .5)], fieldFishHeadModelId);
      },
    );
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
    expect(controller.analyzedId, isNull);
    expect(find.text('1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

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
