import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import 'connection_journey.dart';

class ConnectionOverview extends StatelessWidget {
  final AppState state;
  final VoidCallback? onBoard, onCamera, onDemo;

  const ConnectionOverview({
    super.key,
    required this.state,
    this.onBoard,
    this.onCamera,
    this.onDemo,
  });

  @override
  Widget build(BuildContext context) {
    final boardSaved = !state.connection.demo && state.connection.localEsp32;
    final board = _DeviceTile(
      key: const ValueKey('start-board-setup'),
      title: 'บอร์ดหลัก',
      status: state.fresh && boardSaved
          ? 'ออนไลน์'
          : boardSaved
          ? 'ติดต่อไม่ได้'
          : 'ตั้งค่า Wi-Fi',
      icon: PhosphorIconsRegular.cpu,
      onPressed: onBoard,
    );
    final camera = _DeviceTile(
      key: const ValueKey('start-camera-setup'),
      title: 'กล้อง',
      status: state.usbCameraEnabled
          ? 'ใช้ USB'
          : state.cameraConnection != null
          ? 'จับคู่แล้ว'
          : 'เพิ่มกล้อง',
      icon: PhosphorIconsRegular.camera,
      onPressed: onCamera,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) =>
              constraints.maxWidth >= 310 &&
                  MediaQuery.textScalerOf(context).scale(14) < 20
              ? Row(
                  children: [
                    Expanded(child: board),
                    const SizedBox(width: 12),
                    Expanded(child: camera),
                  ],
                )
              : Column(children: [board, const SizedBox(height: 8), camera]),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              key: const ValueKey('connection-preview'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ConnectionPreviewScreen(),
                ),
              ),
              child: const Text('วิธีเชื่อมต่อ'),
            ),
            if (!state.connection.demo)
              TextButton(onPressed: onDemo, child: const Text('โหมดทดลอง')),
          ],
        ),
      ],
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final String title, status;
  final IconData icon;
  final VoidCallback? onPressed;

  const _DeviceTile({
    super.key,
    required this.title,
    required this.status,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: AquaColors.paper,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onPressed,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 24, color: AquaColors.blue),
                const Spacer(),
                const Icon(
                  PhosphorIconsRegular.arrowUpRight,
                  size: 18,
                  color: AquaColors.muted,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              status,
              style: const TextStyle(color: AquaColors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );
}
