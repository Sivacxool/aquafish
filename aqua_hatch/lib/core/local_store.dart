import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class LocalStore {
  final SharedPreferences preferences;
  LocalStore(this.preferences);
  T? _read<T>(String key, T Function(Map<String, dynamic>) decode) {
    try {
      final raw = preferences.getString(key);
      return raw == null
          ? null
          : decode(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  ConnectionConfig get connection =>
      _read('connection', ConnectionConfig.fromJson) ??
      const ConnectionConfig();
  DeviceSettings get settings =>
      _read('settings', DeviceSettings.fromJson) ?? const DeviceSettings();
  ConnectionConfig? get cameraConnection =>
      _read('camera_connection_v1', ConnectionConfig.fromJson);
  Future<void> saveCameraConnection(ConnectionConfig config) =>
      _write('camera_connection_v1', config.toJson());
  List<ConnectionConfig> get pairedDevices => _list(
    'paired_devices_v1',
    ConnectionConfig.fromJson,
  ).where((c) => c.identity != null && c.validate() == null).toList();
  Future<void> rememberPairedDevice(ConnectionConfig config) async {
    if (config.identity == null) return;
    final items = pairedDevices
        .where(
          (c) =>
              !(c.identity!.kind == config.identity!.kind &&
                  c.deviceId == config.deviceId),
        )
        .toList();
    await _write(
      'paired_devices_v1',
      [config.toJson(), ...items.map((c) => c.toJson())].take(64).toList(),
    );
  }

  bool get usbCameraEnabled =>
      preferences.getBool('usb_camera_enabled_v1') ?? false;
  Future<void> saveUsbCameraEnabled(bool enabled) async {
    if (!await preferences.setBool('usb_camera_enabled_v1', enabled)) {
      throw StateError('บันทึกโหมดกล้อง USB ไม่สำเร็จ');
    }
  }

  String _roundsKey(ConnectionConfig config) => 'rounds_v1:${scope(config)}';

  ({List<HatchBatch> rounds, HatchBatch? active}) hatchRounds(
    ConnectionConfig config,
  ) {
    final saved = _read(_roundsKey(config), (data) {
      final rounds = (data['rounds'] as List<dynamic>)
          .map((item) => HatchBatch.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
      final activeId = data['active_id'] as String?;
      return (
        rounds: rounds,
        active: rounds.where((round) => round.id == activeId).firstOrNull,
      );
    });
    if (saved != null) return saved;

    final legacyKey = 'batch_v2:${scope(config)}';
    final legacy = _read(legacyKey, HatchBatch.fromJson);
    final active =
        legacy ??
        (config.demo && !preferences.containsKey(legacyKey)
            ? HatchBatch(
                id: 'demo-batch',
                name: 'รอบฟักตัวอย่าง 01',
                startedAt: DateTime.now().subtract(
                  const Duration(hours: 6, minutes: 24),
                ),
                eggs: 1200,
              )
            : null);
    return (rounds: [?active], active: active);
  }

  List<CountRecord> get counts {
    try {
      return (jsonDecode(preferences.getString('counts') ?? '[]') as List)
          .map((e) => CountRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String scope(ConnectionConfig c) => c.identity != null
      ? 'paired:${c.identity!.stableKey}'
      : c.demo
      ? 'demo'
      : '${c.localEsp32 ? 'esp32:' : ''}${c.baseUrl}|${c.deviceId}';
  List<T> _list<T>(String key, T Function(Map<String, dynamic>) decode) {
    try {
      return (jsonDecode(preferences.getString(key) ?? '[]') as List)
          .map((e) => decode(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<Telemetry> history(ConnectionConfig c) =>
      _list('history_v2:${scope(c)}', Telemetry.fromJson);
  List<DeviceEvent> events(ConnectionConfig c) =>
      _list('events_v2:${scope(c)}', DeviceEvent.fromJson);
  Future<void> saveHistory(ConnectionConfig c, List<Telemetry> items) =>
      _write('history_v2:${scope(c)}', items.map((e) => e.toJson()).toList());
  Future<void> saveEvents(ConnectionConfig c, List<DeviceEvent> items) =>
      _write(
        'events_v2:${scope(c)}',
        items.take(200).map((e) => e.toJson()).toList(),
      );

  Future<void> _write(String key, Object? data) async {
    if (!await preferences.setString(key, jsonEncode(data))) {
      throw StateError('บันทึกข้อมูลในเครื่องไม่สำเร็จ');
    }
  }

  Future<void> saveConnection(ConnectionConfig config) =>
      _write('connection', config.toJson());
  Future<void> saveSettings(DeviceSettings settings) =>
      _write('settings', settings.toJson());
  Future<void> saveHatchRounds(
    ConnectionConfig config,
    List<HatchBatch> rounds,
    HatchBatch? active,
  ) => _write(_roundsKey(config), {
    'rounds': rounds.map((round) => round.toJson()).toList(),
    'active_id': active?.id,
  });
  Future<void> saveCounts(List<CountRecord> counts) =>
      _write('counts', counts.take(100).map((e) => e.toJson()).toList());
}
