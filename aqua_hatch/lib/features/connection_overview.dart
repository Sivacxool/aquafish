import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import 'connection_journey.dart';

class ConnectionOverview extends StatelessWidget {
  final AppState state;
  final VoidCallback? onBoard;

  const ConnectionOverview({super.key, required this.state, this.onBoard});

  @override
  Widget build(BuildContext context) {
    final boardSaved = !state.connection.demo && state.connection.localEsp32;
    final board = _DeviceTile(
      key: const ValueKey('start-board-setup'),
      title: 'บอร์ด ETT WROOM32UE',
      status: state.fresh && boardSaved
          ? 'ออนไลน์'
          : boardSaved
          ? 'ติดต่อไม่ได้'
          : 'ตั้งค่า Wi-Fi',
      icon: PhosphorIconsRegular.cpu,
      onPressed: onBoard,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (boardSaved) board,
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
