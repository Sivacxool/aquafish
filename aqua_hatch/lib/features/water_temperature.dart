import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/icons.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/sensor_status.dart';
import '../core/ui.dart';

void showWaterTemperatures(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const WaterTemperatureDetails(),
  );
}

class WaterTemperatureCard extends StatelessWidget {
  const WaterTemperatureCard({
    super.key,
    required this.data,
    required this.fresh,
  });
  final Telemetry? data;
  final bool fresh;

  @override
  Widget build(BuildContext context) {
    final average = data?.averageTemperature;
    final count = data?.temperaturePointCount ?? 0;
    return Material(
      color: AquaColors.sage,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('temperature-average-card'),
        onTap: () => showWaterTemperatures(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'อุณหภูมิเฉลี่ย',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$count/3 จุด', style: AquaType.caption),
                  const SizedBox(width: 8),
                  const Icon(PhosphorIconsRegular.arrowUpRight, size: 20),
                ],
              ),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AquaMotion.fade,
                child: Text.rich(
                  key: ValueKey(average),
                  TextSpan(
                    text: number(average),
                    children: [
                      if (average != null)
                        const TextSpan(text: ' °C', style: AquaType.reading),
                    ],
                  ),
                  style: AquaType.metric,
                ),
              ),
              if (!fresh && data != null || count < 3) ...[
                const SizedBox(height: 8),
                Text(
                  !fresh && data != null
                      ? 'ข้อมูลล่าสุด'
                      : count == 0
                      ? 'รอข้อมูลอุณหภูมิ'
                      : 'รออีก ${3 - count} จุด${data?.averagedTemperatureControl == true ? ' · Auto พัก' : ''}',
                  style: AquaType.caption,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class WaterTemperatureDetails extends ConsumerWidget {
  const WaterTemperatureDetails({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final data = state.telemetry;
    final points =
        data?.temperaturePoints ?? Telemetry(at: state.now).temperaturePoints;
    final count = data?.temperaturePointCount ?? 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionHeading('อุณหภูมิแต่ละจุด')),
              IconButton(
                tooltip: 'ปิด',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(PhosphorIconsRegular.x),
              ),
            ],
          ),
          Text(
            'เฉลี่ย ${number(data?.averageTemperature)} °C · $count/3 จุด',
            style: AquaType.reading.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          if (!state.fresh && data != null)
            const Text('ข้อมูลล่าสุด · เครื่องออฟไลน์', style: AquaType.caption)
          else if (count < 3 && data?.averagedTemperatureControl == true)
            const Text(
              'รอข้อมูลครบ 3 จุดเพื่อควบคุมอุณหภูมิอัตโนมัติ',
              style: AquaType.caption,
            ),
          const SizedBox(height: 16),
          for (var i = 0; i < points.length; i++) ...[
            _TemperatureLocation(point: points[i]),
            if (i < points.length - 1) const Divider(height: 24),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _TemperatureLocation extends StatelessWidget {
  const _TemperatureLocation({required this.point});
  final WaterTemperaturePoint point;

  @override
  Widget build(BuildContext context) => Row(
    key: ValueKey('temperature-point-${point.id}'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              point.label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              point.celsius != null
                  ? point.sampledAt == null
                        ? 'พร้อมใช้งาน'
                        : 'อัปเดต ${shortTime(point.sampledAt!)}'
                  : sensorStatusLabel(point.readingStatus, source: 'จุดนี้'),
              style: AquaType.caption,
            ),
          ],
        ),
      ),
      const SizedBox(width: 12),
      Text(
        '${number(point.celsius)}${point.celsius == null ? '' : ' °C'}',
        style: AquaType.reading.copyWith(fontSize: 24),
      ),
    ],
  );
}
