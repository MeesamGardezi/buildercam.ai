import 'package:flutter/material.dart';

import '../../models/template_element_model.dart';

class ContainerElementWidget extends StatelessWidget {
  final ContainerElement element;

  const ContainerElementWidget({super.key, required this.element});

  @override
  Widget build(BuildContext context) {
    final el = element;
    return Opacity(
      opacity: el.opacity.clamp(0.0, 1.0),
      child: Container(
        decoration: BoxDecoration(
          color: el.fillColor,
          borderRadius: BorderRadius.circular(el.borderRadius),
          border: el.borderWidth > 0
              ? Border.all(color: el.borderColor, width: el.borderWidth)
              : null,
        ),
      ),
    );
  }
}
