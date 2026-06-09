import 'package:flutter/material.dart';

import '../../core/app_colors.dart';

class FontSelectorWidget extends StatelessWidget {
  final String value;
  final void Function(String) onChanged;

  const FontSelectorWidget({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const _fonts = [
    'Roboto',
    'Roboto Mono',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Oswald',
    'Raleway',
    'PT Sans',
    'Noto Sans',
    'Source Sans Pro',
  ];

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: _fonts.contains(value) ? value : _fonts.first,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Font',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(4)),
          ),
        ),
        style: const TextStyle(fontSize: 12, color: AppColors.body),
        items: _fonts
            .map((f) => DropdownMenuItem(
                  value: f,
                  child: Text(f,
                      style: TextStyle(fontFamily: f, fontSize: 12)),
                ))
            .toList(),
        onChanged: (f) {
          if (f != null) onChanged(f);
        },
      );
}
