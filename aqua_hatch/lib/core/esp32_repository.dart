import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'camera.dart';
import 'device_tls_client.dart';
import 'models.dart';
import 'repository.dart';
import 'remote_relay.dart';

class Esp32Repository implements DeviceRepository {
  final ConnectionConfig config;
  final String token;
  final http.Client? _providedClient;
  final Duration pollInterval;
  late final RemoteRelay? _relay;
  DateTime? _retryLanAt;
  final _stream = StreamController<Telemetry>.broadcast();
  Future<http.Client>? _creating;
  http.Client? _client;
  DeviceSettings? _settings;
  DateTime? _boardTime;
  Timer? _timer;
  bool _closed = false, _polling = false, _commanding = false;
  int _snapshotGeneration = 0;
  Esp32Repository(
    this.config,
    this.token, {
    http.Client? client,
    http.Client? relayClient,
    this.pollInterval = const Duration(seconds: 2),
  }) : _providedClient = client {
    _relay = RemoteRelay.maybe(config, token, client: relayClient);
  }
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
      config.identity?.hostname ?? deviceTlsHostname,
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
    final http.Response response;
    try {
      response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            Duration(
              seconds: _relay != null && method == 'GET' && suffix.isEmpty
                  ? 4
                  : 8,
            ),
          );
    } catch (_) {
      // Drop sockets from the previous network. The next GET creates a new
      // transport. A failed POST is surfaced to the caller and never replayed.
      if (_providedClient == null && identical(_client, client)) {
        _creating = null;
        _client = null;
        client.close();
      }
      rethrow;
    }
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

  Future<void> _refresh({bool allowRelay = true}) async {
    final generation = _snapshotGeneration;
    void accept(Map<String, dynamic> snapshot, {int? ageMs}) {
      if (generation == _snapshotGeneration) _accept(snapshot, ageMs: ageMs);
    }

    final relay = allowRelay ? _relay : null;
    final retry = _retryLanAt;
    if (relay == null || retry == null || !DateTime.now().isBefore(retry)) {
      try {
        accept(await _request('GET', ''));
        if (generation == _snapshotGeneration) _retryLanAt = null;
        return;
      } catch (_) {
        if (_closed || generation != _snapshotGeneration || relay == null) {
          rethrow;
        }
        _retryLanAt = DateTime.now().add(const Duration(seconds: 30));
      }
    }
    final remote = await relay.readJson('');
    final age = remote['age_ms'];
    final snapshot = remote['snapshot'];
    if (age is! int ||
        age < 0 ||
        age >= 45000 ||
        snapshot is! Map<String, dynamic>) {
      throw StateError('ข้อมูลจากบอร์ดหมดอายุ');
    }
    accept(snapshot, ageMs: age);
  }

  void _accept(Map<String, dynamic> data, {int? ageMs}) {
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
    if (ageMs == null &&
        (capabilities is! Map || capabilities['pump_fill'] != true)) {
      telemetry.remove('fill');
    }
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
    if (ageMs == null) _boardTime = boardTime.toUtc();
    // This authenticated, uncached GET reads the current device snapshot.
    // Use receipt time for polling freshness; phone and NTP clocks may differ.
    // Historical sensor samples must retain their own acquisition timestamps.
    final receivedAt = DateTime.now().toUtc().subtract(
      Duration(milliseconds: ageMs ?? 0),
    );
    telemetry['timestamp'] = receivedAt.toIso8601String();
    telemetry['via_relay'] = ageMs != null;
    if (ageMs != null) telemetry['hardware_ready'] = false;
    if (ageMs == null &&
        (capabilities is! Map || capabilities['ett_manual_control'] != true)) {
      telemetry.remove('ett_control');
    }
    final controls = telemetry['ett_control'];
    if (controls is Map) {
      // The board uses its monotonic clock. Anchor the remaining time to
      // receipt (or to upload age for read-only remote snapshots).
      final remaining = controls['manual_remaining_ms'];
      final active =
          controls['io_ready'] == true &&
          telemetry['mode'] == 'manual' &&
          remaining is int &&
          remaining > (ageMs ?? 0) &&
          remaining <= 300000;
      telemetry['mode'] = active ? 'manual' : 'auto';
      telemetry['manual_until'] = active
          ? receivedAt.add(Duration(milliseconds: remaining)).toIso8601String()
          : null;
    }
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
        _timer = Timer.periodic(pollInterval, (_) => unawaited(pollNow()));
      }
    }
  }

  Future<void> pollNow({bool preferLan = false}) async {
    if (preferLan) _retryLanAt = null;
    if (_closed || _polling || _commanding) return;
    _polling = true;
    final generation = _snapshotGeneration;
    try {
      await _refresh();
    } catch (error) {
      if (!_closed && !_stream.isClosed && generation == _snapshotGeneration) {
        _stream.addError(error);
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<CommandResult> command(
    String action,
    Map<String, dynamic> payload,
  ) async {
    if (_commanding) throw StateError('มีคำสั่งกำลังดำเนินการ');
    _commanding = true;
    // A GET already in flight must not overwrite the command's newer snapshot.
    ++_snapshotGeneration;
    try {
      // A LAN-only GET establishes the board clock for a short-lived POST.
      await _refresh(allowRelay: false);
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
      final applied = data['status'] == 'applied';
      final snapshot = data['snapshot'];
      if (applied && snapshot is Map<String, dynamic>) {
        _accept(snapshot);
      }
      return CommandResult(
        id: id,
        applied: applied,
        message: data['message'] as String? ?? 'บอร์ดตอบกลับแล้ว',
      );
    } finally {
      _commanding = false;
    }
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
    _relay?.close();
    await _stream.close();
  }
}
