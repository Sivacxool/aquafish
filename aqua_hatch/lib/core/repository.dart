import 'dart:typed_data';
import 'models.dart';
import 'camera.dart';

class CommandResult {
  final String id, message;
  final bool applied;
  const CommandResult({
    required this.id,
    required this.applied,
    required this.message,
  });
}

class AnalysisResult {
  final List<CountPoint> points;
  final String model;
  final Uint8List? frameBytes;
  const AnalysisResult(this.points, this.model, {this.frameBytes});
}

abstract class DeviceRepository {
  Stream<Telemetry> get telemetry;
  DeviceSettings? get reportedSettings;
  Future<void> connect();
  Future<CommandResult> command(String action, Map<String, dynamic> payload);
  Future<AnalysisResult> analyze(Uint8List bytes, String filename, bool video);
  Future<DeviceCameraStatus> cameraStatus();
  Future<DeviceCapture> capture(
    String requestId, {
    void Function(String)? onProgress,
    bool Function()? cancelled,
  });
  Future<AnalysisResult> analyzeCapture(String captureId);
  Future<void> dispose();
}
