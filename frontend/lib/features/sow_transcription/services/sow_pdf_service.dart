// Purpose: Structures SOW text via the backend (Gemini) and returns parsed sections.
import 'dart:convert';

import 'package:buildercam/core/core.dart';
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
        }).toList(growable: false),
      );
    }).toList(growable: false);
  }
}
