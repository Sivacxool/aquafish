import 'dart:convert';
import 'device_identity.dart';
import 'models.dart';

class PairingBundle {
  final DeviceIdentity identity;
  final String token;
  const PairingBundle(this.identity, this.token);
  factory PairingBundle.parse(String raw, {String? expectedKind}) {
    if (raw.length > 4096) throw const FormatException('QR มีข้อมูลมากเกินไป');
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.trim());
    } catch (_) {
      throw const FormatException(
        'อ่าน QR จับคู่ไม่ได้ ตรวจว่าเป็นบัตร AquaHatch',
      );
    }
    try {
      final value = decoded;
      if (value is! Map<String, dynamic> ||
          value['format'] != 'aquahatch-pairing' ||
          value['version'] is! int ||
          value['version'] != 1) {
        throw const FormatException(
          'ใช้ QR จับคู่ที่ได้จากบอร์ด AquaHatch เท่านั้น',
        );
      }
      const fields = {
        'format',
        'version',
        'kind',
        'id',
        'host',
        'ssid',
        'ca',
        'token',
      };
      if (value.keys.toSet().difference(fields).isNotEmpty ||
          !fields.every(value.containsKey)) {
        throw const FormatException('รูปแบบ QR จับคู่ไม่ถูกต้อง');
      }
      final identity = DeviceIdentity.fromJson(value), token = value['token'];
      final invalid = identity.validate();
      if (invalid != null) throw FormatException(invalid);
      if (token is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
        throw const FormatException('รหัสจับคู่ใน QR ไม่ถูกต้อง');
      }
      if (expectedKind != null && identity.kind != expectedKind) {
        throw FormatException(
          expectedKind == 's3'
              ? 'นี่คือ QR กล้อง ให้เลือกเพิ่มกล้องแทน'
              : 'นี่คือ QR บอร์ดหลัก ให้เลือกเพิ่มบอร์ดหลักแทน',
        );
      }
      return PairingBundle(identity, token);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'อ่าน QR จับคู่ไม่ได้ ตรวจว่าเป็นบัตร AquaHatch',
      );
    }
  }
  ConnectionConfig config(String url) => ConnectionConfig(
    demo: false,
    localEsp32: true,
    baseUrl: url,
    deviceId: identity.deviceId,
    identity: identity,
  );
  // Never expose token through toString or diagnostics.
  @override
  String toString() => 'PairingBundle(${identity.kind}, ${identity.deviceId})';
}
