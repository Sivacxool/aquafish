import 'package:http/http.dart' as http;
import 'models.dart';

const deviceTlsHostname = 'aquahatch-117c.local';
Future<http.Client> createDeviceClient(ConnectionConfig config) async {
  throw StateError('เชื่อมบอร์ดโดยตรงด้วยแอป Android รุ่น 0.5 บนมือถือ');
}

Future<http.Client> createPairedClient(
  ConnectionConfig config, {
  String hostname = deviceTlsHostname,
  String caAsset = 'assets/device/device_ca.pem',
  Duration connectionTimeout = const Duration(seconds: 6),
}) async {
  throw StateError('เชื่อมกล้องโดยตรงด้วยแอป Android');
}
