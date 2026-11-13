import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/sensor_status.dart';
import '../core/ui.dart';
import 'history.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _phChart = false;
  int _hours = 1;
  void _details(AppState state) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading('สถานะเครื่อง'),
            Text(state.connectionLabel),
            if (state.telemetry?.firmwareVersion != null)
              Text('Firmware ${state.telemetry!.firmwareVersion}'),
            if (state.telemetry != null)
              Text('อัปเดต ${fullTime(state.telemetry!.at)}'),
            const SizedBox(height: 16),
            Text(
              sensorStatusLabel(
                state.telemetry?.temperatureStatus,
                source: 'DS18B20',
              ),
            ),
            Text(
              sensorStatusLabel(
                state.telemetry?.dissolvedOxygenStatus,
                source: 'DO · RS485',
              ),
            ),
            Text(state.telemetry?.phSensor.message ?? 'รอข้อมูล pH'),
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(state.error!),
            ],
            if (state.alerts.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...state.alerts.map((a) => Text('• $a')),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                ref.read(appControllerProvider.notifier).reconnect();
              },
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              label: const Text('เชื่อมต่อใหม่'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final data = state.telemetry;
    final controller = ref.read(appControllerProvider.notifier);
    final stale = !state.fresh;
    final demo = state.connection.demo || data?.simulated == true;
    final history = state.history
        .where(
          (t) => !t.at.isBefore(state.now.subtract(Duration(hours: _hours))),
        )
        .toList();
    final status = demo
        ? 'ข้อมูลทดลอง'
        : stale
        ? 'ออฟไลน์'
        : data?.viaRelay == true
        ? 'ผ่านอินเทอร์เน็ต'
        : 'ออนไลน์';
    return PageBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(child: PageTitle('ฟาร์มของคุณ')),
            InkWell(
              onTap: () => _details(state),
              borderRadius: BorderRadius.circular(20),
              child: Pill(
                status,
                icon: stale
                    ? PhosphorIconsRegular.wifiSlash
                    : PhosphorIconsRegular.circle,
                color: stale && !demo ? AquaColors.orange : AquaColors.blue,
              ),
            ),
          ],
        ),
        Surface(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'อุณหภูมิน้ำ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'สถานะเครื่อง',
                    onPressed: () => _details(state),
                    icon: const Icon(
                      PhosphorIconsRegular.arrowUpRight,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 8,
                children: [
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : AquaMotion.fade,
                    child: Text(
                      number(data?.temperature),
                      key: ValueKey(data?.temperature),
                      style: AquaType.metric.copyWith(fontSize: 60),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      '°C',
                      style: TextStyle(fontSize: 20, color: AquaColors.muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'เป้าหมาย ${number(state.settings.temperatureTarget)} °C${stale
                    ? ' · ค่าล่าสุด'
                    : demo
                    ? ' · ค่าทดลอง'
                    : ''}',
                style: AquaType.caption,
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Reading(
                      key: const ValueKey('dissolved-oxygen-card'),
                      label: 'ออกซิเจน · DO',
                      value: number(data?.dissolvedOxygen, decimals: 2),
                      unit: 'mg/L',
                      onTap: () => _details(state),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: _Reading(
                      label: 'ความเป็นกรด–ด่าง',
                      value: number(data?.ph),
                      unit: 'pH',
                      onTap: () => _details(state),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.waves,
                    color: AquaColors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('ระดับน้ำ')),
                  Text(
                    stale
                        ? 'รอข้อมูล'
                        : data?.fill?.waterLabel ??
                              (data?.waterLevelOk == null
                                  ? 'ไม่ทราบ'
                                  : data!.waterLevelOk!
                                  ? 'ปกติ'
                                  : 'ต่ำ'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AquaColors.blue,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (state.alerts.isNotEmpty && state.fresh) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: () => _details(state),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.info,
                    size: 18,
                    color: AquaColors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${state.alerts.length} รายการที่ควรตรวจสอบ',
                      style: const TextStyle(
                        color: AquaColors.orange,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Icon(
                    PhosphorIconsRegular.caretRight,
                    size: 18,
                    color: AquaColors.orange,
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => context.go('/counting'),
            icon: const Icon(PhosphorIconsRegular.scan),
            label: const Text('นับลูกปลา'),
          ),
        ),
        const SizedBox(height: 24),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'รอบฟัก',
                trailing: state.batch == null
                    ? null
                    : IconButton(
                        tooltip: 'ลบรอบฟัก',
                        onPressed: state.batchBusy
                            ? null
                            : () => showDeleteBatchDialog(
                                context,
                                controller,
                                state.batch!,
                              ),
                        icon: const Icon(PhosphorIconsRegular.trash),
                      ),
              ),
              Text(
                state.batch?.name ?? 'เริ่มรอบแรกของคุณ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (state.batch != null)
                Text(
                  elapsed(state.batch!.startedAt, state.now),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('add-hatch-batch'),
                onPressed: state.batchBusy
                    ? null
                    : () => showBatchDialog(context, controller),
                icon: const Icon(PhosphorIconsRegular.plus),
                label: const Text('เพิ่มรอบฟัก'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'แนวโน้มคุณภาพน้ำ',
                trailing: DropdownButton<bool>(
                  value: _phChart,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('°C')),
                    DropdownMenuItem(value: true, child: Text('pH')),
                  ],
                  onChanged: (v) => setState(() => _phChart = v ?? false),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [1, 6, 24]
                    .map(
                      (h) => ChoiceChip(
                        label: Text('$h ชม.'),
                        selected: _hours == h,
                        onSelected: (_) => setState(() => _hours = h),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 16),
              TrendChart(history: history, ph: _phChart),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen(),
                  ),
                ),
                icon: const Icon(PhosphorIconsRegular.clockCounterClockwise),
                label: const Text('ประวัติคุณภาพน้ำ'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Reading extends StatelessWidget {
  const _Reading({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.onTap,
  });
  final String label, value, unit;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AquaType.caption),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            Text(value, style: AquaType.reading),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(unit, style: AquaType.caption),
            ),
          ],
        ),
      ],
    ),
  );
}
