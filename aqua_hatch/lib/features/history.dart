import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/ui.dart';
import '../core/models.dart';

String telemetryCsv(List<Telemetry> samples) => [
  'timestamp_utc,temperature_c,ph,ph_calibrated,flow_l_min,water_level_ok,simulated',
  ...samples.map(
    (t) => [
      t.at.toUtc().toIso8601String(),
      t.temperature ?? '',
      t.ph ?? '',
      t.phCalibrated,
      t.flow ?? '',
      t.waterLevelOk ?? '',
      t.simulated,
    ].join(','),
  ),
].join('\r\n');

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});
  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  bool _loading = false;
  Future<void> _refresh() async {
    setState(() => _loading = true);
    final error = await ref
        .read(appControllerProvider.notifier)
        .loadServerHistory();
    if (!mounted) return;
    setState(() => _loading = false);
    showFeedback(context, error, success: 'โหลดประวัติแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final samples = state.history.reversed.toList();
    return Scaffold(
      appBar: AppBar(title: const Text('ประวัติคุณภาพน้ำ')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Text(
                  'มือถือเก็บสูงสุด 1,440 จุด ประมาณ 1 จุดต่อนาที ขณะเปิดแอป ส่วน Gateway เก็บต่อเนื่องแม้ปิดแอปเมื่อเซิร์ฟเวอร์ยังทำงาน',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (!state.connection.demo)
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                        label: Text(
                          _loading ? 'กำลังโหลด…' : 'โหลดจากเซิร์ฟเวอร์',
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: samples.isEmpty
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(
                                  text: telemetryCsv(state.history),
                                ),
                              );
                              if (context.mounted) {
                                showFeedback(
                                  context,
                                  null,
                                  success:
                                      'คัดลอก CSV แล้ว วางในไฟล์หรือสเปรดชีตได้',
                                );
                              }
                            },
                      icon: const Icon(Icons.copy_all_outlined),
                      label: const Text('คัดลอก CSV'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (samples.isEmpty)
            const Expanded(
              child: Center(child: Text('ยังไม่มีข้อมูลที่บันทึก')),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: samples.length,
                itemBuilder: (context, index) {
                  final t = samples[index];
                  return ListTile(
                    leading: Icon(
                      t.simulated
                          ? Icons.science_outlined
                          : Icons.water_drop_outlined,
                    ),
                    title: Text(
                      '${fullTime(t.at)}${t.simulated ? ' · จำลอง' : ''}',
                    ),
                    subtitle: Text(
                      '${number(t.temperature)} °C   •   pH ${number(t.ph)}${t.phCalibrated ? '' : ' (ยังไม่สอบเทียบ)'}\nไหล ${number(t.flow)} L/min   •   น้ำ ${t.waterLevelOk == null
                          ? 'ไม่ทราบ'
                          : t.waterLevelOk!
                          ? 'ปกติ'
                          : 'ต่ำ'}',
                    ),
                    isThreeLine: true,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
