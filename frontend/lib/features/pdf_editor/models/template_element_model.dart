import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import 'element_type.dart';

Map<String, dynamic> _asMap(dynamic raw) {
  if (raw is Map<String, dynamic>) return raw;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const {};
}

String _asString(dynamic raw, [String fallback = '']) {
  if (raw == null) return fallback;
  return raw.toString();
}

double _asDouble(dynamic raw, [double fallback = 0]) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw) ?? fallback;
  return fallback;
}

int _asInt(dynamic raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

bool _asBool(dynamic raw, [bool fallback = false]) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final value = raw.trim().toLowerCase();
    if (value == 'true' || value == '1') return true;
    if (value == 'false' || value == '0') return false;
  }
  return fallback;
}

Color _parseColor(dynamic raw, [int fallback = 0xFF000000]) {
  if (raw is num) return Color(raw.toInt());
  if (raw is String) {
    final value = raw.trim();
    if (value.isEmpty) return Color(fallback);

    if (value.startsWith('#')) {
      final hex = value.substring(1);
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }

    final parsed = int.tryParse(value);
    if (parsed != null) return Color(parsed);
  }
  return Color(fallback);
}

// Converts CSS font-weight (100–900) or FontWeight enum index (0–8).
// Preset data uses CSS values; Dart serialises enum indices.
FontWeight _parseFontWeight(dynamic raw) {
  final v = _asInt(raw, 3);
  if (v >= 100) return FontWeight.values[(v ~/ 100 - 1).clamp(0, 8)];
  return FontWeight.values[v.clamp(0, 8)];
}

FontStyle _parseFontStyle(dynamic raw) {
  if (raw is String) {
    return raw.toLowerCase() == 'italic' ? FontStyle.italic : FontStyle.normal;
  }
  return FontStyle.values[_asInt(raw, 0).clamp(0, FontStyle.values.length - 1)];
}

TextAlign _parseTextAlign(dynamic raw) {
  if (raw is String) {
    return switch (raw.toLowerCase()) {
      'center' => TextAlign.center,
      'right' => TextAlign.right,
      'end' => TextAlign.end,
      'justify' => TextAlign.justify,
      'start' => TextAlign.start,
      _ => TextAlign.left,
    };
  }
  return TextAlign
      .values[_asInt(raw, 0).clamp(0, TextAlign.values.length - 1)];
}

BoxFit _parseBoxFit(dynamic raw) {
  if (raw is String) {
    return BoxFit.values.firstWhere(
      (fit) => fit.name == raw,
      orElse: () => BoxFit.contain,
    );
  }
  return BoxFit.values[_asInt(raw, 2).clamp(0, BoxFit.values.length - 1)];
}

// ── Base ────────────────────────────────────────────────────────────────────

sealed class TemplateElement {
  final String id;
  final ElementType type;
  final double x;
  final double y;
  final double width;
  final double height;
  final int zIndex;
  final bool locked;
  final bool visible;
  // Rotation in degrees (0, 90, 180, 270). Visual rotation is applied around
  // the element centre; (x, y, width, height) describe the rotated bounding box.
  final int rotation;

  const TemplateElement({
    required this.id,
    required this.type,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.zIndex,
    required this.locked,
    required this.visible,
    this.rotation = 0,
  });

  Rect get rect => Rect.fromLTWH(x, y, width, height);

  Map<String, dynamic> toJson();

  static TemplateElement fromJson(Map<String, dynamic> json) {
    final type = ElementType.fromJson(json['type'] as String);
    return switch (type) {
      ElementType.text => TextElement.fromJson(json),
      ElementType.image => ImageElement.fromJson(json),
      ElementType.table => TableElement.fromJson(json),
      ElementType.logo => LogoElement.fromJson(json),
      ElementType.signatureBlock => SignatureBlockElement.fromJson(json),
      ElementType.divider => DividerElement.fromJson(json),
    };
  }

  // Deep copy via round-trip serialization — used by undo stack.
  TemplateElement deepCopy() => TemplateElement.fromJson(toJson());

  static String _newId() => const Uuid().v4().substring(0, 8);

  Map<String, dynamic> _baseJson() => {
        'id': id,
        'type': type.jsonKey,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'rotation': rotation,
      };
}

// ── Text ────────────────────────────────────────────────────────────────────

class TextElement extends TemplateElement {
  final String content;
  final TextStyle? textStyle;
  final String fontFamily;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final Color color;
  final TextAlign textAlign;
  final double lineHeight;
  final double letterSpacing;
  final Color? backgroundColor;

  const TextElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.zIndex,
    required super.locked,
    required super.visible,
    super.rotation,
    required this.content,
    required this.fontFamily,
    required this.fontSize,
    required this.fontWeight,
    required this.fontStyle,
    required this.color,
    required this.textAlign,
    required this.lineHeight,
    required this.letterSpacing,
    this.backgroundColor,
    this.textStyle,
  }) : super(type: ElementType.text);

  factory TextElement.defaults({
    double x = 50,
    double y = 50,
    double width = 200,
    double height = 40,
    int zIndex = 0,
    String content = 'Text',
  }) =>
      TextElement(
        id: TemplateElement._newId(),
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: zIndex,
        locked: false,
        visible: true,
        content: content,
        fontFamily: 'Roboto',
        fontSize: 14,
        fontWeight: FontWeight.normal,
        fontStyle: FontStyle.normal,
        color: const Color(0xFF0F172A),
        textAlign: TextAlign.left,
        lineHeight: 1.4,
        letterSpacing: 0,
      );

  TextElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? locked,
    bool? visible,
    int? rotation,
    String? content,
    String? fontFamily,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    Color? color,
    TextAlign? textAlign,
    double? lineHeight,
    double? letterSpacing,
    Color? backgroundColor,
  }) =>
      TextElement(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        zIndex: zIndex ?? this.zIndex,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        rotation: rotation ?? this.rotation,
        content: content ?? this.content,
        fontFamily: fontFamily ?? this.fontFamily,
        fontSize: fontSize ?? this.fontSize,
        fontWeight: fontWeight ?? this.fontWeight,
        fontStyle: fontStyle ?? this.fontStyle,
        color: color ?? this.color,
        textAlign: textAlign ?? this.textAlign,
        lineHeight: lineHeight ?? this.lineHeight,
        letterSpacing: letterSpacing ?? this.letterSpacing,
        backgroundColor: backgroundColor ?? this.backgroundColor,
      );

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'content': content,
        'style': {
          'fontFamily': fontFamily,
          'fontSize': fontSize,
          'fontWeight': fontWeight.index,
          'fontStyle': fontStyle.index,
          'color': color.toARGB32(),
          'textAlign': textAlign.index,
          'lineHeight': lineHeight,
          'letterSpacing': letterSpacing,
          if (backgroundColor != null) 'backgroundColor': backgroundColor!.toARGB32(),
        },
      };

  factory TextElement.fromJson(Map<String, dynamic> json) {
    final style = _asMap(json['style']);
    return TextElement(
      id: _asString(json['id']),
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      width: _asDouble(json['width']),
      height: _asDouble(json['height']),
      zIndex: _asInt(json['zIndex']),
      locked: _asBool(json['locked']),
      visible: _asBool(json['visible'], true),
      rotation: _asInt(json['rotation']),
      content: _asString(json['content']),
      fontFamily: _asString(style['fontFamily'], 'Roboto'),
      fontSize: _asDouble(style['fontSize'], 14),
      fontWeight: _parseFontWeight(style['fontWeight']),
      fontStyle: _parseFontStyle(style['fontStyle']),
      color: _parseColor(style['color'], 0xFF0F172A),
      textAlign: _parseTextAlign(style['textAlign']),
      lineHeight: _asDouble(style['lineHeight'], 1.4),
      letterSpacing: _asDouble(style['letterSpacing']),
      backgroundColor: style['backgroundColor'] != null
          ? _parseColor(style['backgroundColor'])
          : null,
    );
  }
}

// ── Image ───────────────────────────────────────────────────────────────────

class ImageElement extends TemplateElement {
  final String src;
  final double opacity;
  final double borderRadius;
  final BoxFit objectFit;
  final bool hasShadow;

  const ImageElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.zIndex,
    required super.locked,
    required super.visible,
    super.rotation,
    required this.src,
    required this.opacity,
    required this.borderRadius,
    required this.objectFit,
    required this.hasShadow,
  }) : super(type: ElementType.image);

  factory ImageElement.defaults({
    double x = 50,
    double y = 50,
    double width = 150,
    double height = 100,
    int zIndex = 0,
    String src = '',
  }) =>
      ImageElement(
        id: TemplateElement._newId(),
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: zIndex,
        locked: false,
        visible: true,
        src: src,
        opacity: 1.0,
        borderRadius: 0,
        objectFit: BoxFit.contain,
        hasShadow: false,
      );

  ImageElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? locked,
    bool? visible,
    int? rotation,
    String? src,
    double? opacity,
    double? borderRadius,
    BoxFit? objectFit,
    bool? hasShadow,
  }) =>
      ImageElement(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        zIndex: zIndex ?? this.zIndex,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        rotation: rotation ?? this.rotation,
        src: src ?? this.src,
        opacity: opacity ?? this.opacity,
        borderRadius: borderRadius ?? this.borderRadius,
        objectFit: objectFit ?? this.objectFit,
        hasShadow: hasShadow ?? this.hasShadow,
      );

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'src': src,
        'opacity': opacity,
        'borderRadius': borderRadius,
        'objectFit': objectFit.index,
        'hasShadow': hasShadow,
      };

  factory ImageElement.fromJson(Map<String, dynamic> json) => ImageElement(
        id: _asString(json['id']),
        x: _asDouble(json['x']),
        y: _asDouble(json['y']),
        width: _asDouble(json['width']),
        height: _asDouble(json['height']),
        zIndex: _asInt(json['zIndex']),
        locked: _asBool(json['locked']),
        visible: _asBool(json['visible'], true),
        rotation: _asInt(json['rotation']),
        src: _asString(json['src']),
        opacity: _asDouble(json['opacity'], 1.0),
        borderRadius: _asDouble(json['borderRadius']),
        objectFit: _parseBoxFit(json['objectFit']),
        hasShadow: _asBool(json['hasShadow']),
      );
}

// ── Logo ────────────────────────────────────────────────────────────────────

class LogoElement extends TemplateElement {
  final String src;
  final double opacity;

  const LogoElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.zIndex,
    required super.locked,
    required super.visible,
    super.rotation,
    required this.src,
    required this.opacity,
  }) : super(type: ElementType.logo);

  factory LogoElement.defaults({
    double x = 30,
    double y = 30,
    double width = 120,
    double height = 60,
    int zIndex = 0,
    String src = '',
  }) =>
      LogoElement(
        id: TemplateElement._newId(),
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: zIndex,
        locked: false,
        visible: true,
        src: src,
        opacity: 1.0,
      );

  LogoElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? locked,
    bool? visible,
    int? rotation,
    String? src,
    double? opacity,
  }) =>
      LogoElement(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        zIndex: zIndex ?? this.zIndex,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        rotation: rotation ?? this.rotation,
        src: src ?? this.src,
        opacity: opacity ?? this.opacity,
      );

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'src': src,
        'opacity': opacity,
      };

  factory LogoElement.fromJson(Map<String, dynamic> json) => LogoElement(
        id: _asString(json['id']),
        x: _asDouble(json['x']),
        y: _asDouble(json['y']),
        width: _asDouble(json['width']),
        height: _asDouble(json['height']),
        zIndex: _asInt(json['zIndex']),
        locked: _asBool(json['locked']),
        visible: _asBool(json['visible'], true),
        rotation: _asInt(json['rotation']),
        src: _asString(json['src']),
        opacity: _asDouble(json['opacity'], 1.0),
      );
}

// ── Table ───────────────────────────────────────────────────────────────────

class TableData {
  final List<String> headers;
  final List<List<String>> rows;

  const TableData({required this.headers, required this.rows});

  TableData copyWith({List<String>? headers, List<List<String>>? rows}) =>
      TableData(
        headers: headers ?? this.headers,
        rows: rows ?? this.rows,
      );

  Map<String, dynamic> toJson() => {
        'headers': headers,
        'rows': rows,
      };

  factory TableData.fromJson(Map<String, dynamic> json) => TableData(
        headers: ((json['headers'] as List?) ?? const [])
            .map((value) => _asString(value))
            .toList(),
        rows: ((json['rows'] as List?) ?? const [])
            .map((r) => ((r as List?) ?? const [])
                .map((value) => _asString(value))
                .toList())
            .toList(),
      );
}

class TableStyleData {
  final Color headerBg;
  final Color borderColor;
  final double cellPadding;
  final bool alternateRows;
  final Color alternateRowColor;

  const TableStyleData({
    required this.headerBg,
    required this.borderColor,
    required this.cellPadding,
    required this.alternateRows,
    required this.alternateRowColor,
  });

  TableStyleData copyWith({
    Color? headerBg,
    Color? borderColor,
    double? cellPadding,
    bool? alternateRows,
    Color? alternateRowColor,
  }) =>
      TableStyleData(
        headerBg: headerBg ?? this.headerBg,
        borderColor: borderColor ?? this.borderColor,
        cellPadding: cellPadding ?? this.cellPadding,
        alternateRows: alternateRows ?? this.alternateRows,
        alternateRowColor: alternateRowColor ?? this.alternateRowColor,
      );

  Map<String, dynamic> toJson() => {
        'headerBg': headerBg.toARGB32(),
        'borderColor': borderColor.toARGB32(),
        'cellPadding': cellPadding,
        'alternateRows': alternateRows,
        'alternateRowColor': alternateRowColor.toARGB32(),
      };

  factory TableStyleData.fromJson(Map<String, dynamic> json) => TableStyleData(
        headerBg: _parseColor(json['headerBg'], 0xFF0284C7),
        borderColor: _parseColor(json['borderColor'], 0xFFCBD5E1),
        cellPadding: _asDouble(json['cellPadding'], 6),
        alternateRows: _asBool(json['alternateRows']),
        alternateRowColor: _parseColor(json['alternateRowColor'], 0xFFF8FAFC),
      );

  static TableStyleData get defaults => const TableStyleData(
        headerBg: Color(0xFF0284C7),
        borderColor: Color(0xFFCBD5E1),
        cellPadding: 6,
        alternateRows: false,
        alternateRowColor: Color(0xFFF8FAFC),
      );
}

class TableElement extends TemplateElement {
  final TableData tableData;
  final TableStyleData tableStyle;

  const TableElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.zIndex,
    required super.locked,
    required super.visible,
    super.rotation,
    required this.tableData,
    required this.tableStyle,
  }) : super(type: ElementType.table);

  factory TableElement.defaults({
    double x = 30,
    double y = 100,
    double width = 535,
    double height = 120,
    int zIndex = 0,
  }) =>
      TableElement(
        id: TemplateElement._newId(),
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: zIndex,
        locked: false,
        visible: true,
        tableData: const TableData(
          headers: ['Description', 'Qty', 'Unit Price', 'Total'],
          rows: [
            ['Labour — Site Preparation', '8 hrs', '\$85.00', '\$680.00'],
            ['Materials — Concrete Mix', '20 bags', '\$18.50', '\$370.00'],
          ],
        ),
        tableStyle: TableStyleData.defaults,
      );

  TableElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? locked,
    bool? visible,
    int? rotation,
    TableData? tableData,
    TableStyleData? tableStyle,
  }) =>
      TableElement(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        zIndex: zIndex ?? this.zIndex,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        rotation: rotation ?? this.rotation,
        tableData: tableData ?? this.tableData,
        tableStyle: tableStyle ?? this.tableStyle,
      );

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'tableData': tableData.toJson(),
        'tablestyle': tableStyle.toJson(),
      };

  factory TableElement.fromJson(Map<String, dynamic> json) {
    final rawTableData =
        json.containsKey('tableData') ? json['tableData'] : json['table_data'];
    final rawTableStyle = json.containsKey('tablestyle')
        ? json['tablestyle']
        : json['tableStyle'];
    final tableStyleMap = _asMap(rawTableStyle);

    return TableElement(
      id: _asString(json['id']),
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      width: _asDouble(json['width']),
      height: _asDouble(json['height']),
      zIndex: _asInt(json['zIndex']),
      locked: _asBool(json['locked']),
      visible: _asBool(json['visible'], true),
      rotation: _asInt(json['rotation']),
      tableData: TableData.fromJson(_asMap(rawTableData)),
      tableStyle: rawTableStyle is Map
          ? TableStyleData.fromJson(tableStyleMap)
          : TableStyleData.defaults,
    );
  }
}

// ── Signature Block ──────────────────────────────────────────────────────────

class SignatureBlockElement extends TemplateElement {
  final String signatureLabel;
  final String dateLabel;
  final String signatureValue;
  final String dateValue;

  const SignatureBlockElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.zIndex,
    required super.locked,
    required super.visible,
    super.rotation,
    this.signatureLabel = 'Signature',
    this.dateLabel = 'Date',
    this.signatureValue = '',
    this.dateValue = '',
  }) : super(type: ElementType.signatureBlock);

  factory SignatureBlockElement.defaults({
    double x = 30,
    double y = 740,
    double width = 250,
    double height = 60,
    int zIndex = 0,
  }) =>
      SignatureBlockElement(
        id: TemplateElement._newId(),
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: zIndex,
        locked: false,
        visible: true,
        signatureLabel: 'Signature',
        dateLabel: 'Date',
      );

  SignatureBlockElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? locked,
    bool? visible,
    int? rotation,
    String? signatureLabel,
    String? dateLabel,
    String? signatureValue,
    String? dateValue,
  }) =>
      SignatureBlockElement(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        zIndex: zIndex ?? this.zIndex,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        rotation: rotation ?? this.rotation,
        signatureLabel: signatureLabel ?? this.signatureLabel,
        dateLabel: dateLabel ?? this.dateLabel,
        signatureValue: signatureValue ?? this.signatureValue,
        dateValue: dateValue ?? this.dateValue,
      );

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'signatureLabel': signatureLabel,
        'dateLabel': dateLabel,
        'signatureValue': signatureValue,
        'dateValue': dateValue,
      };

  factory SignatureBlockElement.fromJson(Map<String, dynamic> json) =>
      SignatureBlockElement(
        id: _asString(json['id']),
        x: _asDouble(json['x']),
        y: _asDouble(json['y']),
        width: _asDouble(json['width']),
        height: _asDouble(json['height']),
        zIndex: _asInt(json['zIndex']),
        locked: _asBool(json['locked']),
        visible: _asBool(json['visible'], true),
        rotation: _asInt(json['rotation']),
        signatureLabel: _asString(json['signatureLabel'], 'Signature'),
        dateLabel: _asString(json['dateLabel'], 'Date'),
        signatureValue: _asString(json['signatureValue']),
        dateValue: _asString(json['dateValue']),
      );
}

// ── Divider ──────────────────────────────────────────────────────────────────

enum DividerOrientation { horizontal, vertical }

enum DividerDashStyle { solid, dashed, dotted }

class DividerElement extends TemplateElement {
  final DividerOrientation orientation;
  final double thickness;
  final Color color;
  final DividerDashStyle dashStyle;

  const DividerElement({
    required super.id,
    required super.x,
    required super.y,
    required super.width,
    required super.height,
    required super.zIndex,
    required super.locked,
    required super.visible,
    super.rotation,
    required this.orientation,
    required this.thickness,
    required this.color,
    required this.dashStyle,
  }) : super(type: ElementType.divider);

  factory DividerElement.defaults({
    double x = 30,
    double y = 80,
    double width = 535,
    double height = 2,
    int zIndex = 0,
  }) =>
      DividerElement(
        id: TemplateElement._newId(),
        x: x,
        y: y,
        width: width,
        height: height,
        zIndex: zIndex,
        locked: false,
        visible: true,
        orientation: DividerOrientation.horizontal,
        thickness: 1,
        color: const Color(0xFFCBD5E1),
        dashStyle: DividerDashStyle.solid,
      );

  DividerElement copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    int? zIndex,
    bool? locked,
    bool? visible,
    int? rotation,
    DividerOrientation? orientation,
    double? thickness,
    Color? color,
    DividerDashStyle? dashStyle,
  }) =>
      DividerElement(
        id: id ?? this.id,
        x: x ?? this.x,
        y: y ?? this.y,
        width: width ?? this.width,
        height: height ?? this.height,
        zIndex: zIndex ?? this.zIndex,
        locked: locked ?? this.locked,
        visible: visible ?? this.visible,
        rotation: rotation ?? this.rotation,
        orientation: orientation ?? this.orientation,
        thickness: thickness ?? this.thickness,
        color: color ?? this.color,
        dashStyle: dashStyle ?? this.dashStyle,
      );

  @override
  Map<String, dynamic> toJson() => {
        ..._baseJson(),
        'orientation': orientation == DividerOrientation.horizontal
            ? 'horizontal'
            : 'vertical',
        'thickness': thickness,
        'color': color.toARGB32(),
        'dashStyle': dashStyle.name,
      };

  factory DividerElement.fromJson(Map<String, dynamic> json) => DividerElement(
        id: _asString(json['id']),
        x: _asDouble(json['x']),
        y: _asDouble(json['y']),
        width: _asDouble(json['width']),
        height: _asDouble(json['height']),
        zIndex: _asInt(json['zIndex']),
        locked: _asBool(json['locked']),
        visible: _asBool(json['visible'], true),
        rotation: _asInt(json['rotation']),
        orientation: _asString(json['orientation']).toLowerCase() == 'vertical'
            ? DividerOrientation.vertical
            : DividerOrientation.horizontal,
        thickness: _asDouble(json['thickness'], 1),
        color: _parseColor(json['color'], 0xFFCBD5E1),
        dashStyle: DividerDashStyle.values.firstWhere(
          (s) => s.name == _asString(json['dashStyle']),
          orElse: () => DividerDashStyle.solid,
        ),
      );
}
