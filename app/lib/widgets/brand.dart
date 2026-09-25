import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The FastTrack mark: two slanted bars forming an "F" — blue over navy.
/// Geometry matches website/assets/logo-mark.svg (64×64 viewBox).
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 32, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(painter: _MarkPainter(onDark: onDark)),
  );
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.onDark});
  final bool onDark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 64;
    Paint bar(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 11 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final top = Path()
      ..moveTo(9 * s, 30 * s)
      ..lineTo(23 * s, 15 * s)
      ..lineTo(56 * s, 15 * s);
    final bottom = Path()
      ..moveTo(9 * s, 54 * s)
      ..lineTo(23 * s, 39 * s)
      ..lineTo(43 * s, 39 * s);

    canvas
      ..drawPath(top, bar(FT.blue))
      ..drawPath(bottom, bar(onDark ? FT.white : FT.navy));
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.onDark != onDark;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 28, this.onDark = false});

  final double size;
  final bool onDark;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      LogoMark(size: size * 1.15, onDark: onDark),
      SizedBox(width: size * 0.4),
      Text(
        'FastTrack',
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontSize: size,
          fontWeight: FontWeight.w800,
          letterSpacing: -size * 0.03,
          color: onDark ? FT.white : FT.navy,
          height: 1,
        ),
      ),
    ],
  );
}
