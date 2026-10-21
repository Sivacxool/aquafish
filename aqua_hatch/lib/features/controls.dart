import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/models.dart';
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
          title: const Text('ใช้โหมดควบคุมเอง?'),
          content: const Text(
            'ควบคุมเอาต์พุตเองได้ 5 นาที จากนั้นเครื่องจะกลับสู่โหมดอัตโนมัติ ระบบป้องกันของเครื่องยังทำงานอยู่',
          ),
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
      if (confirmed != true) return;
    }
    final error = await controller.send('set_mode', {
      'mode': manual ? 'manual' : 'auto',
      'duration_seconds': 300,
    });
    if (context.mounted) {
      showFeedback(context, error, success: 'เครื่องยืนยันโหมดแล้ว');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final data = state.telemetry;
    final manual = data?.mode == RunMode.manual;
    final remaining = Duration(
      seconds: (data?.manualUntil?.difference(state.now).inSeconds ?? 0).clamp(
        0,
        300,
      ),
    );
    return PageBody(
      children: [
        const PageTitle(
          'ควบคุมเครื่อง',
          'ตั้งค่าโหมดและตรวจสอบการทำงานของอุปกรณ์',
        ),
        if (state.busy) ...[
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 10),
          const Notice('กำลังส่งคำสั่งและรอเครื่องยืนยัน…'),
          const SizedBox(height: 18),
        ],
        if (data?.hardwareReady == false) ...[
          Notice(
            data?.hardwareMessage ?? 'บอร์ดออนไลน์ แต่ยังไม่ติดตั้งวงจรควบคุม',
            warning: true,
          ),
          const SizedBox(height: 18),
        ],
        if (!state.fresh) ...[
          const Notice(
            'ข้อมูลเครื่องไม่เป็นปัจจุบัน ปุ่มควบคุมถูกพักไว้จนเชื่อมต่อได้',
            warning: true,
          ),
          const SizedBox(height: 18),
        ],
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'โหมดการทำงาน',
                trailing: Pill(
                  data?.hardwareReady == false
                      ? 'รอติดตั้งอุปกรณ์'
                      : manual
                      ? 'ควบคุมเอง'
                      : 'อัตโนมัติ',
                  icon: manual
                      ? Icons.touch_app_outlined
                      : Icons.auto_awesome_outlined,
                ),
              ),
              LayoutBuilder(
                builder: (context, c) {
                  final items = [
                    _ModeTile(
                      title: 'อัตโนมัติ',
                      description: 'ให้เครื่องรักษาสภาวะตามค่าที่ตั้งไว้',
                      icon: Icons.auto_awesome_rounded,
                      selected: !manual && data?.hardwareReady != false,
                      onTap: state.canControl && !state.busy
                          ? () => _mode(context, controller, false)
                          : null,
                    ),
                    _ModeTile(
                      title: 'ควบคุมเอง',
                      description: 'เปิด–ปิดอุปกรณ์เอง ชั่วคราว 5 นาที',
                      icon: Icons.touch_app_outlined,
                      selected: manual,
                      onTap: state.canControl && !state.busy
                          ? () => _mode(context, controller, true)
                          : null,
                    ),
                  ];
                  return c.maxWidth >= 550
                      ? Row(
                          children: [
                            Expanded(child: items[0]),
                            const SizedBox(width: 16),
                            Expanded(child: items[1]),
                          ],
                        )
                      : Column(
                          children: [
                            items[0],
                            const SizedBox(height: 14),
                            items[1],
                          ],
                        );
                },
              ),
              if (manual && data?.manualUntil != null) ...[
                const SizedBox(height: 14),
                Notice(
                  'กลับสู่อัตโนมัติใน ${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}',
                  action: TextButton(
                    onPressed: state.busy
                        ? null
                        : () => _mode(context, controller, false),
                    child: const Text('กลับอัตโนมัติ'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Notice(
          data?.hardwareReady == false
              ? 'บันทึกค่าตั้งและทดสอบบอร์ดในหน้า “ตั้งค่า” ได้ การเปิดอุปกรณ์จะพร้อมหลังติดตั้งและตรวจวงจรจริง'
              : manual
              ? 'สั่งงานได้ชั่วคราว สถานะเปลี่ยนเมื่อเครื่องยืนยันคำสั่ง'
              : 'อัตโนมัติกำลังควบคุม เลือก “ควบคุมเอง” เพื่อสั่งเปิด–ปิดอุปกรณ์',
        ),
        const SizedBox(height: 16),
        const SectionHeading('อุปกรณ์ในเครื่อง'),
        ...[
          (Icons.water_rounded, 'ปั๊มน้ำ', 'หมุนเวียนน้ำในระบบฟัก', 'pump'),
          (
            Icons.thermostat_rounded,
            'ฮีตเตอร์',
            'ระบบเพิ่มอุณหภูมิน้ำ',
            'heater',
          ),
          (
            Icons.ac_unit_rounded,
            'ระบบทำความเย็น',
            'ระบบลดอุณหภูมิน้ำ',
            'cooler',
          ),
          (
            Icons.sync_rounded,
            'ระบบหมุนเวียนไข่',
            'ควบคุมกลไกตามชุดอุปกรณ์จริง',
            'tumbler',
          ),
        ].map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Surface(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
              child: Row(
                children: [
                  Container(
                    width: 45,
                    height: 45,
                    decoration: BoxDecoration(
                      color: AquaColors.blue.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(entry.$1, color: AquaColors.blue, size: 23),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.$2,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          entry.$3,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          data?.hardwareReady == false
                              ? 'ยังไม่ติดตั้ง / ยังไม่ยืนยันวงจร'
                              : data == null
                              ? 'รอข้อมูลเครื่อง'
                              : 'เครื่องรายงาน: ${data.output(entry.$4) ? 'เปิด' : 'ปิด'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: data?.output(entry.$4) == true
                                ? AquaColors.teal
                                : AquaColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!manual)
                    Pill(
                      data?.hardwareReady == false
                          ? 'รอติดตั้ง'
                          : data == null
                          ? 'รอข้อมูล'
                          : data.output(entry.$4)
                          ? 'เปิด'
                          : 'ปิด',
                      color: data == null || !data.output(entry.$4)
                          ? AquaColors.muted
                          : AquaColors.teal,
                      icon: data?.output(entry.$4) == true
                          ? Icons.check_circle_outline
                          : Icons.power_settings_new,
                    )
                  else
                    Switch.adaptive(
                      value: data?.output(entry.$4) ?? false,
                      onChanged: manual && state.canControl && !state.busy
                          ? (value) async {
                              final error = await controller.send(
                                'set_output',
                                {'output': entry.$4, 'enabled': value},
                              );
                              if (context.mounted) {
                                showFeedback(
                                  context,
                                  error,
                                  success: 'เครื่องยืนยันคำสั่งแล้ว',
                                );
                              }
                            }
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Notice(
          manual
              ? 'สถานะสวิตช์เปลี่ยนเมื่อเครื่องรายงานกลับ การเปิดรีเลย์ยังไม่ยืนยันว่าอุปกรณ์ทำงานจริง'
              : 'เลือก “ควบคุมเอง” เพื่อเปิด–ปิดอุปกรณ์ โหมดอัตโนมัติควบคุมจากตัวเครื่อง',
        ),
        const SizedBox(height: 22),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('เงื่อนไขป้องกันในเครื่องจำลอง'),
              const _SafetyRow(
                'ระดับน้ำต่ำ: ปิดปั๊ม ฮีตเตอร์ และระบบหมุนเวียนไข่',
              ),
              const _SafetyRow(
                'ไม่มีปั๊มทำงาน: ไม่อนุญาตให้เปิดฮีตเตอร์หรือระบบทำความเย็น',
              ),
              const _SafetyRow('ไม่เปิดระบบทำความร้อนและทำความเย็นพร้อมกัน'),
              const _SafetyRow('เมื่อครบ 5 นาที: กลับสู่โหมดอัตโนมัติ'),
              const SizedBox(height: 10),
              const Text(
                'เครื่องจริงต้องใช้ Firmware ที่ตรวจเงื่อนไขเหล่านี้ด้วย รุ่นเซนเซอร์และวงจรยังต้องยืนยัน',
                style: TextStyle(fontSize: 12, color: AquaColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ModeTile extends StatelessWidget {
  final String title, description;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  const _ModeTile({
    required this.title,
    required this.description,
    required this.icon,
    required this.selected,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: selected ? const Color(0xFFEAF5F8) : AquaColors.background,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AquaColors.blue : AquaColors.line,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? AquaColors.blue : AquaColors.muted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle_rounded,
                color: AquaColors.blue,
                size: 20,
              ),
          ],
        ),
      ),
    ),
  );
}

class _SafetyRow extends StatelessWidget {
  final String text;
  const _SafetyRow(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.verified_user_outlined,
          color: AquaColors.teal,
          size: 17,
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ],
    ),
  );
}
