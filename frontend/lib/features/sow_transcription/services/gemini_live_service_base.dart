// import 'dart:convert';
// import 'dart:typed_data';

// const String geminiLiveModel = 'models/gemini-3.1-flash-live-preview';
// const Duration geminiLiveSetupTimeout = Duration(seconds: 10);
// const Duration geminiLiveChunkInterval = Duration(milliseconds: 100);
// const int geminiLiveSampleRate = 16000;
// const int geminiLiveChannelCount = 1;
// const int geminiLiveBytesPerSample = 2;
// const String geminiLiveMimeType = 'audio/pcm;rate=16000';

// abstract class GeminiLiveService {
//   Stream<String> get transcriptStream;
//   Stream<GeminiLiveError> get errorStream;
//   bool get isConnected;

//   Future<void> connect(String apiKey);
//   Future<void> startStreaming();
//   Future<void> stopStreaming();
//   void dispose();
// }

// enum GeminiLiveErrorType {
//   connectionFailed,
//   setupTimeout,
//   micPermissionDenied,
//   micUnavailable,
//   socketClosed,
//   unknown,
// }

// class GeminiLiveError implements Exception {
//   const GeminiLiveError(this.type, this.message);

//   final GeminiLiveErrorType type;
//   final String message;

//   @override
//   String toString() => message;
// }

// Uri buildGeminiLiveUri(String apiKey) {
//   return Uri.parse(
//     'wss://generativelanguage.googleapis.com/ws/'
//     'google.ai.generativelanguage.v1beta.GenerativeService.'
//     'BidiGenerateContent?key=$apiKey',
//   );
// }

// String buildGeminiLiveSetupPayload() {
//   return jsonEncode(<String, dynamic>{
//     'setup': <String, dynamic>{
//       'model': geminiLiveModel,
//       'generationConfig': <String, dynamic>{
//         'responseModalities': <String>['AUDIO'],
//       },
//       'systemInstruction': <String, dynamic>{
//         'parts': <Map<String, String>>[
//           <String, String>{
//             'text':
//                 'Listen to the user and transcribe their speech verbatim. '
//                 'Do not answer questions, summarize, or add commentary.',
//           },
//         ],
//       },
//       'inputAudioTranscription': <String, dynamic>{},
//     },
//   });
// }

// String buildGeminiLiveAudioPayload(String base64Pcm) {
//   return jsonEncode(<String, dynamic>{
//     'realtimeInput': <String, dynamic>{
//       'audio': <String, dynamic>{
//         'mimeType': geminiLiveMimeType,
//         'data': base64Pcm,
//       },
//     },
//   });
// }

// String buildGeminiLiveAudioStreamEndPayload() {
//   return jsonEncode(<String, dynamic>{
//     'realtimeInput': <String, dynamic>{'audioStreamEnd': true},
//   });
// }

// Iterable<String> extractTranscriptTexts(Map<String, dynamic> message) sync* {
//   final topLevelText = (message['text'] as String?)?.trim();
//   if (topLevelText != null && topLevelText.isNotEmpty) {
//     yield topLevelText;
//   }

//   final serverContent = message['serverContent'];
//   if (serverContent is! Map<String, dynamic>) {
//     return;
//   }

//   final inputText =
//       (serverContent['inputTranscription'] as Map<String, dynamic>?)?['text']
//           as String?;
//   if (inputText != null && inputText.trim().isNotEmpty) {
//     yield inputText.trim();
//   }

//   final outputText =
//       (serverContent['outputTranscription'] as Map<String, dynamic>?)?['text']
//           as String?;
//   if (outputText != null && outputText.trim().isNotEmpty) {
//     yield outputText.trim();
//   }

//   final modelTurn = serverContent['modelTurn'];
//   if (modelTurn is Map<String, dynamic>) {
//     final parts = modelTurn['parts'];
//     if (parts is List) {
//       for (final part in parts) {
//         if (part is! Map<String, dynamic>) {
//           continue;
//         }
//         final text = (part['text'] as String?)?.trim();
//         if (text != null && text.isNotEmpty) {
//           yield text;
//         }
//       }
//     }
//   }
// }

// GeminiLiveError parseGeminiLiveError(Object error, {String? fallbackMessage}) {
//   if (error is GeminiLiveError) {
//     return error;
//   }

//   if (error is Map<String, dynamic>) {
//     final message =
//         (error['message'] as String?)?.trim() ??
//         (error['status'] as String?)?.trim() ??
//         fallbackMessage ??
//         'Gemini Live returned an unknown error.';
//     return GeminiLiveError(GeminiLiveErrorType.unknown, message);
//   }

//   final message = error.toString().replaceFirst('Exception: ', '').trim();
//   return GeminiLiveError(
//     GeminiLiveErrorType.unknown,
//     message.isEmpty ? (fallbackMessage ?? 'Gemini Live failed.') : message,
//   );
// }

// Map<String, dynamic>? decodeGeminiLiveMessage(dynamic rawMessage) {
//   final Object? decoded;

//   if (rawMessage is String) {
//     decoded = jsonDecode(rawMessage);
//   } else if (rawMessage is Uint8List) {
//     decoded = jsonDecode(utf8.decode(rawMessage));
//   } else if (rawMessage is ByteBuffer) {
//     decoded = jsonDecode(utf8.decode(rawMessage.asUint8List()));
//   } else if (rawMessage is List<int>) {
//     decoded = jsonDecode(utf8.decode(rawMessage));
//   } else {
//     decoded = jsonDecode(rawMessage.toString());
//   }

//   return decoded is Map<String, dynamic> ? decoded : null;
// }

import 'dart:convert';
import 'dart:typed_data';

// ─── Model & Timing Constants ────────────────────────────────────────────────

const String geminiLiveModel =
    'models/gemini-2.5-flash-native-audio-preview-12-2025';
// NOTE: gemini-3.1-flash-live-preview killed incremental inputTranscription —
// it now only delivers the full transcript AFTER the full utterance ends.
// If you need word-by-word partial transcripts, stay on 2.5.
// If you don't care and just want the final text after each turn, 3.1 is fine.
// Change back to 'models/gemini-3.1-flash-live-preview' if you want 3.1.

const Duration geminiLiveSetupTimeout = Duration(seconds: 10);
const Duration geminiLiveChunkInterval = Duration(milliseconds: 100);

// ─── Audio Format Constants ───────────────────────────────────────────────────

// INPUT  → must be raw 16-bit signed PCM, little-endian, 16 kHz, mono (base64)
// OUTPUT → raw 16-bit signed PCM, little-endian, 24 kHz, mono (base64 in inlineData)
const int geminiLiveInputSampleRate = 16000;
const int geminiLiveOutputSampleRate = 24000; // always 24kHz from server
const int geminiLiveChannelCount = 1;
const int geminiLiveBytesPerSample = 2; // 16-bit = 2 bytes
const String geminiLiveMimeType = 'audio/pcm;rate=16000';

// Compatibility aliases for older code that referenced `geminiLiveSampleRate`.
// Newer names distinguish input/output rates; keep the old name pointing
// to the input sample rate (16kHz) so existing implementations compile.
const int geminiLiveSampleRate = geminiLiveInputSampleRate;

// ─── Abstract Service Interface ───────────────────────────────────────────────

abstract class GeminiLiveService {
  /// Emits transcript text chunks as they arrive from the server.
  /// In VAD-disabled mode on 2.5, these arrive incrementally mid-speech.
  /// On 3.1, these arrive only after activityEnd.
  Stream<String> get transcriptStream;

  Stream<GeminiLiveError> get errorStream;
  bool get isConnected;

  Future<void> connect(String apiKey);

  /// Call when user starts speaking — sends activityStart to Gemini.
  /// Must be called before streaming any audio chunks.
  Future<void> startStreaming();

  /// Call when user stops speaking — sends activityEnd to Gemini.
  /// Gemini will then process audio and return transcript + response.
  Future<void> stopStreaming();

  void dispose();
}

// ─── Error Types ──────────────────────────────────────────────────────────────

enum GeminiLiveErrorType {
  connectionFailed,
  setupTimeout,
  micPermissionDenied,
  micUnavailable,
  socketClosed,
  unknown,
}

class GeminiLiveError implements Exception {
  const GeminiLiveError(this.type, this.message);

  final GeminiLiveErrorType type;
  final String message;

  @override
  String toString() => message;
}

// ─── WebSocket URI ────────────────────────────────────────────────────────────

Uri buildGeminiLiveUri(String apiKey) {
  return Uri.parse(
    'wss://generativelanguage.googleapis.com/ws/'
    'google.ai.generativelanguage.v1beta.GenerativeService.'
    'BidiGenerateContent?key=$apiKey',
  );
}

// ─── Setup Payload ────────────────────────────────────────────────────────────
//
// CHANGES vs original:
//   1. Added realtimeInputConfig.automaticActivityDetection.disabled = true
//      → Kills server-side VAD. YOU now control when a turn starts/ends
//        via activityStart / activityEnd messages.
//   2. Kept inputAudioTranscription — you get inputTranscription in serverContent.
//   3. Added outputAudioTranscription — you get outputTranscription too (optional,
//      remove if you only care about what the user said, not what Gemini said).
//   4. responseModalities stays AUDIO — Gemini still responds with voice.
//      If you ONLY want transcription and no Gemini audio response, switch to TEXT.
//
// WARNING: With VAD disabled, if you never send activityEnd after activityStart,
// Gemini will wait forever and never respond. Always pair them.

String buildGeminiLiveSetupPayload() {
  return jsonEncode(<String, dynamic>{
    'setup': <String, dynamic>{
      'model': geminiLiveModel,
      'generationConfig': <String, dynamic>{
        'responseModalities': <String>['AUDIO'],
      },
      'systemInstruction': <String, dynamic>{
        'parts': <Map<String, String>>[
          <String, String>{
            'text':
                'Listen to the user and transcribe their speech verbatim in English only. '
                'Always output Latin script English text regardless of the speaker\'s accent. '
                'Do not transliterate into Hindi, Urdu, or any other script. '
                'Do not answer questions, summarize, or add commentary.',
          },
        ],
      },
      // Enable input transcription → serverContent.inputTranscription.text
      'inputAudioTranscription': <String, dynamic>{},
      // Enable output transcription → serverContent.outputTranscription.text
      // Remove this if you don't need Gemini's response as text.
      'outputAudioTranscription': <String, dynamic>{},
      // ── DISABLE SERVER VAD ──────────────────────────────────────────────
      // You are now responsible for sending activityStart / activityEnd.
      // No audioStreamEnd needed — activityEnd replaces it entirely.
      'realtimeInputConfig': <String, dynamic>{
        'automaticActivityDetection': <String, dynamic>{'disabled': true},
      },
    },
  });
}

// ─── Client → Server Payloads ─────────────────────────────────────────────────

/// Send this FIRST when the user starts speaking (mic opens / button pressed).
/// Tells Gemini: "the user is now speaking, start buffering audio".
String buildGeminiLiveActivityStartPayload() {
  return jsonEncode(<String, dynamic>{
    'realtimeInput': <String, dynamic>{'activityStart': <String, dynamic>{}},
  });
}

/// Send this continuously while the user is speaking.
/// [base64Pcm] must be raw 16-bit little-endian PCM at 16kHz, base64-encoded.
String buildGeminiLiveAudioPayload(String base64Pcm) {
  return jsonEncode(<String, dynamic>{
    'realtimeInput': <String, dynamic>{
      'audio': <String, dynamic>{
        'mimeType': geminiLiveMimeType,
        'data': base64Pcm,
      },
    },
  });
}

/// Send this when the user stops speaking (mic closed / button released).
/// Tells Gemini: "turn is over, process what you got and respond".
/// This REPLACES audioStreamEnd when VAD is disabled.
String buildGeminiLiveActivityEndPayload() {
  return jsonEncode(<String, dynamic>{
    'realtimeInput': <String, dynamic>{'activityEnd': <String, dynamic>{}},
  });
}

/// DEPRECATED in VAD-disabled mode — DO NOT USE.
/// audioStreamEnd only applies when server VAD is ON.
/// Keeping this here as a tombstone so you don't accidentally re-add it.
@Deprecated(
  'audioStreamEnd is only valid when server VAD is enabled. '
  'Use buildGeminiLiveActivityEndPayload() instead.',
)
String buildGeminiLiveAudioStreamEndPayload() {
  return jsonEncode(<String, dynamic>{
    'realtimeInput': <String, dynamic>{'audioStreamEnd': true},
  });
}

// ─── Server → Client: Transcript Extraction ───────────────────────────────────
//
// Server message structure (only ONE top-level field is set per message):
//
//   { "setupComplete": {} }
//   { "serverContent": {
//       "modelTurn": { "parts": [{ "inlineData": { "mimeType": "audio/pcm;rate=24000", "data": "<b64>" } }] },
//       "inputTranscription": { "text": "what user said" },   ← from inputAudioTranscription
//       "outputTranscription": { "text": "what gemini said" }, ← from outputAudioTranscription
//       "turnComplete": true,
//       "interrupted": true,      ← user barged in, clear your audio playback buffer
//       "generationComplete": true
//   }}
//   { "usageMetadata": { "totalTokenCount": 123 } }
//   { "goAway": {} }
//
// NOTE: outputTranscription is sent INDEPENDENTLY from serverContent.
// There is no guaranteed ordering between serverContent and outputTranscription.
// Parse each message independently.

Iterable<String> extractTranscriptTexts(Map<String, dynamic> message) sync* {
  // Top-level text (rare, defensive)
  final topLevelText = message['text'] as String?;
  if (topLevelText != null && topLevelText.trim().isNotEmpty) {
    yield topLevelText;
  }

  final serverContent = message['serverContent'];
  if (serverContent is! Map<String, dynamic>) return;

  // ── Input transcription (what user said) ──────────────────────────────────
  // On gemini-2.5: arrives incrementally mid-speech in small chunks.
  // On gemini-3.1: arrives only once after activityEnd (full utterance).
  final inputText =
      (serverContent['inputTranscription'] as Map<String, dynamic>?)?['text']
          as String?;
  if (inputText != null && inputText.isNotEmpty) {
    yield inputText;
  }

  // ── Output transcription (what Gemini said) ───────────────────────────────
  // Arrives asynchronously, not tied to modelTurn timing.
  final outputText =
      (serverContent['outputTranscription'] as Map<String, dynamic>?)?['text']
          as String?;
  if (outputText != null && outputText.isNotEmpty) {
    yield outputText;
  }

  // ── modelTurn text parts (text-mode responses, rare if responseModality=AUDIO)
  final modelTurn = serverContent['modelTurn'];
  if (modelTurn is Map<String, dynamic>) {
    final parts = modelTurn['parts'];
    if (parts is List) {
      for (final part in parts) {
        if (part is! Map<String, dynamic>) continue;
        final text = part['text'] as String?;
        if (text != null && text.isNotEmpty) {
          yield text;
        }
        // NOTE: audio parts live at part['inlineData']['data'] (base64, 24kHz PCM).
        // Handle those in your audio playback layer, not here.
      }
    }
  }
}

/// Returns true if the server message signals Gemini interrupted itself
/// (user barged in). When true, flush your audio playback buffer immediately.
bool isGeminiInterrupted(Map<String, dynamic> message) {
  final sc = message['serverContent'];
  if (sc is! Map<String, dynamic>) return false;
  return sc['interrupted'] == true;
}

/// Returns true when Gemini has finished its full turn.
bool isGeminiTurnComplete(Map<String, dynamic> message) {
  final sc = message['serverContent'];
  if (sc is! Map<String, dynamic>) return false;
  return sc['turnComplete'] == true;
}

/// Extracts raw audio bytes from a modelTurn part, if present.
/// Returns null if the part has no audio inlineData.
/// Caller must play this as 16-bit signed PCM at 24kHz mono.
Uint8List? extractAudioFromPart(Map<String, dynamic> part) {
  final inlineData = part['inlineData'] as Map<String, dynamic>?;
  if (inlineData == null) return null;
  final mimeType = inlineData['mimeType'] as String? ?? '';
  if (!mimeType.startsWith('audio/')) return null;
  final data = inlineData['data'] as String?;
  if (data == null || data.isEmpty) return null;
  return base64Decode(data);
}

// ─── Error Parsing ────────────────────────────────────────────────────────────

GeminiLiveError parseGeminiLiveError(Object error, {String? fallbackMessage}) {
  if (error is GeminiLiveError) return error;

  if (error is Map<String, dynamic>) {
    final message =
        (error['message'] as String?)?.trim() ??
        (error['status'] as String?)?.trim() ??
        fallbackMessage ??
        'Gemini Live returned an unknown error.';
    return GeminiLiveError(GeminiLiveErrorType.unknown, message);
  }

  final message = error.toString().replaceFirst('Exception: ', '').trim();
  return GeminiLiveError(
    GeminiLiveErrorType.unknown,
    message.isEmpty ? (fallbackMessage ?? 'Gemini Live failed.') : message,
  );
}

// ─── Message Decoder ──────────────────────────────────────────────────────────

Map<String, dynamic>? decodeGeminiLiveMessage(dynamic rawMessage) {
  final Object? decoded;

  if (rawMessage is String) {
    decoded = jsonDecode(rawMessage);
  } else if (rawMessage is Uint8List) {
    decoded = jsonDecode(utf8.decode(rawMessage));
  } else if (rawMessage is ByteBuffer) {
    decoded = jsonDecode(utf8.decode(rawMessage.asUint8List()));
  } else if (rawMessage is List<int>) {
    decoded = jsonDecode(utf8.decode(rawMessage));
  } else {
    decoded = jsonDecode(rawMessage.toString());
  }

  return decoded is Map<String, dynamic> ? decoded : null;
}
