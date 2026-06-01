// Purpose: Uploads captured video frames to Firebase Storage and returns
// public download URLs.
import 'package:firebase_storage/firebase_storage.dart';

import '../models/captured_frame.dart';

class VideoFrameStorageService {
  const VideoFrameStorageService();

  /// Uploads all [frames] under `projects/{projectId}/frames/{sessionMs}/`
  /// and returns a list of download URLs in capture order.
  ///
  /// Silently skips any frame that fails to upload so a single bad frame
  /// does not abort the whole session.
  Future<List<String>> uploadFrames({
    required String projectId,
    required List<CapturedFrame> frames,
  }) async {
    if (frames.isEmpty) return const [];

    final storage = FirebaseStorage.instance;
    final sessionMs = DateTime.now().millisecondsSinceEpoch;
    final urls = <String>[];

    Object? firstError;
    for (final frame in frames) {
      try {
        final path =
            'projects/$projectId/frames/$sessionMs/'
            '${frame.capturedAt.millisecondsSinceEpoch}.jpg';
        final ref = storage.ref(path);
        await ref.putData(
          frame.bytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );
        urls.add(await ref.getDownloadURL());
      } catch (e) {
        firstError ??= e;
        // Continue trying remaining frames.
      }
    }

    // Surface the error so callers know uploads failed.
    if (urls.isEmpty && firstError != null) {
      // ignore: only_throw_errors
      throw firstError;
    }
    return urls;
  }
}
