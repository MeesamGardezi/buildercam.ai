import 'package:flutter/material.dart';

import '../../core/app_colors.dart';
import '../../models/template_element_model.dart';
import '../../models/template_model.dart';
import '../elements/divider_element_widget.dart';
import '../elements/image_element_widget.dart';
import '../elements/logo_element_widget.dart';
import '../elements/table_element_widget.dart';
import '../elements/text_element_widget.dart';
import '../elements/signature_block_widget.dart';

/// Read-only, zoomable canvas used by the preview page.
/// Renders all visible elements on an A4-sized white page centred in the
/// available space — no selection, no drag, no editing.
class PreviewCanvasWidget extends StatefulWidget {
  final TemplateModel template;

  const PreviewCanvasWidget({super.key, required this.template});

  @override
  State<PreviewCanvasWidget> createState() => _PreviewCanvasWidgetState();
}

class _PreviewCanvasWidgetState extends State<PreviewCanvasWidget> {
  final TransformationController _controller = TransformationController();
  bool _didCenter = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _centerPage(Size viewSize, double pageW) {
    if (_didCenter) return;
    _didCenter = true;
    const padding = 48.0;
    final contentW = pageW + padding * 2;
    if (viewSize.width < contentW) {
      // Mobile: scale down so the full page width is visible on load.
      final scale = (viewSize.width / contentW).clamp(0.2, 1.0);
      _controller.value = Matrix4.identity()..scale(scale);
      return;
    }
    final dx = ((viewSize.width - contentW) / 2).clamp(0.0, 400.0);
    if (dx > 4) {
      _controller.value = Matrix4.identity()..translate(dx, 0.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pageW = widget.template.pageSize.width;
    final pageH = widget.template.pageSize.height;
    final sorted = [...widget.template.elements]
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final visible = sorted.where((e) => e.visible).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _centerPage(constraints.biggest, pageW),
        );

        return Container(
          color: AppColors.pageBackground,
          child: InteractiveViewer(
            transformationController: _controller,
            minScale: 0.2,
            maxScale: 5.0,
            boundaryMargin: const EdgeInsets.all(1200),
            constrained: false,
            trackpadScrollCausesScale: false,
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Container(
                width: pageW,
                height: pageH,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x33000000),
                      blurRadius: 24,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: visible
                      .map((el) => _PreviewElement(element: el))
                      .toList(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewElement extends StatelessWidget {
  final TemplateElement element;

  const _PreviewElement({required this.element});

  @override
  Widget build(BuildContext context) {
    final el = element;
    return Positioned(
      left: el.x,
      top: el.y,
      width: el.width,
      height: el.height,
      child: IgnorePointer(
        child: ClipRect(child: _buildContent(el)),
      ),
    );
  }

  Widget _buildContent(TemplateElement el) => switch (el) {
        TextElement te => TextElementWidget(
            element: te,
            isEditing: false,
            onCommit: (_) {},
          ),
        ImageElement ie => ImageElementWidget(element: ie),
        TableElement tbl => TableElementWidget(
            element: tbl,
            isEditing: false,
            provider: null,
          ),
        LogoElement le => LogoElementWidget(element: le),
        SignatureBlockElement sb => SignatureBlockWidget(
            element: sb,
            isSelected: false,
            onChanged: (_) {},
          ),
        DividerElement de => DividerElementWidget(element: de),
      };
}
