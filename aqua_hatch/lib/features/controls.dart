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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final data = state.telemetry;
    if (data?.ettControl != null) {
      final floatOnly = data?.fill?.limitSeconds == null;
      return PageBody(
        children: [
          const PageTitle('ควบคุมเครื่อง'),
          RelayModeSelector(state: state, controller: controller),
          const SizedBox(height: 16),
          _RelayOutputs(state: state, controller: controller, ett: true),
          const SizedBox(height: 16),
          if (!state.manualActive && !floatOnly) ...[
            _FillControls(
              state: state,
              fill: data?.fill,
              controller: controller,
              embedded: true,
            ),
            const SizedBox(height: 16),
          ],
          if (data?.heater != null)
            _Thermostat(
              state: state,
              controller: controller,
              label: 'ตั้งอุณหภูมิ',
              details: 'ฮีตเตอร์และพัดลม · ±0.5 °C',
            ),
        ],
      );
    }
    final fill = data?.fill;
    if (fill != null || state.connection.localEsp32) {
      return _FillControls(state: state, fill: fill, controller: controller);
    }
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
          RelayModeSelector(state: state, controller: controller),
          const SizedBox(height: 24),
          _RelayOutputs(state: state, controller: controller),
        ],
      ],
    );
  }
}

class RelayModeSelector extends StatelessWidget {
  const RelayModeSelector({
    super.key,
    required this.state,
    required this.controller,
  });
  final AppState state;
  final AppController controller;

  Future<void> _mode(BuildContext context, bool manual) async {
    if (manual) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ควบคุมเอง 5 นาที?'),
          content: state.telemetry?.ettControl == null
              ? null
              : Text(
                  state.telemetry?.fill?.limitSeconds == null
                      ? 'ปั๊มเดินตามลูกลอยต่อ ฮีตเตอร์กับพัดลมเริ่มจากปิด'
                      : 'บอร์ดจะปิดรีเลย์เมื่อเข้า Manual',
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
  Widget build(BuildContext context) {
    final manual = state.manualActive;
    final remainingMs =
        state.telemetry?.manualUntil?.difference(state.now).inMilliseconds ?? 0;
    final seconds = ((remainingMs + 999) ~/ 1000).clamp(0, 300);
    final time =
        '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
    final localReady = state.canControl;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeading(
            'โหมดการทำงาน',
            trailing: state.busy
                ? const AquaLoader(label: 'กำลังส่งคำสั่ง', compact: true)
                : manual
                ? Semantics(
                    key: const ValueKey('manual-mode-remaining'),
                    label: 'กลับสู่อัตโนมัติใน $time',
                    child: Pill(time, icon: PhosphorIconsRegular.timer),
                  )
                : null,
          ),
          if (state.telemetry?.ettControl != null) ...[
            if (!state.fresh)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('รอข้อมูลล่าสุดจากบอร์ด'),
              )
            else if (state.telemetry?.viaRelay == true)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('เชื่อม Wi-Fi เดียวกับบอร์ดเพื่อสั่งงาน'),
              )
            else if (!localReady)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('วงจรรีเลย์ยังไม่พร้อม'),
              ),
          ],
          SegmentedButton<bool>(
            segments: [
              const ButtonSegment(value: false, label: Text('อัตโนมัติ')),
              ButtonSegment(
                value: true,
                label: Text(
                  state.telemetry?.ettControl != null
                      ? 'Manual 5 นาที'
                      : 'ควบคุมเอง',
                ),
              ),
            ],
            selected: {manual},
            onSelectionChanged: localReady && !state.busy
                ? (values) => _mode(context, values.first)
                : null,
          ),
        ],
      ),
    );
  }
}

class _RelayOutputs extends StatelessWidget {
  const _RelayOutputs({
    required this.state,
    required this.controller,
    this.ett = false,
  });
  final AppState state;
  final AppController controller;
  final bool ett;

  @override
  Widget build(BuildContext context) {
    final data = state.telemetry!;
    final manual = state.manualActive;
    final ready =
        state.fresh &&
        (ett ? data.ettControl?.ioReady == true : data.hardwareReady);
    final canSwitch = manual && state.canControl && !state.busy;
    final fill = data.fill;
    final floatOnly = ett && fill?.limitSeconds == null;
    final String? pumpStatus = !floatOnly || !ready || fill == null
        ? null
        : !fill.requested
        ? 'ลูกลอยตัด'
        : fill.armed
        ? 'ตามลูกลอย'
        : 'พักปั๊ม';
    final rows = [
      (
        PhosphorIconsRegular.waves,
        ett ? 'ปั๊มเติมน้ำ' : 'ปั๊มน้ำ',
        'pump',
        ett ? 'RY1' : null,
        ett
            ? (manual && fill?.requested == true ? fill?.armed : fill?.running)
            : data.output('pump'),
      ),
      (
        PhosphorIconsRegular.thermometer,
        'ฮีตเตอร์',
        'heater',
        ett ? 'RY0' : null,
        ett ? data.heater?.commandedOn : data.output('heater'),
      ),
      (
        PhosphorIconsRegular.snowflake,
        ett ? 'พัดลม' : 'ทำความเย็น',
        'cooler',
        ett ? 'RY2' : null,
        ett ? data.ettControl?.fanCommandedOn : data.output('cooler'),
      ),
      if (!ett)
        (
          PhosphorIconsRegular.arrowsClockwise,
          'หมุนเวียนไข่',
          'tumbler',
          null,
          data.output('tumbler'),
        ),
    ];
    return Surface(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: [
          const SectionHeading('อุปกรณ์'),
          for (final (icon, title, output, relay, active) in rows)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(icon, color: AquaColors.blue),
              title: Text(title),
              subtitle: relay == null
                  ? null
                  : Text(
                      output == 'pump' && pumpStatus != null
                          ? '$relay · $pumpStatus'
                          : relay,
                    ),
              trailing: manual
                  ? Semantics(
                      label: title,
                      child: Switch.adaptive(
                        key: ValueKey('manual-output-$output'),
                        value: active == true,
                        onChanged:
                            canSwitch &&
                                active != null &&
                                (!ett ||
                                    output != 'pump' ||
                                    fill?.requested == true)
                            ? (value) async {
                                final error = await controller.send(
                                  'set_output',
                                  {'output': output, 'enabled': value},
                                );
                                if (context.mounted) {
                                  showFeedback(
                                    context,
                                    error,
                                    success: 'บอร์ดรับคำสั่งแล้ว',
                                  );
                                }
                              }
                            : null,
                      ),
                    )
                  : Pill(
                      !ready || active == null
                          ? 'รอสถานะ'
                          : active
                          ? 'สั่งเปิด'
                          : 'สั่งปิด',
                      color: ready && active == true
                          ? AquaColors.teal
                          : AquaColors.muted,
                    ),
            ),
          if (ett && manual && fill?.timedOut == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('ปั๊มหยุดเมื่อครบ ${fill!.limitSeconds} วินาที'),
            ),
        ],
      ),
    );
  }
}

class _FillControls extends StatelessWidget {
  const _FillControls({
    required this.state,
    required this.fill,
    required this.controller,
    this.embedded = false,
  });

  final AppState state;
  final FillStatus? fill;
  final AppController controller;
  final bool embedded;

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
    final children = <Widget>[
      if (!embedded) const PageTitle('ควบคุมเครื่อง'),
      if (!embedded && state.telemetry?.heater != null) ...[
        const Notice('อัปเดตเฟิร์มแวร์ ETT เพื่อใช้ Manual และพัดลม'),
        const SizedBox(height: 16),
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
                        embedded ? 'เติมน้ำอัตโนมัติ' : 'ปั๊มเติมน้ำ',
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
      if (!embedded && !state.canControlFill) ...[
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
    ];
    return embedded
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          )
        : PageBody(children: children);
  }
}

class _Thermostat extends StatefulWidget {
  const _Thermostat({
    required this.state,
    required this.controller,
    this.label = 'ฮีตเตอร์',
    this.details = 'อัตโนมัติ · RY0',
  });
  final AppState state;
  final AppController controller;
  final String label, details;
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
              Expanded(
                child: Text(
                  widget.label,
                  style: const TextStyle(
                    color: AquaColors.navy,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (state.telemetry?.ettControl == null)
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
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'ขณะนี้ ${number(state.telemetry?.temperature)} °C',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AquaColors.blue),
                  ),
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
            Text(
              widget.details,
              style: const TextStyle(color: AquaColors.blue, fontSize: 12),
            ),
        ],
      ),
    );
  }
}
