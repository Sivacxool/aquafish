import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'device_tls_client.dart';
import 'models.dart';
import 'relay_origin.dart';

class RemoteRelay {
  final Uri origin;
  final String deviceId;
  final bool camera;
  final String _reader, _room;
  final http.Client _client;

  RemoteRelay._(
    this.origin,
    this.deviceId,
    this.camera,
    this._reader,
    this._room,
    this._client,
  );

  factory RemoteRelay(
    ConnectionConfig config,
    String token, {
    http.Client? client,
  }) {
    final origin = parseRelayOrigin(config.relayOrigin ?? '');
    if (origin == null ||
        config.identity == null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      throw StateError('ตรวจลิงก์บริการและ QR ของอุปกรณ์');
    }
    String hash(String label, String value) =>
        sha256.convert(utf8.encode(label + value)).toString();
    final writer = hash('aquahatch relay write v1:', token);
    final reader = hash('aquahatch relay read v1:', writer);
    final room = hash('aquahatch relay room v1:', reader);
    return RemoteRelay._(
      origin,
      config.deviceId,
      config.identity!.kind == 'camera',
      reader,
      room,
      client ?? http.Client(),
    );
  }

  static RemoteRelay? maybe(
    ConnectionConfig config,
    String token, {
    http.Client? client,
  }) {
    if (config.relayOrigin == null ||
        config.validate() != null ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) {
      return null;
    }
    return RemoteRelay(config, token, client: client);
  }

  Future<http.StreamedResponse> send(
    String method,
    String suffix, {
    Object? body,
  }) {
    final kind = camera ? 'cameras' : 'readings';
    final request =
        http.Request(method, origin.replace(path: '/v1/$kind/$_room$suffix'))
          ..followRedirects = false
          ..headers['Authorization'] = 'Bearer $_reader';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    return _client.send(request).timeout(const Duration(seconds: 8));
  }

  Future<Map<String, dynamic>> readJson(
    String suffix, {
    bool allowWaiting = false,
  }) async {
    final response = await send('GET', suffix);
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 5),
    )) {
      if (bytes.length + chunk.length > 16384) {
        throw StateError('ข้อมูลจากบริการใหญ่เกินกำหนด');
      }
      bytes.addAll(chunk);
    }
    Object? data;
    try {
      data = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw StateError('บริการส่งข้อมูลไม่ถูกต้อง');
    }
    if (data is! Map<String, dynamic>) {
      throw StateError('บริการส่งข้อมูลไม่ถูกต้อง');
    }
    if (response.statusCode == 200) return data;
    if (response.statusCode == 401) {
      throw StateError('บริการยังไม่ได้อนุญาตอุปกรณ์นี้');
    }
    final waiting =
        response.statusCode == 404 &&
        data['error'] == (camera ? 'camera_unavailable' : 'board_unavailable');
    if (waiting && allowWaiting) return data;
    throw StateError(
      waiting ? 'รออุปกรณ์เชื่อมอินเทอร์เน็ต' : 'ติดต่อบริการไม่สำเร็จ',
    );
  }

  Future<void> verifyAccess() async {
    final data = await readJson(camera ? '/camera' : '', allowWaiting: true);
    if (data['error'] != null) return;
    final snapshot = camera ? data : data['snapshot'];
    if (snapshot is! Map || snapshot['device_id'] != deviceId) {
      throw StateError('บริการส่งข้อมูลของอุปกรณ์คนละตัว');
    }
  }

  void close() => _client.close();
}

Future<void> configureDeviceRelay(
  ConnectionConfig config,
  String token,
  String? origin,
) async {
  if (config.identity == null || !config.localEsp32 || config.demo) {
    throw StateError('จับคู่อุปกรณ์ด้วย QR ก่อน');
  }
  if (origin != null) {
    final relay = RemoteRelay(config.withRelayOrigin(origin), token);
    try {
      await relay.verifyAccess();
    } finally {
      relay.close();
    }
  }

  final client = await createPairedClient(
    config,
    connectionTimeout: const Duration(seconds: 5),
  );
  try {
    final request =
        http.Request(
            'POST',
            Uri.https(
              config.identity!.hostname,
              '/api/v1/devices/${config.deviceId}/remote',
            ),
          )
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-AquaHatch-Time':
                '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          })
          ..body = jsonEncode({'url': origin ?? ''});
    final response = await client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) {
      throw StateError('อัปเดตเฟิร์มแวร์อุปกรณ์ก่อน');
    }
    if (response.statusCode != 200) {
      throw StateError('อุปกรณ์บันทึกบริการไม่สำเร็จ');
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map || data['enabled'] != (origin != null)) {
      throw StateError('อุปกรณ์ยังไม่ยืนยันการตั้งค่า');
    }
  } finally {
    client.close();
  }
}
