import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/ui.dart';
import 'wifi_setup.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _settingsForm = GlobalKey<FormState>();
  late final TextEditingController _temperature,
      _ph,
      _phMax,
      _flow,
      _url,
      _device;
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
    _flow = TextEditingController(text: number(state.settings.flowTarget));
    _url = TextEditingController(text: state.connection.baseUrl);
    _device = TextEditingController(text: state.connection.deviceId);
    _demo = state.connection.demo;
    _localEsp32 = state.connection.localEsp32;
  }

  @override
  void dispose() {
    for (final c in [_temperature, _ph, _phMax, _flow, _url, _device, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  void _loadSettings(DeviceSettings settings) {
    _temperature.text = number(settings.temperatureTarget);
    _ph.text = number(settings.phMinimum);
    _phMax.text = number(settings.phMaximum);
    _flow.text = number(settings.flowTarget);
    _dirty = false;
  }

  double? _parse(String? value) =>
      double.tryParse((value ?? '').replaceAll(',', '.'));
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
      flowTarget: _parse(_flow.text)!,
    );
    final error = await ref
        .read(appControllerProvider.notifier)
        .saveSettings(settings);
    if (!mounted) return;
    if (error == null) _dirty = false;
    showFeedback(context, error, success: 'เครื่องยืนยันค่าตั้งแล้ว');
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    final config = ConnectionConfig(
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
    return PageBody(
      children: [
        const PageTitle(
          'ตั้งค่า',
          'จัดการการเชื่อมต่อ ค่าตั้งเครื่อง และรอบฟัก',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ตั้ง Wi-Fi ให้เครื่อง',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                const Text(
                  'เลือก Wi-Fi บ้านจากในแอป แล้วเชื่อม ESP32 โดยตรง ใช้งานต่อได้โดยไม่เปิดคอม',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: state.busy || _connecting ? null : _openWifiSetup,
                  icon: const Icon(Icons.wifi_rounded),
                  label: const Text('ตั้ง Wi-Fi ให้บอร์ด'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        _SettingsGroup(
          title: 'เครื่องและการเชื่อมต่อ',
          subtitle: 'โหมดทดลองและเซิร์ฟเวอร์ของเครื่อง',
          icon: Icons.router_outlined,
          initiallyExpanded: !state.fresh,
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
                    icon: Icon(Icons.science_outlined),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('เครื่องจริง'),
                    icon: Icon(Icons.router_outlined),
                  ),
                ],
                selected: {_demo},
                onSelectionChanged: _connecting || state.busy
                    ? null
                    : (values) => setState(() => _demo = values.first),
              ),
              const SizedBox(height: 20),
              if (_demo)
                const Notice(
                  'ใช้ข้อมูลและคำสั่งจำลองได้ทันที ไม่ส่งคำสั่งไปยัง ESP32',
                )
              else ...[
                DropdownButtonFormField<bool>(
                  initialValue: _localEsp32,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'เชื่อมต่อผ่าน'),
                  items: const [
                    DropdownMenuItem(
                      value: false,
                      child: Text('Gateway / เซิร์ฟเวอร์'),
                    ),
                    DropdownMenuItem(value: true, child: Text('ESP32 ในบ้าน')),
                  ],
                  onChanged: _connecting || state.busy
                      ? null
                      : (value) => setState(() => _localEsp32 = value ?? false),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                TextField(
                  key: const PageStorageKey('connection-device'),
                  controller: _device,
                  decoration: const InputDecoration(
                    labelText: 'รหัสเครื่อง',
                    hintText: 'incubator-01',
                  ),
                ),
                const SizedBox(height: 14),
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
                const SizedBox(height: 14),
                Notice(
                  _localEsp32
                      ? 'มือถือและบอร์ดต้องอยู่ Wi-Fi บ้านเดียวกัน ใช้ URL และรหัสจากหน้าตั้งค่าบอร์ด เชื่อมตรงได้ด้วยแอป Android รุ่น 0.5'
                      : kIsWeb
                      ? 'เว็บใช้รหัสเฉพาะครั้งนี้ การเชื่อมต่อภายนอกต้องใช้ HTTPS'
                      : 'มือถือเก็บรหัสแบบเข้ารหัสและเชื่อมต่อใหม่อัตโนมัติ การเชื่อมต่อภายนอกต้องใช้ HTTPS',
                ),
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
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('ลบรหัสที่บันทึก'),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _connecting || state.busy ? null : _connect,
                icon: const Icon(Icons.link_rounded, size: 18),
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
                              success: 'ESP32-S3 ตอบรับคำสั่งจริงแล้ว',
                            );
                          }
                        },
                  icon: const Icon(Icons.network_check_rounded),
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
        const SizedBox(height: 22),
        _SettingsGroup(
          title: 'ค่าควบคุม',
          subtitle: 'อุณหภูมิ ช่วง pH และอัตราการไหล',
          icon: Icons.tune_rounded,
          initiallyExpanded: false,
          child: Form(
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
                const Text(
                  'ตั้งค่าตามชนิดปลา ระยะฟัก และคำแนะนำของผู้ดูแลการเพาะฟัก',
                  style: TextStyle(fontSize: 12, color: AquaColors.muted),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, c) {
                    final fields = [
                      _field(_temperature, 'อุณหภูมิเป้าหมาย', '°C', 20, 35),
                      _field(_ph, 'pH ต่ำสุด', 'pH', 0, 14),
                      _field(_phMax, 'pH สูงสุด', 'pH', 0, 14),
                      _field(_flow, 'อัตราไหลเป้าหมาย', 'L/min', .1, 50),
                    ];
                    final width = c.maxWidth >= 700
                        ? (c.maxWidth - 16) / 2
                        : c.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 14,
                      children: fields
                          .map((field) => SizedBox(width: width, child: field))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: state.fresh && !state.busy ? _saveSettings : null,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: Text(
                    state.busy ? 'รอเครื่องยืนยัน…' : 'ส่งค่าตั้งไปยังเครื่อง',
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'ค่าตั้งเริ่มต้นใช้ทดลองแอป โปรดกำหนดช่วง pH และอุณหภูมิตามรอบฟักจริง ระบบ pH ใช้ตรวจวัดและแจ้งเตือนเท่านั้น',
                  style: TextStyle(fontSize: 12, color: AquaColors.muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        _SettingsGroup(
          title: 'รอบฟัก',
          subtitle: 'รอบปัจจุบันและการเริ่มรอบใหม่',
          icon: Icons.layers_outlined,
          initiallyExpanded: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'รอบฟักปัจจุบัน',
                trailing: OutlinedButton.icon(
                  onPressed: () => showBatchDialog(
                    context,
                    ref.read(appControllerProvider.notifier),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 17),
                  label: const Text('เริ่มรอบใหม่'),
                ),
              ),
              Text(
                state.batch?.name ?? 'ยังไม่มีรอบฟัก',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
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
              ],
              const SizedBox(height: 12),
              const Text(
                'ผลนับบันทึกในมือถือสูงสุด 100 รายการ รุ่นนี้ยังไม่ซิงก์ประวัติรอบฟักกับเซิร์ฟเวอร์',
                style: TextStyle(fontSize: 12, color: AquaColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        if (state.connection.demo) ...[
          _SettingsGroup(
            title: 'เครื่องมือทดลอง',
            subtitle: 'จำลอง pH ผิดปกติและระดับน้ำต่ำ',
            icon: Icons.science_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeading('ทดสอบสถานการณ์จำลอง'),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'pH นอกช่วง',
                    style: TextStyle(fontSize: 13),
                  ),
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
                    style: TextStyle(fontSize: 13),
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
          const SizedBox(height: 22),
        ],
        const _SettingsGroup(
          title: 'การแจ้งเตือน',
          subtitle: 'ดูความสามารถและข้อจำกัดก่อนเฝ้าเครื่อง',
          icon: Icons.notifications_outlined,
          child: Notice(
            'การแจ้งเตือนในมือถือทำงานขณะเปิดแอป เมื่อปิดแอปให้ตรวจประวัติที่ Gateway บันทึกไว้ ระบบยังไม่มี Push notification',
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

class _SettingsGroup extends StatefulWidget {
  final String title, subtitle;
  final IconData icon;
  final bool initiallyExpanded;
  final Widget child;
  const _SettingsGroup({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.initiallyExpanded = false,
  });
  @override
  State<_SettingsGroup> createState() => _SettingsGroupState();
}

class _SettingsGroupState extends State<_SettingsGroup> {
  // ExpansionTile stores a bool in the route bucket. EditableText stores a
  // double scroll offset, so descendants must not share the tile's identifier.
  final _contentStorage = PageStorageBucket();

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: PageStorageKey(widget.title),
      maintainState: true,
      initiallyExpanded: widget.initiallyExpanded,
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Icon(widget.icon, color: AquaColors.blue),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        widget.subtitle,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: PageStorage(bucket: _contentStorage, child: widget.child),
        ),
      ],
    ),
  );
}
