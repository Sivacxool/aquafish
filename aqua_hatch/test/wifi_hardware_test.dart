import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/board_wifi.dart';
import 'package:aqua_hatch/core/models.dart';

class WifiHardwareHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ip = String.fromEnvironment('DEVICE_IP'),
      token = String.fromEnvironment('DEVICE_TOKEN');
  test(
    'physical board Wi-Fi status and scan through the actual paired app TLS client',
    () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final config = ConnectionConfig(
          demo: false,
          localEsp32: true,
          baseUrl: 'https://$ip',
        );
        final client = BoardWifiClient(config, token);
        try {
          final before = await client.status();
          expect(before.connected, isTrue);
          expect(before.savedSsid, isNotEmpty);
          await client.openSetupNetwork();
          var scan = await client.startScan();
          final deadline = DateTime.now().add(const Duration(seconds: 20));
          while (scan.scanState == 'scanning' &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 700));
            scan = await client.status();
          }
          expect(scan.scanState, 'ready');
          expect(scan.networks.any((n) => n.ssid == before.ssid), isTrue);
          expect(scan.apActive, isTrue);
        } finally {
          client.close();
        }
        final wrong = BoardWifiClient(config, 'wrong-token');
        try {
          await expectLater(
            wrong.status(),
            throwsA(
              isA<BoardWifiRejected>().having(
                (e) => e.statusCode,
                'status',
                401,
              ),
            ),
          );
        } finally {
          wrong.close();
        }
      }, WifiHardwareHttpOverrides());
    },
    skip: ip.isEmpty || token.isEmpty
        ? 'Requires physical ESP32 and private device definitions'
        : false,
  );
}
