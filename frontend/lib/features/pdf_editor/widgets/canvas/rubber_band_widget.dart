import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

/// Renders the rubber-band selection rectangle during drag on empty canvas.
class RubberBandWidget extends StatelessWidget {
  final double x;
  final double y;
  final double width;
  final double height;

  const RubberBandWidget({
    super.key,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    // Normalise negative width/height so rect always draws correctly.
    final left = width < 0 ? x + width : x;
    final top = height < 0 ? y + height : y;
    final w = width.abs();
    final h = height.abs();

    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary, width: 1),
            color: AppColors.primary.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }
}
