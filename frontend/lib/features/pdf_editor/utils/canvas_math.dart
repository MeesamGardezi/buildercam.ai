import '../models/template_element_model.dart';

// Handle positions for resize operations.
enum HandlePosition { nw, n, ne, e, se, s, sw, w }

class SnapGuide {
  final bool isVertical; // false = horizontal line
  final double position; // canvas-space coordinate

  const SnapGuide({required this.isVertical, required this.position});
}

/// Pure-function canvas geometry utilities.
/// No Flutter rendering dependencies — unit-testable in isolation.
class CanvasMath {
  CanvasMath._();

  static const double snapThreshold = 4.0;
  static const double minSize = 20.0;
  static const double pageMargin = 8.0;

  // ── Snap ──────────────────────────────────────────────────────────────────

  /// Returns [value] snapped to the nearest guide within [snapThreshold],
  /// or [value] unchanged if none are close enough.
  static double snapValue(double value, Iterable<double> guides) {
    double best = value;
    double bestDist = snapThreshold;
    for (final g in guides) {
      final d = (value - g).abs();
      if (d < bestDist) {
        bestDist = d;
        best = g;
      }
    }
    return best;
  }

  /// Computes all candidate snap guide values (x for vertical, y for
  /// horizontal) from elements on the canvas plus page geometry.
  static List<SnapGuide> computeGuides(
    List<TemplateElement> elements,
    String? excludeId,
    double pageWidth,
    double pageHeight,
  ) {
    final guides = <SnapGuide>[];

    // Page edges and center only
    guides.addAll([
      SnapGuide(isVertical: true, position: pageMargin),
      SnapGuide(isVertical: true, position: pageWidth / 2),
      SnapGuide(isVertical: true, position: pageWidth - pageMargin),
      SnapGuide(isVertical: false, position: pageMargin),
      SnapGuide(isVertical: false, position: pageHeight / 2),
      SnapGuide(isVertical: false, position: pageHeight - pageMargin),
    ]);

    for (final el in elements) {
      if (el.id == excludeId) continue;
      // Left and right edges only
      guides.add(SnapGuide(isVertical: true, position: el.x));
      guides.add(SnapGuide(isVertical: true, position: el.x + el.width));
      // Top and bottom edges only
      guides.add(SnapGuide(isVertical: false, position: el.y));
      guides.add(SnapGuide(isVertical: false, position: el.y + el.height));
    }

    return guides;
  }

  /// Snaps a dragged element rect to the nearest applicable guide.
  /// Returns the snapped (x, y) for the element's top-left corner.
  static (double x, double y) snapElementPosition(
    double x,
    double y,
    double width,
    double height,
    List<SnapGuide> guides,
  ) {
    final vGuides =
        guides.where((g) => g.isVertical).map((g) => g.position).toList();
    final hGuides =
        guides.where((g) => !g.isVertical).map((g) => g.position).toList();

    final snappedX = _nearestSnap([
          for (final g in vGuides) ...[
            (value: g, distance: (x - g).abs()),
            (value: g - width / 2, distance: (x + width / 2 - g).abs()),
            (value: g - width, distance: (x + width - g).abs()),
          ],
        ]) ??
        x;

    final snappedY = _nearestSnap([
          for (final g in hGuides) ...[
            (value: g, distance: (y - g).abs()),
            (value: g - height / 2, distance: (y + height / 2 - g).abs()),
            (value: g - height, distance: (y + height - g).abs()),
          ],
        ]) ??
        y;

    return (snappedX, snappedY);
  }

  /// Returns the active snap guides (those that the element actually snapped
  /// to) for rendering the guide lines.
  static List<SnapGuide> activeGuides(
    double x,
    double y,
    double width,
    double height,
    List<SnapGuide> allGuides,
  ) {
    final active = <SnapGuide>[];
    for (final g in allGuides) {
      if (g.isVertical) {
        if ((x - g.position).abs() < 0.5 ||
            (x + width - g.position).abs() < 0.5) {
          active.add(g);
        }
      } else {
        if ((y - g.position).abs() < 0.5 ||
            (y + height - g.position).abs() < 0.5) {
          active.add(g);
        }
      }
    }
    return active;
  }

  // ── Resize ────────────────────────────────────────────────────────────────

  /// Applies a drag [delta] to [original] rect for the given [handle],
  /// keeping the opposite anchor fixed. Enforces [minSize] on both axes.
  /// If [constrainAspect] is true, maintains the original aspect ratio.
  static ({double x, double y, double width, double height}) applyResize(
    double origX,
    double origY,
    double origWidth,
    double origHeight,
    HandlePosition handle,
    double dx,
    double dy, {
    bool constrainAspect = false,
  }) {
    double x = origX;
    double y = origY;
    double w = origWidth;
    double h = origHeight;
    final aspect = origHeight == 0 ? 1.0 : origWidth / origHeight;

    switch (handle) {
      case HandlePosition.nw:
        x = origX + dx;
        y = origY + dy;
        w = origWidth - dx;
        h = origHeight - dy;
      case HandlePosition.n:
        y = origY + dy;
        h = origHeight - dy;
      case HandlePosition.ne:
        y = origY + dy;
        w = origWidth + dx;
        h = origHeight - dy;
      case HandlePosition.e:
        w = origWidth + dx;
      case HandlePosition.se:
        w = origWidth + dx;
        h = origHeight + dy;
      case HandlePosition.s:
        h = origHeight + dy;
      case HandlePosition.sw:
        x = origX + dx;
        w = origWidth - dx;
        h = origHeight + dy;
      case HandlePosition.w:
        x = origX + dx;
        w = origWidth - dx;
    }

    var aspectWasConstrained = false;
    if (constrainAspect && origWidth > 0 && origHeight > 0) {
      // Dominant axis drives the constrained axis.
      final wRatio = w / origWidth;
      final hRatio = h / origHeight;
      if ((wRatio - 1).abs() > (hRatio - 1).abs()) {
        h = w / aspect;
      } else {
        w = h * aspect;
      }
      aspectWasConstrained = true;
    }

    // Enforce minimum size
    if (aspectWasConstrained) {
      if (w < minSize) {
        w = minSize;
        h = w / aspect;
      }
      if (h < minSize) {
        h = minSize;
        w = h * aspect;
      }

      if (_movesLeft(handle)) {
        x = origX + origWidth - w;
      } else if (!_movesRight(handle)) {
        x = origX + (origWidth - w) / 2;
      } else {
        x = origX;
      }

      if (_movesTop(handle)) {
        y = origY + origHeight - h;
      } else if (!_movesBottom(handle)) {
        y = origY + (origHeight - h) / 2;
      } else {
        y = origY;
      }
    } else if (w < minSize) {
      if (handle == HandlePosition.nw ||
          handle == HandlePosition.w ||
          handle == HandlePosition.sw) {
        x = origX + origWidth - minSize;
      }
      w = minSize;
    }
    if (!aspectWasConstrained && h < minSize) {
      if (handle == HandlePosition.nw ||
          handle == HandlePosition.n ||
          handle == HandlePosition.ne) {
        y = origY + origHeight - minSize;
      }
      h = minSize;
    }

    return (x: x, y: y, width: w, height: h);
  }

  // ── PDF coordinate transform ───────────────────────────────────────────────

  /// Converts canvas top-left Y to PDF bottom-left Y.
  /// PDF origin is bottom-left; canvas origin is top-left.
  static double pdfY(double canvasY, double elementHeight, double pageHeight) =>
      pageHeight - canvasY - elementHeight;

  // ── Rubber-band selection ─────────────────────────────────────────────────

  /// Returns true if [element] rect intersects the rubber-band [selection].
  static bool intersectsRubberBand(
    TemplateElement element,
    double selX,
    double selY,
    double selWidth,
    double selHeight,
  ) {
    final normalised = _normalise(selX, selY, selWidth, selHeight);
    return element.x < normalised.$1 + normalised.$3 &&
        element.x + element.width > normalised.$1 &&
        element.y < normalised.$2 + normalised.$4 &&
        element.y + element.height > normalised.$2;
  }

  // ── Alignment ────────────────────────────────────────────────────────────

  static List<TemplateElement> alignLeft(List<TemplateElement> elements) {
    assert(elements.length >= 2, 'alignLeft requires at least two elements');
    if (elements.isEmpty) return elements;
    final minX = elements.map((e) => e.x).reduce((a, b) => a < b ? a : b);
    return _translateAll(elements, (e) => _setX(e, minX));
  }

  static List<TemplateElement> alignRight(List<TemplateElement> elements) {
    assert(elements.length >= 2, 'alignRight requires at least two elements');
    if (elements.isEmpty) return elements;
    final maxRight = elements
        .map((e) => e.x + e.width)
        .reduce((a, b) => a > b ? a : b);
    return _translateAll(elements, (e) => _setX(e, maxRight - e.width));
  }

  static List<TemplateElement> alignTop(List<TemplateElement> elements) {
    assert(elements.length >= 2, 'alignTop requires at least two elements');
    if (elements.isEmpty) return elements;
    final minY = elements.map((e) => e.y).reduce((a, b) => a < b ? a : b);
    return _translateAll(elements, (e) => _setY(e, minY));
  }

  static List<TemplateElement> alignBottom(List<TemplateElement> elements) {
    assert(elements.length >= 2, 'alignBottom requires at least two elements');
    if (elements.isEmpty) return elements;
    final maxBottom = elements
        .map((e) => e.y + e.height)
        .reduce((a, b) => a > b ? a : b);
    return _translateAll(elements, (e) => _setY(e, maxBottom - e.height));
  }

  static List<TemplateElement> alignCenterH(List<TemplateElement> elements) {
    assert(elements.length >= 2, 'alignCenterH requires at least two elements');
    if (elements.isEmpty) return elements;
    final cx = elements.map((e) => e.x + e.width / 2).reduce((a, b) => a + b) /
        elements.length;
    return _translateAll(elements, (e) => _setX(e, cx - e.width / 2));
  }

  static List<TemplateElement> alignCenterV(List<TemplateElement> elements) {
    assert(elements.length >= 2, 'alignCenterV requires at least two elements');
    if (elements.isEmpty) return elements;
    final cy = elements.map((e) => e.y + e.height / 2).reduce((a, b) => a + b) /
        elements.length;
    return _translateAll(elements, (e) => _setY(e, cy - e.height / 2));
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static (double, double, double, double) _normalise(
          double x, double y, double w, double h) =>
      (w < 0 ? x + w : x, h < 0 ? y + h : y, w.abs(), h.abs());

  static double? _nearestSnap(
    List<({double value, double distance})> candidates,
  ) {
    double? bestValue;
    var bestDistance = snapThreshold;

    for (final candidate in candidates) {
      if (candidate.distance < bestDistance) {
        bestDistance = candidate.distance;
        bestValue = candidate.value;
      }
    }

    return bestValue;
  }

  static bool _movesLeft(HandlePosition handle) =>
      handle == HandlePosition.nw ||
      handle == HandlePosition.w ||
      handle == HandlePosition.sw;

  static bool _movesRight(HandlePosition handle) =>
      handle == HandlePosition.ne ||
      handle == HandlePosition.e ||
      handle == HandlePosition.se;

  static bool _movesTop(HandlePosition handle) =>
      handle == HandlePosition.nw ||
      handle == HandlePosition.n ||
      handle == HandlePosition.ne;

  static bool _movesBottom(HandlePosition handle) =>
      handle == HandlePosition.sw ||
      handle == HandlePosition.s ||
      handle == HandlePosition.se;

  static List<TemplateElement> _translateAll(
    List<TemplateElement> elements,
    TemplateElement Function(TemplateElement) fn,
  ) =>
      elements.map(fn).toList();

  static TemplateElement _setX(TemplateElement e, double x) =>
      switch (e) {
        TextElement te => te.copyWith(x: x),
        ImageElement ie => ie.copyWith(x: x),
        TableElement tbl => tbl.copyWith(x: x),
        LogoElement le => le.copyWith(x: x),
        SignatureBlockElement sb => sb.copyWith(x: x),
        DividerElement de => de.copyWith(x: x),
        ShapeElement se => se.copyWith(x: x),
        ContainerElement ce => ce.copyWith(x: x),
      };

  static TemplateElement _setY(TemplateElement e, double y) =>
      switch (e) {
        TextElement te => te.copyWith(y: y),
        ImageElement ie => ie.copyWith(y: y),
        TableElement tbl => tbl.copyWith(y: y),
        LogoElement le => le.copyWith(y: y),
        SignatureBlockElement sb => sb.copyWith(y: y),
        DividerElement de => de.copyWith(y: y),
        ShapeElement se => se.copyWith(y: y),
        ContainerElement ce => ce.copyWith(y: y),
      };
}
