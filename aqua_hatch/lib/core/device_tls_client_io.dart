import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'models.dart';

const deviceTlsHostname = 'aquahatch-117c.local';

Future<http.Client> createDeviceClient(ConnectionConfig config) async {
  if (!config.localEsp32 || config.validate() != null) {
    throw StateError('การเชื่อมต่อบอร์ดไม่ถูกต้อง');
  }
  final address = Uri.parse(config.baseUrl).host;
  final ca = await rootBundle.load('assets/device/device_ca.pem');
  final context = SecurityContext(withTrustedRoots: false)
    ..setTrustedCertificatesBytes(
      ca.buffer.asUint8List(ca.offsetInBytes, ca.lengthInBytes),
    );
  final client = HttpClient(context: context)
    ..connectionTimeout = const Duration(seconds: 6)
    ..idleTimeout = const Duration(seconds: 8)
    ..findProxy = (_) => 'DIRECT';
  // Use the configured LAN IP for the socket, while TLS still verifies the
  // device DNS identity and its own CA. No certificate-validation bypass.
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    if (uri.scheme != 'https' ||
        uri.host != deviceTlsHostname ||
        uri.port != 443 ||
        proxyHost != null) {
      throw StateError('ปลายทางไม่ตรงกับบอร์ดที่จับคู่ไว้');
    }
    // A custom connectionFactory supplies the final transport: HttpClient does
    // not upgrade this socket to TLS for us. Verify the paired DNS identity
    // while routing the underlying TCP socket to the configured LAN address.
    final tcp = await Socket.startConnect(address, 443);
    Socket? active;
    final secure = tcp.socket.then((socket) async {
      active = socket;
      try {
        final tls = await SecureSocket.secure(
          socket,
          host: deviceTlsHostname,
          context: context,
        );
        active = tls;
        return tls;
      } catch (_) {
        socket.destroy();
        rethrow;
      }
    });
    return ConnectionTask.fromSocket(secure, () {
      tcp.cancel();
      active?.destroy();
    });
  };
  return IOClient(client);
}
