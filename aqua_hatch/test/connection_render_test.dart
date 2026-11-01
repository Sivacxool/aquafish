import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:aqua_hatch/app/theme.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/board_wifi.dart';
import 'package:aqua_hatch/features/connection_overview.dart';
import 'package:aqua_hatch/features/wifi_setup.dart';
import 'board_wifi_test.dart' show wifiStatus, wifiResponse;
import 'wifi_setup_test.dart'
    show WifiTestController, TestWifiPlatform, TestCredentials;

void main() {
  testWidgets(
    'render guided connection at phone size with simulated board responses',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader(
        'NotoSansThai',
      )..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'))).load();
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final boundaryKey = GlobalKey();
      final app = WifiTestController(false);
      var id = '';
      final connect = Completer<void>();
      final platform = TestWifiPlatform();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: ProviderScope(
            overrides: [
              appControllerProvider.overrideWith(() => app),
              credentialStoreProvider.overrideWithValue(
                const TestCredentials(),
              ),
            ],
            child: MaterialApp(
              theme: buildTheme(),
              home: Builder(
                builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('ตั้งค่า')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: ConnectionOverview(
                      state: app.build(),
                      onBoard: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WifiSetupScreen(
                            platform: platform,
                            clientFactory: (config, token) => BoardWifiClient(
                              config,
                              token,
                              client: MockClient((request) async {
                                if (request.method == 'POST' &&
                                    request.url.path.endsWith('/wifi')) {
                                  id =
                                      (jsonDecode(request.body)
                                              as Map)['request_id']
                                          as String;
                                  await connect.future;
                                }
                                return wifiResponse(
                                  request.url.path.endsWith('/start')
                                      ? {'accepted': true}
                                      : wifiStatus(
                                          phase: id.isEmpty
                                              ? 'idle'
                                              : 'connected',
                                          id: id,
                                        ),
                                  request.method == 'POST' ? 202 : 200,
                                );
                              }),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> capture(String name) async {
        await tester.pump();
        expect(tester.takeException(), isNull);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final frame = await boundary.toImage(pixelRatio: 2);
          final bytes = await frame.toByteData(format: ui.ImageByteFormat.png);
          await Directory('artifacts/connection').create(recursive: true);
          await File(
            'artifacts/connection/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          frame.dispose();
        });
      }

      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await tester.pumpAndSettle();
      await capture('overview-mobile');
      await tap('เริ่มเชื่อมต่อบอร์ดหลัก');
      await capture('step-1-prepare');
      await tester.enterText(
        find.widgetWithText(TextField, 'รหัสจับคู่บอร์ด'),
        'example-pairing',
      );
      await tap('เริ่มตั้งค่า');
      await capture('step-2-board-wifi');
      await tap('เชื่อม Wi-Fi บอร์ดแล้ว ตรวจบอร์ด');
      await capture('step-3-home-wifi');
      await tester.ensureVisible(find.text('ส่ง Wi-Fi ให้บอร์ด'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ส่ง Wi-Fi ให้บอร์ด'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await capture('step-4-connecting');
      connect.complete();
      await tester.pumpAndSettle();
      await capture('step-4-return-home');
      await tap('ยืนยันและเข้าใช้งาน');
      await capture('success-simulated');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
