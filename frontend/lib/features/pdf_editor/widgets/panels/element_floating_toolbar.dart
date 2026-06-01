import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../core/app_spacing.dart';
import '../../models/template_element_model.dart';
import '../../providers/template_editor_provider.dart';
import '../shared/color_picker_widget.dart';

/// Floating action toolbar shown above (or below) the selected element.
/// Rendered via Overlay so it appears above the InteractiveViewer chrome.
class ElementFloatingToolbar extends StatefulWidget {
  final TemplateElement element;

  const ElementFloatingToolbar({super.key, required this.element});

  @override
  State<ElementFloatingToolbar> createState() => _ElementFloatingToolbarState();
}

class _ElementFloatingToolbarState extends State<ElementFloatingToolbar> {
  static const double _tableRowHeight = 27.0;

  OverlayEntry? _entry;

  @override
  void didUpdateWidget(ElementFloatingToolbar old) {
    super.didUpdateWidget(old);
    _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _entry?.remove();
      _entry = OverlayEntry(builder: _buildToolbar);
      Overlay.of(context).insert(_entry!);
    });
    return const SizedBox.shrink();
  }

  Widget _buildToolbar(BuildContext context) {
    final el = widget.element;
    final provider = context.read<TemplateEditorProvider>();

    return Positioned(
      // Position at top-center of screen; a real impl would position
      // relative to element via RenderBox lookup.
      top: 60,
      left: 0,
      right: 0,
      child: Center(
        child: Material(
          color: AppColors.charcoal800,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Universal actions
                _iconBtn(Icons.delete_outline, 'Delete', Colors.redAccent,
                    () => provider.deleteSelected()),
                _iconBtn(Icons.control_point_duplicate_outlined, 'Duplicate',
                    Colors.white, () => provider.duplicateSelected()),
                _iconBtn(Icons.flip_to_front_outlined, 'Forward', Colors.white,
                    () => provider.bringForward(el.id)),
                _iconBtn(Icons.flip_to_back_outlined, 'Back', Colors.white,
                    () => provider.sendBackward(el.id)),

                // Type-specific actions
                if (el is TextElement) ..._textActions(el, provider),
                if (el is ImageElement) ..._imageActions(el, provider, context),
                if (el is TableElement) ..._tableActions(el, provider),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _textActions(TextElement el, TemplateEditorProvider provider) => [
        const _Divider(),
        _iconBtn(
          Icons.format_bold,
          'Bold',
          el.fontWeight == FontWeight.bold
              ? AppColors.primary
              : Colors.white,
          () => provider.updateElement(el.copyWith(
            fontWeight: el.fontWeight == FontWeight.bold
                ? FontWeight.normal
                : FontWeight.bold,
          )),
        ),
        _iconBtn(
          Icons.format_italic,
          'Italic',
          el.fontStyle == FontStyle.italic
              ? AppColors.primary
              : Colors.white,
          () => provider.updateElement(el.copyWith(
            fontStyle: el.fontStyle == FontStyle.italic
                ? FontStyle.normal
                : FontStyle.italic,
          )),
        ),
        _iconBtn(Icons.text_decrease, 'Smaller', Colors.white,
            () => provider.updateElement(el.copyWith(fontSize: el.fontSize - 1))),
        _iconBtn(Icons.text_increase, 'Larger', Colors.white,
            () => provider.updateElement(el.copyWith(fontSize: el.fontSize + 1))),
        _ColorButton(
          color: el.color,
          onChanged: (c) => provider.updateElement(el.copyWith(color: c)),
        ),
      ];

  List<Widget> _imageActions(
          ImageElement el, TemplateEditorProvider provider, BuildContext ctx) =>
      [];

  List<Widget> _tableActions(
          TableElement el, TemplateEditorProvider provider) =>
      [
        const _Divider(),
        _iconBtn(Icons.add, 'Add Row', Colors.white, () {
          final td = el.tableData;
          final newRow = List.filled(td.headers.length, '');
          provider.updateElement(el.copyWith(
            height: el.height + _tableRowHeight,
            tableData: td.copyWith(rows: [...td.rows, newRow]),
          ));
        }),
        _iconBtn(Icons.remove, 'Remove Row', Colors.white, () {
          final td = el.tableData;
          if (td.rows.isEmpty) return;
          final rows = [...td.rows]..removeLast();
          provider.updateElement(el.copyWith(
            height: (el.height - _tableRowHeight).clamp(54.0, double.infinity),
            tableData: td.copyWith(rows: rows),
          ));
        }),
      ];

  Widget _iconBtn(
    IconData icon,
    String tooltip,
    Color color,
    VoidCallback onTap,
  ) =>
      Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, color: color, size: 18),
          ),
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        color: Colors.white24,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _ColorButton extends StatelessWidget {
  final Color color;
  final void Function(Color) onChanged;

  const _ColorButton({required this.color, required this.onChanged});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Text Color',
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => _showPicker(context),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white30, width: 1),
              ),
            ),
          ),
        ),
      );

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Text Color'),
        content: ColorPickerWidget(
          initialColor: color,
          onColorChanged: onChanged,
        ),
      ),
    );
  }
}
