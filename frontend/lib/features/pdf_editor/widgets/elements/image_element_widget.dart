import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/template_element_model.dart';

class ImageElementWidget extends StatelessWidget {
  final ImageElement element;

  const ImageElementWidget({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final el = element;

    Widget image;
    if (el.src.isEmpty) {
      image = _placeholder();
    } else {
      image = Image.network(
        el.src,
        fit: el.objectFit,
        width: el.width,
        height: el.height,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return _shimmer();
        },
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }

    Widget result = ClipRRect(
      borderRadius: BorderRadius.circular(el.borderRadius),
      child: image,
    );

    if (el.hasShadow) {
      result = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(el.borderRadius),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: result,
      );
    }

    return Opacity(
      opacity: el.opacity,
      child: SizedBox(
        width: el.width,
        height: el.height,
        child: result,
      ),
    );
  }

  Widget _placeholder() => Container(
        color: AppColors.charcoal100,
        child: const Center(
          child: Icon(Icons.image_outlined,
              color: AppColors.charcoal300, size: 32),
        ),
      );

  Widget _shimmer() => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.charcoal100,
              AppColors.charcoal50,
              AppColors.charcoal100,
            ],
            stops: const [0, 0.5, 1],
          ),
        ),
      );
}
