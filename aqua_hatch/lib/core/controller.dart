import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'local_store.dart';
import 'repository.dart';
import 'demo_repository.dart';
import 'live_repository.dart';
import 'esp32_repository.dart';
import 'credentials.dart';
import 'camera.dart';

final credentialStoreProvider = Provider<CredentialStore>(
  (ref) => const CredentialStore(),
);

final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('LocalStore must be provided at bootstrap'),
);
final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

final cameraStatusProvider = FutureProvider.autoDispose<DeviceCameraStatus>((
  ref,
) async {
  ref.watch(appControllerProvider.select((s) => s.connection));
  Timer? refresh;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    refresh?.cancel();
  });
  try {
    return await ref.read(appControllerProvider.notifier).cameraStatus();
  } catch (_) {
    return const DeviceCameraStatus(
      message: 'ติดต่อกล้องไม่ได้ ตรวจการเชื่อมต่อเซิร์ฟเวอร์',
    );
  } finally {
    if (!disposed) {
      refresh = Timer(const Duration(seconds: 5), ref.invalidateSelf);
    }
  }
});

class AppState {
  final ConnectionConfig connection;
  final DeviceSettings settings;
  final Telemetry? telemetry;
  final HatchBatch? batch;
  final List<CountRecord> counts;
  final List<Telemetry> history;
  final List<DeviceEvent> events;
  final bool connected, busy;
  final String? error;
  final DateTime now;
  const AppState({
    required this.connection,
    required this.settings,
    required this.now,
    this.telemetry,
    this.batch,
    this.counts = const [],
    this.history = const [],
    this.events = const [],
    this.connected = false,
    this.busy = false,
    this.error,
  });
  bool get fresh => connected && (telemetry?.isFresh(now) ?? false);
  bool get canControl => fresh && (telemetry?.hardwareReady ?? false);
  List<String> get alerts => telemetry?.alerts(settings) ?? [];
  String get connectionLabel {
    if (connection.demo) {
      return fresh ? 'เครื่องจำลองพร้อมใช้งาน' : 'กำลังเริ่มเครื่องจำลอง';
    }
    if (telemetry?.simulated == true) {
      return fresh ? 'เซิร์ฟเวอร์ส่งข้อมูลจำลอง' : 'ข้อมูลจำลองขาดการเชื่อมต่อ';
    }
    if (!connected) return 'ยังไม่เชื่อมต่อเครื่อง';
    if (telemetry == null) return 'รอข้อมูลจากเครื่อง';
    if (!telemetry!.deviceOnline) return 'เครื่องออฟไลน์';
    if (!fresh) return 'ข้อมูลเครื่องขาดช่วง';
    if (connection.localEsp32 && telemetry?.hardwareReady == false) {
      return 'บอร์ดออนไลน์ · รอติดตั้งอุปกรณ์';
    }
    return 'เชื่อมต่อเครื่องแล้ว';
  }

  AppState copyWith({
    ConnectionConfig? connection,
    DeviceSettings? settings,
    Telemetry? telemetry,
    HatchBatch? batch,
    List<CountRecord>? counts,
    List<Telemetry>? history,
    List<DeviceEvent>? events,
    bool? connected,
    bool? busy,
    String? error,
    DateTime? now,
    bool clearError = false,
    bool clearTelemetry = false,
    bool clearBatch = false,
  }) => AppState(
    connection: connection ?? this.connection,
    settings: settings ?? this.settings,
    telemetry: clearTelemetry ? null : telemetry ?? this.telemetry,
    batch: clearBatch ? null : batch ?? this.batch,
    counts: counts ?? this.counts,
    history: history ?? this.history,
    events: events ?? this.events,
    connected: connected ?? this.connected,
    busy: busy ?? this.busy,
    error: clearError ? null : error ?? this.error,
    now: now ?? this.now,
  );
}

class AppController extends Notifier<AppState> {
  DeviceRepository? _repository;
  StreamSubscription<Telemetry>? _subscription;
  Timer? _clock;
  String _token = '';
  int _generation = 0;
  bool _disposed = false;
  bool _wifiSetupPaused = false;
  bool _wasFresh = false;
  DateTime? _lastSavedSample;
  DateTime? _startedAt;
  bool _reportedWaiting = false;
  Future<void> _persistence = Future.value();
  void _persist(Future<void> Function() save) {
    _persistence = _persistence.then((_) => save()).catchError((Object _) {
      if (!_disposed) {
        state = state.copyWith(error: 'บันทึกประวัติในมือถือไม่สำเร็จ');
      }
    });
  }

  late LocalStore _store;
  @override
  AppState build() {
    final store = ref.read(localStoreProvider);
    _store = store;
    final config = store.connection;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_disposed) {
        state = state.copyWith(now: DateTime.now());
        _checkConnection();
      }
    });
    ref.onDispose(() {
      _disposed = true;
      _clock?.cancel();
      unawaited(_subscription?.cancel());
      unawaited(_repository?.dispose());
    });
    Future.microtask(() async {
      if (!config.demo) {
        try {
          _token = await ref.read(credentialStoreProvider).read(config);
        } catch (_) {
          if (!_disposed) {
            state = state.copyWith(
              error: 'อ่านรหัสที่บันทึกไม่ได้ กรุณาเชื่อมต่อใหม่ในตั้งค่า',
            );
          }
          return;
        }
      }
      if (!_disposed) await _start(config);
    });
    return AppState(
      connection: config,
      settings: store.settings,
      now: DateTime.now(),
      counts: store.counts,
      batch:
          store.batch ??
          (config.demo
              ? HatchBatch(
                  id: 'demo-batch',
                  name: 'รอบฟักตัวอย่าง 01',
                  startedAt: DateTime.now().subtract(
                    const Duration(hours: 6, minutes: 24),
                  ),
                  eggs: 1200,
                )
              : null),
    );
  }

  void _checkConnection() {
    final fresh = state.fresh;
    if (_wasFresh && !fresh) {
      _event(
        'ข้อมูลเครื่องขาดช่วง ตรวจการเชื่อมต่อและไฟเลี้ยงเครื่อง',
        warning: true,
      );
    }
    if (!_wasFresh && fresh && _reportedWaiting) {
      _event('กลับมารับข้อมูลล่าสุดจากเครื่องแล้ว');
    }
    if (!fresh &&
        !_reportedWaiting &&
        _startedAt != null &&
        state.now.difference(_startedAt!).inSeconds >= 15) {
      _event('ยังไม่ได้รับข้อมูลล่าสุดจากเครื่อง', warning: true);
      _reportedWaiting = true;
    }
    if (_wasFresh && !fresh) _reportedWaiting = true;
    _wasFresh = fresh;
  }

  void acknowledgeEvents() {
    state = state.copyWith(
      events: state.events.map((e) => e.acknowledge()).toList(),
    );
    final config = state.connection;
    final events = state.events;
    _persist(() => _store.saveEvents(config, events));
  }

  void _event(String text, {bool warning = false}) {
    state = state.copyWith(
      events: [
        DeviceEvent(text, warning: warning),
        ...state.events,
      ].take(200).toList(),
    );
    final config = state.connection;
    final events = state.events;
    _persist(() => _store.saveEvents(config, events));
  }

  Future<void> _start(ConnectionConfig config) async {
    if (_disposed || _wifiSetupPaused) return;
    if (state.busy) return;
    _wasFresh = false;
    _reportedWaiting = false;
    _startedAt = DateTime.now();
    _lastSavedSample = null;
    final generation = ++_generation;
    await _subscription?.cancel();
    await _repository?.dispose();
    if (_disposed || generation != _generation) return;
    state = state.copyWith(
      connection: config,
      connected: false,
      clearTelemetry: true,
      history: _store.history(config),
      events: _store.events(config),
      clearError: true,
    );
    final repo = config.demo
        ? DemoRepository(state.settings)
        : config.localEsp32
        ? Esp32Repository(config, _token)
        : LiveRepository(config, _token);
    _repository = repo;
    _subscription = repo.telemetry.listen(
      (reading) {
        if (_disposed || generation != _generation) return;
        final previous = state.alerts;
        state = state.copyWith(
          telemetry: reading,
          settings: repo.reportedSettings ?? state.settings,
          connected: true,
          clearError: true,
          history: _appendHistory(reading),
        );
        _checkConnection();
        if (_lastSavedSample == null ||
            reading.at.difference(_lastSavedSample!).inSeconds >= 60) {
          _lastSavedSample = reading.at;
          final samples = state.history;
          _persist(() => _store.saveHistory(config, samples));
        }
        for (final resolved in previous.where(
          (a) => !state.alerts.contains(a),
        )) {
          _event('กลับสู่ปกติ: $resolved');
        }
        for (final alert in state.alerts) {
          if (!previous.contains(alert)) _event(alert, warning: true);
        }
      },
      onError: (Object e) {
        if (_disposed || generation != _generation) return;
        state = state.copyWith(connected: false, error: _message(e));
        _checkConnection();
      },
    );
    try {
      await repo.connect();
      if (!_disposed && generation == _generation) {
        state = state.copyWith(connected: true);
        _event(
          config.demo
              ? 'เชื่อมต่อเครื่องจำลองแล้ว'
              : 'เชื่อมต่อเซิร์ฟเวอร์แล้ว',
        );
      }
    } catch (e) {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(connected: false, error: _message(e));
      }
    }
  }

  List<Telemetry> _appendHistory(Telemetry reading) {
    final samples = [...state.history];
    if (samples.isNotEmpty && samples.last.simulated != reading.simulated) {
      samples.clear();
    }
    if (samples.isNotEmpty && !reading.at.isAfter(samples.last.at)) {
      return samples;
    }
    if (samples.isNotEmpty &&
        reading.at.difference(samples.last.at).inSeconds < 60) {
      return samples;
    }
    samples.add(reading);
    return samples
        .skip(samples.length > 1440 ? samples.length - 1440 : 0)
        .toList();
  }

  Future<String?> loadServerHistory() async {
    final repo = _repository;
    if (repo is! LiveRepository) return null;
    final generation = _generation;
    try {
      final samples = await repo.loadHistory();
      if (_disposed || generation != _generation) return null;
      final simulated =
          state.telemetry?.simulated ?? samples.lastOrNull?.simulated;
      final indexed = {
        for (final t in [
          ...samples,
          ...state.history,
        ].where((t) => simulated == null || t.simulated == simulated))
          t.at.millisecondsSinceEpoch ~/ 60000: t,
      };
      final merged = indexed.values.toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      final limited = merged
          .skip(merged.length > 1440 ? merged.length - 1440 : 0)
          .toList();
      state = state.copyWith(history: limited);
      final config = state.connection;
      _persist(() => _store.saveHistory(config, limited));
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  String _message(Object e) =>
      e.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
  Future<String?> configure(ConnectionConfig config, String token) async {
    final invalid = config.validate();
    if (invalid != null) return invalid;
    var accessToken = token.trim();
    if (!config.demo && accessToken.isEmpty) {
      try {
        accessToken = await ref.read(credentialStoreProvider).read(config);
      } catch (_) {
        return 'อ่านรหัสที่บันทึกไม่ได้ กรุณากรอกรหัสอีกครั้ง';
      }
      if (accessToken.isEmpty) return 'กรุณาใส่รหัสเข้าถึงเซิร์ฟเวอร์';
    }
    if (state.busy) return 'รอคำสั่งปัจจุบันเสร็จก่อน';
    try {
      if (!config.demo) {
        await ref.read(credentialStoreProvider).save(config, accessToken);
      }
      await _store.saveConnection(config);
      _token = accessToken;
      if (_store.scope(config) != _store.scope(state.connection)) {
        state = state.copyWith(
          batch: _store.batch,
          clearBatch: _store.batch == null,
        );
      }
      _wifiSetupPaused = false;
      await _start(config);
      return state.error;
    } catch (e) {
      return _message(e);
    }
  }

  Future<String?> forgetCredentials() async {
    if (state.busy) return 'รอคำสั่งปัจจุบันเสร็จก่อน';
    try {
      await ref.read(credentialStoreProvider).forget(state.connection);
      _token = '';
      await _start(state.connection);
      return null;
    } catch (_) {
      return 'ลบรหัสที่บันทึกไม่สำเร็จ';
    }
  }

  Future<void> reconnect() async {
    if (_disposed) return;
    _wifiSetupPaused = false;
    await _start(state.connection);
  }

  Future<void> pauseForWifiSetup() async {
    _wifiSetupPaused = true;
    ++_generation;
    _wasFresh = false;
    _reportedWaiting = false;
    _startedAt = null;
    await _subscription?.cancel();
    _subscription = null;
    await _repository?.dispose();
    _repository = null;
    if (!_disposed) {
      state = state.copyWith(
        connected: false,
        clearError: true,
        clearTelemetry: true,
      );
    }
  }

  Future<String?> send(String action, Map<String, dynamic> payload) async {
    if (state.busy) return 'มีคำสั่งกำลังดำเนินการ';
    if ((action == 'set_mode' || action == 'set_output') &&
        state.telemetry?.hardwareReady == false) {
      return state.telemetry?.hardwareMessage ?? 'ยังไม่ติดตั้งวงจรควบคุม';
    }
    if (!state.connected ||
        !(state.telemetry?.isFresh(DateTime.now()) ?? false)) {
      return 'ข้อมูลเครื่องไม่เป็นปัจจุบัน กรุณาเชื่อมต่อใหม่';
    }
    final repo = _repository;
    if (repo == null) return 'ยังไม่เชื่อมต่อเครื่อง';
    final generation = _generation;
    state = state.copyWith(busy: true, clearError: true);
    try {
      final result = await repo.command(action, payload);
      if (_disposed || generation != _generation) {
        return 'การเชื่อมต่อถูกเปลี่ยน';
      }
      _event(result.message, warning: !result.applied);
      return result.applied ? null : result.message;
    } catch (e) {
      if (!_disposed && generation == _generation) {
        _event(_message(e), warning: true);
      }
      return _message(e);
    } finally {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(busy: false);
      }
    }
  }

  Future<String?> saveSettings(DeviceSettings settings) async {
    final error = settings.validate();
    if (error != null) return error;
    final result = await send('set_config', settings.toJson());
    if (result != null) return result;
    try {
      await _store.saveSettings(settings);
      state = state.copyWith(settings: settings);
      return null;
    } catch (e) {
      return 'เครื่องรับค่าแล้ว แต่บันทึกในมือถือไม่ได้: ${_message(e)}';
    }
  }

  Future<String?> startBatch(String name, int? eggs) async {
    if (name.trim().isEmpty) return 'กรุณาตั้งชื่อรอบฟัก';
    if (eggs != null && eggs <= 0) return 'จำนวนไข่ต้องมากกว่า 0';
    final batch = HatchBatch(
      id: createId(),
      name: name.trim(),
      startedAt: DateTime.now(),
      eggs: eggs,
    );
    try {
      await _store.saveBatch(batch);
      state = state.copyWith(batch: batch);
      _event('เริ่มรอบฟัก ${batch.name}');
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  Future<String?> saveCount({
    required int count,
    required String source,
    required String method,
    required bool demo,
    int? aiCount,
  }) async {
    final batch = state.batch;
    if (batch == null) return 'เริ่มรอบฟักก่อนบันทึกผล';
    if (count < 0) return 'จำนวนลูกปลาต้องไม่ติดลบ';
    final record = CountRecord(
      id: createId(),
      batchId: batch.id,
      batchName: batch.name,
      source: source,
      method: method,
      count: count,
      at: DateTime.now(),
      demo: demo,
      aiCount: aiCount,
    );
    final updated = [record, ...state.counts].take(100).toList();
    try {
      await _store.saveCounts(updated);
      state = state.copyWith(counts: updated);
      _event('บันทึกผลนับ $count ตัว');
      return null;
    } catch (e) {
      return _message(e);
    }
  }

  Future<AnalysisResult> analyze(Uint8List bytes, String filename, bool video) {
    final repo = _repository;
    if (repo == null) throw StateError('ยังไม่เชื่อมต่อ');
    return repo.analyze(bytes, filename, video);
  }

  void demoScenario({required bool ph, required bool water}) {
    final repo = _repository;
    if (repo is DemoRepository) repo.scenario(ph: ph, water: water);
  }

  Future<DeviceCameraStatus> cameraStatus() async {
    final repo = _repository;
    if (repo == null) {
      return const DeviceCameraStatus(message: 'กำลังเชื่อมต่อเซิร์ฟเวอร์');
    }
    return repo.cameraStatus();
  }

  Future<DeviceCapture> captureFromDevice(
    String requestId, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async {
    final repo = _repository;
    if (repo == null) throw StateError('ยังไม่เชื่อมต่อเซิร์ฟเวอร์');
    final generation = _generation;
    final image = await repo.capture(
      requestId,
      onProgress: onProgress,
      cancelled: () =>
          _disposed || generation != _generation || cancelled?.call() == true,
    );
    if (_disposed || generation != _generation) {
      throw StateError('การเชื่อมต่อถูกเปลี่ยน');
    }
    _event('ได้รับภาพจากกล้อง ${image.cameraId} แล้ว');
    return image;
  }

  Future<AnalysisResult> analyzeDeviceCapture(String captureId) async {
    final repo = _repository;
    if (repo == null) throw StateError('ยังไม่เชื่อมต่อเซิร์ฟเวอร์');
    final generation = _generation;
    final result = await repo.analyzeCapture(captureId);
    if (_disposed || generation != _generation) {
      throw StateError('การเชื่อมต่อถูกเปลี่ยน');
    }
    return result;
  }
}
