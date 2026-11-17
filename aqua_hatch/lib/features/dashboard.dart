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
  WaterTrend _trend = WaterTrend.jarTemperature;
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
    final batch = state.batch;
    final latestCount = state.counts
        .where((record) => record.batchId == batch?.id && !record.demo)
        .firstOrNull;
    final eggs = batch?.eggs;
    final hatchingRate = latestCount != null && eggs != null && eggs > 0
        ? latestCount.count * 100 / eggs
        : null;
    final history = state.history
        .where(
          (t) => !t.at.isBefore(state.now.subtract(Duration(hours: _hours))),
        )
        .toList();
    final status = state.connection.demo
        ? 'ยังไม่เชื่อมบอร์ด'
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
                color: stale ? AquaColors.orange : AquaColors.blue,
              ),
            ),
          ],
        ),
        Surface(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'อุณหภูมิ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (stale && data != null)
                    const Text('ค่าล่าสุด', style: AquaType.caption),
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
              const SizedBox(height: 4),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _TemperatureReading(
                        label: 'อุณหภูมิในถัง',
                        value: data?.tankTemperature,
                        source: data?.tankTemperature == null
                            ? 'รอค่า DO และ pH'
                            : 'เฉลี่ย DO และ pH',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TemperatureReading(
                        label: 'อุณหภูมิที่ปากโหล',
                        value: data?.temperature,
                        source: 'DS18B20',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'เป้าหมายที่ปากโหล ${number(state.settings.temperatureTarget)} °C',
                style: AquaType.caption,
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),
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
              if (batch != null) ...[
                const SizedBox(height: 12),
                Text(
                  latestCount == null
                      ? 'ยังไม่มีผลนับ'
                      : 'ผลนับล่าสุด ${latestCount.count} ตัว',
                  key: const ValueKey('hatch-round-count'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (eggs != null) Text('ไข่ตั้งต้น $eggs ฟอง'),
                if (hatchingRate != null)
                  Text(
                    'อัตราฟัก ${number(hatchingRate, decimals: 1)}%',
                    key: const ValueKey('hatch-round-rate'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('add-hatch-batch'),
                    onPressed: state.batchBusy
                        ? null
                        : () => showBatchDialog(context, controller),
                    icon: const Icon(PhosphorIconsRegular.plus),
                    label: const Text('เพิ่มรอบฟัก'),
                  ),
                  if (state.hatchRounds.length > 1)
                    TextButton(
                      onPressed: state.batchBusy
                          ? null
                          : () => showBatchPicker(context, state, controller),
                      child: const Text('เลือกรอบฟัก'),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('แนวโน้มคุณภาพน้ำ'),
              DropdownButton<WaterTrend>(
                value: _trend,
                items: [
                  for (final trend in WaterTrend.values)
                    DropdownMenuItem(value: trend, child: Text(trend.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _trend = value);
                },
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
              TrendChart(history: history, trend: _trend),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HistoryScreen(),
                      ),
                    ),
                    icon: const Icon(
                      PhosphorIconsRegular.clockCounterClockwise,
                    ),
                    label: const Text('ประวัติคุณภาพน้ำ'),
                  ),
                  TextButton.icon(
                    onPressed: state.history.isEmpty
                        ? null
                        : () => clearWaterHistory(context, controller),
                    icon: const Icon(PhosphorIconsRegular.trash),
                    label: const Text('ล้างข้อมูลแนวโน้ม'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TemperatureReading extends StatelessWidget {
  const _TemperatureReading({
    required this.label,
    required this.value,
    required this.source,
  });

  final String label, source;
  final double? value;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AquaColors.sage,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AquaType.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AquaColors.navy,
            ),
          ),
          const Spacer(),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : AquaMotion.fade,
            child: Text.rich(
              key: ValueKey(value),
              TextSpan(
                text: number(value),
                children: [
                  if (value != null)
                    const TextSpan(text: ' °C', style: AquaType.caption),
                ],
              ),
              style: AquaType.metric.copyWith(fontSize: 32, height: 1.2),
            ),
          ),
          const SizedBox(height: 4),
          Text(source, style: AquaType.caption),
        ],
      ),
    ),
  );
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
