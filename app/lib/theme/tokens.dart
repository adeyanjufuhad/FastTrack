import 'package:flutter/material.dart';

/// Brand tokens — blue and white, taken from the FastTrack mark:
/// the upper bar is [blue], the lower bar and wordmark are [navy].
/// See docs/design/tokens.md.
abstract final class FT {
  static const navy = Color(0xFF0A2463); // wordmark, headings, primary buttons
  static const navySoft = Color(0xFF14337F); // officer chrome, hover
  static const blue = Color(0xFF2B76E5); // accent bar, links, focus, chips
  static const blueDeep = Color(0xFF1D5BC6);
  static const sky = Color(0xFFEAF2FE); // tinted cards, icon wells
  static const mist = Color(0xFFF5F8FD); // page wash behind white cards
  static const white = Color(0xFFFFFFFF);
  static const line = Color(0xFFDCE5F2);
  static const ink = Color(0xFF0F1B33);
  static const slate = Color(0xFF475569); // body text
  static const muted = Color(0xFF64748B);

  // Functional colours — not brand. Amber is reserved for the sandbox chip.
  static const amber = Color(0xFFB45309);
  static const amberBg = Color(0xFFFEF3C7);
  static const ok = Color(0xFF15803D);
  static const okBg = Color(0xFFDCFCE7);
  static const danger = Color(0xFFB91C1C);
  static const dangerBg = Color(0xFFFEE2E2);

  static const radius = 16.0;
  static const radiusSm = 10.0;
  static const motion = Duration(milliseconds: 200);
}

/// Fluid sizing: interpolates between [min] at a 360px viewport and [max]
/// at 1280px, the same idea as CSS `clamp()` on the website.
double fluid(BuildContext context, double min, double max,
    {double from = 360, double to = 1280}) {
  final w = MediaQuery.sizeOf(context).width;
  final t = ((w - from) / (to - from)).clamp(0.0, 1.0);
  return min + (max - min) * t;
}

extension Breakpoints on BuildContext {
  double get width => MediaQuery.sizeOf(this).width;
  bool get isWide => width >= 900;
  bool get isCompact => width < 600;
}
