import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:aqua_hatch/core/pairing.dart';
import 'package:aqua_hatch/core/device_tls_client_io.dart';
import 'pairing_fixture.dart';

const fixture = String.fromEnvironment(
  'RUNTIME_TLS_DIR',
  defaultValue: 'build/runtime-private',
);
final available = File('$fixture/server-key.pem').existsSync();
void main() {
  Future<(HttpServer, PairingBundle)> server() async {
    final context = SecurityContext()
      ..useCertificateChain('$fixture/server.pem')
      ..usePrivateKey('$fixture/server-key.pem');
    final service = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(() => service.close(force: true));
    return (
      service,
      File('$fixture/pairing.json').existsSync()
          ? PairingBundle.parse(
              File('$fixture/pairing.json').readAsStringSync(),
            )
          : PairingBundle.parse(
              jsonEncode(
                pairingFixture(pem: File('$fixture/ca.pem').readAsStringSync()),
              ),
            ),
    );
  }

  test(
    'actual firmware certificate builder interoperates with Dart TLS and scanned root',
    () async {
      final (service, bundle) = await server();
      service.listen((request) {
        expect(
          request.headers.value('authorization'),
          'Bearer ${bundle.token}',
        );
        request.response.write('{"ok":true}');
        request.response.close();
      }, onError: (Object _) {});
      final client = await createPairedClient(
        bundle.config('https://192.168.1.50'),
        connect: (_, _) => Socket.startConnect('127.0.0.1', service.port),
      );
      addTearDown(client.close);
      final response = await client.get(
        Uri.https(bundle.identity.hostname, '/test'),
        headers: {'Authorization': 'Bearer ${bundle.token}'},
      );
      expect(response.statusCode, 200);
      expect(jsonDecode(response.body)['ok'], true);
    },
    skip: !available,
  );
  test(
    'another board root is rejected before any authenticated HTTP request',
    () async {
      final (service, _) = await server();
      var requests = 0;
      service.listen((request) {
        requests++;
        request.response.close();
      }, onError: (Object _) {});
      final other = PairingBundle.parse(
        jsonEncode(
          pairingFixture(pem: File('$fixture/other-ca.pem').readAsStringSync()),
        ),
      );
      final client = await createPairedClient(
        other.config('https://192.168.1.50'),
        connect: (_, _) => Socket.startConnect('127.0.0.1', service.port),
      );
      addTearDown(client.close);
      await expectLater(
        client.get(Uri.https(other.identity.hostname, '/test')),
        throwsA(isA<HandshakeException>()),
      );
      expect(requests, 0);
    },
    skip: !available,
  );
  test('a trusted root cannot override the QR hostname', () async {
    final (service, _) = await server();
    var requests = 0;
    service.listen((request) {
      requests++;
      request.response.close();
    }, onError: (Object _) {});
    final other = PairingBundle.parse(
      jsonEncode(
        pairingFixture(
          mac: 'aabbccddee99',
          pem: File('$fixture/ca.pem').readAsStringSync(),
        ),
      ),
    );
    final client = await createPairedClient(
      other.config('https://192.168.1.50'),
      connect: (_, _) => Socket.startConnect('127.0.0.1', service.port),
    );
    addTearDown(client.close);
    await expectLater(
      client.get(Uri.https(other.identity.hostname, '/test')),
      throwsA(isA<HandshakeException>()),
    );
    expect(requests, 0);
  }, skip: !available);
  test(
    'the paired transport blocks unexpected hostnames before opening a socket',
    () async {
      final (_, bundle) = await server();
      var dials = 0;
      final client = await createPairedClient(
        bundle.config('https://192.168.1.50'),
        connect: (_, _) async {
          dials++;
          throw StateError('Must not dial');
        },
      );
      addTearDown(client.close);
      await expectLater(
        client.send(http.Request('GET', Uri.https('example.com', '/'))),
        throwsA(anything),
      );
      expect(dials, 0);
    },
    skip: !available,
  );
}
