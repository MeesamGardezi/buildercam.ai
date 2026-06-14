// Purpose: Models for the SOW voice assistant — transcript turns and saved
// conversation history entries.

/// A single transcribed turn in a voice assistant conversation.
class SowChatMessage {
  SowChatMessage.user(this.text)
      : role = 'user',
        isEdit = false;

  SowChatMessage.bot(this.text, {this.isEdit = false}) : role = 'model';

  SowChatMessage._({
    required this.role,
    required this.text,
    required this.isEdit,
  });

  /// 'user' or 'model' — matches the Gemini role names.
  final String role;
  final String text;

  /// True when this turn applied an edit to a SOW document.
  final bool isEdit;

  bool get isUser => role == 'user';

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role,
        'text': text,
        if (isEdit) 'isEdit': true,
      };

  factory SowChatMessage.fromJson(Map<String, dynamic> json) {
    return SowChatMessage._(
      role: json['role'] as String? ?? 'user',
      text: json['text'] as String? ?? '',
      isEdit: json['isEdit'] == true,
    );
  }
}

/// A completed voice assistant conversation, persisted locally as history.
class SowVoiceConversation {
  const SowVoiceConversation({
    required this.projectId,
    required this.projectName,
    required this.startedAt,
    required this.endedAt,
    required this.messages,
  });

  final String projectId;
  final String projectName;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<SowChatMessage> messages;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'projectId': projectId,
        'projectName': projectName,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt.toIso8601String(),
        'messages':
            messages.map((m) => m.toJson()).toList(growable: false),
      };

  factory SowVoiceConversation.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'];
    return SowVoiceConversation(
      projectId: json['projectId'] as String? ?? '',
      projectName: json['projectName'] as String? ?? '',
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '') ??
              DateTime.now(),
      endedAt:
          DateTime.tryParse(json['endedAt'] as String? ?? '') ??
              DateTime.now(),
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map<String, dynamic>>()
              .map(SowChatMessage.fromJson)
              .toList(growable: false)
          : const [],
    );
  }
}
