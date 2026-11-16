import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/controller.dart';

class RemoteSettings extends ConsumerStatefulWidget {
  const RemoteSettings({super.key});

  @override
  ConsumerState<RemoteSettings> createState() => _RemoteSettingsState();
}

class _RemoteSettingsState extends ConsumerState<RemoteSettings> {
  String? _message;
  bool _working = false;

  Future<void> _set(bool enabled) async {
    setState(() {
      _working = true;
      _message = null;
    });
    final error = await ref
        .read(appControllerProvider.notifier)
        .setRemoteViewing(enabled, camera: false);
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
    final enabled = !_working && !state.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('เปิดบน Wi-Fi ของอุปกรณ์ · ปิดได้จากทุกเครือข่าย'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('ดูเซนเซอร์และถ่ายภาพ'),
          value: board.relayOrigin != null,
          onChanged: enabled && board.identity != null ? _set : null,
        ),
        if (board.identity == null) const Text('สแกน QR บอร์ด ETT ก่อน'),
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
