import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'models.dart';
import 'repository.dart';
import 'camera.dart';

class DemoRepository implements DeviceRepository {
  final _stream = StreamController<Telemetry>.broadcast();
  Timer? _timer;
  DeviceSettings settings;
  RunMode mode = RunMode.automatic;
  DateTime? manualUntil;
  bool abnormalPh = false, lowWater = false;
  final outputs = <String, bool>{
    'pump': true,
    'heater': false,
    'cooler': false,
    'tumbler': true,
  };
  int _tick = 0;
  DemoRepository(this.settings);
  @override
  Stream<Telemetry> get telemetry => _stream.stream;
  @override
  DeviceSettings get reportedSettings => settings;
  Telemetry snapshot({DateTime? now}) {
    final time = now ?? DateTime.now();
    if (manualUntil != null && !time.isBefore(manualUntil!)) {
      mode = RunMode.automatic;
      manualUntil = null;
      outputs.addAll({
        'pump': true,
        'tumbler': true,
        'heater': false,
        'cooler': false,
      });
    }
    if (lowWater) {
      outputs.addAll({
        'pump': false,
        'heater': false,
        'cooler': false,
        'tumbler': false,
      });
    }
    return Telemetry(
      at: time,
      temperature: settings.temperatureTarget + .18 * sin(_tick / 4),
      ph: abnormalPh
          ? 5.2
          : (settings.phMinimum + settings.phMaximum) / 2 +
                .04 * cos(_tick / 3),
      phCalibrated: true,
      phCalibratedAt: time.subtract(const Duration(days: 1)),
      wifiRssi: -54,
      firmwareVersion: 'sim-0.2',
      flow: outputs['pump'] == true
          ? settings.flowTarget + .08 * sin(_tick / 3)
          : 0,
      waterLevelOk: !lowWater,
      simulated: true,
      mode: mode,
      outputs: Map.unmodifiable(outputs),
      manualUntil: manualUntil,
    );
  }

  void _emit() {
    if (!_stream.isClosed) _stream.add(snapshot());
  }

  @override
  Future<void> connect() async {
    _emit();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      _tick++;
      _emit();
    });
  }

  @override
  Future<CommandResult> command(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final id = createId();
    await Future<void>.delayed(const Duration(milliseconds: 550));
    snapshot();
    if (action == 'set_mode') {
      mode = payload['mode'] == 'manual' ? RunMode.manual : RunMode.automatic;
      manualUntil = mode == RunMode.manual
          ? DateTime.now().add(const Duration(minutes: 5))
          : null;
      if (mode == RunMode.automatic) {
        outputs.addAll({
          'pump': true,
          'tumbler': true,
          'heater': false,
          'cooler': false,
        });
      }
    } else if (action == 'set_output') {
      if (mode != RunMode.manual) {
        return CommandResult(
          id: id,
          applied: false,
          message: 'เลือกโหมดควบคุมเองก่อน',
        );
      }
      final key = payload['output'] as String;
      final enabled = payload['enabled'] == true;
      if (!outputs.containsKey(key)) {
        return CommandResult(
          id: id,
          applied: false,
          message: 'ไม่พบอุปกรณ์นี้',
        );
      }
      if (lowWater &&
          enabled &&
          ['pump', 'heater', 'cooler', 'tumbler'].contains(key)) {
        return CommandResult(
          id: id,
          applied: false,
          message: 'ระดับน้ำต่ำ เครื่องปฏิเสธคำสั่ง',
        );
      }
      if (enabled &&
          ['heater', 'cooler', 'tumbler'].contains(key) &&
          outputs['pump'] != true) {
        return CommandResult(
          id: id,
          applied: false,
          message: 'ต้องมีการไหลของน้ำก่อน',
        );
      }
      if (enabled && key == 'heater' && outputs['cooler'] == true ||
          enabled && key == 'cooler' && outputs['heater'] == true) {
        return CommandResult(
          id: id,
          applied: false,
          message: 'เปิดระบบทำความร้อนและทำความเย็นพร้อมกันไม่ได้',
        );
      }
      outputs[key] = enabled;
      if (key == 'pump' && !enabled) {
        outputs['heater'] = false;
        outputs['cooler'] = false;
        outputs['tumbler'] = false;
      }
    } else if (action == 'set_config') {
      final candidate = DeviceSettings.fromJson(payload);
      final error = candidate.validate();
      if (error != null) {
        return CommandResult(id: id, applied: false, message: error);
      }
      settings = candidate;
    } else {
      return CommandResult(
        id: id,
        applied: false,
        message: 'ไม่รองรับคำสั่งนี้',
      );
    }
    _emit();
    return CommandResult(
      id: id,
      applied: true,
      message: 'เครื่องจำลองยืนยันคำสั่งแล้ว',
    );
  }

  void scenario({required bool ph, required bool water}) {
    abnormalPh = ph;
    lowWater = water;
    if (!water && mode == RunMode.automatic) {
      outputs.addAll({'pump': true, 'tumbler': true});
    }
    _emit();
  }

  @override
  Future<AnalysisResult> analyze(
    Uint8List bytes,
    String filename,
    bool video,
  ) async => throw StateError(
    'ภาพจริงต้องเชื่อมต่อเซิร์ฟเวอร์ AI หรือใช้การนับด้วยมือ',
  );
  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _stream.close();
  }

  @override
  Future<DeviceCameraStatus> cameraStatus() async => const DeviceCameraStatus(
    message: 'โหมดจำลอง • เชื่อมต่อเครื่องจริงในตั้งค่าเพื่อใช้กล้องในเครื่อง',
  );
  @override
  Future<DeviceCapture> capture(
    String requestId, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  }) async => throw StateError('โหมดจำลองไม่สั่งถ่ายจากกล้องจริง');
  @override
  Future<AnalysisResult> analyzeCapture(String captureId) async =>
      throw StateError('เชื่อมต่อเซิร์ฟเวอร์จริงก่อนนับภาพจากเครื่อง');
}
