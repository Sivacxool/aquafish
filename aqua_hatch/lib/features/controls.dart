import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/motion.dart';
import '../core/ui.dart';

class ControlsScreen extends ConsumerWidget {
  const ControlsScreen({super.key});

  Future<void> _mode(
    BuildContext context,
    AppController controller,
    bool manual,
  ) async {
    if (manual) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ควบคุมเอง 5 นาที?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('เริ่มควบคุม'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final error = await controller.send('set_mode', {
      'mode': manual ? 'manual' : 'auto',
      'duration_seconds': 300,
    });
    if (context.mounted) {
      showFeedback(context, error, success: 'เปลี่ยนโหมดแล้ว');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final data = state.telemetry;
    final fill = data?.fill;
    if (fill != null) {
      return _FillControls(state: state, fill: fill, controller: controller);
    }
    final manual = data?.mode == RunMode.manual;
    final remaining = Duration(
      seconds: (data?.manualUntil?.difference(state.now).inSeconds ?? 0).clamp(
        0,
        300,
      ),
    );
    final time =
        '${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}';
    return PageBody(
      children: [
        const PageTitle('ควบคุมเครื่อง'),
        if (!state.fresh) ...[
          Notice(
            'บอร์ดออฟไลน์',
            warning: true,
            action: TextButton(
              onPressed: () => context.go('/settings'),
              child: const Text('ตั้งค่า'),
            ),
          ),
          const SizedBox(height: 12),
        ] else if (data?.hardwareReady == false) ...[
          const Notice('รอติดตั้งวงจรควบคุม', warning: true),
          const SizedBox(height: 12),
        ],
        if (data != null) ...[
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeading(
                  'โหมดการทำงาน',
                  trailing: state.busy
                      ? const AquaLoader(label: 'กำลังส่งคำสั่ง', compact: true)
                      : manual && data.manualUntil != null
                      ? Semantics(
                          key: const ValueKey('manual-mode-remaining'),
                          label: 'กลับสู่อัตโนมัติใน $time',
                          child: Pill(time, icon: Icons.timer_outlined),
                        )
                      : null,
                ),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('อัตโนมัติ')),
                    ButtonSegment(value: true, label: Text('ควบคุมเอง')),
                  ],
                  selected: {manual},
                  onSelectionChanged: state.canControl && !state.busy
                      ? (values) => _mode(context, controller, values.first)
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const SectionHeading('อุปกรณ์'),
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (final entry in [
                  (Icons.water_rounded, 'ปั๊มน้ำ', 'pump'),
                  (Icons.thermostat_rounded, 'ฮีตเตอร์', 'heater'),
                  (Icons.ac_unit_rounded, 'ทำความเย็น', 'cooler'),
                  (Icons.sync_rounded, 'หมุนเวียนไข่', 'tumbler'),
                ])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(entry.$1, color: AquaColors.blue),
                    title: Text(entry.$2),
                    trailing: manual
                        ? Switch.adaptive(
                            value: data.output(entry.$3),
                            onChanged: state.canControl && !state.busy
                                ? (value) async {
                                    final error = await controller.send(
                                      'set_output',
                                      {'output': entry.$3, 'enabled': value},
                                    );
                                    if (context.mounted) {
                                      showFeedback(
                                        context,
                                        error,
                                        success: 'ส่งคำสั่งแล้ว',
                                      );
                                    }
                                  }
                                : null,
                          )
                        : Pill(
                            data.hardwareReady == false
                                ? 'รอติดตั้ง'
                                : data.output(entry.$3)
                                ? 'สั่งเปิด'
                                : 'สั่งปิด',
                            color: data.output(entry.$3)
                                ? AquaColors.teal
                                : AquaColors.muted,
                          ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _FillControls extends StatelessWidget {
  const _FillControls({
    required this.state,
    required this.fill,
    required this.controller,
  });

  final AppState state;
  final FillStatus fill;
  final AppController controller;

  Future<void> _setFill(BuildContext context) async {
    final enabled = !fill.armed;
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('เปิดเติมน้ำอัตโนมัติ?'),
          content: Text(
            'เติมเมื่อระดับน้ำต่ำ สูงสุด ${fill.limitSeconds} วินาทีต่อรอบ',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ยืนยันเปิด'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    final error = await controller.send('set_fill', {'enabled': enabled});
    if (!context.mounted) return;
    showFeedback(
      context,
      error,
      success: enabled ? 'เปิดระบบเติมน้ำแล้ว' : 'ปิดระบบเติมน้ำแล้ว',
    );
  }

  @override
  Widget build(BuildContext context) {
    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    final active = state.fresh && fill.running;
    final status = !state.fresh
        ? 'ออฟไลน์'
        : active
        ? 'สั่งเปิดปั๊ม'
        : fill.armed
        ? 'รอเติมน้ำ'
        : 'ปิดระบบ';
    return PageBody(
      children: [
        const PageTitle('ควบคุมเครื่อง'),
        AnimatedContainer(
          duration: motion,
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: active ? AquaColors.lime : AquaColors.sage,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.water_drop_outlined,
                size: 35,
                color: AquaColors.blue,
              ),
              const SizedBox(height: 14),
              const Text('ปั๊มเติมน้ำ'),
              AnimatedSwitcher(
                duration: motion,
                child: Text(
                  status,
                  key: ValueKey(status),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.waves_rounded, color: AquaColors.blue),
            title: const Text('ระดับน้ำ'),
            trailing: Pill(
              state.fresh ? fill.waterLabel : 'รอข้อมูล',
              color: state.fresh && !fill.requested
                  ? AquaColors.orange
                  : AquaColors.blue,
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (!state.canControlFill)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Notice('ใช้ Wi-Fi เดียวกับบอร์ดเพื่อสั่งงาน'),
          ),
        if (fill.timedOut)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Notice(
              'ปั๊มหยุดเมื่อครบ ${fill.limitSeconds} วินาที',
              warning: true,
            ),
          ),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: state.canControlFill && !state.busy
                ? () => _setFill(context)
                : null,
            icon: state.busy
                ? const AquaLoader(label: 'กำลังส่งคำสั่ง', compact: true)
                : Icon(
                    fill.armed ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  ),
            label: Text(
              state.busy
                  ? 'กำลังส่งคำสั่ง'
                  : fill.armed
                  ? 'หยุดระบบเติมน้ำ'
                  : 'เปิดเติมน้ำอัตโนมัติ',
            ),
          ),
        ),
      ],
    );
  }
}
