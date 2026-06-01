import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/template_element_model.dart';

class LogoElementWidget extends StatelessWidget {
  final LogoElement element;

  const LogoElementWidget({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final el = element;

    Widget content;
    if (el.src.isEmpty) {
      content = Container(
        decoration: BoxDecoration(
          color: AppColors.charcoal100,
          border: Border.all(
            color: AppColors.charcoal200,
            style: BorderStyle.solid,
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.business_outlined,
                  color: AppColors.charcoal300, size: 24),
              SizedBox(height: 4),
              Text('Company Logo',
                  style: TextStyle(
                      color: AppColors.charcoal400, fontSize: 10)),
            ],
          ),
        ),
      );
    } else {
      content = Image.network(
        el.src,
        fit: BoxFit.contain,
        width: el.width,
        height: el.height,
        errorBuilder: (_, __, ___) => const SizedBox.expand(
          child: Center(
            child: Icon(
              Icons.business_outlined,
              color: AppColors.charcoal300,
              size: 24,
            ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: el.opacity,
      child: SizedBox(
        width: el.width,
        height: el.height,
        child: content,
      ),
    );
  }
}
