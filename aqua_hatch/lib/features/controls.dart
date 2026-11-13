import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/theme.dart';
import '../app/brand.dart';
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
    if (fill != null || state.connection.localEsp32) {
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
                          child: Pill(time, icon: PhosphorIconsRegular.timer),
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
          const SizedBox(height: 24),
          const SectionHeading('อุปกรณ์'),
          Surface(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Column(
              children: [
                for (final entry in [
                  (PhosphorIconsRegular.waves, 'ปั๊มน้ำ', 'pump'),
                  (PhosphorIconsRegular.thermometer, 'ฮีตเตอร์', 'heater'),
                  (PhosphorIconsRegular.snowflake, 'ทำความเย็น', 'cooler'),
                  (
                    PhosphorIconsRegular.arrowsClockwise,
                    'หมุนเวียนไข่',
                    'tumbler',
                  ),
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
  final FillStatus? fill;
  final AppController controller;

  Future<void> _setFill(BuildContext context) async {
    final fill = this.fill;
    if (fill == null) return;
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
    final fill = this.fill;
    final active = state.fresh && fill?.running == true;
    final status = !state.fresh
        ? 'ออฟไลน์'
        : fill == null
        ? 'ไม่พร้อม'
        : active
        ? 'สั่งเปิดปั๊ม'
        : fill.armed
        ? 'รอเติมน้ำ'
        : 'ปิดระบบ';
    return PageBody(
      children: [
        const PageTitle('ควบคุมเครื่อง'),
        if (state.telemetry?.heater != null) ...[
          _Thermostat(state: state, controller: controller),
          const SizedBox(height: 16),
        ],
        AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: active ? AquaColors.deep : AquaColors.paper,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AquaColors.sage,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      PhosphorIconsRegular.drop,
                      color: AquaColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ปั๊มเติมน้ำ',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: active ? AquaColors.paper : AquaColors.deep,
                          ),
                        ),
                        Text(
                          'RY1',
                          style: TextStyle(
                            color: active ? AquaColors.lime : AquaColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    PhosphorIconsRegular.power,
                    size: 30,
                    color: active ? AquaColors.lime : AquaColors.muted,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Align(
                        key: ValueKey(status),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          status,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: active ? AquaColors.paper : AquaColors.deep,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    state.fresh ? fill?.waterLabel ?? 'รอลูกลอย' : 'รอข้อมูล',
                    style: TextStyle(
                      color: active ? AquaColors.lime : AquaColors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.canControlFill && !state.busy
                    ? () => _setFill(context)
                    : null,
                style: active
                    ? FilledButton.styleFrom(
                        backgroundColor: AquaColors.lime,
                        foregroundColor: AquaColors.deep,
                      )
                    : null,
                icon: state.busy
                    ? const AquaLoader(label: 'กำลังส่งคำสั่ง', compact: true)
                    : Icon(
                        fill?.armed == true
                            ? PhosphorIconsRegular.stop
                            : PhosphorIconsRegular.play,
                      ),
                label: Text(
                  state.busy
                      ? 'กำลังส่งคำสั่ง'
                      : fill?.armed == true
                      ? 'หยุดระบบเติมน้ำ'
                      : 'เปิดเติมน้ำอัตโนมัติ',
                ),
              ),
              if (fill?.timedOut == true) ...[
                const SizedBox(height: 12),
                Text(
                  'หยุดเมื่อครบ ${fill!.limitSeconds} วินาที',
                  style: const TextStyle(color: AquaColors.orange),
                ),
              ],
            ],
          ),
        ),
        if (!state.canControlFill) ...[
          const SizedBox(height: 16),
          Notice(
            state.telemetry?.viaRelay == true
                ? 'เชื่อม Wi-Fi ของเครื่องเพื่อสั่งงาน'
                : state.fresh
                ? 'รอวงจรควบคุมพร้อม'
                : 'เชื่อมต่อเครื่องเพื่อสั่งงาน',
            action: TextButton(
              onPressed: () => context.go('/settings'),
              child: const Text('เชื่อมต่อ'),
            ),
          ),
        ],
      ],
    );
  }
}

class _Thermostat extends StatefulWidget {
  const _Thermostat({required this.state, required this.controller});
  final AppState state;
  final AppController controller;
  @override
  State<_Thermostat> createState() => _ThermostatState();
}

class _ThermostatState extends State<_Thermostat> {
  late double _target = widget.state.settings.temperatureTarget;
  bool _dirty = false;
  @override
  void didUpdateWidget(_Thermostat oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dirty) _target = widget.state.settings.temperatureTarget;
  }

  Future<void> _save() async {
    final settings = widget.state.settings;
    final error = await widget.controller.saveSettings(
      DeviceSettings(
        temperatureTarget: _target,
        phMinimum: settings.phMinimum,
        phMaximum: settings.phMaximum,
      ),
    );
    if (!mounted) return;
    if (error == null) setState(() => _dirty = false);
    showFeedback(context, error, success: 'บอร์ดยืนยันอุณหภูมิแล้ว');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final heater = state.telemetry!.heater!;
    final canSet =
        state.fresh &&
        !state.busy &&
        state.telemetry?.viaRelay == false &&
        heater.ready;
    final status = !state.fresh
        ? 'ออฟไลน์'
        : !heater.ready
        ? 'วงจรไม่พร้อม'
        : state.telemetry?.temperature == null
        ? 'รอหัววัด'
        : heater.commandedOn == true
        ? 'สั่งเปิด'
        : heater.commandedOn == false
        ? 'สั่งปิด'
        : 'รอข้อมูล';
    void adjust(double delta) => setState(() {
      _target = ((_target + delta) * 2).round().clamp(40, 70) / 2;
      _dirty = true;
    });
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AquaColors.paper,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                PhosphorIconsRegular.thermometer,
                color: AquaColors.blue,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'ฮีตเตอร์',
                  style: TextStyle(
                    color: AquaColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(status, style: const TextStyle(color: AquaColors.blue)),
            ],
          ),
          DialValue(
            value: number(_target),
            unit: '°C',
            caption: 'อุณหภูมิเป้าหมาย',
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filledTonal(
                tooltip: 'ลดอุณหภูมิ',
                onPressed: canSet && _target > 20 ? () => adjust(-.5) : null,
                icon: const Icon(PhosphorIconsRegular.minus),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'ขณะนี้ ${number(state.telemetry?.temperature)} °C',
                  style: const TextStyle(color: AquaColors.blue),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'เพิ่มอุณหภูมิ',
                onPressed: canSet && _target < 35 ? () => adjust(.5) : null,
                icon: const Icon(PhosphorIconsRegular.plus),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_dirty)
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: canSet ? _save : null,
                icon: const Icon(PhosphorIconsRegular.check),
                label: const Text('บันทึกอุณหภูมิ'),
              ),
            )
          else
            const Text(
              'อัตโนมัติ · RY0',
              style: TextStyle(color: AquaColors.blue, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
