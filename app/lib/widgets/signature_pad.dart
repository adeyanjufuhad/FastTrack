import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// A small CustomPainter signature canvas. Exports a transparent PNG.
/// Not a qualified e-signature — see docs/PRD.md.
class SignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;

  List<List<Offset>> get strokes => _strokes;
  bool get isEmpty => _strokes.every((s) => s.length < 2);

  void _start(Offset p) {
    _strokes.add([p]);
    notifyListeners();
  }

  void _extend(Offset p) {
    if (_strokes.isEmpty) return;
    _strokes.last.add(p);
    notifyListeners();
  }

  void clear() {
    _strokes.clear();
    notifyListeners();
  }

  Future<Uint8List?> toPng({double pixelRatio = 2}) async {
    if (isEmpty || _size.isEmpty) return null;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    _SignaturePainter(_strokes).paint(canvas, _size);
    final image = await recorder.endRecording().toImage(
      (_size.width * pixelRatio).round(),
      (_size.height * pixelRatio).round(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes?.buffer.asUint8List();
  }
}

class SignaturePad extends StatelessWidget {
  const SignaturePad({super.key, required this.controller, this.height = 200});

  final SignatureController controller;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(
      color: FT.white,
      borderRadius: BorderRadius.circular(FT.radius),
      border: Border.all(color: FT.line, width: 1.2),
    ),
    clipBehavior: Clip.antiAlias,
    child: LayoutBuilder(
      builder: (context, box) {
        controller._size = Size(box.maxWidth, box.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => controller._start(d.localPosition),
          onPanUpdate: (d) => controller._extend(d.localPosition),
          child: ListenableBuilder(
            listenable: controller,
            builder: (_, _) => Stack(
              children: [
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: 44,
                  child: Container(height: 1, color: FT.line),
                ),
                if (controller.isEmpty)
                  const Center(
                    child: Text('Sign here', style: TextStyle(color: FT.muted, fontSize: 15)),
                  ),
                Positioned.fill(
                  child: CustomPaint(painter: _SignaturePainter(controller.strokes)),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = FT.navy
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (var i = 1; i < s.length - 1; i++) {
        final mid = Offset((s[i].dx + s[i + 1].dx) / 2, (s[i].dy + s[i + 1].dy) / 2);
        path.quadraticBezierTo(s[i].dx, s[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(s.last.dx, s.last.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_SignaturePainter old) => true;
}
