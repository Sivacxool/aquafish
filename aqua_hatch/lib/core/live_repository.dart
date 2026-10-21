import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'models.dart';
import 'repository.dart';
import 'camera.dart';

class LiveRepository implements DeviceRepository {
  final ConnectionConfig config;
  final String token;
  final http.Client _client;
  final _stream = StreamController<Telemetry>.broadcast();
  final _pending = <String, Completer<CommandResult>>{};
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retry;
  DeviceSettings? _settings;
  bool _closed = false;
  int _attempt = 0;
  LiveRepository(this.config, this.token, {http.Client? client})
    : _client = client ?? http.Client();
  @override
  Stream<Telemetry> get telemetry => _stream.stream;
  @override
  DeviceSettings? get reportedSettings => _settings;
  Uri _uri(String suffix) => Uri.parse(
    '${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}/api/v1/devices/${config.deviceId}$suffix',
  );
  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };
  String _error(http.Response response) {
    try {
      return (jsonDecode(response.body) as Map)['detail']?.toString() ??
          'เซิร์ฟเวอร์ตอบกลับไม่สำเร็จ';
    } catch (_) {
      return 'เซิร์ฟเวอร์ตอบกลับไม่สำเร็จ (HTTP ${response.statusCode})';
    }
  }

  void _snapshot(Map<String, dynamic> data) {
    if (data['config'] is Map) {
      _settings = DeviceSettings.fromJson(
        Map<String, dynamic>.from(data['config'] as Map),
      );
    }
    final raw = data['telemetry'];
    if (raw is Map && !_stream.isClosed) {
      _stream.add(Telemetry.fromJson(Map<String, dynamic>.from(raw)));
    }
  }

  @override
  Future<void> connect() async {
    if (token.trim().isEmpty) {
      throw StateError('ใส่รหัสเข้าถึงเซิร์ฟเวอร์ก่อนเชื่อมต่อ');
    }
    final response = await _client
        .get(_uri(''), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) throw StateError(_error(response));
    _snapshot(jsonDecode(response.body) as Map<String, dynamic>);
    await _openSocket();
  }

  Future<void> _openSocket() async {
    if (_closed) return;
    await _subscription?.cancel();
    await _socket?.sink.close();
    var uri = _uri('/stream');
    uri = uri.replace(scheme: uri.scheme == 'https' ? 'wss' : 'ws');
    final channel = WebSocketChannel.connect(uri);
    _socket = channel;
    try {
      await channel.ready.timeout(const Duration(seconds: 8));
      if (_closed) {
        await channel.sink.close();
        return;
      }
      channel.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      _subscription = channel.stream.listen(
        (raw) {
          try {
            final message = jsonDecode(raw as String) as Map<String, dynamic>;
            if (message['type'] == 'telemetry') {
              _attempt = 0;
              _snapshot(message['data'] as Map<String, dynamic>);
            }
            if (message['type'] == 'ack') {
              final data = message['data'] as Map<String, dynamic>;
              final completer = _pending.remove(data['command_id']);
              completer?.complete(
                CommandResult(
                  id: data['command_id'] as String,
                  applied: data['status'] == 'applied',
                  message: data['message'] as String? ?? 'เครื่องตอบกลับแล้ว',
                ),
              );
            }
            if (message['type'] == 'error') {
              _stream.addError(
                StateError(
                  message['message'] as String? ?? 'เชื่อมต่อไม่สำเร็จ',
                ),
              );
            }
          } catch (_) {
            _stream.addError(StateError('รูปแบบข้อมูลจากเครื่องไม่ถูกต้อง'));
          }
        },
        onError: (Object error) {
          _scheduleRetry();
        },
        onDone: _scheduleRetry,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
      rethrow;
    }
  }

  void _scheduleRetry() {
    if (_closed || _retry?.isActive == true) return;
    _stream.addError(StateError('การเชื่อมต่อหลุด กำลังลองใหม่'));
    _attempt++;
    final seconds = (1 << _attempt.clamp(0, 4)).clamp(2, 16);
    _retry = Timer(Duration(seconds: seconds), () async {
      if (_closed) return;
      try {
        await _openSocket();
      } catch (_) {
        _scheduleRetry();
      }
    });
  }

  @override
  Future<CommandResult> command(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final id = createId();
    final completer = Completer<CommandResult>();
    _pending[id] = completer;
    try {
      final response = await _client
          .post(
            _uri('/commands'),
            headers: _headers,
            body: jsonEncode({
              'command_id': id,
              'action': action,
              'payload': payload,
              'expires_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(seconds: 10))
                  .toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 202) throw StateError(_error(response));
      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => CommandResult(
          id: id,
          applied: false,
          message: 'เครื่องยังไม่ยืนยัน กรุณาตรวจสถานะก่อนส่งใหม่',
        ),
      );
    } finally {
      _pending.remove(id);
    }
  }

  Future<List<Telemetry>> loadHistory() async {
    final response = await _client
        .get(_uri('/history?limit=1440'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) throw StateError(_error(response));
    return ((jsonDecode(response.body) as Map)['items'] as List)
        .map((e) => Telemetry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<AnalysisResult> analyze(
    Uint8List bytes,
    String filename,
    bool video,
  ) async {
    if (bytes.length > 50 * 1024 * 1024) {
      throw StateError('ไฟล์ต้องมีขนาดไม่เกิน 50 MB');
    }
    final request = http.MultipartRequest('POST', _uri('/counts/analyze'))
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['kind'] = video ? 'video' : 'image'
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    final streamed = await _client
        .send(request)
        .timeout(const Duration(seconds: 90));
    final response = await http.Response.fromStream(
      streamed,
    ).timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) throw StateError(_error(response));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final points = (data['points'] as List)
        .map((e) => CountPoint.fromJson(e as Map<String, dynamic>))
        .toList();
    return AnalysisResult(
      points,
      data['model_version'] as String,
      frameBytes: data['frame_base64'] == null
          ? null
          : base64Decode(data['frame_base64'] as String),
    );
  }

  @override
  Future<void> dispose() async {
    _closed = true;
    _retry?.cancel();
    for (final entry in _pending.entries) {
      entry.value.complete(
        CommandResult(
          id: entry.key,
          applied: false,
          message: 'การเชื่อมต่อถูกเปลี่ยน',
        ),
      );
    }
    _pending.clear();
    await _subscription?.cancel();
    await _socket?.sink.close();
    _client.close();
    await _stream.close();
  }

  @override
  Future<DeviceCameraStatus> cameraStatus() async {
    final response = await _client
        .get(_uri('/camera'), headers: _headers)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 404) {
      return const DeviceCameraStatus(
        message: 'เซิร์ฟเวอร์ยังไม่รองรับกล้อง กรุณาอัปเดต Gateway',
      );
    }
    if (response.statusCode != 200) throw StateError(_error(response));
    return DeviceCameraStatus.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  @override
  Future<DeviceCapture> capture(
    String requestId, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async {
    void checkCancelled() {
      if (_closed || cancelled?.call() == true) {
        throw StateError('ยกเลิกการรอภาพแล้ว');
      }
    }

    checkCancelled();
    onProgress?.call('กำลังส่งคำสั่งถึงกล้อง…');
    final accepted = await _client
        .post(
          _uri('/camera/captures'),
          headers: _headers,
          body: jsonEncode({'capture_id': requestId}),
        )
        .timeout(const Duration(seconds: 12));
    if (accepted.statusCode != 202) throw StateError(_error(accepted));
    var job = jsonDecode(accepted.body) as Map<String, dynamic>;
    final watch = Stopwatch()..start();
    while (true) {
      checkCancelled();
      if (job['capture_id'] != requestId) {
        throw StateError('รหัสภาพตอบกลับไม่ตรงกับคำสั่ง');
      }
      if (job['status'] == 'captured') break;
      if (job['status'] == 'failed' || job['status'] == 'expired') {
        throw StateError(job['message'] as String? ?? 'กล้องถ่ายภาพไม่สำเร็จ');
      }
      if (watch.elapsed > const Duration(seconds: 100)) {
        throw StateError(
          'รอภาพเกินเวลา ตรวจกล้องและอินเทอร์เน็ต แล้วตรวจสถานะก่อนถ่ายใหม่',
        );
      }
      onProgress?.call('รอกล้องถ่ายและส่งภาพขึ้นคลาวด์…');
      await Future<void>.delayed(const Duration(seconds: 1));
      checkCancelled();
      final response = await _client
          .get(_uri('/camera/captures/$requestId'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) throw StateError(_error(response));
      job = jsonDecode(response.body) as Map<String, dynamic>;
    }
    onProgress?.call('ได้รับภาพแล้ว กำลังเปิดภาพ…');
    final response = await _client
        .get(_uri('/camera/captures/$requestId/image'), headers: _headers)
        .timeout(const Duration(seconds: 25));
    checkCancelled();
    if (response.statusCode != 200) throw StateError(_error(response));
    if (response.bodyBytes.isEmpty ||
        response.bodyBytes.length > 8 * 1024 * 1024) {
      throw StateError('ขนาดภาพจากกล้องไม่ถูกต้อง');
    }
    return DeviceCapture(
      id: requestId,
      cameraId: job['camera_id'] as String,
      receivedAt: DateTime.parse(job['received_at'] as String).toLocal(),
      bytes: response.bodyBytes,
    );
  }

  @override
  Future<AnalysisResult> analyzeCapture(String captureId) async {
    final response = await _client
        .post(_uri('/camera/captures/$captureId/analyze'), headers: _headers)
        .timeout(const Duration(seconds: 90));
    if (response.statusCode != 200) throw StateError(_error(response));
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return AnalysisResult(
      (data['points'] as List)
          .map((e) => CountPoint.fromJson(e as Map<String, dynamic>))
          .toList(),
      data['model_version'] as String,
      frameBytes: data['frame_base64'] == null
          ? null
          : base64Decode(data['frame_base64'] as String),
    );
  }
}
