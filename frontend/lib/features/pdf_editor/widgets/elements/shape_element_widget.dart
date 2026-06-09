import 'package:flutter/material.dart';

import '../../models/template_element_model.dart';

class ShapeElementWidget extends StatelessWidget {
  final ShapeElement element;

  const ShapeElementWidget({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final el = element;
    return Opacity(
      opacity: el.opacity.clamp(0.0, 1.0),
      child: CustomPaint(
        size: Size(el.width, el.height),
        painter: _ShapePainter(
          kind: el.shapeKind,
          fillColor: el.fillColor,
          borderColor: el.borderColor,
          borderWidth: el.borderWidth,
          borderRadius: el.borderRadius,
        ),
      ),
    );
  }
}

class _ShapePainter extends CustomPainter {
  final ShapeKind kind;
  final Color fillColor;
  final Color borderColor;
  final double borderWidth;
  final double borderRadius;

  const _ShapePainter({
    required this.kind,
    required this.fillColor,
    required this.borderColor,
    required this.borderWidth,
    required this.borderRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = borderColor
      ..strokeWidth = borderWidth;

    switch (kind) {
      case ShapeKind.rectangle:
        final rrect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            borderWidth / 2,
            borderWidth / 2,
            size.width - borderWidth,
            size.height - borderWidth,
          ),
          Radius.circular(borderRadius),
        );
        canvas.drawRRect(rrect, fillPaint);
        if (borderWidth > 0) canvas.drawRRect(rrect, borderPaint);

      case ShapeKind.ellipse:
        final rect = Rect.fromLTWH(
          borderWidth / 2,
          borderWidth / 2,
          size.width - borderWidth,
          size.height - borderWidth,
        );
        canvas.drawOval(rect, fillPaint);
        if (borderWidth > 0) canvas.drawOval(rect, borderPaint);

      case ShapeKind.triangle:
        final path = Path()
          ..moveTo(size.width / 2, borderWidth / 2)
          ..lineTo(size.width - borderWidth / 2, size.height - borderWidth / 2)
          ..lineTo(borderWidth / 2, size.height - borderWidth / 2)
          ..close();
        canvas.drawPath(path, fillPaint);
        if (borderWidth > 0) canvas.drawPath(path, borderPaint);
    }
  }

  @override
  bool shouldRepaint(_ShapePainter old) =>
      old.kind != kind ||
      old.fillColor != fillColor ||
      old.borderColor != borderColor ||
      old.borderWidth != borderWidth ||
      old.borderRadius != borderRadius;
}
