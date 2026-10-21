import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:aqua_hatch/app/theme.dart';
import 'package:aqua_hatch/core/board_wifi.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/credentials.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/wifi_platform.dart';
import 'package:aqua_hatch/features/wifi_setup.dart';
import 'board_wifi_test.dart' show wifiStatus, wifiResponse, wifiConfig;

class WifiTestController extends AppController {
  final bool alreadyPaired;
  ConnectionConfig? configured;
  String? configuredToken;
  WifiTestController(this.alreadyPaired);
  @override
  AppState build() => AppState(
    connection: alreadyPaired ? wifiConfig : const ConnectionConfig(),
    settings: const DeviceSettings(),
    now: DateTime.now(),
  );
  @override
  Future<void> pauseForWifiSetup() async {}
  @override
  Future<void> reconnect() async {}
  @override
  Future<String?> configure(ConnectionConfig config, String token) async {
    configured = config;
    configuredToken = token;
    state = state.copyWith(connection: config, connected: true);
    return null;
  }
}

class TestCredentials extends CredentialStore {
  const TestCredentials();
  @override
  Future<String> read(ConnectionConfig config) async => 'pairing';
}

class TestWifiPlatform extends WifiPlatform {
  int opened = 0, bindings = 0, releases = 0;
  @override
  Future<void> openSettings() async {
    opened++;
  }

  @override
  Future<void> bindWifi() async {
    bindings++;
  }

  @override
  Future<void> releaseWifi() async {
    releases++;
  }
}

void main() {
  Future<void> mount(
    WidgetTester tester,
    WifiTestController app,
    TestWifiPlatform platform,
    BoardWifiClient Function(ConnectionConfig, String) factory,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appControllerProvider.overrideWith(() => app),
          credentialStoreProvider.overrideWithValue(const TestCredentials()),
        ],
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WifiSetupScreen(
                      platform: platform,
                      clientFactory: factory,
                    ),
                  ),
                ),
                child: const Text('เปิดตั้งค่า'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('เปิดตั้งค่า'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    final finder = find.text(text);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'existing paired board completes Wi-Fi setup and saves direct ESP32 mode automatically',
    (tester) async {
      final app = WifiTestController(true), platform = TestWifiPlatform();
      var id = '';
      await mount(
        tester,
        app,
        platform,
        (config, token) => BoardWifiClient(
          config,
          token,
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path.endsWith('/wifi')) {
              id = (jsonDecode(request.body) as Map)['request_id'] as String;
            }
            return wifiResponse(
              request.url.path.endsWith('/start')
                  ? {'accepted': true}
                  : wifiStatus(
                      phase: id.isEmpty ? 'idle' : 'connected',
                      id: id,
                    ),
              request.method == 'POST' ? 202 : 200,
            );
          }),
        ),
      );
      await tap(tester, 'เริ่มตั้งค่า');
      expect(find.text('เลือก Wi-Fi บ้าน'), findsOneWidget);
      await tap(tester, 'ส่ง Wi-Fi ให้บอร์ด');
      expect(find.text('บอร์ดเชื่อมกับ Home แล้ว'), findsOneWidget);
      expect(app.configured, isNull);
      await tap(tester, 'ยืนยันและเข้าใช้งาน');
      expect(app.configured?.localEsp32, isTrue);
      expect(app.configured?.demo, isFalse);
      expect(app.configured?.baseUrl, 'https://192.168.1.156');
      expect(app.configuredToken, 'pairing');
      expect(platform.releases, greaterThan(0));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'first setup explains board Wi-Fi and opens system settings before board scan',
    (tester) async {
      final app = WifiTestController(false), platform = TestWifiPlatform();
      final urls = <String>[];
      await mount(tester, app, platform, (config, token) {
        urls.add(config.baseUrl);
        return BoardWifiClient(
          config,
          token,
          client: MockClient(
            (request) async => wifiResponse(
              wifiStatus(),
              request.method == 'POST' ? 202 : 200,
            ),
          ),
        );
      });
      await tester.enterText(
        find.widgetWithText(TextField, 'รหัสจับคู่บอร์ด'),
        'pairing',
      );
      await tap(tester, 'เริ่มตั้งค่า');
      expect(find.text(setupNetworkName), findsOneWidget);
      await tap(tester, 'เปิดหน้าตั้งค่า Wi-Fi');
      expect(platform.opened, 1);
      await tap(tester, 'เชื่อม Wi-Fi บอร์ดแล้ว ตรวจบอร์ด');
      expect(find.text('เลือก Wi-Fi บ้าน'), findsOneWidget);
      expect(urls, [setupBoardUrl]);
      expect(app.configured, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'failed candidate does not save the old restored network as a successful change',
    (tester) async {
      final app = WifiTestController(true), platform = TestWifiPlatform();
      var id = '';
      await mount(
        tester,
        app,
        platform,
        (config, token) => BoardWifiClient(
          config,
          token,
          client: MockClient((request) async {
            if (request.method == 'POST' &&
                request.url.path.endsWith('/wifi')) {
              id = (jsonDecode(request.body) as Map)['request_id'] as String;
            }
            final data = wifiStatus(
              phase: id.isEmpty ? 'idle' : 'failed',
              id: id,
            );
            data['error'] = 'รหัส Wi-Fi ไม่ถูกต้อง';
            return wifiResponse(
              request.url.path.endsWith('/start') ? {'accepted': true} : data,
              request.method == 'POST' ? 202 : 200,
            );
          }),
        ),
      );
      await tap(tester, 'เริ่มตั้งค่า');
      await tap(tester, 'ส่ง Wi-Fi ให้บอร์ด');
      expect(find.text('เลือก Wi-Fi บ้าน'), findsOneWidget);
      expect(find.text('รหัส Wi-Fi ไม่ถูกต้อง'), findsOneWidget);
      expect(app.configured, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
