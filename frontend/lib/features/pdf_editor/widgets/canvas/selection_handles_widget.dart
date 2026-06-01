import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../models/template_element_model.dart';
import '../../providers/template_editor_provider.dart';
import '../../utils/canvas_math.dart';

/// Renders selection border + 8 resize handles for the currently selected
/// element. Lives INSIDE the canvas Stack so all coordinates are canvas-local —
/// no Overlay / screen-space transforms needed.
///
/// [transformController] is required so that resize drag deltas can be
/// divided by the current zoom scale, keeping handle movement 1:1 with
/// canvas units regardless of zoom level.
class CanvasSelectionLayer extends StatefulWidget {
  final TransformationController transformController;

  const CanvasSelectionLayer({
    super.key,
    required this.transformController,
  });

  @override
  State<CanvasSelectionLayer> createState() => _CanvasSelectionLayerState();
}

class _CanvasSelectionLayerState extends State<CanvasSelectionLayer> {
  double _origX = 0, _origY = 0, _origW = 0, _origH = 0;
  double _liveW = 0, _liveH = 0;
  bool _resizing = false;
  String? _activeResizeId;

  @override
  Widget build(BuildContext context) {
    return Selector<TemplateEditorProvider,
        ({TemplateElement? el, bool editing, bool multi})>(
      selector: (_, p) => (
        el: p.primarySelected,
        editing: p.isEditingText,
        multi: p.hasMultiSelection,
      ),
      builder: (context, s, _) {
        final el = s.el;
        if (el == null || s.editing || s.multi) return const SizedBox.shrink();

        final provider = context.read<TemplateEditorProvider>();
        const dot = 10.0;
        const half = dot / 2;

        // Handles are visually centered on each edge/corner. Resize math uses
        // pointer deltas from pan start, so the -half paint offset does not
        // shift the model-space resize origin.
        final handles = <HandlePosition, Offset>{
          HandlePosition.nw: Offset(el.x - half, el.y - half),
          HandlePosition.n: Offset(el.x + el.width / 2 - half, el.y - half),
          HandlePosition.ne: Offset(el.x + el.width - half, el.y - half),
          HandlePosition.e:
              Offset(el.x + el.width - half, el.y + el.height / 2 - half),
          HandlePosition.se:
              Offset(el.x + el.width - half, el.y + el.height - half),
          HandlePosition.s:
              Offset(el.x + el.width / 2 - half, el.y + el.height - half),
          HandlePosition.sw: Offset(el.x - half, el.y + el.height - half),
          HandlePosition.w: Offset(el.x - half, el.y + el.height / 2 - half),
        };

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // Selection border
            Positioned(
              left: el.x,
              top: el.y,
              width: el.width,
              height: el.height,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),

            // 8 resize handles
            for (final entry in handles.entries)
              Positioned(
                left: entry.value.dx,
                top: entry.value.dy,
                child: _ResizeHandle(
                  key: ValueKey('${el.id}:${entry.key.name}'),
                  position: entry.key,
                  transformController: widget.transformController,
                  onDragStart: () {
                    _origX = el.x;
                    _origY = el.y;
                    _origW = el.width;
                    _origH = el.height;
                    _liveW = el.width;
                    _liveH = el.height;
                    _activeResizeId = el.id;
                    setState(() => _resizing = true);
                    provider.beginResize(el.id);
                  },
                  onDragUpdate: (dx, dy, constrain) {
                    if (_activeResizeId != el.id ||
                        !provider.isSelected(el.id)) {
                      return;
                    }
                    provider.applyResize(el.id, _origX, _origY, _origW, _origH,
                        entry.key, dx, dy,
                        constrainAspect: constrain);
                    final r = CanvasMath.applyResize(
                        _origX, _origY, _origW, _origH, entry.key, dx, dy,
                        constrainAspect: constrain);
                    setState(() {
                      _liveW = r.width;
                      _liveH = r.height;
                    });
                  },
                  onDragEnd: () {
                    final activeId = _activeResizeId;
                    _activeResizeId = null;
                    setState(() => _resizing = false);
                    if (activeId == el.id) provider.endResize(el.id);
                  },
                ),
              ),

            // Live size label while resizing
            if (_resizing)
              Positioned(
                left: el.x + el.width + 6,
                top: el.y + el.height / 2 - 10,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.charcoal800,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${_liveW.round()} × ${_liveH.round()}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontFamily: 'monospace'),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Handle dot ────────────────────────────────────────────────────────────────

class _ResizeHandle extends StatefulWidget {
  final HandlePosition position;
  final TransformationController transformController;
  final VoidCallback onDragStart;
  final void Function(double dx, double dy, bool constrain) onDragUpdate;
  final VoidCallback onDragEnd;

  const _ResizeHandle({
    super.key,
    required this.position,
    required this.transformController,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  Offset? _start;

  double get _scale => widget.transformController.value.getMaxScaleOnAxis();

  MouseCursor get _cursor => switch (widget.position) {
        HandlePosition.nw ||
        HandlePosition.se =>
          SystemMouseCursors.resizeUpLeftDownRight,
        HandlePosition.ne ||
        HandlePosition.sw =>
          SystemMouseCursors.resizeUpRightDownLeft,
        HandlePosition.n || HandlePosition.s => SystemMouseCursors.resizeUpDown,
        HandlePosition.e ||
        HandlePosition.w =>
          SystemMouseCursors.resizeLeftRight,
      };

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: _cursor,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // Consume the tap so the parent canvas onTap (deselectAll) doesn't
          // fire when the user clicks a handle without dragging.
          onTap: () {},
          onPanStart: (d) {
            _start = d.globalPosition;
            widget.onDragStart();
          },
          onPanUpdate: (d) {
            if (_start == null) return;
            // globalPosition delta must be divided by the viewport scale so
            // the resize amount is in canvas units, not screen pixels.
            final rawDelta = d.globalPosition - _start!;
            widget.onDragUpdate(
              rawDelta.dx / _scale,
              rawDelta.dy / _scale,
              HardwareKeyboard.instance.isShiftPressed,
            );
          },
          onPanEnd: (_) {
            _start = null;
            widget.onDragEnd();
          },
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: AppColors.primary, width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 3,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      );
}
