import 'dart:developer' as dev;

import 'package:http/http.dart' as http;

/// HTTP client wrapper that logs every request and response to the Dart
/// developer console (visible in DevTools → Logging, and `flutter run` output).
///
/// Usage:
///   final client = LoggingHttpClient();
///   final response = await client.get(Uri.parse('https://...'));
///
/// Automatically used by PdfExportService when [LoggingHttpClient] is injected.
class LoggingHttpClient extends http.BaseClient {
  final http.Client _inner;

  LoggingHttpClient([http.Client? inner]) : _inner = inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final stopwatch = Stopwatch()..start();

    _log('→ ${request.method} ${request.url}', level: 500);

    try {
      final response = await _inner.send(request);
      stopwatch.stop();

      final level = response.statusCode >= 500
          ? 1000
          : response.statusCode >= 400
              ? 900
              : 500;

      _log(
        '← ${response.statusCode} ${request.method} ${request.url} '
        '(${stopwatch.elapsedMilliseconds}ms)',
        level: level,
      );

      return response;
    } catch (e) {
      stopwatch.stop();
      _log(
        '✗ ${request.method} ${request.url} failed after '
        '${stopwatch.elapsedMilliseconds}ms: $e',
        level: 1000,
      );
      rethrow;
    }
  }

  @override
  void close() => _inner.close();

  static void _log(String message, {int level = 500}) {
    dev.log(message, name: 'HTTP', level: level);
  }
}
