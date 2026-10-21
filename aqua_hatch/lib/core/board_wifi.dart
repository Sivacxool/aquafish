import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'device_tls_client.dart';
import 'models.dart';

const setupNetworkName = 'AquaHatch-117C';
const setupBoardUrl = 'https://192.168.4.1';

class BoardWifiRejected implements Exception {
  final int statusCode;
  final String message;
  const BoardWifiRejected(this.statusCode, this.message);
  @override
  String toString() => message;
}

void validateWifiCredentials(
  String ssid,
  String password, {
  bool reusePassword = false,
  bool allowOpen = false,
}) {
  if (utf8.encode(ssid).isEmpty ||
      utf8.encode(ssid).length > 32 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(ssid)) {
    throw StateError('ชื่อ Wi-Fi ไม่ถูกต้อง');
  }
  if (!reusePassword &&
      !(allowOpen && password.isEmpty) &&
      !(utf8.encode(password).length >= 8 &&
          utf8.encode(password).length <= 63) &&
      !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(password)) {
    throw StateError('รหัส Wi-Fi ต้องมี 8–63 ตัวอักษร หรือ 64 ตัวเลขฐานสิบหก');
  }
}

String setupNetworkPassword(String pairingCode) => sha256
    .convert(utf8.encode('AquaHatch setup v1:${pairingCode.trim()}'))
    .toString()
    .substring(0, 16);

class BoardNetwork {
  final String ssid;
  final int rssi, auth;
  const BoardNetwork(this.ssid, this.rssi, this.auth);
  bool get open => auth == 0;
  bool get supported => [0, 2, 3, 4, 6, 7].contains(auth);
}

class BoardWifiStatus {
  final bool connected, credentialsSaved, apActive;
  final String ip,
      ssid,
      savedSsid,
      phase,
      requestId,
      attemptSsid,
      error,
      scanState;
  final List<BoardNetwork> networks;
  const BoardWifiStatus({
    required this.connected,
    required this.credentialsSaved,
    required this.apActive,
    required this.ip,
    required this.ssid,
    required this.savedSsid,
    required this.phase,
    required this.requestId,
    required this.attemptSsid,
    required this.error,
    required this.scanState,
    required this.networks,
  });
  factory BoardWifiStatus.fromJson(Map<String, dynamic> data, String deviceId) {
    if (data['backend'] != 'esp32-local' ||
        data['provisioning_version'] != 1 ||
        data['device_id'] != deviceId) {
      throw StateError('ข้อมูลตั้งค่าไม่ตรงกับบอร์ดที่จับคู่');
    }
    final ip = data['ip'] as String? ?? '';
    final connected = data['connected'] == true;
    if (connected && !isPrivateIpv4(ip)) {
      throw StateError('บอร์ดส่งที่อยู่เครือข่ายไม่ถูกต้อง');
    }
    final byName = <String, BoardNetwork>{};
    for (final row in data['networks'] as List? ?? []) {
      if (row is! Map ||
          row['ssid'] is! String ||
          row['rssi'] is! num ||
          row['auth'] is! num) {
        continue;
      }
      final network = BoardNetwork(
        row['ssid'] as String,
        (row['rssi'] as num).toInt(),
        (row['auth'] as num).toInt(),
      );
      if (network.ssid.isEmpty || !network.supported) continue;
      if (!byName.containsKey(network.ssid) ||
          byName[network.ssid]!.rssi < network.rssi) {
        byName[network.ssid] = network;
      }
    }
    final networks = byName.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return BoardWifiStatus(
      connected: connected,
      credentialsSaved: data['credentials_saved'] == true,
      apActive: data['ap_active'] == true,
      ip: ip,
      ssid: data['ssid'] as String? ?? '',
      savedSsid: data['saved_ssid'] as String? ?? '',
      phase: data['phase'] as String? ?? '',
      requestId: data['request_id'] as String? ?? '',
      attemptSsid: data['attempt_ssid'] as String? ?? '',
      error: data['error'] as String? ?? '',
      scanState: data['scan_state'] as String? ?? '',
      networks: networks,
    );
  }
}

class BoardWifiClient {
  final ConnectionConfig config;
  final String token;
  final http.Client? _providedClient;
  http.Client? _client;
  bool _closed = false;
  BoardWifiClient(this.config, this.token, {http.Client? client})
    : _providedClient = client;

  Future<Map<String, dynamic>> _request(
    String method,
    String suffix, [
    Map<String, dynamic>? body,
  ]) async {
    if (_closed) throw StateError('ปิดการตั้งค่าแล้ว');
    if (!config.localEsp32 ||
        config.demo ||
        config.validate() != null ||
        token.trim().isEmpty) {
      throw StateError('ตรวจรหัสจับคู่และที่อยู่บอร์ด');
    }
    final client = _client ??=
        _providedClient ?? await createDeviceClient(config);
    if (_closed) {
      client.close();
      throw StateError('ปิดการตั้งค่าแล้ว');
    }
    final request =
        http.Request(
            method,
            Uri.https(
              deviceTlsHostname,
              '/api/v1/devices/${config.deviceId}/wifi$suffix',
            ),
          )
          ..followRedirects = false
          ..persistentConnection = false;
    request.headers.addAll({
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
      'X-AquaHatch-Time':
          '${DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}',
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await client.send(request).timeout(const Duration(seconds: 8)),
    ).timeout(const Duration(seconds: 8));
    dynamic parsed;
    try {
      parsed = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw StateError('บอร์ดส่งข้อมูลตั้งค่าไม่ถูกต้อง');
    }
    if (parsed is! Map<String, dynamic>) {
      throw StateError('บอร์ดส่งข้อมูลตั้งค่าไม่ถูกต้อง');
    }
    if (![200, 202].contains(response.statusCode)) {
      if (response.statusCode == 404) {
        throw BoardWifiRejected(
          404,
          'เฟิร์มแวร์บอร์ดยังไม่รองรับการตั้ง Wi-Fi จากแอป',
        );
      }
      if (response.statusCode == 401) {
        throw BoardWifiRejected(401, 'รหัสจับคู่บอร์ดไม่ถูกต้อง');
      }
      throw BoardWifiRejected(
        response.statusCode,
        parsed['detail']?.toString() ?? 'บอร์ดไม่รับข้อมูลตั้งค่า',
      );
    }
    return parsed;
  }

  Future<BoardWifiStatus> status() async =>
      BoardWifiStatus.fromJson(await _request('GET', ''), config.deviceId);
  Future<void> openSetupNetwork() async {
    await _request('POST', '/start', {});
  }

  Future<BoardWifiStatus> startScan() async => BoardWifiStatus.fromJson(
    await _request('POST', '/scan', {}),
    config.deviceId,
  );
  Future<BoardWifiStatus> submit({
    required String requestId,
    required String ssid,
    required String password,
    bool reusePassword = false,
    bool allowOpen = false,
  }) async {
    validateWifiCredentials(
      ssid,
      password,
      reusePassword: reusePassword,
      allowOpen: allowOpen,
    );
    return BoardWifiStatus.fromJson(
      await _request('POST', '', {
        'request_id': requestId,
        'ssid': ssid,
        'password': password,
        'reuse_password': reusePassword,
        'allow_open': allowOpen,
      }),
      config.deviceId,
    );
  }

  void close() {
    _closed = true;
    _client?.close();
  }
}
