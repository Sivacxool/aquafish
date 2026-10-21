import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/board_wifi.dart';
import 'package:aqua_hatch/core/models.dart';

Map<String, dynamic> wifiStatus({
  String device = 'incubator-01',
  String phase = 'idle',
  String id = '',
}) => {
  'backend': 'esp32-local',
  'device_id': device,
  'provisioning_version': 1,
  'connected': true,
  'ip': '192.168.1.156',
  'ssid': 'Home',
  'saved_ssid': 'Home',
  'credentials_saved': true,
  'ap_active': true,
  'phase': phase,
  'request_id': id,
  'attempt_ssid': 'Home',
  'error': '',
  'scan_state': 'ready',
  'networks': [
    {'ssid': 'Home', 'rssi': -70, 'auth': 3},
    {'ssid': 'Home', 'rssi': -40, 'auth': 3},
    {'ssid': 'Other', 'rssi': -50, 'auth': 3},
    {'ssid': 'Enterprise', 'rssi': -20, 'auth': 5},
  ],
};
http.Response wifiResponse(Object data, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(data)), status);
const wifiConfig = ConnectionConfig(
  demo: false,
  localEsp32: true,
  baseUrl: 'https://192.168.1.156',
);

void main() {
  test(
    'setup uses paired TLS identity and authenticated JSON, without URL credentials',
    () async {
      final requests = <http.Request>[];
      final client = BoardWifiClient(
        wifiConfig,
        'pairing',
        client: MockClient((request) async {
          requests.add(request);
          expect(request.url.host, 'aquahatch-117c.local');
          expect(request.url.scheme, 'https');
          expect(request.url.hasQuery, isFalse);
          expect(request.headers['Authorization'], 'Bearer pairing');
          expect(request.followRedirects, isFalse);
          expect(request.persistentConnection, isFalse);
          return wifiResponse(
            request.url.path.endsWith('/start')
                ? {'accepted': true}
                : wifiStatus(),
            request.method == 'POST' ? 202 : 200,
          );
        }),
      );
      await client.status();
      await client.openSetupNetwork();
      await client.startScan();
      await client.submit(
        requestId: 'job1',
        ssid: 'Home',
        password: 'newpassword',
      );
      expect(jsonDecode(requests.last.body)['password'], 'newpassword');
      expect(requests.last.url.toString(), isNot(contains('newpassword')));
      client.close();
    },
  );
  test(
    'scan deduplicates SSIDs by strongest signal and removes unsupported enterprise networks',
    () {
      final status = BoardWifiStatus.fromJson(wifiStatus(), 'incubator-01');
      expect(status.networks.map((n) => n.ssid), ['Home', 'Other']);
      expect(status.networks.first.rssi, -40);
    },
  );
  test('wrong board, malformed state and public LAN address are rejected', () {
    for (final data in [
      wifiStatus(device: 'other'),
      {...wifiStatus(), 'ip': '8.8.8.8'},
      {...wifiStatus(), 'backend': 'other'},
      {...wifiStatus(), 'provisioning_version': 2},
    ]) {
      expect(
        () => BoardWifiStatus.fromJson(data, 'incubator-01'),
        throwsStateError,
      );
    }
  });
  test(
    'SSID byte limits, control characters and password validation apply before sending',
    () {
      for (final ssid in [
        '',
        List.filled(33, 'x').join(),
        List.filled(11, 'ก').join(),
        'bad\nssid',
      ]) {
        expect(
          () => validateWifiCredentials(ssid, '12345678'),
          throwsStateError,
        );
      }
      expect(() => validateWifiCredentials('Home', 'short'), throwsStateError);
      validateWifiCredentials('Home', '', reusePassword: true);
      validateWifiCredentials('Open', '', allowOpen: true);
      validateWifiCredentials('Home', List.filled(64, 'a').join());
    },
  );
  test(
    'server rejection has a status; malformed success cannot become a saved connection',
    () async {
      for (final code in [401, 404, 409, 422]) {
        final client = BoardWifiClient(
          wifiConfig,
          'pairing',
          client: MockClient(
            (_) async => wifiResponse({'detail': 'rejected'}, code),
          ),
        );
        await expectLater(
          client.status(),
          throwsA(
            isA<BoardWifiRejected>().having(
              (e) => e.statusCode,
              'status',
              code,
            ),
          ),
        );
        client.close();
      }
      final client = BoardWifiClient(
        wifiConfig,
        'pairing',
        client: MockClient((_) async => http.Response('broken', 200)),
      );
      await expectLater(client.status(), throwsStateError);
      client.close();
    },
  );
  test('setup AP password is stable, per pairing code and WPA length', () {
    expect(setupNetworkPassword('pairing'), '47bdf83a0f3e4875');
    expect(setupNetworkPassword('pairing'), hasLength(16));
    expect(setupNetworkPassword(' pairing '), setupNetworkPassword('pairing'));
    expect(
      setupNetworkPassword('other'),
      isNot(setupNetworkPassword('pairing')),
    );
  });
}
