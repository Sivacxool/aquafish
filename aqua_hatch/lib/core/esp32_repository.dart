import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'camera.dart';
import 'device_tls_client.dart';
import 'models.dart';
import 'repository.dart';

class Esp32Repository implements DeviceRepository {
  final ConnectionConfig config;
  final String token;
  final http.Client? _providedClient;
  final Duration pollInterval;
  final _stream = StreamController<Telemetry>.broadcast();
  Future<http.Client>? _creating;
  http.Client? _client;
  DeviceSettings? _settings;
  DateTime? _boardTime;
  Timer? _timer;
  bool _closed = false, _polling = false;
  Esp32Repository(
    this.config,
    this.token, {
    http.Client? client,
    this.pollInterval = const Duration(seconds: 2),
  }) : _providedClient = client;
  @override
  Stream<Telemetry> get telemetry => _stream.stream;
  @override
  DeviceSettings? get reportedSettings => _settings;
  Future<http.Client> _ensureClient() async {
    _creating ??= _providedClient != null
        ? Future.value(_providedClient)
        : createDeviceClient(config);
    final client = await _creating!;
    if (_closed) {
      client.close();
      throw StateError('ปิดการเชื่อมต่อแล้ว');
    }
    return _client = client;
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    if (_closed) throw StateError('ปิดการเชื่อมต่อแล้ว');
    final uri = Uri.https(
      deviceTlsHostname,
      '/api/v1/devices/${config.deviceId}$suffix',
    );
    final request = http.Request(method, uri)..followRedirects = false;
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'X-AquaHatch-Time':
          '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
    });
    if (body != null) request.body = jsonEncode(body);
    final client = await _ensureClient();
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 8)),
    ).timeout(const Duration(seconds: 8));
    final Object? parsed;
    try {
      parsed = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw StateError('บอร์ดตอบข้อมูลไม่ถูกต้อง');
    }
    if (parsed is! Map<String, dynamic>) {
      throw StateError('บอร์ดตอบข้อมูลไม่ถูกต้อง');
    }
    if (response.statusCode != 200) {
      throw StateError(
        parsed['detail']?.toString() ?? 'บอร์ดตอบ HTTP ${response.statusCode}',
      );
    }
    return parsed;
  }

  Future<void> _refresh() async {
    final data = await _request('GET', '');
    if (_closed) return;
    if (data['backend'] != 'esp32-local' ||
        data['protocol_version'] != 1 ||
        data['device_id'] != config.deviceId) {
      throw StateError('ข้อมูลตอบกลับไม่ตรงกับบอร์ด ESP32 ที่เลือก');
    }
    final raw = data['telemetry'];
    if (raw is! Map) throw StateError('ไม่ได้รับสถานะบอร์ด');
    final telemetry = Map<String, dynamic>.from(raw);
    final capabilities = data['capabilities'];
    telemetry['hardware_ready'] =
        capabilities is Map &&
        capabilities['hardware_control'] == true &&
        telemetry['hardware_ready'] == true;
    final settings = data['config'];
    if (settings is Map) {
      _settings = DeviceSettings.fromJson(Map<String, dynamic>.from(settings));
    }
    final boardTime = DateTime.tryParse(
      telemetry['timestamp']?.toString() ?? '',
    );
    if (boardTime == null || boardTime.year < 2025) {
      throw StateError('นาฬิกาบอร์ดยังไม่พร้อม');
    }
    _boardTime = boardTime.toUtc();
    // This authenticated, uncached GET reads the current device snapshot.
    // Use receipt time for polling freshness; phone and NTP clocks may differ.
    // Historical sensor samples must retain their own acquisition timestamps.
    telemetry['timestamp'] = DateTime.now().toUtc().toIso8601String();
    final reading = Telemetry.fromJson(telemetry);
    if (!_stream.isClosed) _stream.add(reading);
  }

  @override
  Future<void> connect() async {
    if (!config.localEsp32 ||
        config.validate() != null ||
        token.trim().isEmpty) {
      throw StateError('ตรวจ URL บอร์ด รหัสเครื่อง และรหัสเข้าถึง');
    }
    _polling = true;
    try {
      await _refresh();
    } finally {
      _polling = false;
      // The first request can race a board reboot or Wi-Fi association. Keep
      // retrying after it fails, just as after a later polling disconnect.
      if (!_closed) {
        _timer?.cancel();
        _timer = Timer.periodic(pollInterval, (_) async {
          if (_closed || _polling) return;
          _polling = true;
          try {
            await _refresh();
          } catch (_) {
            if (!_closed && !_stream.isClosed) {
              _stream.addError(
                StateError('ติดต่อบอร์ดไม่ได้ กำลังลองเชื่อมต่อใหม่'),
              );
            }
          } finally {
            _polling = false;
          }
        });
      }
    }
  }

  @override
  Future<CommandResult> command(
    String action,
    Map<String, dynamic> payload,
  ) async {
    // Obtain the board clock immediately before issuing a short-lived command.
    // Do not extend the server's expiry window to hide clock differences.
    await _refresh();
    final id = createId();
    final data = await _request('POST', '/commands', {
      'command_id': id,
      'action': action,
      'payload': payload,
      'expires_at_unix': _boardTime!.millisecondsSinceEpoch ~/ 1000 + 10,
    });
    if (data['command_id'] != id) {
      throw StateError('รหัสคำตอบจากบอร์ดไม่ตรงกับคำสั่ง');
    }
    return CommandResult(
      id: id,
      applied: data['status'] == 'applied',
      message: data['message'] as String? ?? 'บอร์ดตอบกลับแล้ว',
    );
  }

  @override
  Future<DeviceCameraStatus> cameraStatus() async =>
      DeviceCameraStatus.fromJson(await _request('GET', '/camera'));
  @override
  Future<DeviceCapture> capture(
    String requestId, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async {
    throw StateError('ยังไม่ติดตั้งและยืนยันขากล้อง OV5640 ของบอร์ดนี้');
  }

  @override
  Future<AnalysisResult> analyze(
    Uint8List bytes,
    String filename,
    bool video,
  ) async {
    throw StateError('การวิเคราะห์ AI ต้องใช้ Gateway ที่ติดตั้งโมเดลลูกปลา');
  }

  @override
  Future<AnalysisResult> analyzeCapture(String captureId) async {
    throw StateError('การวิเคราะห์ AI ต้องใช้ Gateway ที่ติดตั้งโมเดลลูกปลา');
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    _timer?.cancel();
    _client?.close();
    await _stream.close();
  }
}
