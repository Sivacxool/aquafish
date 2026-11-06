import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/camera_ui.dart';
import '../core/models.dart';
import '../core/sensor_status.dart';
import '../core/ui.dart';
import 'history.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _phChart = false;
  int _hours = 1;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final data = state.telemetry;
    final controls = ref.read(appControllerProvider.notifier);
    final seconds = data == null
        ? null
        : state.now.difference(data.at).inSeconds.clamp(0, 9999);
    final history = state.history
        .where(
          (t) => !t.at.isBefore(state.now.subtract(Duration(hours: _hours))),
        )
        .toList();
    return PageBody(
      children: [
        Text(
          'ภาพรวมเครื่องฟัก',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        _ConnectionCard(state: state, reconnect: controls.reconnect),
        if (state.fresh &&
            data?.hardwareReady != false &&
            state.alerts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Notice(state.alerts.join('\n'), warning: true),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                state.fresh ? 'คุณภาพน้ำขณะนี้' : 'ค่าคุณภาพน้ำล่าสุด',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            Text(
              seconds == null ? 'รอข้อมูล' : '$seconds วินาทีที่แล้ว',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, c) {
            final columns = c.maxWidth >= 800
                ? 4
                : c.maxWidth >= 300 &&
                      MediaQuery.textScalerOf(context).scale(14) < 20
                ? 2
                : 1;
            final width = (c.maxWidth - 12 * (columns - 1)) / columns;
            final cards = [
              MetricCard(
                title: 'อุณหภูมิน้ำ',
                value: number(data?.temperature),
                unit: '°C',
                detail: state.connection.localEsp32
                    ? sensorStatusLabel(
                        data?.temperatureStatus,
                        source: 'DS18B20 · GPIO4',
                      )
                    : 'ค่าตั้ง ${number(state.settings.temperatureTarget)} °C',
                icon: Icons.thermostat_rounded,
                warning:
                    data?.temperature == null ||
                    (data!.temperature! - state.settings.temperatureTarget)
                            .abs() >
                        1,
              ),
              MetricCard(
                key: const ValueKey('dissolved-oxygen-card'),
                title: 'ออกซิเจนละลายน้ำ (DO)',
                value: number(data?.dissolvedOxygen, decimals: 2),
                unit: 'mg/L',
                detail: data?.dissolvedOxygen == 0
                    ? 'หัววัดรายงานศูนย์ ตรวจหัววัดและสภาพน้ำ'
                    : sensorStatusLabel(
                        data?.dissolvedOxygenStatus,
                        source: 'หัววัด DO ผ่าน RS485',
                      ),
                icon: Icons.air_rounded,
                color: AquaColors.teal,
                warning:
                    data?.dissolvedOxygen == null || data?.dissolvedOxygen == 0,
              ),
              MetricCard(
                title: 'ค่า pH',
                value: number(data?.ph),
                unit: 'pH',
                detail: data?.phSensor.supported == true && data?.ph == null
                    ? data!.phSensor.message
                    : 'ช่วง ${number(state.settings.phMinimum)}–${number(state.settings.phMaximum)}',
                icon: Icons.bubble_chart_outlined,
                color: AquaColors.teal,
                warning:
                    data?.ph == null ||
                    !data!.phCalibrated ||
                    data.ph! < state.settings.phMinimum ||
                    data.ph! > state.settings.phMaximum,
              ),
              MetricCard(
                title: 'ระดับน้ำ',
                value: data?.waterLevelOk == null
                    ? 'ไม่ทราบ'
                    : data!.waterLevelOk!
                    ? 'ปกติ'
                    : 'ต่ำ',
                unit: '',
                detail: 'ระบบตรวจระดับน้ำ',
                icon: Icons.water_drop_outlined,
                warning: data?.waterLevelOk != true,
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards
                  .map((card) => SizedBox(width: width, child: card))
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 18),
        const CameraConnectionCard(),
        const SizedBox(height: 18),
        _BatchCard(
          state: state,
          onNew: () => showBatchDialog(context, controls),
        ),
        const SizedBox(height: 18),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'แนวโน้มคุณภาพน้ำ',
                trailing: DropdownButton<bool>(
                  value: _phChart,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('°C')),
                    DropdownMenuItem(value: true, child: Text('pH')),
                  ],
                  onChanged: (v) => setState(() => _phChart = v ?? false),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [1, 6, 24]
                      .map(
                        (h) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text('$h ชม.'),
                            selected: _hours == h,
                            onSelected: (_) => setState(() => _hours = h),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 16),
              TrendChart(history: history, ph: _phChart),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen(),
                  ),
                ),
                icon: const Icon(Icons.history_rounded),
                label: const Text('ประวัติคุณภาพน้ำ / คัดลอก CSV'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                'สถานะที่เครื่องรายงาน',
                trailing: TextButton(
                  onPressed: () => context.go('/controls'),
                  child: const Text('ควบคุม'),
                ),
              ),
              ...[
                (Icons.water_rounded, 'ปั๊มน้ำ', 'pump'),
                (Icons.thermostat_rounded, 'ฮีตเตอร์', 'heater'),
                (Icons.ac_unit_rounded, 'ทำความเย็น', 'cooler'),
                (Icons.sync_rounded, 'หมุนเวียนไข่', 'tumbler'),
              ].map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    children: [
                      Icon(entry.$1, size: 22, color: AquaColors.blue),
                      const SizedBox(width: 12),
                      Expanded(child: Text(entry.$2)),
                      Pill(
                        data?.hardwareReady == false
                            ? 'รอติดตั้ง'
                            : data == null
                            ? 'รอข้อมูล'
                            : data.output(entry.$3)
                            ? 'เปิด'
                            : 'ปิด',
                        color: data?.output(entry.$3) == true
                            ? AquaColors.teal
                            : AquaColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
              Text(
                'การเปิดรีเลย์ยังไม่ยืนยันว่าอุปกรณ์ทำงานจริง',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('กิจกรรมล่าสุด'),
              if (state.events.isEmpty) const Text('ยังไม่มีกิจกรรม'),
              ...state.events
                  .take(3)
                  .map(
                    (e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        e.warning
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle_outline,
                        color: e.warning ? AquaColors.orange : AquaColors.teal,
                      ),
                      title: Text(e.message),
                      subtitle: Text(fullTime(e.at)),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectionCard extends StatelessWidget {
  final AppState state;
  final VoidCallback reconnect;
  const _ConnectionCard({required this.state, required this.reconnect});

  void _details(BuildContext context) {
    final data = state.telemetry;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading('การเชื่อมต่อ'),
              Text(state.connectionLabel),
              if (!state.connection.demo)
                Text('อุปกรณ์ ${state.connection.deviceId}'),
              if (data != null) Text('อัปเดต ${fullTime(data.at)}'),
              if (data?.firmwareVersion != null)
                Text('เฟิร์มแวร์ ${data!.firmwareVersion}'),
              if (data?.wifiRssi != null)
                Text('สัญญาณ Wi-Fi ${data!.wifiRssi} dBm'),
              if (!state.fresh && state.connection.localEsp32) ...[
                const SizedBox(height: 12),
                const Text(
                  'กลับเข้า Wi-Fi ของเครื่อง หรือเปิดดูจากนอกบ้านในตั้งค่า',
                ),
              ],
              if (state.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  state.error!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final online = state.fresh;
    final title = state.connection.demo
        ? 'โหมดทดลอง'
        : online
        ? (state.telemetry?.viaRelay == true
              ? 'ออนไลน์ · ผ่านอินเทอร์เน็ต'
              : 'เชื่อมต่อแล้ว')
        : state.error != null || state.telemetry != null
        ? 'ติดต่อบอร์ดไม่ได้'
        : 'กำลังเชื่อมต่อ';
    final subtitle = !online && state.connection.localEsp32
        ? 'ลองเชื่อมต่อใหม่อัตโนมัติ'
        : null;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => _details(context),
        leading: Icon(
          online ? Icons.wifi_rounded : Icons.wifi_off_rounded,
          color: online ? AquaColors.teal : AquaColors.muted,
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle),
        trailing: online
            ? const Icon(Icons.chevron_right_rounded)
            : IconButton(
                onPressed: state.busy ? null : reconnect,
                tooltip: 'เชื่อมต่อใหม่',
                icon: const Icon(Icons.refresh_rounded),
              ),
      ),
    );
  }
}

class _BatchCard extends StatelessWidget {
  final AppState state;
  final VoidCallback onNew;
  const _BatchCard({required this.state, required this.onNew});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF086A73), Color(0xFF064563)],
      ),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'รอบฟักปัจจุบัน',
                style: TextStyle(color: Color(0xFFD9EEF2)),
              ),
            ),
            IconButton(
              tooltip: 'เริ่มรอบฟักใหม่',
              onPressed: onNew,
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
            ),
          ],
        ),
        Text(
          state.batch?.name ?? 'ยังไม่มีรอบฟัก',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        if (state.batch != null)
          Text(
            'ผ่านมา ${elapsed(state.batch!.startedAt, state.now)}',
            style: const TextStyle(color: Colors.white),
          ),
        const SizedBox(height: 8),
        Text(
          state.telemetry?.hardwareReady == false
              ? 'รอติดตั้งวงจรควบคุม'
              : state.telemetry == null
              ? 'รอข้อมูลโหมดเครื่อง'
              : state.telemetry!.mode == RunMode.manual
              ? 'ควบคุมเองชั่วคราว'
              : 'โหมดอัตโนมัติ',
          style: const TextStyle(color: Color(0xFFD9EEF2)),
        ),
        const SizedBox(height: 12),
        Text(
          !state.fresh
              ? 'รอข้อมูลล่าสุดก่อนตรวจสถานะ'
              : state.telemetry?.hardwareReady == false
              ? 'ยังไม่มีข้อมูลคุณภาพน้ำจากเซนเซอร์จริง'
              : state.alerts.isEmpty
              ? 'ค่าที่ตรวจวัดอยู่ในช่วงที่ตั้งไว้'
              : 'มีค่าต้องตรวจสอบ ดูการแจ้งเตือนด้านบน',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}
