import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/template_element_model.dart';
import '../../providers/template_editor_provider.dart';
import '../elements/divider_element_widget.dart';
import '../elements/image_element_widget.dart';
import '../elements/logo_element_widget.dart';
import '../elements/shape_element_widget.dart';
import '../elements/container_element_widget.dart';
import '../elements/signature_block_widget.dart';
import '../elements/table_element_widget.dart';
import '../elements/text_element_widget.dart';

/// Wraps a single template element with drag, tap, double-tap, and
/// context-menu interactions. During drag it reads a per-element
/// ValueNotifier<Offset> instead of rebuilding the full provider tree.
class CanvasElementWidget extends StatefulWidget {
  final TemplateElement element;
  final TransformationController transformController;

  const CanvasElementWidget({
    super.key,
    required this.element,
    required this.transformController,
  });

  @override
  State<CanvasElementWidget> createState() => _CanvasElementWidgetState();
}

enum _ContextAction { copy, cut, paste, duplicate, bringForward, sendBack, rotate, delete }

class _CanvasElementWidgetState extends State<CanvasElementWidget> {
  double _startX = 0, _startY = 0;
  bool _isDragging = false;
  // ID of the element actually being dragged — may differ from widget.element.id
  // when the user starts a drag on this element but another element is selected.
  String? _dragTargetId;
  Offset? _pointerDown;
  int? _activePointer;
  Offset _secondaryTapPosition = Offset.zero;

  TemplateEditorProvider get _provider =>
      context.read<TemplateEditorProvider>();

  @override
  Widget build(BuildContext context) {
    final el = widget.element;
    if (!el.visible) return const SizedBox.shrink();

    // Use ValueListenableBuilder for the drag position so only this widget
    // rebuilds during drag, not the entire canvas consumer.
    final dragNotifier = _provider.dragPositionFor(el.id);
    // Only show drag visuals on this element if it is the actual drag target.
    final isActualTarget = _dragTargetId == null || _dragTargetId == el.id;
    final isDragging = (isActualTarget && _isDragging) || dragNotifier != null;

    return ValueListenableBuilder<Offset>(
      valueListenable: dragNotifier ?? ValueNotifier(Offset(el.x, el.y)),
      builder: (context, pos, _) {
        final x = dragNotifier != null ? pos.dx : el.x;
        final y = dragNotifier != null ? pos.dy : el.y;

        return Positioned(
          left: x,
          top: y,
          width: el.width,
          height: el.height,
          child: _buildInteractiveLayer(el, x, y, isDragging),
        );
      },
    );
  }

  Widget _buildInteractiveLayer(
    TemplateElement el,
    double x,
    double y,
    bool isDragging,
  ) {
    return Selector<TemplateEditorProvider,
        ({bool selected, bool editingText})>(
      selector: (_, p) => (
        selected: p.isSelected(el.id),
        editingText: p.editingTextId == el.id,
      ),
      builder: (context, state, _) {
        final content = _applyDragShadow(
          el,
          _buildElementContent(el, state.editingText, state.selected),
          isDragging,
        );

        if (el.locked) return content;

        // While a TextField is active, let it own ALL pointer events.
        // Keeping a GestureDetector with HitTestBehavior.opaque around an
        // active TextField causes a Flutter Web engine assertion
        // (targetElement == domElement) on every mouse move.
        if (state.editingText) return content;

        final allowDoubleTap = el is! SignatureBlockElement;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: content),
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) => _onPointerDown(event, el),
                onPointerMove: (event) => _onPointerMove(event, el),
                onPointerUp: (event) => _onPointerUp(event, el),
                onPointerCancel: (event) => _onPointerCancel(event, el),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  _provider.selectElement(
                    el.id,
                    addToSelection: _isShiftHeld(),
                  );
                  if (el is ImageElement) {
                    _provider.openImagePicker();
                  }
                },
                onDoubleTap: allowDoubleTap ? () => _handleDoubleTap(el) : null,
                // Long-press triggers context menu on touch devices only.
                // On web/desktop use right-click (onSecondaryTap) instead.
                onLongPress: kIsWeb ? null : () => _showMobileContextMenu(el),
                onSecondaryTapDown: (d) => _secondaryTapPosition = d.globalPosition,
                onSecondaryTap: () => _showDesktopContextMenu(el),
              ),
            ),
          ],
        );
      },
    );
  }

  // Every element is clipped to its model bounds so that content that
  // overflows (e.g. Flutter's Table widget, which ignores tight height
  // constraints) never bleeds into adjacent elements or makes the
  // selection box appear smaller than the visible content.
  Widget _buildElementContent(
    TemplateElement el,
    bool isEditingText,
    bool isSelected,
  ) {
    final inner = switch (el) {
      TextElement te => TextElementWidget(
          element: te,
          isEditing: isEditingText,
          onCommit: (text) => _provider.commitTextEdit(te.id, text),
        ),
      ImageElement ie => ImageElementWidget(element: ie),
      TableElement tbl => TableElementWidget(
          element: tbl,
          isEditing: isEditingText,
          provider: _provider,
        ),
      LogoElement le => LogoElementWidget(element: le),
      SignatureBlockElement sb => SignatureBlockWidget(
          element: sb,
          isSelected: isSelected,
          onChanged: _provider.updateElement,
          onSelect: () => _provider.selectElement(sb.id),
          onBeginEdit: () => _provider.beginInlineEdit(sb.id),
          onEndEdit: _provider.endInlineEdit,
        ),
      DividerElement de => DividerElementWidget(element: de),
      ShapeElement se => ShapeElementWidget(element: se),
      ContainerElement ce => ContainerElementWidget(element: ce),
    };
    final clipped = ClipRect(child: inner);
    if (el.rotation % 360 == 0) return clipped;
    return Transform.rotate(
      angle: el.rotation * math.pi / 180,
      alignment: Alignment.center,
      child: clipped,
    );
  }

  Widget _applyDragShadow(
    TemplateElement el,
    Widget child,
    bool isDragging,
  ) {
    if (!isDragging) return child;

    final borderRadius = switch (el) {
      ImageElement ie => BorderRadius.circular(ie.borderRadius),
      _ => BorderRadius.zero,
    };

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 8),
                ),
                BoxShadow(
                  color: Color(0x1A000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
        child,
      ],
    );
  }

  void _handleDoubleTap(TemplateElement el) {
    switch (el) {
      case TextElement _:
        _provider.beginTextEdit(el.id);
      case LogoElement le:
        _pickAndReplaceLogo(le);
      default:
        _provider.selectElement(el.id);
    }
  }

  Future<void> _pickAndReplaceLogo(LogoElement el) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'png').toLowerCase();
    final mime = (ext == 'jpg' || ext == 'jpeg') ? 'image/jpeg' : 'image/png';
    final src = 'data:$mime;base64,${base64Encode(bytes)}';

    _provider.updateElement(el.copyWith(src: src));
  }

  void _onPointerDown(PointerDownEvent event, TemplateElement el) {
    if (el.locked || _provider.editingTextId == el.id) return;
    _activePointer = event.pointer;
    _pointerDown = event.position;
    _dragTargetId = el.id;
    _startX = el.x;
    _startY = el.y;
  }

  void _onPointerMove(PointerMoveEvent event, TemplateElement el) {
    if (_activePointer != event.pointer || _pointerDown == null) return;
    if (_provider.isPanMode) return;

    final delta = event.position - _pointerDown!;
    if (!_isDragging && delta.distance < 4.0) return;

    final dragId = _dragTargetId ?? el.id;

    if (!_isDragging) {
      if (!_provider.isSelected(dragId)) {
        _provider.selectElement(dragId);
      }
      _provider.beginDrag(dragId);
      if (mounted) setState(() => _isDragging = true);
    }

    final scale = widget.transformController.value.getMaxScaleOnAxis();
    _provider.updateDrag(
      dragId,
      _startX + delta.dx / scale,
      _startY + delta.dy / scale,
    );
  }

  void _onPointerUp(PointerUpEvent event, TemplateElement el) {
    if (_activePointer != event.pointer) return;
    _finishDrag(el);
  }

  void _onPointerCancel(PointerCancelEvent event, TemplateElement el) {
    if (_activePointer != event.pointer) return;
    _finishDrag(el);
  }

  void _finishDrag(TemplateElement el) {
    _pointerDown = null;
    _activePointer = null;
    final dragId = _dragTargetId ?? el.id;
    _dragTargetId = null;
    if (_isDragging) {
      _provider.endDrag(dragId);
    }
    if (!mounted) return;
    setState(() => _isDragging = false);
  }

  bool _isShiftHeld() => HardwareKeyboard.instance.isShiftPressed;

  Future<void> _showDesktopContextMenu(TemplateElement el) async {
    _provider.selectElement(el.id);
    final pos = _secondaryTapPosition;
    final action = await showMenu<_ContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 12,
      color: Colors.white,
      constraints: const BoxConstraints(minWidth: 180),
      items: [
        _popupItem(_ContextAction.copy,        Icons.copy_rounded,                    'Copy',          '⌘C'),
        _popupItem(_ContextAction.cut,         Icons.cut_rounded,                     'Cut',           '⌘X'),
        _popupItem(_ContextAction.paste,       Icons.content_paste_rounded,           'Paste',         '⌘V'),
        _popupItem(_ContextAction.duplicate,   Icons.control_point_duplicate_rounded, 'Duplicate',     '⌘D'),
        const PopupMenuDivider(height: 1),
        _popupItem(_ContextAction.bringForward, Icons.flip_to_front_rounded,          'Bring Forward', null),
        _popupItem(_ContextAction.sendBack,     Icons.flip_to_back_rounded,           'Send Back',     null),
        _popupItem(_ContextAction.rotate,       Icons.rotate_90_degrees_cw_rounded,   'Rotate 90°',    null),
        const PopupMenuDivider(height: 1),
        _popupItem(_ContextAction.delete,       Icons.delete_outline_rounded,         'Delete',        '⌫',
            isDestructive: true),
      ],
    );
    if (!mounted) return;
    _handleContextAction(action, el);
  }

  void _showMobileContextMenu(TemplateElement el) {
    _provider.selectElement(el.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ContextMenuSheet(element: el, provider: _provider),
    );
  }

  PopupMenuItem<_ContextAction> _popupItem(
    _ContextAction action,
    IconData icon,
    String label,
    String? shortcut, {
    bool isDestructive = false,
  }) {
    final color = isDestructive ? const Color(0xFFDC2626) : const Color(0xFF1E293B);
    return PopupMenuItem<_ContextAction>(
      value: action,
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
          if (shortcut != null)
            Text(
              shortcut,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
              ),
            ),
        ],
      ),
    );
  }

  void _handleContextAction(_ContextAction? action, TemplateElement el) {
    switch (action) {
      case _ContextAction.copy:         _provider.copySelected();
      case _ContextAction.cut:          _provider.cutSelected();
      case _ContextAction.paste:        _provider.paste();
      case _ContextAction.duplicate:    _provider.duplicateSelected();
      case _ContextAction.bringForward: _provider.bringForward(el.id);
      case _ContextAction.sendBack:     _provider.sendBackward(el.id);
      case _ContextAction.rotate:       _provider.rotateSelectedBy(90);
      case _ContextAction.delete:       _provider.deleteSelected();
      case null:                        break;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Mobile context menu bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _ContextMenuSheet extends StatelessWidget {
  final TemplateElement element;
  final TemplateEditorProvider provider;

  const _ContextMenuSheet({required this.element, required this.provider});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 12),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Clipboard group
          _group(context, [
            _item(context, 'Copy',      Icons.copy_rounded,                    () => provider.copySelected()),
            _item(context, 'Cut',       Icons.cut_rounded,                     () => provider.cutSelected()),
            _item(context, 'Paste',     Icons.content_paste_rounded,           () => provider.paste()),
            _item(context, 'Duplicate', Icons.control_point_duplicate_rounded, () => provider.duplicateSelected()),
          ]),
          const SizedBox(height: 8),
          // Layer group
          _group(context, [
            _item(context, 'Bring Forward', Icons.flip_to_front_rounded, () => provider.bringForward(element.id)),
            _item(context, 'Send Back',     Icons.flip_to_back_rounded,  () => provider.sendBackward(element.id)),
            _item(context, 'Rotate 90°',    Icons.rotate_90_degrees_cw_rounded, () => provider.rotateSelectedBy(90)),
          ]),
          const SizedBox(height: 8),
          // Destructive group
          _group(context, [
            _item(context, 'Delete', Icons.delete_outline_rounded, () => provider.deleteSelected(), isDestructive: true),
          ]),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.hardEdge,
      child: Column(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  Widget _item(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    final color = isDestructive ? const Color(0xFFDC2626) : const Color(0xFF1E293B);
    return InkWell(
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
