// Purpose: Defines API-backed transcript models for saved SOW recordings.

class SowProjectFields {
  static const String id = 'id';
  static const String name = 'name';
  static const String clientName = 'clientName';
  static const String siteLocation = 'siteLocation';
  static const String scopeSummary = 'scopeSummary';
  static const String notes = 'notes';
  static const String status = 'status';
  static const String createdBy = 'createdBy';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String transcriptCount = 'transcriptCount';
  static const String totalTranscriptSeconds = 'totalTranscriptSeconds';
  static const String lastTranscriptAt = 'lastTranscriptAt';
  static const String latestTranscriptExcerpt = 'latestTranscriptExcerpt';
}

class SowTranscriptFields {
  static const String id = 'id';
  static const String projectId = 'projectId';
  static const String rawTranscript = 'rawTranscript';
  static const String text = 'text';
  static const String durationSeconds = 'durationSeconds';
  static const String duration = 'duration';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
  static const String createdBy = 'createdBy';
  static const String status = 'status';
}

class SowTranscriptStatus {
  static const String completed = 'completed';
  static const String failed = 'failed';
}

class SowProjectModel {
  const SowProjectModel({
    required this.id,
    required this.name,
    required this.clientName,
    required this.siteLocation,
    required this.scopeSummary,
    required this.notes,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.transcriptCount,
    required this.totalTranscriptSeconds,
    required this.lastTranscriptAt,
    required this.latestTranscriptExcerpt,
  });

  final String id;
  final String name;
  final String clientName;
  final String siteLocation;
  final String scopeSummary;
  final String notes;
  final String status;
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int transcriptCount;
  final int totalTranscriptSeconds;
  final DateTime? lastTranscriptAt;
  final String latestTranscriptExcerpt;

  factory SowProjectModel.fromJson(Map<String, dynamic> json) {
    return SowProjectModel(
      id: json[SowProjectFields.id] as String? ?? '',
      name: json[SowProjectFields.name] as String? ?? '',
      clientName: json[SowProjectFields.clientName] as String? ?? '',
      siteLocation: json[SowProjectFields.siteLocation] as String? ?? '',
      scopeSummary: json[SowProjectFields.scopeSummary] as String? ?? '',
      notes: json[SowProjectFields.notes] as String? ?? '',
      status: json[SowProjectFields.status] as String? ?? 'planning',
      createdBy: json[SowProjectFields.createdBy] as String? ?? '',
      createdAt: _parseDate(json[SowProjectFields.createdAt]),
      updatedAt: _parseDate(json[SowProjectFields.updatedAt]),
      transcriptCount:
          json[SowProjectFields.transcriptCount] is int
              ? json[SowProjectFields.transcriptCount] as int
              : int.tryParse(
                    '${json[SowProjectFields.transcriptCount] ?? 0}',
                  ) ??
                  0,
      totalTranscriptSeconds:
          json[SowProjectFields.totalTranscriptSeconds] is int
              ? json[SowProjectFields.totalTranscriptSeconds] as int
              : int.tryParse(
                    '${json[SowProjectFields.totalTranscriptSeconds] ?? 0}',
                  ) ??
                  0,
      lastTranscriptAt: _parseDate(json[SowProjectFields.lastTranscriptAt]),
      latestTranscriptExcerpt:
          json[SowProjectFields.latestTranscriptExcerpt] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      SowProjectFields.id: id,
      SowProjectFields.name: name,
      SowProjectFields.clientName: clientName,
      SowProjectFields.siteLocation: siteLocation,
      SowProjectFields.scopeSummary: scopeSummary,
      SowProjectFields.notes: notes,
      SowProjectFields.status: status,
      SowProjectFields.createdBy: createdBy,
      SowProjectFields.createdAt: createdAt?.toIso8601String(),
      SowProjectFields.updatedAt: updatedAt?.toIso8601String(),
      SowProjectFields.transcriptCount: transcriptCount,
      SowProjectFields.totalTranscriptSeconds: totalTranscriptSeconds,
      SowProjectFields.lastTranscriptAt: lastTranscriptAt?.toIso8601String(),
      SowProjectFields.latestTranscriptExcerpt: latestTranscriptExcerpt,
    };
  }

  String get totalDurationLabel {
    final minutes = totalTranscriptSeconds ~/ 60;
    final seconds = totalTranscriptSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }

  String get statusLabel => status.isEmpty ? 'planning' : status;
}

class SowTranscriptModel {
  const SowTranscriptModel({
    required this.id,
    required this.projectId,
    required this.rawTranscript,
    required this.durationSeconds,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.status,
    this.title,
    this.frameUrls = const [],
  });

  final String id;
  final String projectId;
  final String rawTranscript;
  final int durationSeconds;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String createdBy;
  final String status;
  final String? title;
  final List<String> frameUrls;

  factory SowTranscriptModel.fromJson(Map<String, dynamic> json) {
    final createdAt =
        _parseDate(json[SowTranscriptFields.createdAt]) ??
        DateTime.fromMillisecondsSinceEpoch(0);

    return SowTranscriptModel(
      id: json[SowTranscriptFields.id] as String? ?? '',
      projectId: json[SowTranscriptFields.projectId] as String? ?? '',
      rawTranscript:
          json[SowTranscriptFields.rawTranscript] as String? ??
          json[SowTranscriptFields.text] as String? ??
          '',
      durationSeconds:
          json[SowTranscriptFields.durationSeconds] is int
              ? json[SowTranscriptFields.durationSeconds] as int
              : json[SowTranscriptFields.duration] is int
              ? json[SowTranscriptFields.duration] as int
              : int.tryParse(
                    '${json[SowTranscriptFields.durationSeconds] ?? json[SowTranscriptFields.duration] ?? 0}',
                  ) ??
                  0,
      createdAt: createdAt,
      updatedAt: _parseDate(json[SowTranscriptFields.updatedAt]),
      createdBy: json[SowTranscriptFields.createdBy] as String? ?? '',
      status:
          json[SowTranscriptFields.status] as String? ??
          SowTranscriptStatus.completed,
      title: json['title'] as String?,
      frameUrls:
          (json['frameUrls'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      SowTranscriptFields.id: id,
      SowTranscriptFields.projectId: projectId,
      SowTranscriptFields.rawTranscript: rawTranscript,
      SowTranscriptFields.durationSeconds: durationSeconds,
      SowTranscriptFields.createdAt: createdAt.toIso8601String(),
      SowTranscriptFields.updatedAt: updatedAt?.toIso8601String(),
      SowTranscriptFields.createdBy: createdBy,
      SowTranscriptFields.status: status,
      if (title != null && title!.isNotEmpty) 'title': title,
      if (frameUrls.isNotEmpty) 'frameUrls': frameUrls,
    };
  }

  SowTranscriptModel copyWith({
    String? id,
    String? projectId,
    String? rawTranscript,
    int? durationSeconds,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    String? status,
    String? title,
    List<String>? frameUrls,
  }) {
    return SowTranscriptModel(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      rawTranscript: rawTranscript ?? this.rawTranscript,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      status: status ?? this.status,
      title: title ?? this.title,
      frameUrls: frameUrls ?? this.frameUrls,
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null || value is! String || value.isEmpty) {
    return null;
  }

  return DateTime.tryParse(value);
}
