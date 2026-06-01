// Purpose: Represents a single image frame captured during a video feed session.
import 'dart:typed_data';

class CapturedFrame {
  const CapturedFrame({
    required this.bytes,
    required this.capturedAt,
    required this.secondsElapsed,
  });

  /// Raw JPEG bytes of the captured image.
  final Uint8List bytes;

  /// Wall-clock time when the frame was captured.
  final DateTime capturedAt;

  /// Seconds into the recording session when this frame was captured.
  final int secondsElapsed;
}
