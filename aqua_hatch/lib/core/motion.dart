import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/theme.dart';

class AquaLoader extends StatefulWidget {
  const AquaLoader({
    super.key,
    required this.label,
    this.color = AquaColors.blue,
    this.compact = false,
  });

  final String label;
  final Color color;
  final bool compact;

  @override
  State<AquaLoader> createState() => _AquaLoaderState();
}

class _AquaLoaderState extends State<AquaLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _phase.stop();
    } else if (!_phase.isAnimating) {
      _phase.repeat();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 24.0 : 54.0;
    return Semantics(
      label: widget.label,
      liveRegion: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size,
            child: CustomPaint(painter: _Ripples(_phase, widget.color)),
          ),
          if (!widget.compact) ...[
            const SizedBox(height: 8),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Ripples extends CustomPainter {
  _Ripples(this.phase, this.color) : super(repaint: phase);

  final Animation<double> phase;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius * .17, Paint()..color = color);
    for (final offset in [0.0, .5]) {
      final t = (phase.value + offset) % 1;
      canvas.drawCircle(
        center,
        radius * (.3 + .64 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = color.withValues(alpha: .65 * (1 - t)),
      );
    }
    final angle = phase.value * math.pi * 2 - math.pi / 2;
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * (radius * .72),
      radius * .09,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_Ripples oldDelegate) => oldDelegate.color != color;
}
