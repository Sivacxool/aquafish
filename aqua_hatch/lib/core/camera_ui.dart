import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/theme.dart';
import 'controller.dart';
import 'ui.dart';

class CameraConnectionCard extends ConsumerWidget {
  const CameraConnectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camera = ref.watch(cameraStatusProvider);
    final status = camera.asData?.value;
    final demo = ref.watch(
      appControllerProvider.select((s) => s.connection.demo),
    );
    return Surface(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.linked_camera_outlined, color: AquaColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ดูถาดฟัก · นับลูกปลา',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  status?.message ?? 'กำลังตรวจการเชื่อมต่อกล้อง…',
                  style: const TextStyle(fontSize: 12, color: AquaColors.muted),
                ),
                if (status?.cameraId.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    status!.cameraId,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AquaColors.muted,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Pill(
                  demo
                      ? 'โหมดจำลอง'
                      : status?.ready == true
                      ? 'พร้อมถ่าย'
                      : 'ยังไม่พร้อมถ่าย',
                  color: status?.ready == true
                      ? AquaColors.teal
                      : AquaColors.blue,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'เปิดกล้องในเครื่อง',
            onPressed: () => context.go('/counting'),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }
}
