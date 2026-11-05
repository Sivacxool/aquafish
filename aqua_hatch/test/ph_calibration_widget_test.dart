import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/app/theme.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/ph.dart';
import 'package:aqua_hatch/features/ph_calibration.dart';

class PhController extends AppController {
  final bool live, stable;
  final calls = <Map<String, Object>>[];
  PhController({this.live = true, this.stable = true});
  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(
      demo: false,
      localEsp32: true,
      baseUrl: 'https://192.168.1.10',
    ),
    settings: const DeviceSettings(),
    now: DateTime.now(),
    connected: live,
    telemetry: Telemetry(
      at: DateTime.now(),
      phSensor: PhSensorInfo(
        supported: true,
        status: 'not_calibrated',
        adcVoltage: 1.25,
        stable: stable,
      ),
    ),
  );
  @override
  Future<String?> calibratePh(double bufferPh, {required bool startNew}) async {
    calls.add({'buffer': bufferPh, 'startNew': startNew});
    state = state.copyWith(
      telemetry: Telemetry(
        at: DateTime.now(),
        phCalibrated: !startNew,
        phSensor: PhSensorInfo(
          supported: true,
          status: startNew ? 'not_calibrated' : 'ok',
          stable: true,
          adcVoltage: startNew ? 1.25 : 1.50,
          neutralVoltage: 1.25,
          acidVoltage: startNew ? null : 1.50,
          neutralPh: startNew ? bufferPh : state.telemetry!.phSensor.neutralPh,
        ),
      ),
    );
    return null;
  }
}

void main() {
  Future<GlobalKey> mount(WidgetTester tester, PhController controller) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ProviderScope(
          overrides: [appControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: buildTheme(),
            home: const PhCalibrationScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets(
    'pH setup requires fresh stable input and stores neutral before acid',
    (tester) async {
      final c = PhController();
      await mount(tester, c);
      final neutral = find.byKey(const ValueKey('ph-calibrate-neutral')),
          acid = find.byKey(const ValueKey('ph-calibrate-acid'));
      expect(tester.widget<FilledButton>(acid).onPressed, isNull);
      await tester.ensureVisible(neutral);
      await tester.tap(neutral);
      await tester.pumpAndSettle();
      expect(c.calls, [
        {'buffer': 7.0, 'startNew': true},
      ]);
      await tester.ensureVisible(acid);
      await tester.tap(acid);
      await tester.pumpAndSettle();
      expect(c.calls.last, {'buffer': 4.0, 'startNew': false});
      expect(c.state.telemetry!.phCalibrated, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
  testWidgets('offline or unstable pH cannot send calibration commands', (
    tester,
  ) async {
    for (final c in [PhController(live: false), PhController(stable: false)]) {
      await mount(tester, c);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey('ph-calibrate-neutral')),
            )
            .onPressed,
        isNull,
      );
      expect(c.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }
  });
  testWidgets('render pH setup for visual QA using simulated voltage only', (
    tester,
  ) async {
    final font = FontLoader('NotoSansThai')
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final key = await mount(tester, PhController());
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory('artifacts/ph').create(recursive: true);
      await File(
        'artifacts/ph/setup-simulated.png',
      ).writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
