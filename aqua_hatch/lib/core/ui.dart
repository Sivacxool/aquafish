import 'dart:math';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app/theme.dart';
import 'models.dart';
import 'controller.dart';

void showFeedback(
  BuildContext context,
  String? error, {
  String success = 'บันทึกแล้ว',
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(error ?? success),
      backgroundColor: error == null ? AquaColors.deep : AquaColors.red,
      behavior: SnackBarBehavior.floating,
    ),
  );
}

String number(double? value, {int decimals = 1}) =>
    value?.toStringAsFixed(decimals) ?? '—';
String shortTime(DateTime time) => DateFormat('HH:mm', 'th').format(time);
String fullTime(DateTime time) =>
    DateFormat('d MMM yyyy · HH:mm', 'th').format(time);
String elapsed(DateTime start, DateTime now) {
  final d = now.difference(start);
  if (d.isNegative) return 'ยังไม่เริ่ม';
  return '${d.inHours} ชม. ${d.inMinutes % 60} นาที';
}

class Surface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: padding, child: child),
  );
}

class PageTitle extends StatelessWidget {
  final String title, subtitle;
  final Widget? trailing;
  const PageTitle(this.title, this.subtitle, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 20,
        runSpacing: 14,
        children: [
          SizedBox(
            width: c.maxWidth < 650 ? c.maxWidth : c.maxWidth - 230,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 5),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    ),
  );
}

class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const Pill(this.label, {super.key, this.color = AquaColors.teal, this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(30),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
        ],
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeading(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}

class Notice extends StatelessWidget {
  final String text;
  final bool warning;
  final Widget? action;
  const Notice(this.text, {super.key, this.warning = false, this.action});
  @override
  Widget build(BuildContext context) {
    final color = warning ? AquaColors.orange : AquaColors.blue;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            warning ? Icons.info_outline_rounded : Icons.water_drop_outlined,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: color, fontSize: 12, height: 1.7),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class MetricCard extends StatelessWidget {
  final String title, value, unit, detail;
  final IconData icon;
  final Color color;
  final bool warning;
  const MetricCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.detail,
    required this.icon,
    this.color = AquaColors.blue,
    this.warning = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label:
        '$title $value $unit. ${warning ? 'ควรตรวจสอบ' : 'อยู่ในค่าที่ตั้งไว้'}. $detail',
    excludeSemantics: true,
    child: Surface(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 19, color: color),
              ),
              const Spacer(),
              Icon(
                warning
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline_rounded,
                color: warning ? AquaColors.orange : AquaColors.teal,
                size: 18,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontSize: 13, color: AquaColors.muted),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 5,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              Text(unit, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          Text(
            detail,
            style: TextStyle(
              fontSize: 12,
              color: warning ? AquaColors.orange : AquaColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class FishIllustration extends StatelessWidget {
  final double size;
  final Color color;
  const FishIllustration({
    super.key,
    this.size = 50,
    this.color = AquaColors.blue,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'มาสคอตปลาดุก',
    child: CustomPaint(
      size: Size(size, size * .8),
      painter: _FishPainter(color),
    ),
  );
}

class _FishPainter extends CustomPainter {
  final Color color;
  _FishPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 80);
    final paint = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(70, 40)
        ..lineTo(95, 21)
        ..quadraticBezierTo(90, 40, 95, 58)
        ..close(),
      paint,
    );
    canvas.drawOval(const Rect.fromLTWH(10, 19, 70, 42), paint);
    canvas.drawPath(
      Path()
        ..moveTo(36, 22)
        ..lineTo(48, 7)
        ..lineTo(61, 22),
      paint,
    );
    canvas.drawCircle(const Offset(29, 34), 4, Paint()..color = Colors.white);
    canvas.drawCircle(
      const Offset(30, 34),
      2,
      Paint()..color = AquaColors.deep,
    );
    final whisker = Paint()
      ..color = color
      ..strokeWidth = 2.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(
      Path()
        ..moveTo(15, 46)
        ..quadraticBezierTo(3, 43, 1, 31),
      whisker,
    );
    canvas.drawPath(
      Path()
        ..moveTo(16, 47)
        ..quadraticBezierTo(4, 56, 2, 65),
      whisker,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FishPainter old) => old.color != color;
}

class IncubatorIllustration extends StatelessWidget {
  const IncubatorIllustration({super.key});
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(230, 180), painter: _IncubatorPainter());
}

class _IncubatorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 230, size.height / 180);
    canvas.drawOval(
      const Rect.fromLTWH(31, 158, 172, 16),
      Paint()..color = Colors.black.withValues(alpha: .1),
    );
    final border = Paint()
      ..color = const Color(0xFFA0D8E8)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final jar = RRect.fromRectAndRadius(
      const Rect.fromLTWH(49, 31, 128, 126),
      const Radius.circular(17),
    );
    canvas.drawRRect(jar, Paint()..color = Colors.white.withValues(alpha: .13));
    canvas.save();
    canvas.clipRRect(jar);
    canvas.drawRect(
      const Rect.fromLTWH(50, 66, 127, 92),
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF67C9DF), Color(0xFF1587AC)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(const Rect.fromLTWH(50, 66, 127, 92)),
    );
    for (var i = 0; i < 7; i++) {
      canvas.drawCircle(
        Offset(63 + i * 16, 90 + (i % 3) * 18),
        3,
        Paint()..color = Colors.white.withValues(alpha: .4),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(62, 112, 103, 10),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFDBEDF0),
    );
    for (var i = 0; i < 16; i++) {
      canvas.drawCircle(
        Offset(71 + (i % 8) * 12, 107 - (i ~/ 8) * 8),
        2.3,
        Paint()..color = const Color(0xFFF4DCA9),
      );
    }
    canvas.restore();
    canvas.drawRRect(jar, border);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(42, 24, 142, 15),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFFDEEDF1),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(40, 147, 146, 18),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xFFB7D9E3),
    );
    canvas.drawPath(
      Path()
        ..moveTo(177, 112)
        ..lineTo(198, 112)
        ..lineTo(198, 54)
        ..lineTo(177, 54),
      Paint()
        ..color = const Color(0xFF91D8E4)
        ..strokeWidth = 7
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(86, 7, 54, 12),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFDEEDF1),
    );
    canvas.drawCircle(
      const Offset(113, 14),
      3.5,
      Paint()..color = AquaColors.deep,
    );
    canvas.drawLine(const Offset(113, 19), const Offset(113, 24), border);
    canvas.drawCircle(
      const Offset(148, 156),
      3,
      Paint()..color = const Color(0xFF50DFB7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IncubatorPainter old) => false;
}

class TrendChart extends StatelessWidget {
  final List<Telemetry> history;
  final bool ph;
  const TrendChart({super.key, required this.history, this.ph = false});
  @override
  Widget build(BuildContext context) {
    final values = history
        .map((t) => ph ? t.ph : t.temperature)
        .whereType<double>()
        .toList();
    if (values.length < 2) {
      return const SizedBox(
        height: 185,
        child: Center(
          child: Text(
            'กำลังเก็บข้อมูลสำหรับกราฟ…',
            style: TextStyle(color: AquaColors.muted),
          ),
        ),
      );
    }
    final minY = values.reduce(min) - .4, maxY = values.reduce(max) + .4;
    return Column(
      children: [
        SizedBox(
          height: 185,
          child: Row(
            children: [
              SizedBox(
                width: 35,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(
                    4,
                    (i) => Text(
                      (maxY - (maxY - minY) * i / 3).toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AquaColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: CustomPaint(
                  size: const Size(double.infinity, 185),
                  painter: _TrendPainter(
                    history,
                    ph,
                    minY,
                    maxY,
                    ph ? AquaColors.teal : AquaColors.blue,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                shortTime(history.first.at),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                'ข้อมูลที่รับในช่วงนี้',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                shortTime(history.last.at),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<Telemetry> samples;
  final bool ph;
  final double minY, maxY;
  final Color color;
  _TrendPainter(this.samples, this.ph, this.minY, this.maxY, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = AquaColors.line
      ..strokeWidth = 1;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final line = Path();
    var connected = false;
    final duration = max(
      1,
      samples.last.at.difference(samples.first.at).inMilliseconds,
    );
    for (var i = 0; i < samples.length; i++) {
      final value = ph ? samples[i].ph : samples[i].temperature;
      if (value == null) {
        connected = false;
        continue;
      }
      if (i > 0 &&
          samples[i].at.difference(samples[i - 1].at).inSeconds > 120) {
        connected = false;
      }
      final x =
              size.width *
              samples[i].at.difference(samples.first.at).inMilliseconds /
              duration,
          y = size.height * (1 - (value - minY) / (maxY - minY));
      if (!connected) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      connected = true;
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = color);
    }
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => true;
}

class PageBody extends StatelessWidget {
  final List<Widget> children;
  const PageBody({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width < 600 ? 18 : 30,
            20,
            MediaQuery.sizeOf(context).width < 600 ? 18 : 30,
            32,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    ),
  );
}

Future<void> showBatchDialog(
  BuildContext context,
  AppController controller,
) async {
  final name = TextEditingController();
  final eggs = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('เริ่มรอบฟักใหม่'),
        content: SizedBox(
          width: 380,
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  maxLength: 60,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อรอบฟัก',
                    hintText: 'เช่น รอบฟัก 01',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'กรุณาตั้งชื่อรอบฟัก'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: eggs,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'จำนวนไข่เริ่มต้น (ไม่บังคับ)',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? null
                      : int.tryParse(v) == null || int.parse(v) <= 0
                      ? 'ใส่จำนวนเต็มที่มากกว่า 0'
                      : null,
                ),
                const SizedBox(height: 14),
                const Text(
                  'ประวัติของรอบเดิมยังคงอยู่ ผลนับใหม่จะผูกกับรอบนี้',
                  style: TextStyle(fontSize: 12, color: AquaColors.muted),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (form.currentState?.validate() != true) return;
                    setState(() => busy = true);
                    final error = await controller.startBatch(
                      name.text,
                      int.tryParse(eggs.text),
                    );
                    if (!dialogContext.mounted) return;
                    if (error == null) {
                      Navigator.pop(dialogContext);
                      showFeedback(
                        context,
                        null,
                        success: 'เริ่มรอบฟักใหม่แล้ว',
                      );
                    } else {
                      setState(() => busy = false);
                      showFeedback(dialogContext, error);
                    }
                  },
            child: Text(busy ? 'กำลังบันทึก…' : 'เริ่มรอบฟัก'),
          ),
        ],
      ),
    ),
  );
  // Dispose after the closing route animation releases its text fields.
  Future<void>.delayed(const Duration(milliseconds: 350), () {
    name.dispose();
    eggs.dispose();
  });
}
