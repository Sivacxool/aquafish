class PhSensorInfo {
  final bool supported, stable;
  final String status;
  final double? adcVoltage, neutralVoltage, acidVoltage;
  final double neutralPh, acidPh;
  final DateTime? sampledAt;
  const PhSensorInfo({
    this.supported = false,
    this.stable = false,
    this.status = 'unavailable',
    this.adcVoltage,
    this.neutralVoltage,
    this.acidVoltage,
    this.neutralPh = 7,
    this.acidPh = 4,
    this.sampledAt,
  });
  factory PhSensorInfo.fromJson(Map<String, dynamic> j) {
    double? value(Object? n) => n is num && n.isFinite ? n.toDouble() : null;
    final c = j['ph_calibration'] is Map
        ? j['ph_calibration'] as Map
        : const {};
    return PhSensorInfo(
      supported: j['ph_status'] is String,
      status: j['ph_status'] is String
          ? j['ph_status'] as String
          : 'unavailable',
      stable: j['ph_stable'] == true,
      adcVoltage: value(j['ph_adc_voltage']),
      neutralVoltage: value(c['neutral_voltage']),
      acidVoltage: value(c['acid_voltage']),
      neutralPh: value(c['neutral_ph']) ?? 7,
      acidPh: value(c['acid_ph']) ?? 4,
      sampledAt: DateTime.tryParse(
        j['ph_sampled_at']?.toString() ?? '',
      )?.toLocal(),
    );
  }
  String get message => switch (status) {
    'ok' => 'อ่าน pH ที่สอบเทียบแล้ว',
    'not_calibrated' =>
      neutralVoltage != null && acidVoltage == null
          ? 'บันทึกจุดแรกแล้ว รอน้ำยา pH 4'
          : 'รอสอบเทียบด้วยน้ำยามาตรฐานสองจุด',
    'adc_not_found' => 'ไม่พบ ADS1115 ตรวจสายและไฟเลี้ยง',
    'warming_up' => 'กำลังรอแรงดันหัววัดให้คงที่',
    'input_out_of_range' => 'แรงดัน A0 อยู่นอกช่วง ตรวจวงจรแบ่งแรงดัน',
    'ph_out_of_range' => 'ค่าอยู่นอกช่วง pH 0–14 ตรวจหัววัดและการสอบเทียบ',
    'stale' => 'ข้อมูล pH ไม่เป็นปัจจุบัน',
    'read_error' ||
    'conversion_timeout' ||
    'config_mismatch' => 'อ่าน ADS1115 ไม่สำเร็จ ตรวจสาย I²C',
    _ => 'ต้องเชื่อม S3 ที่ใช้เฟิร์มแวร์รองรับ pH',
  };
  Map<String, dynamic> toJson() => supported
      ? {
          'ph_status': status,
          'ph_adc_voltage': adcVoltage,
          'ph_stable': stable,
          'ph_sampled_at': sampledAt?.toUtc().toIso8601String(),
          'ph_calibration': {
            'neutral_ph': neutralPh,
            'acid_ph': acidPh,
            'neutral_voltage': neutralVoltage,
            'acid_voltage': acidVoltage,
          },
        }
      : {};
}
