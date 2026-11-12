import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/theme.dart';
import 'controller.dart';

class CameraConnectionCard extends ConsumerWidget {
  const CameraConnectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final camera = ref.watch(cameraStatusProvider);
    final status = camera.asData?.value;
    final demo = ref.watch(
      appControllerProvider.select((s) => s.connection.demo),
    );
    final usb = ref.watch(
      appControllerProvider.select((s) => s.usbCameraEnabled),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.go('/counting'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const CircleAvatar(
          foregroundColor: AquaColors.blue,
          backgroundColor: AquaColors.sage,
          child: Icon(Icons.photo_camera_outlined),
        ),
        title: const Text(
          'เปิดกล้อง',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          usb
              ? 'กล้อง USB'
              : status?.ready == true
              ? 'พร้อมถ่าย'
              : demo
              ? 'โหมดทดลอง'
              : camera.isLoading
              ? 'กำลังเช็กกล้อง'
              : 'ยังไม่เชื่อมต่อ',
        ),
        trailing: const Icon(Icons.arrow_forward_rounded),
      ),
    );
  }
}
