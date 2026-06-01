// Purpose: Models for per-project, per-member permission settings.

/// All permission toggles a company owner can set for a team member on a project.
class MemberPermission {
  const MemberPermission({
    required this.uid,
    required this.projectId,
    required this.companyId,
    this.canView = true,
    this.canRecord = false,
    this.canTranscribe = false,
    this.canEditDocument = false,
    this.canExport = false,
    this.canDeleteTranscript = false,
    this.canCreateProject = false,
    this.canEditProject = false,
    this.canDeleteProject = false,
    this.canManageTemplates = false,
    this.canUploadFiles = false,
    this.canViewSow = true,
    this.canCreateSow = false,
    this.canDeleteSow = false,
    this.canViewPdf = true,
    this.canCreatePdf = false,
    this.canDeletePdf = false,
    this.updatedAt,
  });

  factory MemberPermission.fromJson(Map<String, dynamic> json) {
    return MemberPermission(
      uid: json['uid'] as String? ?? '',
      projectId: json['projectId'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      canView: json['canView'] as bool? ?? true,
      canRecord: json['canRecord'] as bool? ?? false,
      canTranscribe: json['canTranscribe'] as bool? ?? false,
      canEditDocument: json['canEditDocument'] as bool? ?? false,
      canExport: json['canExport'] as bool? ?? false,
      canDeleteTranscript: json['canDeleteTranscript'] as bool? ?? false,
      canCreateProject: json['canCreateProject'] as bool? ?? false,
      canEditProject: json['canEditProject'] as bool? ?? false,
      canDeleteProject: json['canDeleteProject'] as bool? ?? false,
      canManageTemplates: json['canManageTemplates'] as bool? ?? false,
      canUploadFiles: json['canUploadFiles'] as bool? ?? false,
      canViewSow: json['canViewSow'] as bool? ?? true,
      canCreateSow: json['canCreateSow'] as bool? ?? false,
      canDeleteSow: json['canDeleteSow'] as bool? ?? false,
      canViewPdf: json['canViewPdf'] as bool? ?? true,
      canCreatePdf: json['canCreatePdf'] as bool? ?? false,
      canDeletePdf: json['canDeletePdf'] as bool? ?? false,
      updatedAt: json['updatedAt'] as String?,
    );
  }

  /// Default (view-only) permission for a member on a project they haven't been configured for yet.
  factory MemberPermission.defaultFor({
    required String uid,
    required String projectId,
    required String companyId,
  }) {
    return MemberPermission(
      uid: uid,
      projectId: projectId,
      companyId: companyId,
    );
  }

  final String uid;
  final String projectId;
  final String companyId;

  final bool canView;
  final bool canRecord;
  final bool canTranscribe;
  final bool canEditDocument;
  final bool canExport;
  final bool canDeleteTranscript;
  final bool canCreateProject;
  final bool canEditProject;
  final bool canDeleteProject;
  final bool canManageTemplates;
  final bool canUploadFiles;
  final bool canViewSow;
  final bool canCreateSow;
  final bool canDeleteSow;
  final bool canViewPdf;
  final bool canCreatePdf;
  final bool canDeletePdf;

  final String? updatedAt;

  MemberPermission copyWith({
    bool? canView,
    bool? canRecord,
    bool? canTranscribe,
    bool? canEditDocument,
    bool? canExport,
    bool? canDeleteTranscript,
    bool? canCreateProject,
    bool? canEditProject,
    bool? canDeleteProject,
    bool? canManageTemplates,
    bool? canUploadFiles,
    bool? canViewSow,
    bool? canCreateSow,
    bool? canDeleteSow,
    bool? canViewPdf,
    bool? canCreatePdf,
    bool? canDeletePdf,
  }) {
    return MemberPermission(
      uid: uid,
      projectId: projectId,
      companyId: companyId,
      canView: canView ?? this.canView,
      canRecord: canRecord ?? this.canRecord,
      canTranscribe: canTranscribe ?? this.canTranscribe,
      canEditDocument: canEditDocument ?? this.canEditDocument,
      canExport: canExport ?? this.canExport,
      canDeleteTranscript: canDeleteTranscript ?? this.canDeleteTranscript,
      canCreateProject: canCreateProject ?? this.canCreateProject,
      canEditProject: canEditProject ?? this.canEditProject,
      canDeleteProject: canDeleteProject ?? this.canDeleteProject,
      canManageTemplates: canManageTemplates ?? this.canManageTemplates,
      canUploadFiles: canUploadFiles ?? this.canUploadFiles,
      canViewSow: canViewSow ?? this.canViewSow,
      canCreateSow: canCreateSow ?? this.canCreateSow,
      canDeleteSow: canDeleteSow ?? this.canDeleteSow,
      canViewPdf: canViewPdf ?? this.canViewPdf,
      canCreatePdf: canCreatePdf ?? this.canCreatePdf,
      canDeletePdf: canDeletePdf ?? this.canDeletePdf,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'projectId': projectId,
    'companyId': companyId,
    'canView': canView,
    'canRecord': canRecord,
    'canTranscribe': canTranscribe,
    'canEditDocument': canEditDocument,
    'canExport': canExport,
    'canDeleteTranscript': canDeleteTranscript,
    'canCreateProject': canCreateProject,
    'canEditProject': canEditProject,
    'canDeleteProject': canDeleteProject,
    'canManageTemplates': canManageTemplates,
    'canUploadFiles': canUploadFiles,
    'canViewSow': canViewSow,
    'canCreateSow': canCreateSow,
    'canDeleteSow': canDeleteSow,
    'canViewPdf': canViewPdf,
    'canCreatePdf': canCreatePdf,
    'canDeletePdf': canDeletePdf,
  };
}
