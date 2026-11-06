import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/theme.dart';

/// The motion describes activity only; completion must come from the caller.
class ConnectionSignal extends StatefulWidget {
  final bool active, complete;
  final IconData icon;
  final double size;
  const ConnectionSignal({
    super.key,
    this.active = false,
    this.complete = false,
    this.icon = Icons.router_rounded,
    this.size = 100,
  });
  @override
  State<ConnectionSignal> createState() => _ConnectionSignalState();
}

class _ConnectionSignalState extends State<ConnectionSignal>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(ConnectionSignal oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  void _syncMotion() {
    if (widget.active && !MediaQuery.disableAnimationsOf(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
      _motion.value = 0;
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _motion,
        builder: (context, child) => CustomPaint(
          painter: _SignalRings(_motion.value, widget.active),
          child: Center(child: child),
        ),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          width: widget.size * .54,
          height: widget.size * .54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.size * .18),
            color: widget.complete ? const Color(0xFFBDF4DB) : Colors.white,
            boxShadow: const [
              BoxShadow(
                color: Color(0x22001D35),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Icon(
              widget.complete ? Icons.check_rounded : widget.icon,
              key: ValueKey(widget.complete),
              size: widget.size * .29,
              color: AquaColors.blue,
            ),
          ),
        ),
      ),
    ),
  );
}

class _SignalRings extends CustomPainter {
  final double phase;
  final bool active;
  const _SignalRings(this.phase, this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final t = active ? (phase + i / 3) % 1 : .25 + i * .26;
      canvas.drawCircle(
        center,
        size.width * (.29 + t * .2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = Colors.white.withValues(alpha: (1 - t) * .35),
      );
    }
    if (active) {
      final a = phase * math.pi * 2;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * (size.width * .4),
        3,
        Paint()..color = const Color(0xFF92ECD9),
      );
    }
  }

  @override
  bool shouldRepaint(_SignalRings oldDelegate) =>
      phase != oldDelegate.phase || active != oldDelegate.active;
}

class ConnectionJourneyHeader extends StatelessWidget {
  final int step;
  final String title, subtitle, device;
  final bool busy, complete;
  final IconData icon;
  const ConnectionJourneyHeader({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.device,
    this.busy = false,
    this.complete = false,
    this.icon = Icons.router_rounded,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(22),
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
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 6,
              children: [
                Text(
                  device,
                  style: const TextStyle(
                    color: Color(0xFFBBE8E8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  complete ? 'เรียบร้อย' : 'ขั้นที่ ${step + 1} / 4',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConnectionSignal(
                  active: busy,
                  complete: complete,
                  icon: icon,
                  size: 86,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white, height: 1.65),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Semantics(
        label: complete
            ? 'ตั้งค่าเสร็จครบ 4 ขั้นตอน'
            : 'ขั้นตอนที่ ${step + 1} จาก 4',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(4, (i) {
            final done = complete || i < step;
            final current = !complete && i == step;
            return Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == 0
                              ? Colors.transparent
                              : i <= step || complete
                              ? AquaColors.teal
                              : AquaColors.line,
                        ),
                      ),
                      AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done || current
                              ? AquaColors.teal
                              : Colors.white,
                          border: Border.all(
                            color: done || current
                                ? AquaColors.teal
                                : AquaColors.line,
                            width: 1.5,
                          ),
                        ),
                        child: Center(
                          child: done
                              ? const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                    color: current
                                        ? Colors.white
                                        : AquaColors.muted,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 2,
                          color: i == 3
                              ? Colors.transparent
                              : i < step || complete
                              ? AquaColors.teal
                              : AquaColors.line,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    const ['เตรียม', 'ต่อบอร์ด', 'เลือก Wi-Fi', 'ยืนยัน'][i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: current || done
                          ? AquaColors.teal
                          : AquaColors.muted,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    ],
  );
}

class ConnectionHint extends StatelessWidget {
  final String text;
  final IconData icon;
  final bool error;
  const ConnectionHint(
    this.text, {
    super.key,
    this.icon = Icons.info_outline_rounded,
    this.error = false,
  });
  @override
  Widget build(BuildContext context) {
    final color = error ? AquaColors.red : AquaColors.blue;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : icon,
            color: color,
            size: 21,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: color, height: 1.65)),
          ),
        ],
      ),
    );
  }
}

/// A read-only walkthrough. It never instantiates a client or changes pairing.
class ConnectionPreviewScreen extends StatefulWidget {
  const ConnectionPreviewScreen({super.key});
  @override
  State<ConnectionPreviewScreen> createState() =>
      _ConnectionPreviewScreenState();
}

class _ConnectionPreviewScreenState extends State<ConnectionPreviewScreen> {
  int _step = 0;
  @override
  Widget build(BuildContext context) {
    const titles = [
      'เตรียมอุปกรณ์',
      'เชื่อม Wi-Fi ของบอร์ด',
      'เลือก Wi-Fi บ้าน',
      'ตรวจยืนยันการเชื่อมต่อ',
    ];
    const explanations = [
      'จ่ายไฟให้บอร์ด เตรียม Wi-Fi บ้าน 2.4 GHz และรหัสจับคู่จากบัตรประจำเครื่อง',
      'เปิดตั้งค่า Wi-Fi ของมือถือ เลือกเครือข่าย AquaHatch ของบอร์ด แล้วกลับมาที่แอป',
      'เลือก Wi-Fi บ้านที่บอร์ดค้นพบ ใส่รหัสผ่าน แล้วส่งให้บอร์ดเชื่อมต่อ',
      'กลับไปเชื่อม Wi-Fi บ้านบนมือถือ แอปจะตรวจว่าติดต่อบอร์ดได้จริงก่อนบันทึก',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('ดูวิธีเชื่อมต่อ')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ConnectionHint(
                    'ตัวอย่างขั้นตอน • ไม่เชื่อมต่อหรือเปลี่ยนค่าอุปกรณ์',
                    icon: Icons.play_circle_outline_rounded,
                  ),
                  const SizedBox(height: 16),
                  ConnectionJourneyHeader(
                    step: _step,
                    title: titles[_step],
                    subtitle: explanations[_step],
                    device: 'ESP32-WROOM-DA · บอร์ดหลัก',
                    busy: _step == 3,
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 300),
                    child: Card(
                      key: ValueKey(_step),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Icon(
                              [
                                Icons.power_rounded,
                                Icons.wifi_find_rounded,
                                Icons.home_rounded,
                                Icons.sync_rounded,
                              ][_step],
                              color: AquaColors.blue,
                              size: 38,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              explanations[_step],
                              textAlign: TextAlign.center,
                              style: const TextStyle(height: 1.8),
                            ),
                            if (_step == 3) ...[
                              const SizedBox(height: 16),
                              const ConnectionHint(
                                'ภาพเคลื่อนไหวนี้เป็นตัวอย่าง แอปจะแสดงว่าสำเร็จเมื่อบอร์ดตอบรับจริงเท่านั้น',
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _step < 3
                        ? setState(() => _step++)
                        : Navigator.of(context).pop(),
                    icon: Icon(
                      _step < 3
                          ? Icons.arrow_forward_rounded
                          : Icons.check_rounded,
                    ),
                    label: Text(_step < 3 ? 'ดูขั้นตอนถัดไป' : 'เข้าใจแล้ว'),
                  ),
                  if (_step > 0)
                    TextButton(
                      onPressed: () => setState(() => _step--),
                      child: const Text('ย้อนกลับ'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
