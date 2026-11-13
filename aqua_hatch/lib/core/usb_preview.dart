import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import 'camera.dart';
import 'controller.dart';
import 'usb_camera.dart';
import 'ui.dart';

class UsbLivePreview extends ConsumerStatefulWidget {
  final ValueChanged<DeviceCapture> onFrame;
  const UsbLivePreview({super.key, required this.onFrame});
  @override
  ConsumerState<UsbLivePreview> createState() => _UsbLivePreviewState();
}

class _UsbLivePreviewState extends ConsumerState<UsbLivePreview>
    with WidgetsBindingObserver {
  late UsbCameraClient _client;
  late Stream<DeviceCapture> _frames;
  void _open() {
    _client = ref.read(usbCameraFactoryProvider)();
    _frames = _client.frames();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _open();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _client.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _client.close();
      if (mounted) setState(_open);
    } else {
      _client.close();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<DeviceCapture>(
    stream: _frames,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Column(
          children: [
            const Notice(
              'ภาพ USB ขาดการเชื่อมต่อ ตรวจสายและตัวรับภาพบนคอม',
              warning: true,
            ),
            TextButton.icon(
              onPressed: () {
                _client.close();
                setState(_open);
              },
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              label: const Text('รับภาพใหม่'),
            ),
          ],
        );
      }
      final image = snapshot.data;
      if (image == null) {
        return const AspectRatio(
          aspectRatio: 4 / 3,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 14),
                Text('กำลังรับภาพจากสาย USB…'),
              ],
            ),
          ),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFrame(image);
      });
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(
                color: const Color(0xff08232c),
                child: Image.memory(
                  image.bytes,
                  key: const ValueKey('usb-live-frame'),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('ถอดรหัสภาพ USB ไม่สำเร็จ')),
                ),
              ),
              const Positioned(
                top: 12,
                left: 12,
                child: Pill(
                  'ภาพสด · USB',
                  color: AquaColors.teal,
                  icon: PhosphorIconsRegular.usb,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
