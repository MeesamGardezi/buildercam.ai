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
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Consumer<TemplateEditorProvider>(
        builder: (context, provider, _) {
          final el = provider.primarySelected;
          if (el == null) {
            return const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'A4 — 595 × 842 pt',
                  style: TextStyle(fontSize: 12, color: AppColors.bodyMuted),
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

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Element type badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
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
          ),
          const _VDiv(),
          // Position & size
          _TBNumField('X', element.x,
              (v) => provider.updateElement(_set(element, _Field.x, v))),
          const SizedBox(width: 4),
          _TBNumField('Y', element.y,
              (v) => provider.updateElement(_set(element, _Field.y, v))),
          const SizedBox(width: 4),
          _TBNumField('W', element.width,
              (v) => provider.updateElement(_set(element, _Field.w, v))),
          const SizedBox(width: 4),
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
          // Type-specific controls
          ..._typeControls(),
        ],
      ),
    );
  }

  List<Widget> _typeControls() => switch (element) {
        TextElement te => _textControls(te),
        ImageElement ie => _imageControls(ie),
        LogoElement le => _logoControls(le),
        DividerElement de => _dividerControls(de),
        TableElement tbl => _tableControls(tbl),
        _ => const [],
      };

  // ── Text ────────────────────────────────────────────────────────────────

  List<Widget> _textControls(TextElement te) => [
        const _VDiv(),
        SizedBox(
          width: 120,
          child: FontSelectorWidget(
            value: te.fontFamily,
            onChanged: (f) => provider.updateElement(te.copyWith(fontFamily: f)),
          ),
        ),
        const SizedBox(width: 6),
        _TBNumField('Size', te.fontSize,
            (v) => provider.updateElement(te.copyWith(fontSize: v))),
        const SizedBox(width: 6),
        _TBToggle('B', te.fontWeight == FontWeight.bold, () {
          provider.updateElement(te.copyWith(
            fontWeight: te.fontWeight == FontWeight.bold
                ? FontWeight.normal
                : FontWeight.bold,
          ));
        }),
        const SizedBox(width: 3),
        _TBToggle('I', te.fontStyle == FontStyle.italic, () {
          provider.updateElement(te.copyWith(
            fontStyle: te.fontStyle == FontStyle.italic
                ? FontStyle.normal
                : FontStyle.italic,
          ));
        }),
        const SizedBox(width: 6),
        ColorPickerWidget(
          compact: true,
          initialColor: te.color,
          onColorChanged: (c) => provider.updateElement(te.copyWith(color: c)),
        ),
        const SizedBox(width: 6),
        _TBNumField('LH', te.lineHeight,
            (v) => provider.updateElement(te.copyWith(lineHeight: v))),
        const SizedBox(width: 4),
        _TBNumField('LS', te.letterSpacing,
            (v) => provider.updateElement(te.copyWith(letterSpacing: v))),
      ];

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

  const _TBIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(3),
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Icon(
              icon,
              size: 16,
              color: enabled ? AppColors.body : AppColors.bodyMuted,
            ),
          ),
        ),
      );
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
