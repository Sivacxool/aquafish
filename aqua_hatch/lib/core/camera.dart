import 'dart:typed_data';

class DeviceCameraStatus {
  final String cameraId, message;
  final String sensor;
  final int? captureWidth, captureHeight;
  final bool? autofocusSupported;
  final bool configured, online;
  final DateTime? lastSeen;
  const DeviceCameraStatus({
    this.cameraId = '',
    this.configured = false,
    this.online = false,
    this.lastSeen,
    this.sensor = '',
    this.captureWidth,
    this.captureHeight,
    this.autofocusSupported,
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
        sensor: json['sensor'] as String? ?? '',
        captureWidth: json['default_capture_width'] as int?,
        captureHeight: json['default_capture_height'] as int?,
        autofocusSupported: json['autofocus_supported'] as bool?,
      );
  bool get ready => configured && online;
  String get captureResolution => switch (sensor) {
    'OV3660' => '3mp',
    'OV2640' => 'uxga',
    _ => '5mp', // Backwards compatibility with paired camera firmware 0.9.
  };
  bool get requestAutofocus =>
      autofocusSupported ?? (sensor != 'OV3660' && sensor != 'OV2640');
  String get description => [
    if (sensor.isNotEmpty) sensor,
    if (captureWidth != null && captureHeight != null)
      '$captureWidth × $captureHeight พิกเซล',
  ].join(' · ');
}

class DeviceCapture {
  final String id, cameraId;
  final DateTime receivedAt;
  final Uint8List bytes;
  final int? width, height;
  final bool? flashUsed;
  final String? sensor;
  const DeviceCapture({
    required this.id,
    required this.cameraId,
    required this.receivedAt,
    required this.bytes,
    this.width,
    this.height,
    this.flashUsed,
    this.sensor,
  });
}
