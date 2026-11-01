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
    final boardOnline =
        !state.connection.demo && state.connection.localEsp32 && state.fresh;
    final boardSaved = !state.connection.demo && state.connection.localEsp32;
    final boardCard = _DeviceStep(
      number: '01',
      title: 'บอร์ดหลัก',
      model: 'ESP32-S3',
      description: 'รับค่าอุณหภูมิและออกซิเจนในน้ำ',
      icon: Icons.memory_rounded,
      status: boardOnline
          ? 'ออนไลน์'
          : boardSaved
          ? 'บันทึกแล้ว · ยังไม่ออนไลน์'
          : 'ยังไม่ได้เชื่อมต่อ',
      online: boardOnline,
      action: boardSaved ? 'จัดการ Wi-Fi บอร์ด' : 'เริ่มเชื่อมต่อบอร์ดหลัก',
      onPressed: onBoard,
    );
    final cameraCard = _DeviceStep(
      number: '02',
      title: 'เพิ่มกล้อง',
      model: 'ESP32-CAM · ทำภายหลังได้',
      description: 'รับภาพจากกล้องสำหรับนับลูกปลา',
      icon: Icons.photo_camera_outlined,
      status: state.usbCameraEnabled
          ? 'เลือกใช้ USB อยู่'
          : state.cameraConnection != null
          ? 'บันทึกแล้ว · ยังไม่ได้ตรวจครั้งนี้'
          : 'ยังไม่ได้เพิ่มกล้อง',
      action: state.cameraConnection != null
          ? 'จัดการ Wi-Fi กล้อง'
          : 'เชื่อมต่อกล้อง',
      onPressed: onCamera,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF103F58), Color(0xFF087D86)],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.wifi_rounded, color: Color(0xFFB3F2E6), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'เชื่อมต่ออุปกรณ์',
                      style: TextStyle(
                        color: Color(0xFFB3F2E6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'เริ่มที่บอร์ดหลัก\nแล้วค่อยเพิ่มกล้อง',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'แอปพาเชื่อมทีละขั้น ใช้ Wi-Fi บ้านเดียวกัน\nตั้งค่าเสร็จแล้ว ไม่ต้องเปิดคอมค้างไว้',
                style: TextStyle(color: Colors.white, height: 1.7),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.phone_android_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'มือถือ และอุปกรณ์ใช้ Wi-Fi บ้านเดียวกัน',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth >= 700
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: boardCard),
                    const SizedBox(width: 16),
                    Expanded(child: cameraCard),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [boardCard, const SizedBox(height: 14), cameraCard],
                ),
        ),
        const SizedBox(height: 14),
        const Text(
          'บอร์ดหลักกับกล้องมี IP แยกกัน ตั้ง Wi-Fi ให้แต่ละตัวครั้งแรก กล้องเชื่อมแยกได้โดยไม่ต้องรอบอร์ดหลัก',
          style: TextStyle(color: AquaColors.muted, fontSize: 13, height: 1.7),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          key: const ValueKey('connection-preview'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ConnectionPreviewScreen(),
            ),
          ),
          icon: const Icon(Icons.play_circle_outline_rounded),
          label: const Text('ดูวิธีเชื่อมต่อ · ยังไม่มีบอร์ดก็เปิดดูได้'),
        ),
        if (!state.connection.demo)
          TextButton(
            onPressed: onDemo,
            child: const Text('ยังไม่ต่ออุปกรณ์? ใช้โหมดทดลอง'),
          ),
        if (state.connection.demo)
          const ConnectionHint(
            'กำลังใช้โหมดทดลอง ค่าที่แสดงเป็นข้อมูลจำลอง',
            icon: Icons.science_outlined,
          ),
      ],
    );
  }
}

class _DeviceStep extends StatelessWidget {
  final String number, title, model, description, status, action;
  final IconData icon;
  final bool online;
  final VoidCallback? onPressed;
  const _DeviceStep({
    required this.number,
    required this.title,
    required this.model,
    required this.description,
    required this.status,
    required this.action,
    required this.icon,
    this.online = false,
    this.onPressed,
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFE7F3F2),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: AquaColors.teal),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      model,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AquaColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                number,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7B9BA5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(description),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Icon(
                  online ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 14,
                  color: online ? AquaColors.teal : AquaColors.muted,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    color: online ? AquaColors.teal : AquaColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (number == '01')
            FilledButton.icon(
              key: const ValueKey('start-board-setup'),
              onPressed: onPressed,
              icon: const Icon(Icons.arrow_forward_rounded, size: 19),
              label: Text(action),
            )
          else
            OutlinedButton.icon(
              key: const ValueKey('start-camera-setup'),
              onPressed: onPressed,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: Text(action),
            ),
        ],
      ),
    ),
  );
}
