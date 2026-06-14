// Purpose: Structures SOW text via the backend (Gemini) and returns parsed sections.
import 'dart:convert';

import 'package:buildercam/core/core.dart';
import 'package:buildercam/features/pdf_editor/models/pdf_document_data.dart';
import 'package:http/http.dart' as http;

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

enum SowPdfItemType { paragraph, bullet, numbered }

class SowPdfItem {
  const SowPdfItem({required this.type, required this.text});
  final SowPdfItemType type;
  final String text;
}

class SowPdfSection {
  const SowPdfSection({required this.heading, required this.items});
  final String heading;
  final List<SowPdfItem> items;
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

/// Parses a raw SOW string into [SowPdfSection]s via the backend (which calls
/// Gemini using the server-side API key).
class SowPdfService {
  const SowPdfService();

  // ── Public API ──────────────────────────────────────────────────────────

  /// Structures [sowText] by calling the backend `/structure-sow` endpoint.
  /// Throws on network or server failure so callers can surface a clear error.
  /// [instructions] is an optional user note passed verbatim into the prompt.
  /// [tokenProvider] returns a Firebase ID token for backend auth.
  Future<List<SowPdfSection>> structureSow(
    String sowText, {
    String instructions = '',
    Future<String?> Function()? tokenProvider,
  }) async {
    if (sowText.trim().isEmpty) return const [];

    final token = await tokenProvider?.call();
    final resp = await http
        .post(
          Uri.parse('${ApiConfig.sowProxyBaseUrl}/api/sow-transcription/structure-sow'),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({'sowText': sowText, 'instructions': instructions}),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode != 200) {
      throw StateError('Structure SOW failed (${resp.statusCode}): ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['sections'] as List<dynamic>?) ?? [];
    return list.map((e) {
      final m = e as Map<String, dynamic>;
      final rawItems = (m['items'] as List<dynamic>?) ?? [];
      return SowPdfSection(
        heading: m['heading'] as String? ?? '',
        items: rawItems.map((i) {
          final im = i as Map<String, dynamic>;
          final type = switch (im['type'] as String? ?? '') {
            'bullet' => SowPdfItemType.bullet,
            'numbered' => SowPdfItemType.numbered,
            _ => SowPdfItemType.paragraph,
          };
          return SowPdfItem(type: type, text: im['text'] as String? ?? '');
        }).toList(),
      );
    }).toList();
  }

  /// AI-generates a complete, ready-to-edit PDF layout from [sowText] by calling
  /// the backend `/projects/:projectId/generate-pdf-layout` endpoint. Gemini
  /// emits the full element list (positions, styles, colours, content), so the
  /// result is dropped straight into [PdfEditorWidget] — no client-side layout.
  ///
  /// When [pdfTemplate] is supplied (the raw template map with a `pdfJson` key),
  /// its branding/structural elements (logos, banners, dividers, signature
  /// blocks) are preserved and the SOW content is laid out around them.
  ///
  /// Throws on network or server failure so callers can surface a clear error.
  Future<PdfDocumentData> generatePdfLayout({
    required String projectId,
    required String sowText,
    String instructions = '',
    String projectName = '',
    String clientName = '',
    String siteLocation = '',
    Map<String, dynamic>? pdfTemplate,
    Future<String?> Function()? tokenProvider,
  }) async {
    if (sowText.trim().isEmpty) {
      throw StateError('Cannot generate a PDF layout from empty SOW text.');
    }

    final token = await tokenProvider?.call();
    final resp = await http
        .post(
          Uri.parse(
            '${ApiConfig.sowProxyBaseUrl}'
            '/api/sow-transcription/projects/$projectId/generate-pdf-layout',
          ),
          headers: {
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'sowText': sowText,
            'instructions': instructions,
            'projectName': projectName,
            'clientName': clientName,
            'siteLocation': siteLocation,
            if (pdfTemplate != null) 'pdfTemplate': pdfTemplate,
          }),
        )
        .timeout(const Duration(seconds: 120));

    if (resp.statusCode != 200) {
      throw StateError('AI PDF layout failed (${resp.statusCode}): ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    // Backend returns { success, pageSize, elements } — PdfDocumentData.fromJson
    // reads pageSize + elements directly and skips any malformed element.
    return PdfDocumentData.fromJson(data);
  }
}