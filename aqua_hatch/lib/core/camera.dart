import 'dart:typed_data';

class DeviceCameraStatus {
  final String cameraId, message;
  final bool configured, online;
  final DateTime? lastSeen;
  const DeviceCameraStatus({
    this.cameraId = '',
    this.configured = false,
    this.online = false,
    this.lastSeen,
    required this.message,
  });
  factory DeviceCameraStatus.fromJson(Map<String, dynamic> json) =>
      DeviceCameraStatus(
        cameraId: json['camera_id'] as String? ?? '',
        configured: json['configured'] == true,
        online: json['online'] == true,
        lastSeen: DateTime.tryParse(
          json['last_seen'] as String? ?? '',
        )?.toLocal(),
        message: json['message'] as String? ?? 'ยังไม่ทราบสถานะกล้อง',
      );
  bool get ready => configured && online;
}

class DeviceCapture {
  final String id, cameraId;
  final DateTime receivedAt;
  final Uint8List bytes;
  const DeviceCapture({
    required this.id,
    required this.cameraId,
    required this.receivedAt,
    required this.bytes,
  });
}
