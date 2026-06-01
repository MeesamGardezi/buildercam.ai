// Purpose: Model for a reusable SOW text template.
class SowTemplateModel {
  const SowTemplateModel({
    required this.id,
    required this.name,
    required this.content,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String content;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory SowTemplateModel.fromJson(Map<String, dynamic> json) {
    return SowTemplateModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Untitled Template',
      content: json['content'] as String? ?? '',
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
