import 'dart:convert';
import 'dart:io';

Map<String, dynamic> pairingFixture({
  String kind = 's3',
  String mac = 'aabbccddee01',
  String? pem,
}) {
  final ca = pem ?? File('assets/device/device_ca.pem').readAsStringSync();
  final encoded = ca.replaceAll(RegExp(r'-----[^-]+-----|\s'), '');
  final id = '${kind == 's3' ? 's3' : 'cam'}-$mac';
  return {
    'format': 'aquahatch-pairing',
    'version': 1,
    'kind': kind,
    'id': id,
    'host': 'aquahatch-$id.local',
    'ssid':
        'AquaHatch-${kind == 's3' ? 'S3' : 'CAM'}-${mac.substring(6).toUpperCase()}',
    'token': List.filled(32, '01').join(),
    'ca': base64Url.encode(base64.decode(encoded)).replaceAll('=', ''),
  };
}
