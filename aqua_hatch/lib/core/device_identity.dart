import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class DeviceIdentity {
  final String kind, deviceId, hostname, setupSsid, caDer;
  const DeviceIdentity({
    required this.kind,
    required this.deviceId,
    required this.hostname,
    required this.setupSsid,
    required this.caDer,
  });
  Uint8List get caBytes => base64Url.decode(base64Url.normalize(caDer));
  String get fingerprint => sha256.convert(caBytes).toString();
  String get stableKey => '$kind:$deviceId:$fingerprint';
  String get currentSetupSsid =>
      'Smart Catfish System-${kind == 's3' ? 'B' : 'C'}-${deviceId.substring(deviceId.length - 6).toUpperCase()}';
  String get caPem {
    final encoded = base64.encode(caBytes);
    final lines = [
      for (var i = 0; i < encoded.length; i += 64)
        encoded.substring(i, (i + 64).clamp(0, encoded.length)),
    ];
    return '-----BEGIN CERTIFICATE-----\n${lines.join('\n')}\n-----END CERTIFICATE-----\n';
  }

  String? validate() {
    if (!['s3', 'camera'].contains(kind)) {
      return 'QR ไม่ใช่บอร์ดหรือกล้อง AquaHatch ที่รองรับ';
    }
    final prefix = kind == 's3' ? 's3' : 'cam';
    final match = RegExp('^$prefix-([0-9a-f]{12})\$').firstMatch(deviceId);
    if (match == null || hostname != 'aquahatch-$deviceId.local') {
      return 'รหัสและชื่อบอร์ดใน QR ไม่ตรงกัน';
    }
    final expected =
        'AquaHatch-${kind == 's3' ? 'S3' : 'CAM'}-${match.group(1)!.substring(6).toUpperCase()}';
    final current =
        'Smart Catfish System-${kind == 's3' ? 'B' : 'C'}-${match.group(1)!.substring(6).toUpperCase()}';
    if (setupSsid != expected && setupSsid != current) {
      return 'ชื่อ Wi-Fi ใน QR ไม่ตรงกับบอร์ด';
    }
    if (caDer.length < 200 ||
        caDer.length > 2048 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(caDer)) {
      return 'ใบรับรองใน QR ไม่ถูกต้อง';
    }
    try {
      final bytes = caBytes;
      if (bytes.length < 150 || bytes[0] != 0x30) {
        return 'ใบรับรองใน QR ไม่ใช่ X.509';
      }
      var offset = 2, length = bytes[1];
      if ((length & 0x80) != 0) {
        final count = length & 0x7f;
        if (count < 1 || count > 3 || bytes.length < 2 + count) {
          return 'ใบรับรองใน QR ไม่สมบูรณ์';
        }
        length = 0;
        for (var i = 0; i < count; i++) {
          length = (length << 8) | bytes[2 + i];
        }
        offset += count;
      }
      if (offset + length != bytes.length) {
        return 'ใบรับรองใน QR มีข้อมูลเกินหรือไม่ครบ';
      }
    } catch (_) {
      return 'อ่านใบรับรองจาก QR ไม่ได้';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'id': deviceId,
    'host': hostname,
    'ssid': setupSsid,
    'ca': caDer,
  };
  factory DeviceIdentity.fromJson(Map<String, dynamic> j) => DeviceIdentity(
    kind: j['kind'] as String,
    deviceId: j['id'] as String,
    hostname: j['host'] as String,
    setupSsid: j['ssid'] as String,
    caDer: j['ca'] as String,
  );
}
