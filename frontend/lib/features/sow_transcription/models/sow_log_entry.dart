// Purpose: Defines readable activity log entries shared across the SOW flow.

class SowLogLevel {
  static const String info = 'info';
  static const String success = 'success';
  static const String warning = 'warning';
  static const String error = 'error';
}

class SowLogSource {
  static const String backend = 'backend';
  static const String recorder = 'recorder';
  static const String transcription = 'transcription';
}

class SowLogEntry {
  SowLogEntry({
    required this.source,
    required this.level,
    required this.message,
    this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final String source;
  final String level;
  final String message;
  final String? details;
  final DateTime timestamp;
}
