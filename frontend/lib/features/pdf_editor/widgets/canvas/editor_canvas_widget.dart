import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_colors.dart';
import '../../providers/template_editor_provider.dart';
import 'canvas_element_widget.dart';
import 'rubber_band_widget.dart';
import 'selection_handles_widget.dart';
import 'snap_guide_widget.dart';

/// The main WYSIWYG canvas. Wraps an A4-proportioned white Stack inside
/// an InteractiveViewer for zoom/pan. All element coordinates are in
/// canvas logical units (595 × 842); the InteractiveViewer handles the
/// viewport transform.
class EditorCanvasWidget extends StatefulWidget {
  const EditorCanvasWidget({super.key});

  @override
  State<EditorCanvasWidget> createState() => _EditorCanvasWidgetState();
}

class _EditorCanvasWidgetState extends State<EditorCanvasWidget> {
  final TransformationController _transformController =
      TransformationController();

  // Rubber-band state — all in canvas-local coordinates (localPosition).
  Offset? _rubberStart;
  double _rubberX = 0, _rubberY = 0, _rubberW = 0, _rubberH = 0;
  bool _isRubberBanding = false;

  bool _didCenter = false;
  int _handledFocusRequestVersion = 0;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  // Center (or scale-to-fit on mobile) the page within the viewport on first render.
  void _centerPage(Size viewSize, double pageW) {
    if (_didCenter) return;
    _didCenter = true;
    const padding = 48.0;
    final contentW = pageW + padding * 2;
    if (viewSize.width < contentW) {
      // Mobile: scale down so the full page width is visible on load.
      final scale = (viewSize.width / contentW).clamp(0.2, 1.0);
      _transformController.value = Matrix4.identity()..scale(scale);
      return;
    }
    final dx = ((viewSize.width - contentW) / 2).clamp(0.0, 400.0);
    if (dx > 4) {
      _transformController.value = Matrix4.identity()..translate(dx, 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TemplateEditorProvider>();
    final pageSize = provider.template?.pageSize;
    final pageW = pageSize?.width ?? 595.0;
    final pageH = pageSize?.height ?? 842.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Center on the very first layout pass (only once).
        WidgetsBinding.instance.addPostFrameCallback(
          (_) {
            _centerPage(constraints.biggest, pageW);
            _handleFocusRequest(provider, constraints.biggest);
          },
        );

        return Container(
          color: AppColors.pageBackground,
          child: ValueListenableBuilder<bool>(
            valueListenable: provider.panModeNotifier,
            builder: (context, isPanMode, _) {
              return Stack(
                children: [
                  Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (event) {
                      if (event.buttons & kSecondaryButton != 0) {
                        provider.setPanMode(true);
                      }
                    },
                    onPointerUp: (event) {
                      if (provider.isPanMode &&
                          event.buttons & kSecondaryButton == 0) {
                        provider.setPanMode(false);
                      }
                    },
                    child: InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.2,
                      maxScale: 5.0,
                      boundaryMargin: const EdgeInsets.all(1200),
                      constrained: false,
                      panEnabled: isPanMode,
                      // Keep wheel/trackpad gestures for panning long pages.
                      // Zoom is intentionally only via the controls to avoid
                      // accidental mouse-wheel zoom-outs.
                      trackpadScrollCausesScale: false,
                      onInteractionUpdate: (_) => provider.setZoom(
                        _transformController.value.getMaxScaleOnAxis(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: _buildPage(context, provider, pageW, pageH, isPanMode),
                      ),
                    ),
                  ),

                  // Zoom controls — bottom-right corner
                  Positioned(
                    right: 12,
                    bottom: 12,
                    child: _ZoomControls(
                      controller: _transformController,
                      viewportSize: constraints.biggest,
                      pageWidth: pageW,
                      onScaleChanged: provider.setZoom,
                      isPanMode: isPanMode,
                      onTogglePan: () => provider.setPanMode(!isPanMode),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _handleFocusRequest(
    TemplateEditorProvider provider,
    Size viewportSize,
  ) {
    if (_handledFocusRequestVersion == provider.focusRequestVersion) return;
    _handledFocusRequestVersion = provider.focusRequestVersion;

    final id = provider.focusRequestId;
    if (id == null) return;

    final matches = provider.elements.where((el) => el.id == id);
    if (matches.isEmpty) return;
    final el = matches.first;

    const pagePadding = 48.0;
    final scale = _transformController.value
        .getMaxScaleOnAxis()
        .clamp(0.2, 5.0)
        .toDouble();
    final scenePoint = Offset(
      pagePadding + el.x + el.width / 2,
      pagePadding + el.y + el.height / 2,
    );

    _transformController.value = Matrix4.identity()
      ..translate(
        viewportSize.width / 2 - scenePoint.dx * scale,
        viewportSize.height / 2 - scenePoint.dy * scale,
      )
      ..scale(scale);
    provider.setZoom(scale);
  }

  Widget _buildPage(
    BuildContext context,
    TemplateEditorProvider provider,
    double pageW,
    double pageH,
    bool isPanMode,
  ) {
    return Container(
      width: pageW,
      height: pageH,
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          // Soft ambient halo
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 32,
            offset: Offset(0, 12),
          ),
          // Crisper contact shadow
          BoxShadow(
            color: Color(0x1A0F172A),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      // onTap (not onTapDown) so that touching a resize handle doesn't
      // immediately deselect — see selection_handles_widget.dart.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isPanMode
            ? null
            : () {
                // TapGestureRecognizer fires handleTapUp during its own dispose(),
                // which runs inside finalizeTree while the framework is locked.
                // Deferring to the next frame avoids the markNeedsBuild-while-locked crash.
                if (!mounted) return;
                final p = context.read<TemplateEditorProvider>();
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => p.deselectAll());
              },
        onPanStart:
            isPanMode ? null : (d) => _onRubberStart(d.localPosition),
        onPanUpdate:
            isPanMode ? null : (d) => _onRubberUpdate(d.localPosition),
        onPanEnd: isPanMode ? null : (_) => _onRubberEnd(provider),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            ...provider.sortedElements.map(
              (el) => CanvasElementWidget(
                key: ValueKey(el.id),
                element: el,
                transformController: _transformController,
              ),
            ),
            SnapGuideWidget(
              guidesNotifier: provider.snapGuides,
              pageWidth: pageW,
              pageHeight: pageH,
            ),
            CanvasSelectionLayer(
              transformController: _transformController,
            ),
            if (_isRubberBanding)
              RubberBandWidget(
                x: _rubberX,
                y: _rubberY,
                width: _rubberW,
                height: _rubberH,
              ),
          ],
        ),
      ),
    );
  }

  // ── Rubber-band ───────────────────────────────────────────────────────

  void _onRubberStart(Offset local) {
    // Don't start rubber-band if the user is dragging an element.
    if (context.read<TemplateEditorProvider>().isDragging) return;
    _rubberStart = local;
    setState(() {
      _rubberX = local.dx;
      _rubberY = local.dy;
      _rubberW = 0;
      _rubberH = 0;
      _isRubberBanding = false;
    });
  }

  void _onRubberUpdate(Offset local) {
    if (_rubberStart == null) return;
    setState(() {
      _rubberW = local.dx - _rubberStart!.dx;
      _rubberH = local.dy - _rubberStart!.dy;
      _isRubberBanding = (_rubberW.abs() + _rubberH.abs()) > 8;
    });
  }

  void _onRubberEnd(TemplateEditorProvider provider) {
    if (_isRubberBanding) {
      provider.selectByRubberBand(_rubberX, _rubberY, _rubberW, _rubberH);
    }
    setState(() {
      _rubberStart = null;
      _isRubberBanding = false;
      _rubberW = 0;
      _rubberH = 0;
    });
  }
}

// ── Zoom controls ─────────────────────────────────────────────────────────────

class _ZoomControls extends StatelessWidget {
  final TransformationController controller;
  final Size viewportSize;
  final double pageWidth;
  final ValueChanged<double> onScaleChanged;
  final bool isPanMode;
  final VoidCallback onTogglePan;

  const _ZoomControls({
    required this.controller,
    required this.viewportSize,
    required this.pageWidth,
    required this.onScaleChanged,
    required this.isPanMode,
    required this.onTogglePan,
  });

  double get _scale => controller.value.getMaxScaleOnAxis();

  void _zoom(double factor) {
    final nextScale = (_scale * factor).clamp(0.2, 5.0).toDouble();
    final focal = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final scenePoint = controller.toScene(focal);
    final next = Matrix4.identity()
      ..translate(
        focal.dx - scenePoint.dx * nextScale,
        focal.dy - scenePoint.dy * nextScale,
      )
      ..scale(nextScale);
    controller.value = next;
    onScaleChanged(nextScale);
  }

  void _reset() {
    const padding = 48.0;
    final contentW = pageWidth + padding * 2;
    if (viewportSize.width < contentW) {
      final scale = (viewportSize.width / contentW).clamp(0.2, 1.0);
      controller.value = Matrix4.identity()..scale(scale);
      onScaleChanged(scale);
      return;
    }
    final dx =
        ((viewportSize.width - contentW) / 2).clamp(0.0, 400.0).toDouble();
    controller.value = Matrix4.identity()..translate(dx, 0.0);
    onScaleChanged(1.0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [
            BoxShadow(color: Color(0x22000000), blurRadius: 6),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomBtn(
              icon: Icons.add,
              tooltip: 'Zoom in (⌘+)',
              onTap: () => _zoom(1.2),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${(_scale * 100).round()}%',
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF64748B),
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _ZoomBtn(
              icon: Icons.remove,
              tooltip: 'Zoom out (⌘-)',
              onTap: () => _zoom(1 / 1.2),
            ),
            const Divider(height: 1, thickness: 0.5, indent: 6, endIndent: 6),
            _ZoomBtn(
              icon: Icons.fit_screen_outlined,
              tooltip: 'Reset zoom (⌘0)',
              onTap: _reset,
            ),
            const Divider(height: 1, thickness: 0.5, indent: 6, endIndent: 6),
            _ZoomBtn(
              icon: Icons.pan_tool_outlined,
              tooltip: 'Pan mode',
              onTap: onTogglePan,
              active: isPanMode,
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _ZoomBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(
              icon,
              size: 16,
              color: active
                  ? const Color(0xFF0284C7)
                  : const Color(0xFF475569),
            ),
          ),
        ),
      );
}

// ── Margin guides (currently unused — kept for future ruler implementation) ───

// ignore: unused_element
class _MarginGuides extends StatelessWidget {
  final double pageW;
  final double pageH;

  const _MarginGuides({required this.pageW, required this.pageH});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size(pageW, pageH),
          painter: _MarginPainter(pageW, pageH),
        ),
      );
}

// ignore: unused_element
class _MarginPainter extends CustomPainter {
  final double pageW;
  final double pageH;
  static const double _margin = 8.0;

  const _MarginPainter(this.pageW, this.pageH);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x22B0C4DE)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..addRect(Rect.fromLTWH(
          _margin, _margin, pageW - _margin * 2, pageH - _margin * 2));

    const dashLen = 4.0;
    const gapLen = 3.0;
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      while (dist < metric.length) {
        final end = (dist + dashLen).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(dist, end), paint);
        dist += dashLen + gapLen;
      }
    }
  }

  @override
  bool shouldRepaint(_MarginPainter old) =>
      old.pageW != pageW || old.pageH != pageH;
}
