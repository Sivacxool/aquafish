import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';

class RemoteSettings extends ConsumerStatefulWidget {
  const RemoteSettings({super.key});

  @override
  ConsumerState<RemoteSettings> createState() => _RemoteSettingsState();
}

class _RemoteSettingsState extends ConsumerState<RemoteSettings> {
  late final TextEditingController _url;
  String? _message;
  bool _working = false;

  @override
  void initState() {
    super.initState();
    final state = ref.read(appControllerProvider);
    _url = TextEditingController(
      text: state.connection.relayOrigin ?? state.cameraConnection?.relayOrigin,
    );
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _set(bool camera, bool enabled) async {
    if (enabled && _url.text.trim().isEmpty) {
      setState(() => _message = 'ใส่ลิงก์บริการก่อน');
      return;
    }
    setState(() {
      _working = true;
      _message = null;
    });
    final error = await ref
        .read(appControllerProvider.notifier)
        .setRelayOrigin(enabled ? _url.text : '', camera: camera);
    if (!mounted) return;
    setState(() {
      _working = false;
      _message = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final board = state.connection;
    final camera = state.cameraConnection;
    final enabled = !_working && !state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('ตั้งครั้งเดียวบน Wi-Fi ของอุปกรณ์'),
        const SizedBox(height: 12),
        TextField(
          controller: _url,
          enabled: enabled,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: const InputDecoration(labelText: 'ลิงก์บริการ AquaHatch'),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ดูค่าเซนเซอร์'),
          value: board.relayOrigin != null,
          onChanged: enabled && board.identity != null
              ? (on) => _set(false, on)
              : null,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ถ่ายภาพจากกล้อง'),
          value: camera?.relayOrigin != null,
          onChanged: enabled && camera?.identity != null
              ? (on) => _set(true, on)
              : null,
        ),
        if (board.identity == null && camera?.identity == null)
          const Text('สแกน QR ของอุปกรณ์ก่อน'),
        if (_working) const LinearProgressIndicator(),
        if (_message != null)
          Text(
            _message!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}
