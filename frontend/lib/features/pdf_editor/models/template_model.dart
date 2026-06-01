import 'element_type.dart';
import 'template_element_model.dart';

class PageSize {
  final double width;
  final double height;

  const PageSize({required this.width, required this.height});

  static const PageSize a4 = PageSize(width: 595, height: 842);

  Map<String, dynamic> toJson() => {'width': width, 'height': height};

  factory PageSize.fromJson(Map<String, dynamic> json) => PageSize(
        width: (json['width'] as num?)?.toDouble() ??
            double.tryParse('${json['width']}') ??
            595,
        height: (json['height'] as num?)?.toDouble() ??
            double.tryParse('${json['height']}') ??
            842,
      );
}

class TemplateModel {
  final String id;
  final String name;
  final TemplateType type;
  final bool isPreset;
  final String? thumbnailUrl;
  final String? pdfUrl;
  final PageSize pageSize;
  final List<TemplateElement> elements;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;

  const TemplateModel({
    required this.id,
    required this.name,
    required this.type,
    required this.isPreset,
    this.thumbnailUrl,
    this.pdfUrl,
    required this.pageSize,
    required this.elements,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
  });

  factory TemplateModel.blank({
    required String id,
    required String name,
    required TemplateType type,
    required String createdBy,
  }) =>
      TemplateModel(
        id: id,
        name: name,
        type: type,
        isPreset: false,
        pageSize: PageSize.a4,
        elements: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        createdBy: createdBy,
      );

  TemplateModel copyWith({
    String? id,
    String? name,
    TemplateType? type,
    bool? isPreset,
    String? thumbnailUrl,
    String? pdfUrl,
    PageSize? pageSize,
    List<TemplateElement>? elements,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
  }) =>
      TemplateModel(
        id: id ?? this.id,
        name: name ?? this.name,
        type: type ?? this.type,
        isPreset: isPreset ?? this.isPreset,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        pdfUrl: pdfUrl ?? this.pdfUrl,
        pageSize: pageSize ?? this.pageSize,
        elements: elements ?? this.elements,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        createdBy: createdBy ?? this.createdBy,
      );

  // Dates serialised as ISO-8601 strings — backend/Firestore handles Timestamps.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.jsonKey,
        'isPreset': isPreset,
        'thumbnailUrl': thumbnailUrl,
        'pdfUrl': pdfUrl,
        'pageSize': pageSize.toJson(),
        'elements': elements.map((e) => e.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'createdBy': createdBy,
      };

  factory TemplateModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
      // Firestore Timestamp-shaped map from the backend REST response
      if (value is Map) {
        final seconds = (value['_seconds'] ?? value['seconds']) as num?;
        if (seconds != null) {
          return DateTime.fromMillisecondsSinceEpoch(seconds.toInt() * 1000);
        }
      }
      return DateTime.now();
    }

    return TemplateModel(
      id: '${json['id'] ?? ''}',
      name: json['name']?.toString() ?? 'Untitled',
      type: TemplateType.fromJson(json['type']?.toString() ?? 'custom'),
      isPreset: json['isPreset'] == true,
      thumbnailUrl: json['thumbnailUrl']?.toString(),
      pdfUrl: json['pdfUrl']?.toString(),
      pageSize: json['pageSize'] != null
          ? PageSize.fromJson(Map<String, dynamic>.from(json['pageSize'] as Map))
          : PageSize.a4,
      elements: (json['elements'] as List<dynamic>? ?? [])
          .map((e) {
            try {
              return TemplateElement.fromJson(
                Map<String, dynamic>.from(e as Map),
              );
            } catch (err) {
              // ignore: avoid_print
              print('[TemplateModel] skipped element: $err — $e');
              return null;
            }
          })
          .whereType<TemplateElement>()
          .toList(),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      createdBy: json['createdBy']?.toString() ?? '',
    );
  }
}
