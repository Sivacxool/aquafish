import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'camera.dart';
import 'device_tls_client.dart';
import 'models.dart';
import 'paired_camera.dart';
import 'remote_relay.dart';

class DirectCameraClient {
  final ConnectionConfig config;
  final String token;
  final http.Client? _provided;
  http.Client? _client;
  Future<void> _requests = Future<void>.value();
  bool _closed = false;
  int? _boardTime;
  late final RemoteRelay? _relay;
  DateTime? _retryLanAt;

  DirectCameraClient(
    this.config,
    this.token, {
    http.Client? client,
    http.Client? relayClient,
  }) : _provided = client {
    _relay = RemoteRelay.maybe(config, token, client: relayClient);
  }

  void _check(bool Function()? cancelled) {
    if (_closed || cancelled?.call() == true) {
      throw StateError('ยกเลิกการรับภาพแล้ว');
    }
  }

  Future<http.Response> _send(
    String method,
    String suffix, {
    Object? body,
    bool Function()? cancelled,
    bool viaRelay = false,
    bool lanProbe = false,
  }) {
    // The camera has limited TLS sockets and RAM. Finish reading one response
    // before polling status or starting the next capture request.
    final response = _requests.then(
      (_) => _sendWithRetry(
        method,
        suffix,
        body: body,
        cancelled: cancelled,
        viaRelay: viaRelay,
        lanProbe: lanProbe,
      ),
    );
    _requests = response.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return response;
  }

  Future<http.Response> _sendWithRetry(
    String method,
    String suffix, {
    Object? body,
    bool Function()? cancelled,
    bool viaRelay = false,
    bool lanProbe = false,
  }) async {
    for (var attempt = 0; ; attempt++) {
      try {
        return await _sendNow(
          method,
          suffix,
          body: body,
          cancelled: cancelled,
          viaRelay: viaRelay,
          lanProbe: lanProbe,
        );
      } catch (error) {
        if (lanProbe ||
            method != 'GET' ||
            attempt != 0 ||
            (error is! TimeoutException && error is! http.ClientException)) {
          rethrow;
        }
        _check(cancelled);
        if (!viaRelay && _provided == null) {
          _client?.close();
          _client = null;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
        _check(cancelled);
      }
    }
  }

  Future<http.Response> _sendNow(
    String method,
    String suffix, {
    Object? body,
    bool Function()? cancelled,
    bool viaRelay = false,
    bool lanProbe = false,
  }) async {
    _check(cancelled);
    if (config.demo ||
        !config.localEsp32 ||
        config.validate() != null ||
        token.isEmpty) {
      throw StateError('ตรวจที่อยู่และรหัสจับคู่กล้อง');
    }
    final http.StreamedResponse streamed;
    if (viaRelay) {
      streamed = await _relay!.send(method, '/camera$suffix', body: body);
    } else {
      final client = _client ??=
          _provided ??
          await createPairedClient(
            config,
            hostname: cameraTlsHostname,
            caAsset: cameraCaAsset,
            connectionTimeout: const Duration(seconds: 15),
          );
      _check(cancelled);
      final request =
          http.Request(
              method,
              Uri.https(
                config.identity?.hostname ?? cameraTlsHostname,
                '/api/v1/devices/${config.deviceId}/camera$suffix',
              ),
            )
            ..followRedirects = false
            ..persistentConnection = true;
      request.headers.addAll({
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-AquaHatch-Time':
            '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
      });
      if (body != null) request.body = jsonEncode(body);
      streamed = await client
          .send(request)
          .timeout(
            Duration(
              seconds: lanProbe
                  ? 3
                  : method == 'POST'
                  ? 40
                  : 20,
            ),
          );
    }
    final limit = suffix.endsWith('/image') ? 4 * 1024 * 1024 : 32768;
    if ((streamed.contentLength ?? 0) > limit) {
      throw StateError('ข้อมูลจากกล้องใหญ่เกินกำหนด');
    }
    final chunks = <int>[];
    await for (final chunk in streamed.stream.timeout(
      const Duration(seconds: 15),
    )) {
      _check(cancelled);
      if (chunks.length + chunk.length > limit) {
        throw StateError('ข้อมูลจากกล้องใหญ่เกินกำหนด');
      }
      chunks.addAll(chunk);
    }
    _check(cancelled);
    final response = http.Response.bytes(
      chunks,
      streamed.statusCode,
      headers: streamed.headers,
    );
    if (response.statusCode != 200 && response.statusCode != 202) {
      var detail = 'กล้องตอบ HTTP ${response.statusCode}';
      try {
        detail =
            (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['detail']
                ?.toString() ??
            detail;
      } catch (_) {}
      throw StateError(detail);
    }
    return response;
  }

  Map<String, dynamic> _json(http.Response response) {
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> ||
        data['backend'] != 'esp32-camera' ||
        data['device_id'] != config.deviceId ||
        data['camera_id'] != (config.identity?.deviceId ?? cameraDeviceId)) {
      throw StateError('ข้อมูลไม่ตรงกับบอร์ดกล้องที่จับคู่');
    }
    final clock = data['server_time_unix'];
    if (clock is int && clock >= 1735689600) _boardTime = clock;
    return data;
  }

  Future<(DeviceCameraStatus, bool)> _selectCamera({
    bool Function()? cancelled,
  }) async {
    final relay = _relay;
    final retry = _retryLanAt;
    if (relay == null || retry == null || !DateTime.now().isBefore(retry)) {
      try {
        final local = _json(
          await _send('GET', '', cancelled: cancelled, lanProbe: relay != null),
        );
        _retryLanAt = null;
        return (DeviceCameraStatus.fromJson(local), false);
      } catch (_) {
        _check(cancelled);
        if (relay == null) rethrow;
        if (_provided == null) {
          _client?.close();
          _client = null;
        }
        _retryLanAt = DateTime.now().add(const Duration(seconds: 30));
      }
    }
    final online = _json(
      await _send('GET', '', cancelled: cancelled, viaRelay: true),
    );
    return (DeviceCameraStatus.fromJson(online), true);
  }

  Future<DeviceCameraStatus> status() async => (await _selectCamera()).$1;

  Future<DeviceCapture> capture(
    String id, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async {
    _check(cancelled);
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(id)) {
      throw StateError('รหัสถ่ายภาพไม่ถูกต้อง');
    }
    onProgress?.call('กำลังเปิดแฟลชและปรับแสงเพื่อถ่ายภาพความละเอียดสูง…');
    final (camera, viaRelay) = await _selectCamera(cancelled: cancelled);
    _check(cancelled);
    if (_boardTime == null) throw StateError('นาฬิกากล้องยังไม่พร้อม');
    Map<String, dynamic> job;
    try {
      job = _json(
        await _send(
          'POST',
          '/captures',
          body: {
            'capture_id': id,
            'expires_at_unix': _boardTime! + 30,
            'flash': true,
            'flash_duty': 64,
            'autofocus': camera.requestAutofocus,
            'resolution': camera.captureResolution,
            'jpeg_quality': 10,
            'warmup_ms': 1800,
          },
          cancelled: cancelled,
          viaRelay: viaRelay,
        ),
      );
    } on TimeoutException {
      // A lost acknowledgement must not trigger another exposure with a new ID.
      job = _json(
        await _send(
          'GET',
          '/captures/$id',
          cancelled: cancelled,
          viaRelay: viaRelay,
        ),
      );
    } on http.ClientException {
      job = _json(
        await _send(
          'GET',
          '/captures/$id',
          cancelled: cancelled,
          viaRelay: viaRelay,
        ),
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (true) {
      _check(cancelled);
      if (job['capture_id'] != id) {
        throw StateError('ภาพตอบกลับไม่ตรงกับคำสั่ง');
      }
      if (job['status'] == 'captured') break;
      if (job['status'] == 'failed' ||
          job['status'] == 'expired' ||
          DateTime.now().isAfter(deadline)) {
        throw StateError(job['message']?.toString() ?? 'กล้องถ่ายภาพไม่สำเร็จ');
      }
      await Future<void>.delayed(Duration(milliseconds: viaRelay ? 1400 : 700));
      job = _json(
        await _send(
          'GET',
          '/captures/$id',
          cancelled: cancelled,
          viaRelay: viaRelay,
        ),
      );
    }
    onProgress?.call('กำลังรับภาพ JPEG จากบอร์ดกล้อง…');
    final image = await _send(
      'GET',
      '/captures/$id/image',
      cancelled: cancelled,
      viaRelay: viaRelay,
    );
    final bytes = image.bodyBytes;
    if (image.headers['content-type']?.split(';').first != 'image/jpeg' ||
        bytes.length < 4 ||
        bytes[0] != 0xff ||
        bytes[1] != 0xd8 ||
        bytes[bytes.length - 2] != 0xff ||
        bytes.last != 0xd9 ||
        job['bytes'] != bytes.length ||
        job['sha256'] != sha256.convert(bytes).toString()) {
      throw StateError('ภาพจากกล้องไม่ครบหรือข้อมูลตรวจสอบไม่ตรง');
    }
    final received = DateTime.tryParse(job['received_at']?.toString() ?? '');
    if (received == null) throw StateError('ภาพไม่มีเวลาที่บอร์ดยืนยัน');
    return DeviceCapture(
      id: id,
      cameraId: config.identity?.deviceId ?? cameraDeviceId,
      receivedAt: received.toLocal(),
      bytes: bytes,
      width: job['width'] is int ? job['width'] as int : null,
      height: job['height'] is int ? job['height'] as int : null,
      flashUsed: job['flash_used'] is bool ? job['flash_used'] as bool : null,
      sensor: job['sensor'] is String ? job['sensor'] as String : null,
    );
  }

  void close() {
    _closed = true;
    _client?.close();
    _relay?.close();
  }
}
