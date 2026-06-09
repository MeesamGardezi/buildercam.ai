// Purpose: Horizontal properties top bar for the selected element.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../models/template_element_model.dart';
import '../../providers/template_editor_provider.dart';
import '../shared/color_picker_widget.dart';
import '../shared/font_selector_widget.dart';

// ── Geometry field enum (top-level; Dart doesn't allow enums inside classes) ─
enum _Field { x, y, w, h }

/// Horizontal properties bar rendered between the toolbar and the canvas.
/// Shows position/size + type-specific controls for the selected element.
class PropertiesTopBar extends StatelessWidget {
  const PropertiesTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Consumer<TemplateEditorProvider>(
        builder: (context, provider, _) {
          final el = provider.primarySelected;
          if (el == null) {
            return const SizedBox(
              height: 48,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'A4 — 595 × 842 pt',
                    style: TextStyle(fontSize: 12, color: AppColors.bodyMuted),
                  ),
                ),
              ),
            );
          }
          return ElementTopBar(element: el, provider: provider);
        },
      ),
    );
  }
}

// ── Per-element bar ───────────────────────────────────────────────────────────

class ElementTopBar extends StatelessWidget {
  final TemplateElement element;
  final TemplateEditorProvider provider;

  const ElementTopBar({super.key, required this.element, required this.provider});

  // ── Shared: geometry row prefix ──────────────────────────────────────────

  Widget _typeBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.blue100,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          element.type.label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      );

  List<Widget> _geomAndRotate() => [
        _TBNumField('X', element.x,
            (v) => provider.updateElement(_set(element, _Field.x, v))),
        const SizedBox(width: 3),
        _TBNumField('Y', element.y,
            (v) => provider.updateElement(_set(element, _Field.y, v))),
        const SizedBox(width: 3),
        _TBNumField('W', element.width,
            (v) => provider.updateElement(_set(element, _Field.w, v))),
        const SizedBox(width: 3),
        _TBNumField('H', element.height,
            (v) => provider.updateElement(_set(element, _Field.h, v))),
        const _VDiv(),
        _TBIconBtn(
          icon: Icons.rotate_90_degrees_cw_rounded,
          tooltip: 'Rotate 90° (${element.rotation}°)',
          onTap: () {
            if (!provider.isSelected(element.id)) {
              provider.selectElement(element.id);
            }
            provider.rotateSelectedBy(90);
          },
        ),
      ];

  @override
  Widget build(BuildContext context) {
    if (element is TextElement) {
      return _buildTextBar(element as TextElement);
    }
    // Non-text: scrollable row + pinned action strip
    return _wrapBar([
      _typeBadge(),
      const _VDiv(),
      ..._geomAndRotate(),
      ..._nonTextTypeControls(),
    ]);
  }

  /// Scrollable content area with pinned action buttons on the right.
  Widget _wrapBar(List<Widget> scrollItems) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: scrollItems,
                ),
              ),
            ),
          ),
          _actionSuffix(),
        ],
      ),
    );
  }

  /// Z-order, lock, duplicate, delete — pinned to the right of every bar.
  Widget _actionSuffix() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TBIconBtn(
              icon: Icons.flip_to_front_rounded,
              tooltip: 'Bring Forward',
              onTap: () => provider.bringForward(element.id),
            ),
            const SizedBox(width: 2),
            _TBIconBtn(
              icon: Icons.flip_to_back_rounded,
              tooltip: 'Send Backward',
              onTap: () => provider.sendBackward(element.id),
            ),
            const _VDiv(),
            _TBIconBtn(
              icon: element.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              tooltip: element.locked ? 'Unlock' : 'Lock',
              active: element.locked,
              onTap: () => provider.toggleLock(element.id),
            ),
            const SizedBox(width: 2),
            _TBIconBtn(
              icon: element.visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              tooltip: element.visible ? 'Hide' : 'Show',
              active: !element.visible,
              onTap: () => provider.toggleVisibility(element.id),
            ),
            const _VDiv(),
            _TBIconBtn(
              icon: Icons.control_point_duplicate_rounded,
              tooltip: 'Duplicate',
              onTap: () => provider.duplicateSelected(),
            ),
            const SizedBox(width: 2),
            _TBIconBtn(
              icon: Icons.delete_outline_rounded,
              tooltip: 'Delete',
              onTap: () => provider.deleteSelected(),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _nonTextTypeControls() => switch (element) {
        ImageElement ie => _imageControls(ie),
        LogoElement le => _logoControls(le),
        DividerElement de => _dividerControls(de),
        TableElement tbl => _tableControls(tbl),
        ShapeElement se => _shapeControls(se),
        ContainerElement ce => _containerControls(ce),
        _ => const [],
      };

  // ── Text ────────────────────────────────────────────────────────────────

  Widget _buildTextBar(TextElement te) {
    return _wrapBar([
      _typeBadge(),
      const _VDiv(),
      ..._geomAndRotate(),
      const _VDiv(),
      SizedBox(
        width: 110,
        child: FontSelectorWidget(
          value: te.fontFamily,
          onChanged: (f) => provider.updateElement(te.copyWith(fontFamily: f)),
        ),
      ),
      const SizedBox(width: 4),
      _TBNumField('Size', te.fontSize,
          (v) => provider.updateElement(te.copyWith(fontSize: v.clamp(1, 300)))),
      const SizedBox(width: 4),
      _TBNumField('Line H', te.lineHeight,
          (v) => provider.updateElement(te.copyWith(lineHeight: v.clamp(0.5, 5)))),
      const SizedBox(width: 4),
      _TBNumField('Spacing', te.letterSpacing,
          (v) => provider.updateElement(te.copyWith(letterSpacing: v.clamp(-10, 50)))),
      const _VDiv(),
      _TBToggle('B', te.fontWeight == FontWeight.bold, () {
        provider.updateElement(te.copyWith(
          fontWeight: te.fontWeight == FontWeight.bold
              ? FontWeight.normal
              : FontWeight.bold,
        ));
      }),
      const SizedBox(width: 2),
      _TBToggle('I', te.fontStyle == FontStyle.italic, () {
        provider.updateElement(te.copyWith(
          fontStyle: te.fontStyle == FontStyle.italic
              ? FontStyle.normal
              : FontStyle.italic,
        ));
      }),
      const SizedBox(width: 2),
      _TBToggle('U', te.underline, () {
        provider.updateElement(te.copyWith(underline: !te.underline));
      }),
      const SizedBox(width: 2),
      _TBToggle('S', te.strikethrough, () {
        provider.updateElement(te.copyWith(strikethrough: !te.strikethrough));
      }),
      const _VDiv(),
      _TBIconBtn(
        icon: Icons.format_align_left,
        tooltip: 'Align Left',
        active: te.textAlign == TextAlign.left || te.textAlign == TextAlign.start,
        onTap: () => provider.updateElement(te.copyWith(textAlign: TextAlign.left)),
      ),
      const SizedBox(width: 1),
      _TBIconBtn(
        icon: Icons.format_align_center,
        tooltip: 'Align Center',
        active: te.textAlign == TextAlign.center,
        onTap: () => provider.updateElement(te.copyWith(textAlign: TextAlign.center)),
      ),
      const SizedBox(width: 1),
      _TBIconBtn(
        icon: Icons.format_align_right,
        tooltip: 'Align Right',
        active: te.textAlign == TextAlign.right || te.textAlign == TextAlign.end,
        onTap: () => provider.updateElement(te.copyWith(textAlign: TextAlign.right)),
      ),
      const SizedBox(width: 1),
      _TBIconBtn(
        icon: Icons.format_align_justify,
        tooltip: 'Justify',
        active: te.textAlign == TextAlign.justify,
        onTap: () => provider.updateElement(te.copyWith(textAlign: TextAlign.justify)),
      ),
      const _VDiv(),
      ColorPickerWidget(
        compact: true,
        initialColor: te.color,
        onColorChanged: (c) => provider.updateElement(te.copyWith(color: c)),
      ),
      const SizedBox(width: 4),
      _BgColorButton(
        color: te.backgroundColor,
        onChanged: (c) => provider.updateElement(te.copyWith(backgroundColor: c)),
        onClear: () => provider.updateElement(
            te.copyWith(backgroundColor: const Color(0x00000000))),
      ),
    ]);
  }

  // ── Image ───────────────────────────────────────────────────────────────

  List<Widget> _imageControls(ImageElement ie) => [
        const _VDiv(),
        _TBIconBtn(
          icon: Icons.upload_outlined,
          tooltip: ie.src.isEmpty ? 'Upload Image' : 'Replace Image',
          onTap: () => _pickImage(ie),
        ),
        const SizedBox(width: 6),
        _TBNumField('Opacity', ie.opacity,
            (v) => provider.updateElement(ie.copyWith(opacity: v.clamp(0, 1)))),
        const SizedBox(width: 4),
        _TBNumField('Radius', ie.borderRadius,
            (v) => provider.updateElement(ie.copyWith(borderRadius: v))),
      ];

  // ── Logo ────────────────────────────────────────────────────────────────

  List<Widget> _logoControls(LogoElement le) => [
        const _VDiv(),
        _TBNumField('Opacity', le.opacity,
            (v) => provider.updateElement(le.copyWith(opacity: v.clamp(0, 1)))),
        const SizedBox(width: 6),
        _TBIconBtn(
          icon: Icons.upload_outlined,
          tooltip: 'Replace Logo',
          onTap: () => _pickLogo(le),
        ),
      ];

  // ── Divider ─────────────────────────────────────────────────────────────

  List<Widget> _dividerControls(DividerElement de) => [
        const _VDiv(),
        _TBNumField('Thickness', de.thickness,
            (v) => provider.updateElement(de.copyWith(thickness: v))),
        const SizedBox(width: 6),
        ColorPickerWidget(
          compact: true,
          initialColor: de.color,
          onColorChanged: (c) => provider.updateElement(de.copyWith(color: c)),
        ),
      ];

  // ── Shape ────────────────────────────────────────────────────────────────

  List<Widget> _shapeControls(ShapeElement se) => [
        const _VDiv(),
        // Shape kind cycle button
        _TBIconBtn(
          icon: switch (se.shapeKind) {
            ShapeKind.rectangle => Icons.crop_square_outlined,
            ShapeKind.ellipse => Icons.circle_outlined,
            ShapeKind.triangle => Icons.change_history_outlined,
          },
          tooltip: 'Shape: ${se.shapeKind.name}  (click to cycle)',
          onTap: () {
            final next = ShapeKind.values[
                (se.shapeKind.index + 1) % ShapeKind.values.length];
            provider.updateElement(se.copyWith(shapeKind: next));
          },
        ),
        const SizedBox(width: 4),
        ColorPickerWidget(
          compact: true,
          initialColor: se.fillColor,
          onColorChanged: (c) => provider.updateElement(se.copyWith(fillColor: c)),
        ),
        const SizedBox(width: 4),
        ColorPickerWidget(
          compact: true,
          initialColor: se.borderColor,
          onColorChanged: (c) =>
              provider.updateElement(se.copyWith(borderColor: c)),
        ),
        const SizedBox(width: 4),
        _TBNumField('Border', se.borderWidth,
            (v) => provider.updateElement(se.copyWith(borderWidth: v.clamp(0, 20)))),
        const SizedBox(width: 4),
        _TBNumField('Radius', se.borderRadius,
            (v) => provider.updateElement(se.copyWith(borderRadius: v.clamp(0, 200)))),
        const SizedBox(width: 4),
        _TBNumField('Opacity', se.opacity,
            (v) => provider.updateElement(se.copyWith(opacity: v.clamp(0, 1)))),
      ];

  // ── Container ────────────────────────────────────────────────────────────

  List<Widget> _containerControls(ContainerElement ce) => [
        const _VDiv(),
        ColorPickerWidget(
          compact: true,
          initialColor: ce.fillColor,
          onColorChanged: (c) => provider.updateElement(ce.copyWith(fillColor: c)),
        ),
        const SizedBox(width: 4),
        ColorPickerWidget(
          compact: true,
          initialColor: ce.borderColor,
          onColorChanged: (c) =>
              provider.updateElement(ce.copyWith(borderColor: c)),
        ),
        const SizedBox(width: 4),
        _TBNumField('Border', ce.borderWidth,
            (v) => provider.updateElement(ce.copyWith(borderWidth: v.clamp(0, 20)))),
        const SizedBox(width: 4),
        _TBNumField('Radius', ce.borderRadius,
            (v) => provider.updateElement(ce.copyWith(borderRadius: v.clamp(0, 200)))),
        const SizedBox(width: 4),
        _TBNumField('Opacity', ce.opacity,
            (v) => provider.updateElement(ce.copyWith(opacity: v.clamp(0, 1)))),
      ];

  // ── Table ───────────────────────────────────────────────────────────────

  List<Widget> _tableControls(TableElement tbl) => [
        const _VDiv(),
        ColorPickerWidget(
          compact: true,
          initialColor: tbl.tableStyle.headerBg,
          onColorChanged: (c) => provider.updateElement(
              tbl.copyWith(tableStyle: tbl.tableStyle.copyWith(headerBg: c))),
        ),
        const SizedBox(width: 8),
        _TBIconBtn(
          icon: Icons.add,
          tooltip: 'Add Row',
          onTap: () {
            final td = tbl.tableData;
            provider.updateElement(tbl.copyWith(
              height: tbl.height + 27,
              tableData: td.copyWith(
                  rows: [...td.rows, List.filled(td.headers.length, '')]),
            ));
          },
        ),
        const SizedBox(width: 3),
        _TBIconBtn(
          icon: Icons.remove,
          tooltip: 'Remove Row',
          enabled: tbl.tableData.rows.isNotEmpty,
          onTap: () {
            final td = tbl.tableData;
            if (td.rows.isEmpty) return;
            provider.updateElement(tbl.copyWith(
              height: (tbl.height - 27).clamp(54.0, double.infinity),
              tableData:
                  td.copyWith(rows: td.rows.sublist(0, td.rows.length - 1)),
            ));
          },
        ),
        const SizedBox(width: 8),
        _TBIconBtn(
          icon: Icons.view_column_outlined,
          tooltip: 'Add Column',
          onTap: () {
            final td = tbl.tableData;
            final avgW =
                td.headers.isEmpty ? 80.0 : tbl.width / td.headers.length;
            provider.updateElement(tbl.copyWith(
              width: tbl.width + avgW,
              tableData: td.copyWith(
                headers: [...td.headers, 'Col ${td.headers.length + 1}'],
                rows: td.rows.map((r) => [...r, '']).toList(),
              ),
            ));
          },
        ),
        const SizedBox(width: 3),
        _TBIconBtn(
          icon: Icons.view_column,
          tooltip: 'Remove Column',
          enabled: tbl.tableData.headers.isNotEmpty,
          onTap: () {
            final td = tbl.tableData;
            if (td.headers.isEmpty) return;
            final colW = tbl.width / td.headers.length;
            provider.updateElement(tbl.copyWith(
              width: (tbl.width - colW).clamp(60.0, double.infinity),
              tableData: td.copyWith(
                headers: td.headers.sublist(0, td.headers.length - 1),
                rows: td.rows
                    .map((r) => r.isEmpty ? r : r.sublist(0, r.length - 1))
                    .toList(),
              ),
            ));
          },
        ),
      ];

  // ── Logo upload ──────────────────────────────────────────────────────────

  Future<void> _pickLogo(LogoElement le) async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime =
        (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';
    provider
        .updateElement(le.copyWith(src: 'data:$mime;base64,${base64Encode(bytes)}'));
  }

  // ── Image upload (Firebase Storage) ──────────────────────────────────────

  Future<void> _pickImage(ImageElement ie) async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    final ext = (file.extension ?? 'png').toLowerCase();
    final mime =
        (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';
    final company = provider.companyId.isEmpty ? 'guest' : provider.companyId;
    final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'pdf-editor-images/$company/${DateTime.now().millisecondsSinceEpoch}-$safeName';
    try {
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putData(bytes, SettableMetadata(contentType: mime));
      final url = await ref.getDownloadURL();
      provider.updateElement(ie.copyWith(src: url));
    } catch (_) {
      // Fallback: embed as base64 so the user isn't blocked when Storage fails.
      provider.updateElement(
          ie.copyWith(src: 'data:$mime;base64,${base64Encode(bytes)}'));
    }
  }

  // ── Geometry helpers ─────────────────────────────────────────────────────

  static TemplateElement _set(TemplateElement el, _Field f, double v) =>
      switch (el) {
        TextElement te => switch (f) {
            _Field.x => te.copyWith(x: v),
            _Field.y => te.copyWith(y: v),
            _Field.w => te.copyWith(width: v),
            _Field.h => te.copyWith(height: v),
          },
        ImageElement ie => switch (f) {
            _Field.x => ie.copyWith(x: v),
            _Field.y => ie.copyWith(y: v),
            _Field.w => ie.copyWith(width: v),
            _Field.h => ie.copyWith(height: v),
          },
        TableElement tbl => switch (f) {
            _Field.x => tbl.copyWith(x: v),
            _Field.y => tbl.copyWith(y: v),
            _Field.w => tbl.copyWith(width: v),
            _Field.h => tbl.copyWith(height: v),
          },
        LogoElement le => switch (f) {
            _Field.x => le.copyWith(x: v),
            _Field.y => le.copyWith(y: v),
            _Field.w => le.copyWith(width: v),
            _Field.h => le.copyWith(height: v),
          },
        SignatureBlockElement sb => switch (f) {
            _Field.x => sb.copyWith(x: v),
            _Field.y => sb.copyWith(y: v),
            _Field.w => sb.copyWith(width: v),
            _Field.h => sb.copyWith(height: v),
          },
        DividerElement de => switch (f) {
            _Field.x => de.copyWith(x: v),
            _Field.y => de.copyWith(y: v),
            _Field.w => de.copyWith(width: v),
            _Field.h => de.copyWith(height: v),
          },
        ShapeElement se => switch (f) {
            _Field.x => se.copyWith(x: v),
            _Field.y => se.copyWith(y: v),
            _Field.w => se.copyWith(width: v),
            _Field.h => se.copyWith(height: v),
          },
        ContainerElement ce => switch (f) {
            _Field.x => ce.copyWith(x: v),
            _Field.y => ce.copyWith(y: v),
            _Field.w => ce.copyWith(width: v),
            _Field.h => ce.copyWith(height: v),
          },
      };
}

// ── Compact UI primitives ─────────────────────────────────────────────────────

/// Compact numeric field: tiny label stacked above a narrow 26 px text input.
class _TBNumField extends StatefulWidget {
  final String label;
  final double value;
  final void Function(double) onChanged;

  const _TBNumField(this.label, this.value, this.onChanged);

  @override
  State<_TBNumField> createState() => _TBNumFieldState();
}

class _TBNumFieldState extends State<_TBNumField> {
  late TextEditingController _ctrl;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(_TBNumField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && !_focused &&
        !_ctrl.text.endsWith('.')) {
      _ctrl.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.label,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.bodyMuted,
              fontWeight: FontWeight.w600,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 26,
            child: Focus(
              onFocusChange: (f) => setState(() => _focused = f),
              child: TextField(
                controller: _ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.body),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(3)),
                    borderSide: BorderSide(color: AppColors.border),
                  ),
                ),
                onSubmitted: (v) {
                  final p = double.tryParse(v);
                  if (p != null) widget.onChanged(p);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact bold / italic toggle.
class _TBToggle extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TBToggle(this.label, this.active, this.onTap);

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.primaryLight : AppColors.charcoal50,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: active ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: active ? AppColors.primary : AppColors.body,
              fontSize: 12,
            ),
          ),
        ),
      );
}

/// Compact icon button with tooltip.
class _TBIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;
  final bool active;

  const _TBIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(3),
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: active
                ? BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4)),
                  )
                : null,
            child: Icon(
              icon,
              size: 16,
              color: active
                  ? AppColors.primary
                  : (enabled ? AppColors.body : AppColors.bodyMuted),
            ),
          ),
        ),
      );
}

/// Background-color button: shows a checkerboard when null, color swatch when set.
class _BgColorButton extends StatelessWidget {
  final Color? color;
  final void Function(Color) onChanged;
  final VoidCallback onClear;

  const _BgColorButton({
    required this.color,
    required this.onChanged,
    required this.onClear,
  });

  bool get _hasColor =>
      color != null && color!.a > 0;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Background Color',
        child: InkWell(
          borderRadius: BorderRadius.circular(3),
          onTap: () => _showPicker(context),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _hasColor ? color : null,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(2),
                    // checkerboard via gradient when transparent
                    gradient: _hasColor
                        ? null
                        : const LinearGradient(
                            colors: [Colors.white, Colors.white],
                          ),
                  ),
                  child: _hasColor
                      ? null
                      : CustomPaint(painter: _CheckerPainter()),
                ),
                // "A" underline indicator
                Positioned(
                  bottom: 0,
                  child: Container(
                    width: 16,
                    height: 3,
                    decoration: BoxDecoration(
                      color: _hasColor ? color : AppColors.bodyMuted,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Background Color'),
        content: ColorPickerWidget(
          initialColor: _hasColor ? color! : Colors.white,
          onColorChanged: onChanged,
        ),
        actions: [
          TextButton(
            onPressed: () {
              onClear();
              Navigator.of(context).pop();
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const sq = 4.0;
    final p1 = Paint()..color = Colors.white;
    final p2 = Paint()..color = const Color(0xFFCBD5E1);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), p1);
    for (double y = 0; y < size.height; y += sq) {
      for (double x = 0; x < size.width; x += sq) {
        if (((x ~/ sq) + (y ~/ sq)).isOdd) {
          canvas.drawRect(
              Rect.fromLTWH(x, y, sq, sq), p2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}

/// Thin vertical separator between control groups.
class _VDiv extends StatelessWidget {
  const _VDiv();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 24,
          child: VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppColors.border,
          ),
        ),
      );
}
