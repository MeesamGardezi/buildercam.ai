// Purpose: Calls the backend API for project and transcript persistence.
import 'dart:convert';

import 'package:buildercam/core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/sow_log_entry.dart';
import '../models/sow_document_model.dart';
import '../models/sow_template_model.dart';
import '../models/sow_transcript_model.dart';
import '../models/pdf_document_model.dart';
import 'shared_prefs_service.dart';

/// Thrown when the backend returns 403 for the current user.
/// Callers can catch this to silently degrade (e.g. hide a project the
/// member doesn't have view permission on) instead of surfacing an error.
class SowPermissionException implements Exception {
  SowPermissionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SowBackendService {
  SowBackendService({http.Client? client, this.tokenProvider})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// Optional callback to retrieve the current Firebase ID token.
  final Future<String?> Function()? tokenProvider;
  final ValueNotifier<List<SowLogEntry>> logs =
      ValueNotifier<List<SowLogEntry>>(<SowLogEntry>[]);

  Uri get _baseUri => Uri.parse(ApiConfig.sowProxyBaseUrl);

  void dispose() {
    logs.dispose();
    _client.close();
  }

  Future<SowTranscriptModel> saveTranscript({
    required String projectId,
    String? id,
    required String text,
    required int duration,
    required DateTime createdAt,
    String createdBy = 'frontend-user',
    List<String> frameUrls = const [],
    String? title,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/sow-transcription/projects/$projectId/transcripts',
      body: <String, dynamic>{
        if (id != null) 'id': id,
        'rawTranscript': text,
        'durationSeconds': duration,
        'createdAt': createdAt.toIso8601String(),
        'createdBy': createdBy,
        if (frameUrls.isNotEmpty) 'frameUrls': frameUrls,
        if (title != null && title.isNotEmpty) 'title': title,
      },
    );

    final payload = _decodeResponse(response);
    return SowTranscriptModel.fromJson(
      payload['transcript'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  Future<List<SowTranscriptModel>> fetchHistory(String projectId) async {
    final response = await _send(
      method: 'GET',
      path: '/api/sow-transcription/projects/$projectId/transcripts',
    );

    final payload = _decodeResponse(response);
    final rawTranscripts = payload['transcripts'];
    if (rawTranscripts is! List) {
      return const <SowTranscriptModel>[];
    }

    return rawTranscripts
        .whereType<Map<String, dynamic>>()
        .map(SowTranscriptModel.fromJson)
        .toList(growable: false);
  }

  Future<void> deleteTranscript(String projectId, String transcriptId) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/sow-transcription/projects/$projectId/transcripts/$transcriptId',
    );
    // Treat 404 as success — transcript already gone (idempotent delete).
    if (response.statusCode != 404) {
      _decodeResponse(response);
    }
  }

  Future<List<SowProjectModel>> fetchProjects() async {
    final response = await _send(
      method: 'GET',
      path: '/api/sow-transcription/projects',
    );

    final payload = _decodeResponse(response);
    final rawProjects = payload['projects'];
    if (rawProjects is! List) {
      return const <SowProjectModel>[];
    }

    return rawProjects
        .whereType<Map<String, dynamic>>()
        .map(SowProjectModel.fromJson)
        .toList(growable: false);
  }

  Future<SowProjectModel> createProject({
    required String name,
    required String clientName,
    required String siteLocation,
    required String scopeSummary,
    required String notes,
    required String createdBy,
    String status = 'planning',
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/sow-transcription/projects',
      body: <String, dynamic>{
        'name': name,
        'clientName': clientName,
        'siteLocation': siteLocation,
        'scopeSummary': scopeSummary,
        'notes': notes,
        'createdBy': createdBy,
        'status': status,
      },
    );

    final payload = _decodeResponse(response);
    return SowProjectModel.fromJson(
      payload['project'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  Future<SowProjectModel?> fetchProject(String projectId) async {
    final response = await _send(
      method: 'GET',
      path: '/api/sow-transcription/projects/$projectId',
    );

    if (response.statusCode == 404) {
      return null;
    }

    final payload = _decodeResponse(response);
    return SowProjectModel.fromJson(
      payload['project'] as Map<String, dynamic>? ?? <String, dynamic>{},
    );
  }

  Future<void> deleteProject(String projectId) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/sow-transcription/projects/$projectId',
    );
    if (response.statusCode != 404) {
      _decodeResponse(response);
    }
  }

  Future<String> generateSow({
    required String projectId,
    required List<String> transcriptIds,
    SowSettings? settings,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/sow-transcription/projects/$projectId/generate-sow',
      body: <String, dynamic>{
        'transcriptIds': transcriptIds,
        if (settings != null) ...{
          'specialInstructions': settings.specialInstructions,
          'notes': settings.notes,
          'includeMaterials': settings.includeMaterials,
          'includeEstimate': settings.includeEstimate,
        },
      },
    );
    final payload = _decodeResponse(response);
    return payload['sow'] as String? ?? '';
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final decoded = _tryDecodeJson(response.body);

    if (response.statusCode >= 400) {
      final serverMessage =
          decoded['message'] as String? ?? decoded['error'] as String?;
      final message = switch (response.statusCode) {
        401 => 'Session expired. Please sign out and sign in again.',
        403 => 'You do not have permission to perform this action.',
        404 => serverMessage ?? 'Resource not found.',
        429 => 'Too many requests. Please wait a moment and try again.',
        >= 500 => serverMessage ?? 'Server error. Please try again later.',
        _ => serverMessage ?? 'Request failed (${response.statusCode}).',
      };
      if (response.statusCode == 403) {
        throw SowPermissionException(message);
      }
      throw StateError(message);
    }

    return decoded;
  }

  Map<String, dynamic> _tryDecodeJson(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      if (kDebugMode) {
        debugPrint('[SOW API] Non-JSON response: $body');
      }
    }

    return <String, dynamic>{};
  }

  Future<http.Response> _send({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    final uri = _baseUri.resolve(path);
    final startedAt = DateTime.now();

    _appendLog(
      source: SowLogSource.backend,
      level: SowLogLevel.info,
      message: '$method ${uri.path}',
      details: body == null ? 'Request started.' : _summarizeBody(body),
    );

    try {
      final token = await tokenProvider?.call();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      late final http.Response response;
      if (method == 'GET') {
        response = await _client.get(uri, headers: headers);
      } else if (method == 'POST') {
        response = await _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        );
      } else if (method == 'DELETE') {
        response = await _client.delete(uri, headers: headers);
      } else if (method == 'PUT') {
        response = await _client.put(
          uri,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        );
      } else {
        throw UnsupportedError('Unsupported method: $method');
      }

      final decoded = _tryDecodeJson(response.body);
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      final message =
          decoded['message'] as String? ??
          decoded['error'] as String? ??
          (response.statusCode >= 400
              ? 'Request failed.'
              : 'Request completed successfully.');

      _appendLog(
        source: SowLogSource.backend,
        level:
            response.statusCode >= 400
                ? SowLogLevel.error
                : SowLogLevel.success,
        message:
            '$method ${uri.path} -> ${response.statusCode} (${durationMs}ms)',
        details: message,
      );

      if (kDebugMode) {
        debugPrint(
          '[SOW API] $method ${uri.path} -> ${response.statusCode} (${durationMs}ms) $message',
        );
      }

      return response;
    } catch (error) {
      _appendLog(
        source: SowLogSource.backend,
        level: SowLogLevel.error,
        message: '$method ${uri.path} failed',
        details: error.toString(),
      );
      rethrow;
    }
  }

  void _appendLog({
    required String source,
    required String level,
    required String message,
    String? details,
  }) {
    final nextEntries = <SowLogEntry>[
      SowLogEntry(
        source: source,
        level: level,
        message: message,
        details: details,
      ),
      ...logs.value,
    ];

    logs.value = nextEntries.take(80).toList(growable: false);
  }

  String _summarizeBody(Map<String, dynamic> body) {
    final json = jsonEncode(body);
    if (json.length <= 180) {
      return json;
    }

    return '${json.substring(0, 180)}...';
  }

  // ── SOW document persistence ─────────────────────────────────────────

  Future<SowDocumentModel> saveSowDocument({
    required String projectId,
    String? id,
    required String title,
    required String content,
    required List<String> transcriptIds,
    List<String> frameUrls = const [],
    Map<String, dynamic>? pdfData,
  }) async {
    final response = await _send(
      method: id == null ? 'POST' : 'PUT',
      path: id == null
          ? '/api/sow-transcription/projects/$projectId/sow-documents'
          : '/api/sow-transcription/projects/$projectId/sow-documents/$id',
      body: <String, dynamic>{
        'title': title,
        'content': content,
        'transcriptIds': transcriptIds,
        if (frameUrls.isNotEmpty) 'frameUrls': frameUrls,
        if (pdfData != null) 'pdfData': pdfData,
      },
    );
    final payload = _decodeResponse(response);
    return SowDocumentModel.fromJson(
      payload['document'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<List<SowDocumentModel>> fetchSowDocuments(String projectId) async {
    final response = await _send(
      method: 'GET',
      path: '/api/sow-transcription/projects/$projectId/sow-documents',
    );
    final payload = _decodeResponse(response);
    final rawDocs = payload['documents'];
    if (rawDocs is! List) return [];
    return rawDocs
        .whereType<Map<String, dynamic>>()
        .map(SowDocumentModel.fromJson)
        .toList();
  }

  Future<SowDocumentModel?> getSowDocument(
    String projectId,
    String sowDocId,
  ) async {
    final response = await _send(
      method: 'GET',
      path:
          '/api/sow-transcription/projects/$projectId/sow-documents/$sowDocId',
    );
    if (response.statusCode == 404) return null;
    final payload = _decodeResponse(response);
    final raw = payload['document'];
    if (raw is! Map<String, dynamic>) return null;
    return SowDocumentModel.fromJson(raw);
  }

  Future<void> deleteSowDocument(String projectId, String sowDocId) async {
    final response = await _send(
      method: 'DELETE',
      path:
          '/api/sow-transcription/projects/$projectId/sow-documents/$sowDocId',
    );
    if (response.statusCode != 404) _decodeResponse(response);
  }

  // ── Standalone PDF documents ──────────────────────────────────────────────

  Future<List<PdfDocumentModel>> fetchPdfDocuments(String projectId) async {
    final response = await _send(
      method: 'GET',
      path: '/api/sow-transcription/projects/$projectId/pdf-documents',
    );
    final payload = _decodeResponse(response);
    final rawDocs = payload['documents'];
    if (rawDocs is! List) return [];
    return rawDocs
        .whereType<Map<String, dynamic>>()
        .map(PdfDocumentModel.fromJson)
        .toList();
  }

  Future<PdfDocumentModel?> getPdfDocument(
    String projectId,
    String pdfDocId,
  ) async {
    final response = await _send(
      method: 'GET',
      path:
          '/api/sow-transcription/projects/$projectId/pdf-documents/$pdfDocId',
    );
    if (response.statusCode == 404) return null;
    final payload = _decodeResponse(response);
    final raw = payload['document'];
    if (raw is! Map<String, dynamic>) return null;
    return PdfDocumentModel.fromJson(raw);
  }

  Future<PdfDocumentModel> savePdfDocument({
    required String projectId,
    String? id,
    required String title,
    required Map<String, dynamic> pdfData,
  }) async {
    final method = id != null ? 'PUT' : 'POST';
    final path = id != null
        ? '/api/sow-transcription/projects/$projectId/pdf-documents/$id'
        : '/api/sow-transcription/projects/$projectId/pdf-documents';
    final response = await _send(
      method: method,
      path: path,
      body: <String, dynamic>{'title': title, 'pdfData': pdfData},
    );
    final payload = _decodeResponse(response);
    final raw = payload['document'];
    if (raw is! Map<String, dynamic>) {
      throw Exception('Unexpected response from savePdfDocument');
    }
    return PdfDocumentModel.fromJson(raw);
  }

  Future<void> deletePdfDocument(String projectId, String pdfDocId) async {
    final response = await _send(
      method: 'DELETE',
      path:
          '/api/sow-transcription/projects/$projectId/pdf-documents/$pdfDocId',
    );
    if (response.statusCode != 404) _decodeResponse(response);
  }

  // ── SOW templates ──────────────────────────────────────────────────

  Future<SowTemplateModel> saveAsTemplate({
    required String name,
    required String content,
  }) async {
    final response = await _send(
      method: 'POST',
      path: '/api/sow-transcription/templates',
      body: <String, dynamic>{'name': name, 'content': content},
    );
    final payload = _decodeResponse(response);
    return SowTemplateModel.fromJson(
      payload['template'] as Map<String, dynamic>? ?? {},
    );
  }

  Future<List<SowTemplateModel>> fetchTemplates() async {
    final response = await _send(
      method: 'GET',
      path: '/api/sow-transcription/templates',
    );
    final payload = _decodeResponse(response);
    final raw = payload['templates'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(SowTemplateModel.fromJson)
        .toList(growable: false);
  }

  Future<void> deleteTemplate(String templateId) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/sow-transcription/templates/$templateId',
    );
    if (response.statusCode != 404) _decodeResponse(response);
  }

  // ── PDF templates (company-level PDF layouts) ──────────────────────

  Future<List<Map<String, dynamic>>> fetchPdfTemplates() async {
    final response = await _send(
      method: 'GET',
      path: '/api/pdf-templates',
    );
    final payload = _decodeResponse(response);
    final raw = payload['templates'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> deletePdfTemplate(String templateId) async {
    final response = await _send(
      method: 'DELETE',
      path: '/api/pdf-templates/$templateId',
    );
    if (response.statusCode != 404) _decodeResponse(response);
  }
}
