import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/pairing.dart';
import '../core/ui.dart';
import 'wifi_setup.dart';

class QrPairingScreen extends ConsumerStatefulWidget {
  final String? expectedKind;
  final Future<String?> Function(BuildContext)? scanCode;
  const QrPairingScreen({super.key, this.expectedKind, this.scanCode});
  @override
  ConsumerState<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends ConsumerState<QrPairingScreen> {
  PairingBundle? _bundle;
  String? _error;
  bool _busy = false;
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.clear();
    _input.dispose();
    super.dispose();
  }

  void _parse(String raw) {
    try {
      final bundle = PairingBundle.parse(
        raw,
        expectedKind: widget.expectedKind,
      );
      setState(() {
        _bundle = bundle;
        _error = null;
      });
      _input.clear();
    } on FormatException catch (e) {
      setState(() {
        _bundle = null;
        _error = e.message.toString();
      });
    }
  }

  Future<void> _scan() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final raw =
          await (widget.scanCode?.call(context) ??
              Navigator.of(context).push<String>(
                MaterialPageRoute(builder: (_) => const QrCameraScreen()),
              ));
      if (mounted && raw != null) _parse(raw);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'เปิดกล้องสแกนไม่ได้ อนุญาตกล้องหรือวางข้อมูลจากบัตร QR แทน',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _continue() async {
    final bundle = _bundle;
    if (bundle == null) return;
    final existing = ref
        .read(localStoreProvider)
        .pairedDevices
        .where(
          (c) =>
              c.deviceId == bundle.identity.deviceId &&
              c.identity!.kind == bundle.identity.kind,
        );
    if (existing.isNotEmpty &&
        existing.first.identity!.fingerprint != bundle.identity.fingerprint) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('ใบรับรองของอุปกรณ์เปลี่ยน'),
          content: const Text(
            'ทำต่อเมื่อคุณล้างข้อมูลบอร์ดและได้ QR ใหม่จากบอร์ดตัวนี้โดยตรงเท่านั้น',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ยืนยัน QR ใหม่'),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WifiSetupScreen(
          camera: bundle.identity.kind == 'camera',
          pairing: bundle,
        ),
      ),
    );
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openSaved(ConnectionConfig config) async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WifiSetupScreen(
          camera: config.identity!.kind == 'camera',
          savedConfig: config,
        ),
      ),
    );
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appControllerProvider);
    final paired = ref
        .read(localStoreProvider)
        .pairedDevices
        .where(
          (c) =>
              widget.expectedKind == null ||
              c.identity!.kind == widget.expectedKind,
        )
        .toList();
    final identity = _bundle?.identity;
    return Scaffold(
      appBar: AppBar(title: const Text('จับคู่บอร์ดด้วย QR')),
      body: PageBody(
        children: [
          const PageTitle(
            'บอร์ดแต่ละตัว มี QR ของตัวเอง',
            'สแกนบัตรที่ได้หลังลงเฟิร์มแวร์ แล้วตั้ง Wi-Fi ให้บอร์ดตัวนั้น',
          ),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const ValueKey('scan-device-qr'),
                  onPressed: _busy ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('สแกน QR จากบอร์ด'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'หลังลงเฟิร์มแวร์ โปรแกรมบนคอมจะแสดงบัตร QR ให้สแกนหรือพิมพ์แปะกล่อง เก็บบัตรไว้เป็นส่วนตัว',
                ),
                const SizedBox(height: 16),
                ExpansionTile(
                  title: const Text('ใช้บนเครื่องจำลอง หรือไม่มีกล้อง'),
                  tilePadding: EdgeInsets.zero,
                  children: [
                    TextField(
                      key: const ValueKey('pairing-qr-text'),
                      controller: _input,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'ข้อมูล QR จากบัตรอุปกรณ์',
                        helperText: 'คัดลอกข้อมูลทั้งหมด ไม่ใช่เฉพาะรหัสจับคู่',
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _parse(_input.text),
                      icon: const Icon(Icons.qr_code),
                      label: const Text('ตรวจข้อมูล QR'),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      key: const ValueKey('qr-pairing-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (identity != null) ...[
            const SizedBox(height: 16),
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identity.kind == 's3'
                        ? 'บอร์ดหลัก ESP32'
                        : 'กล้อง ESP32-CAM',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('รหัสอุปกรณ์: ${identity.deviceId}'),
                  Text('Wi-Fi ตั้งค่า: ${identity.setupSsid}'),
                  const SizedBox(height: 12),
                  Text(
                    'ใบรับรองเฉพาะตัว: ${identity.fingerprint.substring(0, 16)}…',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'ตรวจว่าเป็นบัตรจากบอร์ดของคุณ แอปจะตรวจใบรับรองเฉพาะตัวนี้ทุกครั้งที่เชื่อมต่อ',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const ValueKey('confirm-device-qr'),
                    onPressed: _continue,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('ใช้บอร์ดนี้และตั้ง Wi-Fi'),
                  ),
                ],
              ),
            ),
          ],
          if (paired.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Text(
              'อุปกรณ์ที่เคยจับคู่',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'เลือกบอร์ดหลักและกล้องที่ต้องการใช้ ขณะนี้แอปอ่านบอร์ดหลักและกล้องอย่างละหนึ่งตัว',
            ),
            ...paired.map(
              (c) => Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Surface(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      c.identity!.kind == 's3'
                          ? Icons.memory
                          : Icons.camera_alt_outlined,
                    ),
                    title: Text(c.deviceId),
                    subtitle: Text(c.baseUrl),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openSaved(c),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class QrCameraScreen extends StatefulWidget {
  const QrCameraScreen({super.key});
  @override
  State<QrCameraScreen> createState() => _QrCameraScreenState();
}

class _QrCameraScreenState extends State<QrCameraScreen>
    with WidgetsBindingObserver {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _finished = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_finished) return;
    if (!_controller.value.hasCameraPermission) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.start());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_controller.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _detected(BarcodeCapture capture) {
    if (_finished) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      _finished = true;
      unawaited(_controller.stop());
      Navigator.of(context).pop(raw);
      break;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สแกน QR AquaHatch')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _controller,
            onDetect: _detected,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'ใช้กล้องสแกนไม่ได้ ตรวจสิทธิ์กล้อง แล้วลองใหม่ หรือย้อนกลับไปวางข้อมูล QR จากบัตร',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('กลับไปใช้ข้อมูลจากบัตร'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'เล็ง QR บนบัตรของบอร์ด ไม่ต้องถ่ายหรือส่งภาพไปที่เซิร์ฟเวอร์',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    ),
  );
}
