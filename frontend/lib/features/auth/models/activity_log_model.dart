// Purpose: Model for a single activity log entry visible to users and owners.

/// Known action constants — used for display labels and icons.
class ActivityLogAction {
  static const String login = 'login';
  static const String logout = 'logout';
  static const String createProject = 'create_project';
  static const String updateProject = 'update_project';
  static const String deleteProject = 'delete_project';
  static const String startRecording = 'start_recording';
  static const String stopRecording = 'stop_recording';
  static const String transcriptionSaved = 'transcription_saved';
  static const String exportDocument = 'export_document';
  static const String viewDocument = 'view_document';
  static const String teamMemberAdded = 'team_member_added';
  static const String teamMemberRemoved = 'team_member_removed';
  static const String permissionsUpdated = 'permissions_updated';
}

class ActivityLogEntry {
  const ActivityLogEntry({
    required this.id,
    required this.companyId,
    required this.userId,
    required this.userEmail,
    required this.userName,
    required this.action,
    required this.timestamp,
    this.projectId,
    this.projectName,
    this.details,
  });

  factory ActivityLogEntry.fromJson(Map<String, dynamic> json) {
    return ActivityLogEntry(
      id: json['id'] as String? ?? '',
      companyId: json['companyId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      userEmail: json['userEmail'] as String? ?? '',
      userName: json['userName'] as String? ?? '',
      action: json['action'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      projectId: json['projectId'] as String?,
      projectName: json['projectName'] as String?,
      details: json['details'] as String?,
    );
  }

  final String id;
  final String companyId;
  final String userId;
  final String userEmail;
  final String userName;
  final String action;
  final String timestamp;
  final String? projectId;
  final String? projectName;
  final String? details;

  /// Human-readable label for the action type.
  String get actionLabel => switch (action) {
    ActivityLogAction.login => 'Logged in',
    ActivityLogAction.logout => 'Logged out',
    ActivityLogAction.createProject => 'Created project',
    ActivityLogAction.updateProject => 'Updated project',
    ActivityLogAction.deleteProject => 'Deleted project',
    ActivityLogAction.startRecording => 'Started recording',
    ActivityLogAction.stopRecording => 'Stopped recording',
    ActivityLogAction.transcriptionSaved => 'Transcription saved',
    ActivityLogAction.exportDocument => 'Exported document',
    ActivityLogAction.viewDocument => 'Viewed document',
    ActivityLogAction.teamMemberAdded => 'Team member added',
    ActivityLogAction.teamMemberRemoved => 'Team member removed',
    ActivityLogAction.permissionsUpdated => 'Permissions updated',
    _ => action.replaceAll('_', ' '),
  };

  DateTime? get parsedTimestamp {
    if (timestamp.isEmpty) return null;
    return DateTime.tryParse(timestamp);
  }
}
