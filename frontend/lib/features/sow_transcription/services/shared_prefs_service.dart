import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sow_chat_message.dart';

class SowSettings {
  const SowSettings({
    this.specialInstructions = '',
    this.notes = '',
    this.includeMaterials = true,
    this.includeEstimate = true,
  });

  final String specialInstructions;
  final String notes;
  final bool includeMaterials;
  final bool includeEstimate;
}

class SowSharedPrefsService {
  static const String _keyDraft = 'sow_draft_transcript';
  static const String _keyProjectId = 'sow_draft_project_id';
  static const String _keyDuration = 'sow_draft_duration_seconds';
  static const String _keyTranscriptId = 'sow_draft_transcript_id';
  static const String _keySavedAt = 'sow_draft_saved_at';

  Future<void> saveDraft({
    required String projectId,
    required String transcript,
    required int durationSeconds,
    String? transcriptId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.setString(_keyDraft, transcript),
      prefs.setString(_keyProjectId, projectId),
      prefs.setInt(_keyDuration, durationSeconds),
      prefs.setString(_keySavedAt, DateTime.now().toIso8601String()),
      if (transcriptId != null)
        prefs.setString(_keyTranscriptId, transcriptId)
      else
        prefs.remove(_keyTranscriptId),
    ]);
  }

  Future<SowDraftSnapshot?> loadDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final transcript = prefs.getString(_keyDraft);
    final projectId = prefs.getString(_keyProjectId);
    if (transcript == null || transcript.trim().isEmpty) {
      return null;
    }

    return SowDraftSnapshot(
      projectId: projectId ?? '',
      transcript: transcript,
      durationSeconds: prefs.getInt(_keyDuration) ?? 0,
      transcriptId: prefs.getString(_keyTranscriptId),
      savedAt:
          DateTime.tryParse(prefs.getString(_keySavedAt) ?? '') ??
          DateTime.now(),
    );
  }

  Future<void> clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.remove(_keyDraft),
      prefs.remove(_keyProjectId),
      prefs.remove(_keyDuration),
      prefs.remove(_keyTranscriptId),
      prefs.remove(_keySavedAt),
    ]);
  }

  // ── SOW Generation Settings ───────────────────────────────────────────────

  static const String _keySpecialInstructions =
      'sow_settings_special_instructions';
  static const String _keySettingsNotes = 'sow_settings_notes';
  static const String _keyIncludeMaterials = 'sow_settings_include_materials';
  static const String _keyIncludeEstimate = 'sow_settings_include_estimate';

  Future<SowSettings> loadSowSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return SowSettings(
      specialInstructions: prefs.getString(_keySpecialInstructions) ?? '',
      notes: prefs.getString(_keySettingsNotes) ?? '',
      includeMaterials: prefs.getBool(_keyIncludeMaterials) ?? true,
      includeEstimate: prefs.getBool(_keyIncludeEstimate) ?? true,
    );
  }

  Future<void> saveSowSettings(SowSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait(<Future<bool>>[
      prefs.setString(_keySpecialInstructions, settings.specialInstructions),
      prefs.setString(_keySettingsNotes, settings.notes),
      prefs.setBool(_keyIncludeMaterials, settings.includeMaterials),
      prefs.setBool(_keyIncludeEstimate, settings.includeEstimate),
    ]);
  }

  // ── Voice assistant conversation history ─────────────────────────────────
  // Stored newest-first, capped so prefs stay small.

  static const String _keyVoiceHistory = 'sow_voice_history';
  static const int _voiceHistoryLimit = 20;

  Future<void> addVoiceConversation(SowVoiceConversation conversation) async {
    if (conversation.messages.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final existing = await loadVoiceConversations();
    final updated = <SowVoiceConversation>[conversation, ...existing]
        .take(_voiceHistoryLimit)
        .map((c) => c.toJson())
        .toList(growable: false);
    await prefs.setString(_keyVoiceHistory, jsonEncode(updated));
  }

  Future<List<SowVoiceConversation>> loadVoiceConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyVoiceHistory);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SowVoiceConversation.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearVoiceConversations() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyVoiceHistory);
  }

  // ── PDF editor draft ─────────────────────────────────────────────────────
  // Key: pdf_draft_<projectId>_<sowId>
  String _pdfDraftKey(String projectId, String sowId) =>
      'pdf_draft_${projectId}_$sowId';

  Future<void> savePdfDraft(
      String projectId, String sowId, Map<String, dynamic> pdfJson) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pdfDraftKey(projectId, sowId), jsonEncode(pdfJson));
  }

  Future<Map<String, dynamic>?> loadPdfDraft(
      String projectId, String sowId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pdfDraftKey(projectId, sowId));
    if (raw == null) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPdfDraft(String projectId, String sowId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pdfDraftKey(projectId, sowId));
  }
}

class SowDraftSnapshot {
  const SowDraftSnapshot({
    required this.projectId,
    required this.transcript,
    required this.durationSeconds,
    this.transcriptId,
    required this.savedAt,
  });

  final String projectId;
  final String transcript;
  final int durationSeconds;
  final String? transcriptId;
  final DateTime savedAt;
}
