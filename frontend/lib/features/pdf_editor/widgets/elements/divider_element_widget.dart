import 'package:flutter/material.dart';

import '../../models/template_element_model.dart';

class DividerElementWidget extends StatelessWidget {
  final DividerElement element;

  const DividerElementWidget({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final el = element;
    final isH = el.orientation == DividerOrientation.horizontal;

    return SizedBox(
      width: el.width,
      height: el.height,
      child: CustomPaint(
        painter: _DividerPainter(
          color: el.color,
          thickness: el.thickness,
          dashStyle: el.dashStyle,
          isHorizontal: isH,
        ),
      ),
    );
  }
}

class _DividerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final DividerDashStyle dashStyle;
  final bool isHorizontal;

  const _DividerPainter({
    required this.color,
    required this.thickness,
    required this.dashStyle,
    required this.isHorizontal,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    if (dashStyle == DividerDashStyle.solid) {
      _drawSolid(canvas, size, paint);
    } else {
      _drawDashed(canvas, size, paint);
    }
  }

  void _drawSolid(Canvas canvas, Size size, Paint paint) {
    if (isHorizontal) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    } else {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
    }
  }

  void _drawDashed(Canvas canvas, Size size, Paint paint) {
    final dashLength = dashStyle == DividerDashStyle.dashed ? 8.0 : 2.0;
    final gapLength = dashStyle == DividerDashStyle.dashed ? 4.0 : 4.0;
    final total = isHorizontal ? size.width : size.height;

    double pos = 0;
    while (pos < total) {
      final end = (pos + dashLength).clamp(0.0, total);
      if (isHorizontal) {
        canvas.drawLine(
          Offset(pos, size.height / 2),
          Offset(end, size.height / 2),
          paint,
        );
      } else {
        canvas.drawLine(
          Offset(size.width / 2, pos),
          Offset(size.width / 2, end),
          paint,
        );
      }
      pos += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(_DividerPainter old) =>
      old.color != color ||
      old.thickness != thickness ||
      old.dashStyle != dashStyle ||
      old.isHorizontal != isHorizontal;
}
