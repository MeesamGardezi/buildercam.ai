import 'package:uuid/uuid.dart';

import '../models/template_element_model.dart';

/// In-app clipboard — does not touch the OS clipboard.
/// Elements are serialised to JSON on copy so the clipboard holds
/// an independent value snapshot (not references into the live model).
class ClipboardService {
  ClipboardService._();
  static final ClipboardService instance = ClipboardService._();

  List<Map<String, dynamic>>? _payload;

  bool get hasContent => _payload != null && _payload!.isNotEmpty;

  void copy(List<TemplateElement> elements) {
    _payload = elements.map((e) => e.toJson()).toList();
  }

  /// Returns deep copies of the copied elements with:
  ///   • New generated IDs (avoids ID collisions on paste)
  ///   • Position offset by +10, +10 from the original
  ///   • The pasted group shifted back inside the page bounds when needed
  List<TemplateElement> paste({
    double pageWidth = 595,
    double pageHeight = 842,
    double pageMargin = 8,
  }) {
    if (_payload == null) return const [];
    final pasted = _payload!.map((json) {
      final copy = Map<String, dynamic>.from(json);
      copy['id'] = const Uuid().v4().substring(0, 8);
      copy['x'] = ((json['x'] as num).toDouble()) + 10;
      copy['y'] = ((json['y'] as num).toDouble()) + 10;
      return TemplateElement.fromJson(copy);
    }).toList();

    if (pasted.isEmpty) return const [];

    final minX = pasted.map((element) => element.x).reduce(_min);
    final minY = pasted.map((element) => element.y).reduce(_min);
    final maxX =
        pasted.map((element) => element.x + element.width).reduce(_max);
    final maxY =
        pasted.map((element) => element.y + element.height).reduce(_max);

    final dx = _boundShift(
      min: minX,
      max: maxX,
      lower: pageMargin,
      upper: pageWidth - pageMargin,
    );
    final dy = _boundShift(
      min: minY,
      max: maxY,
      lower: pageMargin,
      upper: pageHeight - pageMargin,
    );

    if (dx == 0 && dy == 0) return pasted;
    return pasted
        .map((element) => _moveElement(element, element.x + dx, element.y + dy))
        .toList();
  }

  void clear() => _payload = null;

  double _boundShift({
    required double min,
    required double max,
    required double lower,
    required double upper,
  }) {
    if (max - min > upper - lower) return lower - min;
    if (max > upper) return upper - max;
    if (min < lower) return lower - min;
    return 0;
  }

  double _min(double a, double b) => a < b ? a : b;
  double _max(double a, double b) => a > b ? a : b;

  TemplateElement _moveElement(TemplateElement element, double x, double y) =>
      switch (element) {
        TextElement text => text.copyWith(x: x, y: y),
        ImageElement image => image.copyWith(x: x, y: y),
        TableElement table => table.copyWith(x: x, y: y),
        LogoElement logo => logo.copyWith(x: x, y: y),
        SignatureBlockElement signature => signature.copyWith(x: x, y: y),
        DividerElement divider => divider.copyWith(x: x, y: y),
        ShapeElement shape => shape.copyWith(x: x, y: y),
        ContainerElement container => container.copyWith(x: x, y: y),
      };
}
