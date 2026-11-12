import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/ph.dart';
import '../core/ui.dart';

class PhCalibrationScreen extends ConsumerStatefulWidget {
  const PhCalibrationScreen({super.key});
  @override
  ConsumerState<PhCalibrationScreen> createState() =>
      _PhCalibrationScreenState();
}

class _PhCalibrationScreenState extends ConsumerState<PhCalibrationScreen> {
  double _neutral = 7, _acid = 4;
  bool _sending = false;
  Future<void> _capture(double buffer, bool startNew) async {
    setState(() => _sending = true);
    final error = await ref
        .read(appControllerProvider.notifier)
        .calibratePh(buffer, startNew: startNew);
    if (!mounted) return;
    setState(() => _sending = false);
    showFeedback(
      context,
      error,
      success: startNew
          ? 'บันทึกจุดแรกแล้ว ล้างหัววัดก่อนย้ายไปน้ำยา pH 4'
          : 'S3 ยืนยันบันทึกการสอบเทียบสองจุดแล้ว',
    );
  }

  Widget _selector(
    String label,
    double value,
    List<double> options,
    ValueChanged<double?> changed,
  ) => DropdownButtonFormField<double>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: options
        .map(
          (v) => DropdownMenuItem(
            value: v,
            child: Text('pH ${v.toStringAsFixed(2)}'),
          ),
        )
        .toList(),
    onChanged: _sending ? null : changed,
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider), t = state.telemetry;
    final info = t?.phSensor ?? const PhSensorInfo();
    final live =
        state.connected &&
        !state.connection.demo &&
        state.connection.localEsp32 &&
        (t?.isFresh(DateTime.now()) ?? false);
    final ready =
        live &&
        info.supported &&
        info.stable &&
        info.adcVoltage != null &&
        !_sending &&
        !state.busy;
    final firstSaved =
        t?.phCalibrated == false &&
        info.neutralVoltage != null &&
        (info.neutralPh - _neutral).abs() < 0.001;
    return Scaffold(
      appBar: AppBar(title: const Text('สอบเทียบ pH')),
      body: PageBody(
        children: [
          const PageTitle(
            'ตั้งค่า pH ครั้งแรก',
            subtitle: 'E-201-C / PH-4502C / ADS1115',
          ),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  live
                      ? info.message
                      : 'เชื่อม S3 จริงเพื่อดูแรงดันและสอบเทียบ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'แรงดัน A0: ${live && info.adcVoltage != null ? '${info.adcVoltage!.toStringAsFixed(3)} V' : '—'}',
                ),
                Text(
                  live && info.stable
                      ? 'แรงดันคงที่ พร้อมบันทึกจุด'
                      : 'รอค่าคงที่ก่อนบันทึก',
                ),
                if (t?.phCalibrated == true)
                  const Text(
                    'บอร์ดเก็บค่าการสอบเทียบแล้ว เปิดครั้งถัดไปใช้งานต่อได้',
                  ),
                if (live && !info.supported)
                  const Text('ต้องลงเฟิร์มแวร์ S3 0.13.0 ก่อน'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '1. จุ่มน้ำยาจุดแรก',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'เลือกค่าตามฉลากน้ำยา จุ่มหัววัด รอค่าคงที่ประมาณ 30–60 วินาทีหรือจนหัววัดนิ่ง แล้วบันทึก',
                ),
                const SizedBox(height: 12),
                _selector('น้ำยาจุดแรก', _neutral, const [7, 6.86], (v) {
                  if (v != null) setState(() => _neutral = v);
                }),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('ph-calibrate-neutral'),
                  onPressed: ready ? () => _capture(_neutral, true) : null,
                  icon: const Icon(Icons.science_outlined),
                  label: Text(
                    'เริ่มสอบเทียบ · pH ${_neutral.toStringAsFixed(2)}',
                  ),
                ),
                const Text(
                  'การเริ่มรอบใหม่จะพักค่า pH จนกว่าจะบันทึกครบสองจุด',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '2. ล้างแล้วจุ่มน้ำยา pH 4',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'ล้างหัววัดด้วยน้ำกลั่น ซับเบา ๆ แล้วจุ่มน้ำยาจุดที่สอง รอค่าคงที่ก่อนบันทึก',
                ),
                const SizedBox(height: 12),
                _selector('น้ำยาจุดที่สอง', _acid, const [4, 4.01], (v) {
                  if (v != null) setState(() => _acid = v);
                }),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('ph-calibrate-acid'),
                  onPressed: ready && firstSaved
                      ? () => _capture(_acid, false)
                      : null,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text('บันทึกจุด pH ${_acid.toStringAsFixed(2)}'),
                ),
                const Text(
                  'บันทึกในบอร์ด S3 และใช้ต่อหลังเปิดเครื่องใหม่ได้ ไม่ต้องจุ่มน้ำยาทุกครั้ง',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'สายที่ใช้',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  'ADS1115: VDD = 3.3V · GND ร่วม · ADDR = GND · ต่อ SDA/SCL ตามผังของบอร์ดหลัก',
                ),
                SizedBox(height: 8),
                Text(
                  'PH-4502C: V+ = 5V · G = GND ร่วม · PO ผ่าน 10kΩ เข้า A0 และต่อ 10kΩ จาก A0 ลง GND',
                ),
                SizedBox(height: 8),
                Text(
                  'หัววัดเสียบ BNC ของ PH-4502C ห้ามต่อหัววัดเข้า ADS1115 โดยตรง และไม่ต่อ PO 5V ตรงเข้า A0',
                ),
                SizedBox(height: 8),
                Text(
                  'รุ่นนี้สอบเทียบแบบสองจุด ไม่ชดเชยอุณหภูมิอัตโนมัติ ควรสอบเทียบใกล้อุณหภูมิที่จะใช้งานจริง',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
