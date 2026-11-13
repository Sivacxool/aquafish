import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/app/bootstrap.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/pairing.dart';
import 'package:aqua_hatch/features/ph_calibration.dart';
import 'pairing_fixture.dart';

Map<String, dynamic> ettPacket() => {
  'timestamp': DateTime.now().toUtc().toIso8601String(),
  'firmware_version': '0.19.0-ett32ue.5',
  'temperature_c': 27.3,
  'temperature_status': 'ok',
  'do_mg_l': 6.2,
  'do_status': 'ok',
  'ph': 7.2,
  'ph_status': 'ok',
  'sensors': {
    'ph': {
      'model': 'MI-Water-PH-T',
      'protocol': 'Modbus RTU',
      'address': 1,
      'baud': 9600,
    },
  },
  'hardware_ready': false,
  'simulated': false,
  'fill': {
    'armed': false,
    'requested': true,
    'running': false,
    'timed_out': false,
    'limit_seconds': 60,
  },
  'heater': {'io_ready': true, 'relay_commanded_on': true},
};

class EttController extends AppController {
  EttController({this.remote = false});
  final bool remote;
  DeviceSettings? sent;
  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(demo: false, localEsp32: true),
    connected: true,
    settings: const DeviceSettings(),
    now: DateTime.now(),
    telemetry: Telemetry.fromJson({...ettPacket(), 'via_relay': remote}),
  );
  @override
  Future<String?> saveSettings(DeviceSettings settings) async {
    sent = settings;
    return null;
  }
}

Future<void> saveImage(GlobalKey key, String name, WidgetTester tester) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('artifacts/screens').create(recursive: true);
    await File(
      'artifacts/screens/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('th');
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets(
    'cold launch paints motion before storage finishes and opens offline',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final fonts = FontLoader('NotoSansThai')
        ..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'));
      await fonts.load();
      await (FontLoader(
        'PhosphorRegular',
      )..addFont(rootBundle.load('assets/fonts/Phosphor.ttf'))).load();
      final pending = Completer<SharedPreferences>();
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: AppBootstrap(loadPreferences: () => pending.future),
        ),
      );
      expect(find.byKey(const ValueKey('startup-animation')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await saveImage(key, 'startup-01', tester);
      await tester.pump(const Duration(milliseconds: 700));
      await saveImage(key, 'startup-02', tester);
      expect(
        File('artifacts/screens/startup-01.png').readAsBytesSync(),
        isNot(
          orderedEquals(
            File('artifacts/screens/startup-02.png').readAsBytesSync(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('กำลังเปิดแอป'), findsOneWidget);
      pending.complete(preferences);
      await tester.pump();
      await tester.pump();
      expect(find.byType(AquaHatchApp), findsOneWidget);
      expect(find.byKey(const ValueKey('startup-animation')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );

  testWidgets('storage error offers retry instead of an endless splash', (
    tester,
  ) async {
    var attempts = 0;
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      AppBootstrap(
        loadPreferences: () async {
          attempts++;
          if (attempts == 1) throw StateError('test storage failure');
          return preferences;
        },
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('เปิดข้อมูลไม่สำเร็จ'), findsOneWidget);
    await tester.tap(find.text('ลองอีกครั้ง'));
    await tester.pump();
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(AquaHatchApp), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test(
    'new and old QR retain credentials, reject mismatched role and suffix',
    () {
      for (final kind in ['s3', 'camera']) {
        final old = pairingFixture(kind: kind);
        final current = {
          ...old,
          'ssid': 'Smart Catfish System-${kind == 's3' ? 'B' : 'C'}-DDEE01',
        };
        final a = PairingBundle.parse(jsonEncode(old));
        final b = PairingBundle.parse(jsonEncode(current));
        expect(a.identity.stableKey, b.identity.stableKey);
        expect(a.token, b.token);
        expect(b.identity.setupSsid.length, lessThanOrEqualTo(32));
        for (final bad in [
          'Smart Catfish System-B-000000',
          'Smart Catfish System-X-DDEE01',
        ]) {
          expect(
            () => PairingBundle.parse(jsonEncode({...old, 'ssid': bad})),
            throwsFormatException,
          );
        }
      }
    },
  );

  test(
    '.5 RS485 pH and commanded heater state survive storage without claiming calibration',
    () {
      final data = Telemetry.fromJson(ettPacket());
      final restored = Telemetry.fromJson(data.toJson());
      expect(restored.ph, 7.2);
      expect(restored.phSensor.externalCalibration, isTrue);
      expect(restored.phCalibrated, isFalse);
      expect(restored.phSensor.adcVoltage, isNull);
      expect(restored.heater?.commandedOn, isTrue);
      expect(restored.alerts(const DeviceSettings()), isEmpty);
      for (final failure in [
        'stale',
        'timeout',
        'crc_error',
        'invalid_response',
      ]) {
        expect(
          Telemetry.fromJson({...ettPacket(), 'ph_status': failure}).ph,
          isNull,
        );
      }
      expect(
        Telemetry.fromJson({
          ...ettPacket(),
          'heater': {'io_ready': false, 'relay_commanded_on': true},
        }).heater?.commandedOn,
        isNull,
      );
    },
  );

  for (final remote in [false, true]) {
    testWidgets('ETT thermostat and pump use firmware .5 with remote=$remote', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = EttController(remote: remote);
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: [appControllerProvider.overrideWith(() => controller)],
            child: const AquaHatchApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('ควบคุม').last);
      await tester.pumpAndSettle();
      expect(find.text('ฮีตเตอร์'), findsOneWidget);
      expect(find.text('สั่งเปิด'), findsOneWidget);
      final increase = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'เพิ่มอุณหภูมิ',
      );
      expect(tester.widget<IconButton>(increase).onPressed == null, remote);
      if (!remote) {
        await saveImage(key, 'ett-controls', tester);
        await tester.tap(increase);
        await tester.pumpAndSettle();
        expect(controller.sent, isNull);
        await tester.tap(find.text('บันทึกอุณหภูมิ'));
        await tester.pumpAndSettle();
        expect(controller.sent?.temperatureTarget, 28.5);
        expect(controller.sent?.phMinimum, 6.5);
      }
      final pump = find.widgetWithText(FilledButton, 'เปิดเติมน้ำอัตโนมัติ');
      await tester.ensureVisible(pump);
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(pump).onPressed == null, remote);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('RS485 calibration does not offer ADC commands', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appControllerProvider.overrideWith(EttController.new)],
        child: const MaterialApp(home: PhCalibrationScreen()),
      ),
    );
    expect(find.text('pH · RS485'), findsOneWidget);
    expect(find.textContaining('ADS1115'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
