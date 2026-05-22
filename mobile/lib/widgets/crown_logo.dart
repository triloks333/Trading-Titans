import 'package:flutter/material.dart';

class CrownLogo extends StatelessWidget {
  final double size;
  final bool withRing;

  const CrownLogo({super.key, this.size = 64, this.withRing = true});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CrownPainter(withRing: withRing),
      ),
    );
  }
}

class _CrownPainter extends CustomPainter {
  final bool withRing;
  
  _CrownPainter({this.withRing = true});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 100.0;
    
    if (withRing) {
      final ringPaint = Paint()
        ..color = const Color(0xFFF9F6EE)
        ..style = PaintingStyle.fill;
      final ringStroke = Paint()
        ..color = const Color(0xFFC9A227)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * scale;
      canvas.drawCircle(Offset(50 * scale, 50 * scale), 46 * scale, ringPaint);
      canvas.drawCircle(Offset(50 * scale, 50 * scale), 46 * scale, ringStroke);
    }
    
    // Gradient
    final Rect bounds = Rect.fromLTWH(0, 0, 100 * scale, 100 * scale);
    final Gradient gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: const [Color(0xFFE8C84A), Color(0xFFC9970C), Color(0xFF8B6914)],
    );
    
    final crownPaint = Paint()
      ..shader = gradient.createShader(bounds)
      ..style = PaintingStyle.fill;
      
    final crownStroke = Paint()
      ..color = const Color(0xFF8B6914)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * scale
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    path.moveTo(22 * scale, 62 * scale);
    path.lineTo(28 * scale, 38 * scale);
    path.lineTo(40 * scale, 52 * scale);
    path.lineTo(50 * scale, 30 * scale);
    path.lineTo(60 * scale, 52 * scale);
    path.lineTo(72 * scale, 38 * scale);
    path.lineTo(78 * scale, 62 * scale);
    path.close();

    canvas.drawPath(path, crownPaint);
    canvas.drawPath(path, crownStroke);

    // Base
    final basePaint = Paint()
      ..color = const Color(0xFFC9970C)
      ..style = PaintingStyle.fill;
    final basePath = Path();
    basePath.moveTo(22 * scale, 64 * scale);
    basePath.lineTo(78 * scale, 64 * scale);
    basePath.lineTo(78 * scale, 70 * scale);
    basePath.lineTo(22 * scale, 70 * scale);
    basePath.close();
    
    canvas.drawPath(basePath, basePaint);
    canvas.drawPath(basePath, crownStroke);

    // Gems
    final gemPaint = Paint()..color = const Color(0xFFFFF8DC)..style = PaintingStyle.fill;
    final gemStroke = Paint()..color = const Color(0xFF8B6914)..style = PaintingStyle.stroke..strokeWidth = 1 * scale;
    
    _drawGem(canvas, Offset(28 * scale, 38 * scale), 3 * scale, gemPaint, gemStroke);
    _drawGem(canvas, Offset(50 * scale, 30 * scale), 3.5 * scale, gemPaint, gemStroke);
    _drawGem(canvas, Offset(72 * scale, 38 * scale), 3 * scale, gemPaint, gemStroke);
  }

  void _drawGem(Canvas canvas, Offset center, double radius, Paint fill, Paint stroke) {
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
