import 'dart:math';

enum RunMode { automatic, manual }

class DeviceSettings {
  final double temperatureTarget, phMinimum, phMaximum, flowTarget;
  const DeviceSettings({
    this.temperatureTarget = 28,
    this.phMinimum = 6.5,
    this.phMaximum = 8.5,
    this.flowTarget = 2.4,
  });
  String? validate() {
    if (!temperatureTarget.isFinite ||
        temperatureTarget < 20 ||
        temperatureTarget > 35) {
      return 'อุณหภูมิต้องอยู่ระหว่าง 20–35 °C';
    }
    if (!phMinimum.isFinite ||
        !phMaximum.isFinite ||
        phMinimum < 0 ||
        phMaximum > 14 ||
        phMinimum >= phMaximum) {
      return 'ช่วง pH ต้องอยู่ระหว่าง 0–14 และค่าต่ำสุดต้องน้อยกว่าค่าสูงสุด';
    }
    if (!flowTarget.isFinite || flowTarget <= 0 || flowTarget > 50) {
      return 'อัตราไหลต้องมากกว่า 0 และไม่เกิน 50 L/min';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'temperature_target': temperatureTarget,
    'ph_minimum': phMinimum,
    'ph_maximum': phMaximum,
    'flow_target': flowTarget,
  };
  factory DeviceSettings.fromJson(Map<String, dynamic> json) => DeviceSettings(
    temperatureTarget: (json['temperature_target'] as num?)?.toDouble() ?? 28,
    phMinimum: (json['ph_minimum'] as num?)?.toDouble() ?? 6.5,
    phMaximum: (json['ph_maximum'] as num?)?.toDouble() ?? 8.5,
    flowTarget: (json['flow_target'] as num?)?.toDouble() ?? 2.4,
  );
}

class ConnectionConfig {
  final bool demo;
  final bool localEsp32;
  final String baseUrl, deviceId;
  const ConnectionConfig({
    this.demo = true,
    this.localEsp32 = false,
    this.baseUrl = 'http://localhost:8000',
    this.deviceId = 'incubator-01',
  });
  String? validate() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,64}$').hasMatch(deviceId)) {
      return 'รหัสเครื่องใช้ตัวอักษรอังกฤษ ตัวเลข - หรือ _';
    }
    if (demo) return null;
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        uri.host.isEmpty ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return 'กรุณาใส่ URL เซิร์ฟเวอร์ให้ถูกต้อง';
    }
    if (localEsp32) {
      if (uri.scheme != 'https' ||
          uri.port != 443 ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          !isPrivateIpv4(uri.host)) {
        return 'ใส่ URL บอร์ดในบ้านแบบ HTTPS เช่น https://192.168.1.50';
      }
      return null;
    }
    final local = [
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
      '::1',
    ].contains(uri.host);
    if (uri.scheme != 'https' && !local) {
      return 'การเชื่อมเครื่องจริงต้องใช้ HTTPS';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'demo': demo,
    'local_esp32': localEsp32,
    'base_url': baseUrl,
    'device_id': deviceId,
  };
  factory ConnectionConfig.fromJson(Map<String, dynamic> j) => ConnectionConfig(
    demo: j['demo'] != false,
    localEsp32: j['local_esp32'] == true,
    baseUrl: j['base_url'] as String? ?? 'http://localhost:8000',
    deviceId: j['device_id'] as String? ?? 'incubator-01',
  );
}

bool isPrivateIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;
  final bytes = <int>[];
  for (final part in parts) {
    if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) return false;
    final value = int.tryParse(part);
    if (value == null || value > 255) return false;
    bytes.add(value);
  }
  return bytes[0] == 10 ||
      (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
      (bytes[0] == 192 && bytes[1] == 168);
}

class Telemetry {
  final DateTime at;
  final double? temperature, ph, flow;
  final bool? waterLevelOk;
  final bool phCalibrated;
  final DateTime? phCalibratedAt;
  final int? wifiRssi;
  final String? firmwareVersion;
  final bool simulated;
  final bool deviceOnline;
  final bool hardwareReady;
  final String? hardwareMessage;
  final RunMode mode;
  final Map<String, bool> outputs;
  final DateTime? manualUntil;
  const Telemetry({
    required this.at,
    this.temperature,
    this.ph,
    this.flow,
    this.waterLevelOk,
    this.phCalibrated = false,
    this.phCalibratedAt,
    this.wifiRssi,
    this.firmwareVersion,
    this.simulated = false,
    this.deviceOnline = true,
    this.hardwareReady = true,
    this.hardwareMessage,
    this.mode = RunMode.automatic,
    this.outputs = const {},
    this.manualUntil,
  });
  bool isFresh(DateTime now) =>
      deviceOnline &&
      now.difference(at).inSeconds <= 15 &&
      !at.isAfter(now.add(const Duration(seconds: 5)));
  bool output(String key) => outputs[key] ?? false;
  List<String> alerts(DeviceSettings settings) {
    final result = <String>[];
    if (temperature == null) {
      result.add('อ่านค่าอุณหภูมิไม่ได้');
    } else if ((temperature! - settings.temperatureTarget).abs() > 1) {
      result.add('อุณหภูมิออกนอกช่วงที่ตั้งไว้');
    }
    if (ph == null) {
      result.add('อ่านค่า pH ไม่ได้');
    } else if (!phCalibrated) {
      result.add('เซนเซอร์ pH ยังไม่ยืนยันการสอบเทียบ');
    } else if (ph! < settings.phMinimum || ph! > settings.phMaximum) {
      result.add('pH อยู่นอกช่วงที่ตั้งไว้');
    }
    if (flow == null) {
      result.add('อ่านค่าอัตราไหลไม่ได้');
    } else if (output('pump') && flow! < 0.1) {
      result.add('ปั๊มเปิดอยู่ แต่ไม่พบการไหล');
    }
    if (waterLevelOk == null) result.add('อ่านค่าระดับน้ำไม่ได้');
    if (waterLevelOk == false) result.add('ระดับน้ำต่ำ ระบบป้องกันทำงาน');
    return result;
  }

  Map<String, dynamic> toJson() => {
    'timestamp': at.toUtc().toIso8601String(),
    'temperature_c': temperature,
    'ph': ph,
    'ph_calibrated': phCalibrated,
    'ph_calibrated_at': phCalibratedAt?.toUtc().toIso8601String(),
    'wifi_rssi': wifiRssi,
    'firmware_version': firmwareVersion,
    'flow_l_min': flow,
    'water_level_ok': waterLevelOk,
    'simulated': simulated,
    'device_online': deviceOnline,
    'hardware_ready': hardwareReady,
    'hardware_message': hardwareMessage,
    'mode': mode == RunMode.manual ? 'manual' : 'auto',
    'outputs': outputs,
    'manual_until': manualUntil?.toUtc().toIso8601String(),
  };
  factory Telemetry.fromJson(Map<String, dynamic> j) {
    double? reading(String name) {
      final n = j[name];
      return n is num && n.isFinite ? n.toDouble() : null;
    }

    return Telemetry(
      at: DateTime.parse(j['timestamp'] as String).toLocal(),
      temperature: reading('temperature_c'),
      ph: reading('ph') != null && reading('ph')! >= 0 && reading('ph')! <= 14
          ? reading('ph')
          : null,
      phCalibrated: j['ph_calibrated'] == true,
      phCalibratedAt: DateTime.tryParse(
        j['ph_calibrated_at']?.toString() ?? '',
      )?.toLocal(),
      wifiRssi: j['wifi_rssi'] is int ? j['wifi_rssi'] as int : null,
      firmwareVersion: j['firmware_version'] as String?,
      flow: reading('flow_l_min'),
      waterLevelOk: j['water_level_ok'] is bool
          ? j['water_level_ok'] as bool
          : null,
      simulated: j['simulated'] == true,
      deviceOnline: j['device_online'] != false,
      hardwareReady: j['hardware_ready'] != false,
      hardwareMessage: j['hardware_message'] as String?,
      mode: j['mode'] == 'manual' ? RunMode.manual : RunMode.automatic,
      outputs: (j['outputs'] as Map? ?? {}).map(
        (k, v) => MapEntry(k.toString(), v == true),
      ),
      manualUntil: j['manual_until'] == null
          ? null
          : DateTime.parse(j['manual_until'] as String).toLocal(),
    );
  }
}

class HatchBatch {
  final String id, name;
  final DateTime startedAt;
  final int? eggs;
  const HatchBatch({
    required this.id,
    required this.name,
    required this.startedAt,
    this.eggs,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'started_at': startedAt.toUtc().toIso8601String(),
    'eggs': eggs,
  };
  factory HatchBatch.fromJson(Map<String, dynamic> j) => HatchBatch(
    id: j['id'] as String,
    name: j['name'] as String,
    startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
    eggs: j['eggs'] as int?,
  );
}

class CountPoint {
  final double x, y;
  const CountPoint(this.x, this.y);
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
  factory CountPoint.fromJson(Map<String, dynamic> j) => CountPoint(
    (j['x'] as num).toDouble().clamp(0, 1),
    (j['y'] as num).toDouble().clamp(0, 1),
  );
}

class CountRecord {
  final String id, batchId, batchName, source, method;
  final int count;
  final int? aiCount;
  final DateTime at;
  final bool demo;
  const CountRecord({
    required this.id,
    required this.batchId,
    required this.batchName,
    required this.source,
    required this.method,
    required this.count,
    required this.at,
    required this.demo,
    this.aiCount,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'batch_id': batchId,
    'batch_name': batchName,
    'source': source,
    'method': method,
    'count': count,
    'ai_count': aiCount,
    'at': at.toUtc().toIso8601String(),
    'demo': demo,
  };
  factory CountRecord.fromJson(Map<String, dynamic> j) => CountRecord(
    id: j['id'] as String,
    batchId: j['batch_id'] as String,
    batchName: j['batch_name'] as String,
    source: j['source'] as String,
    method: j['method'] as String,
    count: j['count'] as int,
    at: DateTime.parse(j['at'] as String).toLocal(),
    demo: j['demo'] == true,
    aiCount: j['ai_count'] as int?,
  );
}

String createId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    Random.secure().nextInt(1 << 30).toRadixString(36);
final samplePoints = List<CountPoint>.unmodifiable(
  List.generate(48, (i) {
    final r = Random(i * 97 + 11);
    return CountPoint(
      .07 + (i % 8) * .12 + r.nextDouble() * .035,
      .08 + (i ~/ 8) * .14 + r.nextDouble() * .05,
    );
  }),
);

class DeviceEvent {
  final String message;
  final DateTime at;
  final bool warning, acknowledged;
  DeviceEvent(
    this.message, {
    this.warning = false,
    this.acknowledged = false,
    DateTime? at,
  }) : at = at ?? DateTime.now();
  DeviceEvent acknowledge() =>
      DeviceEvent(message, warning: warning, acknowledged: true, at: at);
  Map<String, dynamic> toJson() => {
    'message': message,
    'at': at.toUtc().toIso8601String(),
    'warning': warning,
    'acknowledged': acknowledged,
  };
  factory DeviceEvent.fromJson(Map<String, dynamic> j) => DeviceEvent(
    j['message'] as String,
    at: DateTime.parse(j['at'] as String).toLocal(),
    warning: j['warning'] == true,
    acknowledged: j['acknowledged'] == true,
  );
}
