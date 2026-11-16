import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/camera.dart';
import '../core/controller.dart';
import '../core/ui.dart';

Future<void> showArducamSettings(BuildContext context, WidgetRef ref) async {
  final controller = ref.read(appControllerProvider.notifier);
  final board = ref.read(appControllerProvider).connection;
  final settings = await showModalBottomSheet<ArducamSettings>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ArducamSettingsSheet(controller.arducamSettings),
  );
  if (settings == null || !context.mounted) return;
  if (ref.read(appControllerProvider).connection.deviceId != board.deviceId) {
    showFeedback(context, 'เปลี่ยนบอร์ดแล้ว กรุณาเปิดการตั้งค่าใหม่');
    return;
  }
  try {
    await controller.saveArducamSettings(settings);
  } catch (_) {
    if (context.mounted) showFeedback(context, 'บันทึกค่ากล้องไม่สำเร็จ');
  }
}

class _ArducamSettingsSheet extends StatefulWidget {
  const _ArducamSettingsSheet(this.settings);
  final ArducamSettings settings;

  @override
  State<_ArducamSettingsSheet> createState() => _ArducamSettingsSheetState();
}

class _ArducamSettingsSheetState extends State<_ArducamSettingsSheet> {
  static const labels = {
    'ev': 'ชดเชยแสง (EV)',
    'brightness': 'ความสว่าง',
    'contrast': 'คอนทราสต์',
    'saturation': 'ความอิ่มสี',
  };
  static const whiteBalance = [
    'อัตโนมัติ',
    'แดด',
    'ไฟสำนักงาน',
    'เมฆ',
    'ไฟในบ้าน',
  ];
  late bool _fullSize;
  late String _lighting;
  late Map<String, int> _levels;

  @override
  void initState() {
    super.initState();
    _fullSize = widget.settings.fullSize;
    _lighting = widget.settings.lighting;
    _levels = Map.of(widget.settings.levels);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ตั้งค่ากล้อง Arducam',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<bool>(
            key: const ValueKey('arducam-resolution'),
            initialValue: _fullSize,
            decoration: const InputDecoration(labelText: 'ความละเอียด'),
            items: const [
              DropdownMenuItem(value: true, child: Text('2048 × 1536')),
              DropdownMenuItem(value: false, child: Text('640 × 480')),
            ],
            onChanged: (value) => setState(() => _fullSize = value!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const ValueKey('arducam-lighting'),
            initialValue: _lighting,
            decoration: const InputDecoration(labelText: 'โหมดแสง'),
            items: const [
              DropdownMenuItem(value: 'normal', child: Text('ปกติ')),
              DropdownMenuItem(value: 'low-light', child: Text('แสงน้อย')),
              DropdownMenuItem(value: 'manual', child: Text('ตั้งค่าเอง')),
            ],
            onChanged: (value) => setState(() => _lighting = value!),
          ),
          if (_lighting == 'manual') ...[
            const SizedBox(height: 16),
            for (final MapEntry(:key, :value) in labels.entries)
              _slider(key, value),
            DropdownButtonFormField<int>(
              initialValue: _levels['white_balance'] ?? 0,
              decoration: const InputDecoration(labelText: 'สมดุลแสงขาว'),
              items: [
                for (var i = 0; i < whiteBalance.length; i++)
                  DropdownMenuItem(value: i, child: Text(whiteBalance[i])),
              ],
              onChanged: (value) =>
                  setState(() => _levels['white_balance'] = value!),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              ArducamSettings(
                fullSize: _fullSize,
                lighting: _lighting,
                levels: _levels,
              ),
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );

  Widget _slider(String key, String title) {
    final value = _levels[key] ?? 0;
    final limit = ArducamSettings.limits[key]!;
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(title)),
            Text(value > 0 ? '+$value' : '$value'),
          ],
        ),
        Slider(
          key: ValueKey('arducam-$key'),
          value: value.toDouble(),
          min: -limit.toDouble(),
          max: limit.toDouble(),
          divisions: limit * 2,
          label: '$value',
          onChanged: (next) => setState(() => _levels[key] = next.round()),
        ),
      ],
    );
  }
}
