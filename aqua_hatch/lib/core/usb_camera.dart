import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'camera.dart';

// LDPlayer's host-loopback alias, verified on this computer. The receiver is
// bound to Windows 127.0.0.1; no router/LAN camera address is used.
const usbCameraBridgeUrl = 'http://172.16.1.2:8771';

class UsbCameraClient {
  final http.Client _client;
  final Uri _base;
  bool _closed = false;
  UsbCameraClient({http.Client? client, String baseUrl = usbCameraBridgeUrl})
    : _client = client ?? http.Client(),
      _base = Uri.parse(baseUrl) {
    if (_base.scheme != 'http' ||
        !{'172.16.1.2', '127.0.0.1', 'localhost'}.contains(_base.host) ||
        _base.port != 8771 ||
        _base.userInfo.isNotEmpty ||
        (_base.path.isNotEmpty && _base.path != '/') ||
        _base.hasQuery ||
        _base.hasFragment) {
      throw ArgumentError('USB camera must use the local computer receiver');
    }
  }
  Future<http.Response> _get(String path, int limit) async {
    if (_closed) throw StateError('ปิดการรับภาพ USB แล้ว');
    final request = http.Request('GET', _base.resolve(path))
      ..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 4));
    if ((response.contentLength ?? 0) > limit) {
      throw StateError('ข้อมูลกล้อง USB ใหญ่เกินกำหนด');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 4),
    )) {
      if (_closed) throw StateError('ปิดการรับภาพ USB แล้ว');
      if (bytes.length + chunk.length > limit) {
        throw StateError('ข้อมูลกล้อง USB ใหญ่เกินกำหนด');
      }
      bytes.addAll(chunk);
    }
    if (response.statusCode != 200) {
      throw StateError('ยังรับภาพ USB ไม่ได้ เปิดตัวรับภาพบนคอมและตรวจสาย USB');
    }
    return http.Response.bytes(
      bytes,
      response.statusCode,
      headers: response.headers,
    );
  }

  Future<DeviceCameraStatus> status() async {
    final response = await _get('/status', 16384);
    final data =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (data['transport'] != 'usb-uart' || data['wifi_mode'] != 0) {
      throw StateError('ปลายทางไม่ใช่กล้อง USB ที่ปิด Wi-Fi');
    }
    final at = (data['last_frame_time'] as num?)?.toDouble() ?? 0;
    final fresh = (DateTime.now().millisecondsSinceEpoch / 1000 - at).abs() < 3;
    return DeviceCameraStatus(
      cameraId: 'usb-ov5640',
      configured: data['camera_ready'] == true,
      online: data['connected'] == true && fresh,
      lastSeen: DateTime.fromMillisecondsSinceEpoch((at * 1000).round()),
      message: data['connected'] == true && fresh
          ? 'กล้อง USB พร้อมใช้งาน · Wi-Fi ปิดอยู่'
          : 'เปิดตัวรับภาพ USB บนคอม และปิด Serial Monitor',
    );
  }

  Future<DeviceCapture> capture(
    String id, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async {
    if (cancelled?.call() == true) throw StateError('ยกเลิกรับภาพ USB แล้ว');
    onProgress?.call('กำลังรับภาพจากสาย USB…');
    final response = await _get('/snapshot.jpg', 512 * 1024);
    if (cancelled?.call() == true) throw StateError('ยกเลิกรับภาพ USB แล้ว');
    final bytes = response.bodyBytes;
    final sequence = int.tryParse(
      response.headers['x-aquahatch-sequence'] ?? '',
    );
    final seconds = double.tryParse(
      response.headers['x-aquahatch-captured-at'] ?? '',
    );
    if (response.headers['x-aquahatch-transport'] != 'usb-uart' ||
        response.headers['content-type']?.split(';').first != 'image/jpeg' ||
        bytes.length < 4 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9 ||
        response.headers['x-aquahatch-sha256'] !=
            sha256.convert(bytes).toString() ||
        sequence == null ||
        sequence < 1 ||
        seconds == null ||
        !seconds.isFinite ||
        (DateTime.now().millisecondsSinceEpoch / 1000 - seconds).abs() > 3) {
      throw StateError('ภาพ USB ไม่ครบ หมดอายุ หรือข้อมูลตรวจสอบไม่ตรง');
    }
    return DeviceCapture(
      id: id,
      cameraId: 'usb-ov5640',
      receivedAt: DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()),
      bytes: bytes,
    );
  }

  Stream<DeviceCapture> frames() async* {
    var frame = 0;
    while (!_closed) {
      try {
        final photo = await capture('usb-preview-${frame++}');
        if (_closed) return;
        yield photo;
      } catch (_) {
        if (_closed) return;
        rethrow;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  void close() {
    _closed = true;
    _client.close();
  }
}
