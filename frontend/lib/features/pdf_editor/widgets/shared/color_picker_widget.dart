import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';

/// Lightweight colour picker backed by a predefined palette.
/// Set [compact] = true for the small inline swatch button.
class ColorPickerWidget extends StatefulWidget {
  final Color initialColor;
  final void Function(Color) onColorChanged;
  final bool compact;

  const ColorPickerWidget({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
    this.compact = false,
  });

  @override
  State<ColorPickerWidget> createState() => _ColorPickerWidgetState();
}

class _ColorPickerWidgetState extends State<ColorPickerWidget> {
  late Color _selected;
  final TextEditingController _hexCtrl = TextEditingController();

  static const _palette = [
    Color(0xFF0F172A), Color(0xFF334155), Color(0xFF94A3B8),
    Color(0xFFFFFFFF), Color(0xFF0284C7), Color(0xFF38BDF8),
    Color(0xFF16A34A), Color(0xFF22C55E), Color(0xFFD97706),
    Color(0xFFEF4444), Color(0xFF8B5CF6), Color(0xFFEC4899),
    Color(0xFF065F46), Color(0xFF92400E), Color(0xFF1E40AF),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.initialColor;
    _hexCtrl.text = _toHex(_selected);
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  String _toHex(Color c) =>
      '#${c.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

  Color? _fromHex(String hex) {
    final cleaned = hex.replaceFirst('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse('FF$cleaned', radix: 16);
    return value != null ? Color(value) : null;
  }

  void _pick(Color c) {
    setState(() {
      _selected = c;
      _hexCtrl.text = _toHex(c);
    });
    widget.onColorChanged(c);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.compact) return _compactSwatch();
    return _fullPicker();
  }

  Widget _compactSwatch() => GestureDetector(
        onTap: () => _showDialog(context),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: _selected,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
        ),
      );

  void _showDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Choose Color'),
        content: SizedBox(
          width: 280,
          child: ColorPickerWidget(
            initialColor: _selected,
            onColorChanged: (c) {
              _pick(c);
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _fullPicker() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Palette swatches
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _palette.map((c) => _Swatch(
              color: c,
              isSelected: _selected == c,
              onTap: () => _pick(c),
            )).toList(),
          ),
          const SizedBox(height: AppSpacing.s4),
          // Hex input
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _selected,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.border),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hex',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                  onSubmitted: (v) {
                    final c = _fromHex(v);
                    if (c != null) _pick(c);
                  },
                ),
              ),
            ],
          ),
        ],
      );
}

class _Swatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _Swatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 2.5 : 1,
            ),
          ),
        ),
      );
}
