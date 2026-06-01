import 'package:flutter/material.dart';

import '../../utils/canvas_math.dart';

/// Renders active snap guides as thin colored lines over the canvas.
/// Listens to a ValueNotifier so it rebuilds independently from the
/// main element tree during drag.
class SnapGuideWidget extends StatelessWidget {
  final ValueNotifier<List<SnapGuide>> guidesNotifier;
  final double pageWidth;
  final double pageHeight;

  const SnapGuideWidget({
    super.key,
    required this.guidesNotifier,
    required this.pageWidth,
    required this.pageHeight,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<SnapGuide>>(
      valueListenable: guidesNotifier,
      builder: (context, guides, _) {
        if (guides.isEmpty) return const SizedBox.shrink();
        return IgnorePointer(
          child: CustomPaint(
            size: Size(pageWidth, pageHeight),
            painter: _SnapGuidePainter(guides, pageWidth, pageHeight),
          ),
        );
      },
    );
  }
}

class _SnapGuidePainter extends CustomPainter {
  final List<SnapGuide> guides;
  final double pageWidth;
  final double pageHeight;

  _SnapGuidePainter(this.guides, this.pageWidth, this.pageHeight);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFEC4899) // magenta — Figma-style snap accent
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = const Color(0xFFEC4899)
      ..style = PaintingStyle.fill;

    for (final g in guides) {
      if (g.isVertical) {
        canvas.drawLine(
          Offset(g.position, 0),
          Offset(g.position, pageHeight),
          paint,
        );
        // tiny end-cap dots so the line reads as intentional
        canvas.drawCircle(Offset(g.position, 0), 1.4, dotPaint);
        canvas.drawCircle(Offset(g.position, pageHeight), 1.4, dotPaint);
      } else {
        canvas.drawLine(
          Offset(0, g.position),
          Offset(pageWidth, g.position),
          paint,
        );
        canvas.drawCircle(Offset(0, g.position), 1.4, dotPaint);
        canvas.drawCircle(Offset(pageWidth, g.position), 1.4, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(_SnapGuidePainter old) => old.guides != guides;
}
