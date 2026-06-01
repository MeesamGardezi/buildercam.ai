// Purpose: Model for a saved AI-generated Scope of Work document.
class SowDocumentModel {
  const SowDocumentModel({
    required this.id,
    required this.projectId,
    required this.title,
    required this.content,
    required this.transcriptIds,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.frameUrls = const [],
    this.pdfData,
  });

  final String id;
  final String projectId;
  final String title;
  final String content;
  final List<String> transcriptIds;
  final List<String> frameUrls;
  /// Serialised PDF layout — present when the user has saved a PDF for this SOW.
  final Map<String, dynamic>? pdfData;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get hasPdf => pdfData != null;

  factory SowDocumentModel.fromJson(Map<String, dynamic> json) {
    return SowDocumentModel(
      id: json['id'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      title: json['title'] as String? ?? 'Untitled SOW',
      content: json['content'] as String? ?? '',
      transcriptIds: (json['transcriptIds'] as List<dynamic>?)
              ?.cast<String>()
              .toList(growable: false) ??
          const [],
      frameUrls: (json['frameUrls'] as List<dynamic>?)
              ?.cast<String>()
              .toList(growable: false) ??
          const [],
      pdfData: json['pdfData'] is Map
          ? Map<String, dynamic>.from(json['pdfData'] as Map)
          : null,
      createdBy: json['createdBy'] as String? ?? '',
      createdAt: _parseDate(json['createdAt']),
      updatedAt: _parseDate(json['updatedAt']),
    );
  }

  SowDocumentModel copyWith({
    String? title,
    String? content,
    List<String>? transcriptIds,
    List<String>? frameUrls,
    Map<String, dynamic>? pdfData,
    DateTime? updatedAt,
  }) {
    return SowDocumentModel(
      id: id,
      projectId: projectId,
      title: title ?? this.title,
      content: content ?? this.content,
      transcriptIds: transcriptIds ?? this.transcriptIds,
      frameUrls: frameUrls ?? this.frameUrls,
      pdfData: pdfData ?? this.pdfData,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
