import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/paired_camera.dart';
import '../core/ui.dart';
import 'qr_pairing.dart';

class CameraConnectionScreen extends ConsumerStatefulWidget {
  const CameraConnectionScreen({super.key});

  @override
  ConsumerState<CameraConnectionScreen> createState() =>
      _CameraConnectionScreenState();
}

class _CameraConnectionScreenState
    extends ConsumerState<CameraConnectionScreen> {
  late final TextEditingController _address;
  final _token = TextEditingController();
  bool _busy = false;

  ConnectionConfig? get _camera =>
      ref.read(appControllerProvider).cameraConnection;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: _camera?.baseUrl);
  }

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const QrPairingScreen(expectedKind: 'camera'),
      ),
    );
    if (!mounted) return;
    _address.text = _camera?.baseUrl ?? '';
    _token.clear();
  }

  Future<void> _connectCamera() async {
    final camera = _camera;
    final address = _address.text.trim();
    await _connect(
      (controller) => controller.configureCamera(
        ConnectionConfig(
          demo: false,
          localEsp32: true,
          baseUrl: isPrivateIpv4(address) ? 'https://$address' : address,
          deviceId: camera?.deviceId ?? cameraDeviceId,
          identity: camera?.identity,
          relayOrigin: camera?.relayOrigin,
        ),
        _token.text,
      ),
      'เชื่อมกล้องแล้ว',
    );
  }

  Future<void> _connect(
    Future<String?> Function(AppController) action,
    String success,
  ) async {
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final error = await action(ref.read(appControllerProvider.notifier));
    if (!mounted) return;
    setState(() => _busy = false);
    if (error == null) _token.clear();
    showFeedback(context, error, success: success);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final camera = state.cameraConnection;
    final disabled = _busy || state.busy;
    return Scaffold(
      appBar: AppBar(title: const Text('กล้อง: IP และ USB')),
      body: SafeArea(
        child: PageBody(
          children: [
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeading('กล้องผ่าน Wi-Fi'),
                  if (camera?.identity == null)
                    TextButton.icon(
                      onPressed: disabled ? null : _pair,
                      icon: const Icon(PhosphorIconsRegular.scan),
                      label: const Text('สแกน QR กล้อง'),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _address,
                    enabled: !disabled,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'IP หรือ URL บอร์ดกล้อง',
                      hintText: '192.168.1.55',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _token,
                    enabled: !disabled,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: 'รหัสจับคู่กล้อง',
                      helperText: camera == null
                          ? 'ใช้รหัสจากบัตรกล้อง'
                          : 'เว้นว่างเพื่อใช้รหัสที่บันทึกไว้',
                      helperMaxLines: 2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: disabled ? null : _connectCamera,
                    child: const Text('เชื่อมกล้องด้วย IP'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeading('กล้อง USB สำหรับ LDPlayer'),
                  const Text('ต่อ USB กับคอมแล้วเปิดโปรแกรมรับภาพ'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    key: const ValueKey('connect-usb-camera'),
                    onPressed: disabled
                        ? null
                        : () => _connect(
                            (controller) => controller.configureUsbCamera(true),
                            'เชื่อมกล้อง USB แล้ว',
                          ),
                    child: Text(
                      state.usbCameraEnabled
                          ? 'ตรวจกล้อง USB อีกครั้ง'
                          : 'เชื่อมกล้อง USB',
                    ),
                  ),
                  if (state.usbCameraEnabled)
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => _connect(
                              (controller) =>
                                  controller.configureUsbCamera(false),
                              'เปลี่ยนไปใช้กล้อง Wi-Fi แล้ว',
                            ),
                      child: const Text('เปลี่ยนไปใช้กล้อง Wi-Fi'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
