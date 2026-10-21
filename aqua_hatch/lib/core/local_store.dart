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
  HatchBatch? get batch =>
      _read('batch_v2:${scope(connection)}', HatchBatch.fromJson);
  List<CountRecord> get counts {
    try {
      return (jsonDecode(preferences.getString('counts') ?? '[]') as List)
          .map((e) => CountRecord.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String scope(ConnectionConfig c) => c.demo
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

  Future<void> _write(String key, Object data) async {
    if (!await preferences.setString(key, jsonEncode(data))) {
      throw StateError('บันทึกข้อมูลในเครื่องไม่สำเร็จ');
    }
  }

  Future<void> saveConnection(ConnectionConfig config) =>
      _write('connection', config.toJson());
  Future<void> saveSettings(DeviceSettings settings) =>
      _write('settings', settings.toJson());
  Future<void> saveBatch(HatchBatch batch) =>
      _write('batch_v2:${scope(connection)}', batch.toJson());
  Future<void> saveCounts(List<CountRecord> counts) =>
      _write('counts', counts.take(100).map((e) => e.toJson()).toList());
}
