import 'package:aqua_hatch/app/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/ui.dart';
import 'wifi_setup.dart';
import 'camera_connection.dart';
import 'connection_overview.dart';
import 'controls.dart' show RelayModeSelector;
import 'remote_settings.dart';
import 'ph_calibration.dart';
import 'qr_pairing.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section});
  final String? section;
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _settingsForm = GlobalKey<FormState>();
  late final TextEditingController _temperature, _ph, _phMax, _url, _device;
  final _token = TextEditingController();
  bool _demo = true,
      _localEsp32 = false,
      _connecting = false,
      _dirty = false,
      _abnormalPh = false,
      _lowWater = false;
  @override
  void initState() {
    super.initState();
    final state = ref.read(appControllerProvider);
    _temperature = TextEditingController(
      text: number(state.settings.temperatureTarget),
    );
    _ph = TextEditingController(text: number(state.settings.phMinimum));
    _phMax = TextEditingController(text: number(state.settings.phMaximum));
    _url = TextEditingController(text: state.connection.baseUrl);
    _device = TextEditingController(text: state.connection.deviceId);
    _demo = state.connection.demo;
    _localEsp32 = state.connection.localEsp32;
  }

  @override
  void dispose() {
    for (final c in [_temperature, _ph, _phMax, _url, _device, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadSettings(DeviceSettings settings) {
    _temperature.text = number(settings.temperatureTarget);
    _ph.text = number(settings.phMinimum);
    _phMax.text = number(settings.phMaximum);
    _dirty = false;
  }

  double? _parse(String? value) =>
      double.tryParse((value ?? '').replaceAll(',', '.'));
  Future<void> _openQrPairing() async {
    await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => const QrPairingScreen(scanOnOpen: true),
      ),
    );
    if (!mounted) return;
    final state = ref.read(appControllerProvider);
    setState(() {
      _demo = state.connection.demo;
      _localEsp32 = state.connection.localEsp32;
      _url.text = state.connection.baseUrl;
      _device.text = state.connection.deviceId;
      _token.clear();
    });
  }

  Future<void> _openWifiSetup() async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const WifiSetupScreen()));
    if (!mounted) return;
    final config = ref.read(appControllerProvider).connection;
    setState(() {
      _demo = config.demo;
      _localEsp32 = config.localEsp32;
      _url.text = config.baseUrl;
      _device.text = config.deviceId;
      _token.clear();
    });
  }

  Future<void> _saveSettings() async {
    if (_settingsForm.currentState?.validate() != true) return;
    final settings = DeviceSettings(
      temperatureTarget: _parse(_temperature.text)!,
      phMinimum: _parse(_ph.text)!,
      phMaximum: _parse(_phMax.text)!,
    );
    final error = await ref
        .read(appControllerProvider.notifier)
        .saveSettings(settings);
    if (!mounted) return;
    if (error == null) _dirty = false;
    showFeedback(context, error, success: 'เครื่องยืนยันค่าตั้งแล้ว');
  }

  Future<void> _openCameraWifi() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WifiSetupScreen(camera: true)),
    );
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    final config = ConnectionConfig(
      identity:
          !_demo &&
              _localEsp32 &&
              _device.text.trim() ==
                  ref.read(appControllerProvider).connection.deviceId
          ? ref.read(appControllerProvider).connection.identity
          : null,
      demo: _demo,
      localEsp32: _localEsp32,
      baseUrl: _url.text.trim(),
      deviceId: _device.text.trim(),
    );
    final error = await ref
        .read(appControllerProvider.notifier)
        .configure(config, _token.text);
    if (!mounted) return;
    setState(() {
      _connecting = false;
      _abnormalPh = false;
      _lowWater = false;
    });
    showFeedback(
      context,
      error,
      success: _demo ? 'เข้าสู่โหมดทดลองแล้ว' : 'เชื่อมต่อเซิร์ฟเวอร์แล้ว',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    ref.listen(appControllerProvider, (previous, next) {
      if (!_dirty && previous?.settings != next.settings) {
        _loadSettings(next.settings);
      }
    });
    final content = <Widget>[
      _SettingsGroup(
        title: 'ดูจากนอกบ้าน',
        subtitle:
            state.connection.relayOrigin != null ||
                state.cameraConnection?.relayOrigin != null
            ? 'เปิดใช้งานแล้ว'
            : 'ผ่านอินเทอร์เน็ต',
        icon: PhosphorIconsRegular.globe,
        child: const RemoteSettings(),
      ),
      const SizedBox(height: 12),
      Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 8,
          ),
          leading: const Icon(
            PhosphorIconsRegular.camera,
            color: AquaColors.blue,
          ),
          title: const Text(
            'กล้อง: IP และ USB',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          trailing: const Icon(PhosphorIconsRegular.caretRight),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const CameraConnectionScreen()),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _SettingsGroup(
        title: 'ตั้งค่าบอร์ดขั้นสูง',
        subtitle: 'IP และเซิร์ฟเวอร์ของบอร์ด',
        icon: PhosphorIconsRegular.wifiHigh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeading(
              'การเชื่อมต่อ',
              trailing: Pill(
                state.connection.demo
                    ? 'ทดลอง'
                    : state.fresh
                    ? 'ออนไลน์'
                    : 'ออฟไลน์',
                color: state.fresh ? AquaColors.teal : AquaColors.orange,
              ),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('เครื่องจำลอง'),
                  icon: Icon(PhosphorIconsRegular.flask),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('เครื่องจริง'),
                  icon: Icon(PhosphorIconsRegular.wifiHigh),
                ),
              ],
              selected: {_demo},
              onSelectionChanged: _connecting || state.busy
                  ? null
                  : (values) => setState(() => _demo = values.first),
            ),
            const SizedBox(height: 20),
            if (!_demo) ...[
              DropdownButtonFormField<bool>(
                initialValue: _localEsp32,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'เชื่อมต่อผ่าน'),
                items: const [
                  DropdownMenuItem(
                    value: false,
                    child: Text('เซิร์ฟเวอร์ของบอร์ด'),
                  ),
                  DropdownMenuItem(value: true, child: Text('ESP32 ในบ้าน')),
                ],
                onChanged: _connecting || state.busy
                    ? null
                    : (value) => setState(() => _localEsp32 = value ?? false),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const PageStorageKey('connection-url'),
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: _localEsp32 ? 'URL บอร์ด' : 'URL เซิร์ฟเวอร์',
                  hintText: _localEsp32
                      ? 'https://192.168.1.50'
                      : 'https://incubator.example.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const PageStorageKey('connection-device'),
                controller: _device,
                decoration: const InputDecoration(
                  labelText: 'รหัสเครื่อง',
                  hintText: 'incubator-01',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const PageStorageKey('connection-token'),
                controller: _token,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'รหัสเข้าถึงเซิร์ฟเวอร์',
                  helperText: 'เว้นว่างเพื่อใช้รหัสเดิมของเครื่องนี้',
                ),
              ),
              const SizedBox(height: 12),
              if (!_localEsp32) const Notice('เซิร์ฟเวอร์ภายนอกใช้ HTTPS'),
              TextButton.icon(
                onPressed: state.busy
                    ? null
                    : () async {
                        final error = await ref
                            .read(appControllerProvider.notifier)
                            .forgetCredentials();
                        if (context.mounted) {
                          showFeedback(
                            context,
                            error,
                            success: 'ลบรหัสที่บันทึกแล้ว',
                          );
                        }
                      },
                icon: const Icon(PhosphorIconsRegular.signOut),
                label: const Text('ลบรหัสที่บันทึก'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _connecting || state.busy ? null : _connect,
              icon: const Icon(PhosphorIconsRegular.link, size: 18),
              label: Text(
                _connecting ? 'กำลังเชื่อมต่อ…' : 'บันทึกและเชื่อมต่อ',
              ),
            ),
            if (state.connection.localEsp32 && state.fresh) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: state.busy
                    ? null
                    : () async {
                        final error = await ref
                            .read(appControllerProvider.notifier)
                            .send('ping', {});
                        if (context.mounted) {
                          showFeedback(
                            context,
                            error,
                            success: 'บอร์ดหลักตอบรับคำสั่งจริงแล้ว',
                          );
                        }
                      },
                icon: const Icon(PhosphorIconsRegular.gauge),
                label: const Text('ทดสอบบอร์ด'),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Text(
                state.error!,
                style: const TextStyle(fontSize: 12, color: AquaColors.red),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'สอบเทียบ pH',
        subtitle: '',
        icon: PhosphorIconsRegular.flask,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PhCalibrationScreen(),
                ),
              ),
              icon: const Icon(PhosphorIconsRegular.flask),
              label: const Text('เปิดคู่มือและสอบเทียบ pH'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'ค่าควบคุม',
        subtitle: 'โหมดและอุณหภูมิ',
        icon: PhosphorIconsRegular.slidersHorizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.telemetry?.ettControl != null) ...[
              RelayModeSelector(
                state: state,
                controller: ref.read(appControllerProvider.notifier),
              ),
              const SizedBox(height: 16),
            ],
            Form(
              key: _settingsForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeading(
                    'ค่าตั้งการควบคุม',
                    trailing: TextButton(
                      onPressed: () =>
                          setState(() => _loadSettings(state.settings)),
                      child: const Text(
                        'โหลดค่าปัจจุบัน',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, c) {
                      final fields = [
                        _field(_temperature, 'อุณหภูมิเป้าหมาย', '°C', 20, 35),
                        _field(_ph, 'pH ต่ำสุด', 'pH', 0, 14),
                        _field(_phMax, 'pH สูงสุด', 'pH', 0, 14),
                      ];
                      final width = c.maxWidth >= 700
                          ? (c.maxWidth - 16) / 2
                          : c.maxWidth;
                      return Wrap(
                        spacing: 16,
                        runSpacing: 14,
                        children: fields
                            .map(
                              (field) => SizedBox(width: width, child: field),
                            )
                            .toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: state.fresh && !state.busy
                        ? _saveSettings
                        : null,
                    icon: const Icon(PhosphorIconsRegular.floppyDisk, size: 18),
                    label: Text(
                      state.busy
                          ? 'รอเครื่องยืนยัน…'
                          : 'ส่งค่าตั้งไปยังเครื่อง',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'pH ใช้ตรวจวัดและแจ้งเตือน',
                    style: TextStyle(fontSize: 12, color: AquaColors.muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      _SettingsGroup(
        title: 'รอบฟัก',
        subtitle: 'รอบปัจจุบันและการเพิ่มรอบฟัก',
        icon: PhosphorIconsRegular.stack,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeading('รอบปัจจุบัน'),
            Text(
              state.batch?.name ?? 'ยังไม่มีรอบฟัก',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            if (state.batch != null) ...[
              const SizedBox(height: 8),
              Text(
                'เริ่ม ${fullTime(state.batch!.startedAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'ไข่เริ่มต้น: ${state.batch!.eggs?.toString() ?? 'ยังไม่ระบุ'}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: state.batchBusy
                    ? null
                    : () => showDeleteBatchDialog(
                        context,
                        ref.read(appControllerProvider.notifier),
                        state.batch!,
                      ),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(PhosphorIconsRegular.trash, size: 18),
                label: const Text('ลบรอบฟัก'),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: state.batchBusy
                  ? null
                  : () => showBatchDialog(
                      context,
                      ref.read(appControllerProvider.notifier),
                    ),
              icon: const Icon(PhosphorIconsRegular.plus, size: 17),
              label: const Text('เพิ่มรอบฟัก'),
            ),
            if (state.hatchRounds.length > 1)
              TextButton(
                onPressed: state.batchBusy
                    ? null
                    : () => showBatchPicker(
                        context,
                        state,
                        ref.read(appControllerProvider.notifier),
                      ),
                child: const Text('เลือกรอบฟัก'),
              ),
            const SizedBox(height: 12),
            const Text(
              'เก็บผลนับบนมือถือสูงสุด 100 รายการ',
              style: TextStyle(fontSize: 12, color: AquaColors.muted),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      if (state.connection.demo) ...[
        _SettingsGroup(
          title: 'เครื่องมือทดลอง',
          subtitle: 'จำลอง pH ผิดปกติและระดับน้ำต่ำ',
          icon: PhosphorIconsRegular.flask,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('ทดสอบสถานการณ์จำลอง'),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('pH นอกช่วง', style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'ดูการแจ้งเตือนบนหน้าแรก',
                  style: TextStyle(fontSize: 12),
                ),
                value: _abnormalPh,
                onChanged: (v) {
                  setState(() => _abnormalPh = v);
                  ref
                      .read(appControllerProvider.notifier)
                      .demoScenario(ph: v, water: _lowWater);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'ระดับน้ำต่ำ',
                  style: TextStyle(fontSize: 14),
                ),
                subtitle: const Text(
                  'ทดสอบการตัดอุปกรณ์และปฏิเสธคำสั่ง',
                  style: TextStyle(fontSize: 12),
                ),
                value: _lowWater,
                onChanged: (v) {
                  setState(() => _lowWater = v);
                  ref
                      .read(appControllerProvider.notifier)
                      .demoScenario(ph: _abnormalPh, water: v);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    ];
    final groups = content.whereType<_SettingsGroup>().toList();
    if (widget.section != null) {
      final chosen = groups.where((g) => g.title == widget.section);
      return Scaffold(
        appBar: AppBar(title: Text(widget.section!)),
        body: PageBody(
          children: chosen.isEmpty
              ? [const Text('เชื่อมต่อเครื่องเพื่อเปิดส่วนนี้')]
              : [chosen.first.child],
        ),
      );
    }
    return PageBody(
      children: [
        const PageTitle('อุปกรณ์ของคุณ'),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AquaColors.sage,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.qrCode,
                    size: 64,
                    color: AquaColors.blue,
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'เพิ่มอุปกรณ์',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'บอร์ดควบคุม หรือกล้อง',
                          style: AquaType.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const ValueKey('add-device-by-qr'),
                onPressed: state.busy ? null : _openQrPairing,
                icon: const Icon(PhosphorIconsRegular.scan),
                label: const Text('สแกน QR เพื่อเพิ่มอุปกรณ์'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        ConnectionOverview(
          state: state,
          onBoard: state.busy || _connecting ? null : _openWifiSetup,
          onCamera: state.busy ? null : _openCameraWifi,
          onDemo: _connecting || state.busy
              ? null
              : () {
                  setState(() => _demo = true);
                  _connect();
                },
        ),
        const SizedBox(height: 16),
        const SectionHeading('จัดการ'),
        Surface(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < groups.length; i++) ...[
                groups[i],
                if (i < groups.length - 1)
                  const Divider(height: 1, indent: 16, endIndent: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(PhosphorIconsRegular.camera),
            title: const Text('กล้อง: IP และ USB'),
            trailing: const Icon(PhosphorIconsRegular.caretRight),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(builder: (_) => const CameraConnectionScreen()),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Column(
            children: [
              Text(
                'Smart Catfish System',
                style: TextStyle(color: AquaColors.muted, fontSize: 12),
              ),
              Text(
                '0.22.2',
                style: TextStyle(color: AquaColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String unit,
    double min,
    double max,
  ) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    onChanged: (_) => _dirty = true,
    decoration: InputDecoration(labelText: label, suffixText: unit),
    validator: (v) {
      final parsed = _parse(v);
      if (label == 'pH สูงสุด' &&
          parsed != null &&
          parsed <= (_parse(_ph.text) ?? -1)) {
        return 'ต้องมากกว่า pH ต่ำสุด';
      }
      return parsed == null || !parsed.isFinite || parsed < min || parsed > max
          ? 'ใส่ค่า $min–$max'
          : null;
    },
  );
}

class _SettingsGroup extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Widget child;
  const _SettingsGroup({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    leading: Icon(icon, color: AquaColors.blue),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
    ),
    trailing: const Icon(
      PhosphorIconsRegular.caretRight,
      color: AquaColors.muted,
    ),
    onTap: () => Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => SettingsScreen(section: title)),
    ),
  );
}
