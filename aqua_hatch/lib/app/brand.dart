import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// The same offline vector mark and animation on Android and iOS.
class CatfishMark extends StatefulWidget {
  const CatfishMark({
    super.key,
    this.size = 80,
    this.animate = false,
    this.color = AquaColors.lime,
  });
  final double size;
  final bool animate;
  final Color color;
  @override
  State<CatfishMark> createState() => _CatfishMarkState();
}

class _CatfishMarkState extends State<CatfishMark>
    with SingleTickerProviderStateMixin {
  late final _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );
  void _sync() {
    if (widget.animate && !MediaQuery.disableAnimationsOf(context)) {
      if (!_motion.isAnimating) _motion.repeat();
    } else {
      _motion.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CatfishMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _MarkPainter(_motion, widget.color)),
      ),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.motion, this.color) : super(repaint: motion);
  final Animation<double> motion;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(size.shortestSide / 100);
    final t = motion.value * math.pi * 2;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.translate(0, math.sin(t) * 2);
    final fish = Path()
      ..moveTo(-22, 0)
      ..cubicTo(-8, -17, 15, -14, 21, -3)
      ..cubicTo(28, -3, 31, -10, 34, -12)
      ..quadraticBezierTo(30, 0, 34, 12)
      ..quadraticBezierTo(26, 6, 21, 3)
      ..cubicTo(8, 17, -12, 12, -22, 0)
      ..close();
    canvas.drawPath(fish, Paint()..color = color);
    stroke
      ..color = color
      ..strokeWidth = 1.5;
    canvas.drawPath(
      Path()
        ..moveTo(-18, -2)
        ..quadraticBezierTo(-28, -11, -32, -6),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-18, 2)
        ..quadraticBezierTo(-29, 12, -32, 7),
      stroke,
    );
    canvas.drawCircle(
      const Offset(-11, -3),
      1.7,
      Paint()..color = AquaColors.deep,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color;
}

class DialValue extends StatelessWidget {
  const DialValue({
    super.key,
    required this.value,
    required this.unit,
    required this.caption,
    this.dark = false,
  });
  final String value, unit, caption;
  final bool dark;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          caption,
          style: AquaType.caption.copyWith(
            color: dark ? AquaColors.lime : AquaColors.muted,
          ),
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AquaMotion.fade,
          child: Text(
            '$value $unit',
            key: ValueKey(value),
            style: AquaType.metric.copyWith(
              color: dark ? AquaColors.paper : AquaColors.navy,
            ),
          ),
        ),
      ],
    ),
  );
}
