import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Draws a clearly-fake "SAMPLE ID" card as a PNG, so an offline demo can
/// walk A6 on a laptop with no ID file to hand. Demo mode only.
Future<Uint8List> sampleIdPng(String name) async {
  const w = 640.0, h = 400.0;
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);

  final card = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, h), const Radius.circular(28));
  c.drawRRect(card, Paint()..color = FT.sky);
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, w, 84), const Radius.circular(28)),
    Paint()..color = FT.navy,
  );
  c.drawRect(const Rect.fromLTWH(0, 56, w, 28), Paint()..color = FT.navy);
  c.drawRRect(
    RRect.fromRectAndRadius(const Rect.fromLTWH(36, 116, 150, 190), const Radius.circular(16)),
    Paint()..color = FT.white,
  );
  c.drawCircle(const Offset(111, 186), 38, Paint()..color = FT.line);
  c.drawOval(const Rect.fromLTWH(61, 236, 100, 70), Paint()..color = FT.line);

  void text(String s, Offset at, double size, Color color, {FontWeight weight = FontWeight.w600}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: color, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: w - at.dx - 30);
    tp.paint(c, at);
  }

  text('SAMPLE ID · DEMO ONLY', const Offset(36, 26), 26, FT.white, weight: FontWeight.w800);
  text('NAME', const Offset(216, 124), 16, FT.muted);
  text(name.isEmpty ? 'Demo Applicant' : name, const Offset(216, 146), 28, FT.navy, weight: FontWeight.w800);
  text('ID NUMBER', const Offset(216, 206), 16, FT.muted);
  text('00000 000000', const Offset(216, 228), 24, FT.navy);
  text('Not a real identity document.', const Offset(216, 290), 17, FT.amber);

  final image = await recorder.endRecording().toImage(w.toInt(), h.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
