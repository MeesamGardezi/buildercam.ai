import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../core/logging_http_client.dart';
import '../models/template_element_model.dart';
import '../models/template_model.dart';

class PdfExportService {
  final String _baseUrl;
  final String _companyId;
  final http.Client _client;

  /// Optional project id. When set, it is sent in the body of generate calls
  /// so the backend can enforce per-project `canExport` permission for team
  /// members. Owners bypass the check; null is fine for owner-only flows.
  final String? projectId;

  /// Called before every authenticated request to obtain a fresh Firebase ID
  /// token. When null, no Authorization header is sent.
  final Future<String?> Function()? tokenProvider;

  // Preset thumbnails — cached by presetId, stable for the session.
  final Map<String, Future<Uint8List>> _presetThumbnailCache = {};

  // User-template thumbnails — cached by "$templateId_$updatedAtMs" so a
  // save automatically busts the stale entry on the next home-page visit.
  final Map<String, Future<Uint8List>> _userThumbnailCache = {};

  PdfExportService({
    required String baseUrl,
    String companyId = 'demo-company',
    http.Client? client,
    this.tokenProvider,
    this.projectId,
  })  : _baseUrl = baseUrl,
        _companyId = companyId,
        _client = client ?? LoggingHttpClient();

  Map<String, String> get _baseHeaders => {
        'Content-Type': 'application/json',
        'x-company-id': _companyId,
      };

  /// Returns headers with an Authorization bearer token when [tokenProvider]
  /// is set. Falls back to base headers when not configured.
  Future<Map<String, String>> _authHeaders() async {
    final token = await tokenProvider?.call();
    return {
      ..._baseHeaders,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Generates and returns raw PDF bytes from the backend.
  Future<Uint8List> generatePdfBytes({
    required String templateId,
    required List<TemplateElement> elements,
    required PageSize pageSize,
  }) async {
    final uri = Uri.parse('$_baseUrl/api/templates/$templateId/generate');
    final response = await _client.post(
      uri,
      headers: await _authHeaders(),
      body: jsonEncode({
        'elements': elements.map((e) => e.toJson()).toList(),
        'pageSize': pageSize.toJson(),
        if (projectId != null) 'projectId': projectId,
      }),
    );

    if (response.statusCode != 200) {
      throw PdfExportException(
          'PDF generation failed (${response.statusCode}): ${response.body}');
    }
    return response.bodyBytes;
  }

  /// Returns a PNG thumbnail for a preset template.
  /// Results are cached for the lifetime of this service instance so the
  /// backend is called at most once per preset per session.
  Future<Uint8List> generatePresetThumbnailBytes({
    required String presetId,
  }) =>
      _presetThumbnailCache.putIfAbsent(presetId, () => _fetchPresetThumbnail(presetId));

  Future<Uint8List> _fetchPresetThumbnail(String presetId) async {
    final uri = Uri.parse('$_baseUrl/api/presets/$presetId/thumbnail');
    final response = await _client.post(uri, headers: _baseHeaders, body: jsonEncode({}));
    if (response.statusCode != 200) {
      throw PdfExportException(
          'Preset thumbnail failed (${response.statusCode}): ${response.body}');
    }
    return response.bodyBytes;
  }

  /// Returns a PNG thumbnail for a user-created template.
  ///
  /// The cache key is "${templateId}_${updatedAt.ms}" so a save automatically
  /// invalidates the old entry — no explicit invalidation needed.
  Future<Uint8List> generateUserTemplateThumbnailBytes({
    required TemplateModel template,
  }) {
    final key =
        '${template.id}_${template.updatedAt.millisecondsSinceEpoch}';
    return _userThumbnailCache.putIfAbsent(
      key,
      () => generateThumbnailBytes(
        templateId: template.id,
        elements: template.elements,
        pageSize: template.pageSize,
      ),
    );
  }

  /// Generates a PNG thumbnail and returns the raw bytes.
  Future<Uint8List> generateThumbnailBytes({
    required String templateId,
    required List<TemplateElement> elements,
    required PageSize pageSize,
  }) async {
    final uri =
        Uri.parse('$_baseUrl/api/templates/$templateId/thumbnail');
    final response = await _client.post(
      uri,
      headers: _baseHeaders,
      body: jsonEncode({
        'elements': elements.map((e) => e.toJson()).toList(),
        'pageSize': pageSize.toJson(),
      }),
    );

    if (response.statusCode != 200) {
      throw PdfExportException(
          'Thumbnail generation failed (${response.statusCode}): ${response.body}');
    }
    return response.bodyBytes;
  }

  /// Triggers a platform-native save / share dialog for the generated PDF.
  ///
  /// - Web: browser download
  /// - iOS / Android: system share sheet
  /// - macOS / Windows / Linux: native "Save As" dialog
  Future<Uint8List> downloadPdf({
    required String templateId,
    required List<TemplateElement> elements,
    required PageSize pageSize,
    String? fileName,
  }) async {
    final bytes = await generatePdfBytes(
      templateId: templateId,
      elements: elements,
      pageSize: pageSize,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: fileName ?? 'document.pdf',
    );
    return bytes;
  }

  /// Opens the platform-native print dialog for the generated PDF.
  Future<Uint8List> printPdf({
    required String templateId,
    required List<TemplateElement> elements,
    required PageSize pageSize,
    String? fileName,
  }) async {
    final bytes = await generatePdfBytes(
      templateId: templateId,
      elements: elements,
      pageSize: pageSize,
    );
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      name: fileName ?? 'Document',
    );
    return bytes;
  }

  /// Alias for [downloadPdf] — triggers platform-native share / save.
  Future<Uint8List> sharePdf({
    required String templateId,
    required List<TemplateElement> elements,
    required PageSize pageSize,
    String? fileName,
  }) => downloadPdf(
        templateId: templateId,
        elements: elements,
        pageSize: pageSize,
        fileName: fileName,
      );
}

class PdfExportException implements Exception {
  final String message;
  const PdfExportException(this.message);

  @override
  String toString() => 'PdfExportException: $message';
}
