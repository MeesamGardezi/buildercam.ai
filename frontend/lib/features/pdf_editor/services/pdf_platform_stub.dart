import 'dart:io';
import 'dart:typed_data';

import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

/// Saves [bytes] to the system temp directory and opens the file with
/// the platform's default application for [mimeType].
/// Called on Android, iOS, macOS, Windows, and Linux — anywhere that is
/// not compiled with dart:html.
void triggerWebDownload({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
}) =>
    _saveAndOpen(bytes, fileName);

Object? prepareWebPrintTarget() => null;

void openWebBlob({
  required Uint8List bytes,
  required String mimeType,
  Object? printTarget,
}) =>
    _saveAndOpen(bytes, 'document.pdf');

void _saveAndOpen(Uint8List bytes, String fileName) {
  // Fire-and-forget: callers are synchronous void; errors are silently dropped
  // because there is nothing meaningful to surface to the user at call-site.
  Future<void>(() async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      await OpenFile.open(file.path);
    } catch (_) {}
  });
}
