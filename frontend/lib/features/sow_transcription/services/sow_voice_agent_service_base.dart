// Purpose: Shared interface, events, and Live API payload builders for the
// SOW voice assistant — a full-duplex hands-free Gemini Live session.
import 'dart:convert';

import 'gemini_live_service_base.dart'
    show geminiLiveModel, geminiLiveMimeType;

// ─── Service interface ────────────────────────────────────────────────────────

abstract class SowVoiceAgentService {
  /// Typed events: transcript deltas, tool calls, speaking state, errors.
  Stream<SowVoiceEvent> get events;

  bool get isConnected;

  /// Opens the Live session and starts streaming the microphone immediately.
  /// Server-side VAD handles turn taking, so the user just talks.
  ///
  /// [uri] is the backend voice proxy WebSocket — the server holds the
  /// Gemini API key and pipes frames both ways (see backend voice-proxy.js).
  Future<void> connect({
    required Uri uri,
    required String systemInstruction,
  });

  /// Replies to a [VoiceToolCall] so the model can continue its turn.
  Future<void> sendToolResponse(
    String id,
    String name,
    Map<String, dynamic> response,
  );

  /// Pauses/resumes sending microphone audio without ending the session.
  void setMuted(bool muted);

  Future<void> disconnect();

  void dispose();
}

// ─── Events ───────────────────────────────────────────────────────────────────

sealed class SowVoiceEvent {
  const SowVoiceEvent();
}

/// Incremental transcription of what the user is saying.
class VoiceUserTranscriptDelta extends SowVoiceEvent {
  const VoiceUserTranscriptDelta(this.text);
  final String text;
}

/// Incremental transcription of what the agent is saying.
class VoiceAgentTranscriptDelta extends SowVoiceEvent {
  const VoiceAgentTranscriptDelta(this.text);
  final String text;
}

/// The agent finished its spoken turn.
class VoiceTurnComplete extends SowVoiceEvent {
  const VoiceTurnComplete();
}

/// The user barged in — agent audio was flushed mid-sentence.
class VoiceInterrupted extends SowVoiceEvent {
  const VoiceInterrupted();
}

/// The model wants a tool executed; reply via [SowVoiceAgentService.sendToolResponse].
class VoiceToolCall extends SowVoiceEvent {
  const VoiceToolCall({required this.id, required this.name, required this.args});
  final String id;
  final String name;
  final Map<String, dynamic> args;
}

/// Audio playback started/stopped — drives the speaking/listening indicator.
class VoiceSpeakingChanged extends SowVoiceEvent {
  const VoiceSpeakingChanged(this.speaking);
  final bool speaking;
}

class VoiceErrorEvent extends SowVoiceEvent {
  const VoiceErrorEvent(this.message);
  final String message;
}

/// The session ended (server closed the socket or [disconnect] was called).
class VoiceDisconnected extends SowVoiceEvent {
  const VoiceDisconnected();
}

// ─── Tool names ───────────────────────────────────────────────────────────────

const String voiceToolUpdateSowDocument = 'update_sow_document';

// ─── Backend proxy URI ────────────────────────────────────────────────────────

/// WebSocket URI of the backend voice proxy. The Firebase ID token
/// authenticates the upgrade; the Gemini key stays server-side.
Uri buildVoiceAgentProxyUri({
  required String backendBaseUrl,
  required String firebaseIdToken,
}) {
  final base = Uri.parse(backendBaseUrl);
  return base.replace(
    scheme: base.scheme == 'https' ? 'wss' : 'ws',
    path: '/voice-agent',
    queryParameters: <String, String>{'token': firebaseIdToken},
  );
}

// ─── Payload builders ─────────────────────────────────────────────────────────

/// Setup for a hands-free conversation: server VAD left ON (default) so turn
/// taking is automatic, and the SOW edit tool declared so the model can change
/// documents while talking.
///
/// [audioOutput] — true on web, where the model's native audio is played back
/// directly. False on mobile, where the model responds with TEXT and the reply
/// is spoken locally via flutter_tts (the urbox approach).
String buildVoiceAgentSetupPayload(
  String systemInstruction, {
  required bool audioOutput,
}) {
  return jsonEncode(<String, dynamic>{
    'setup': <String, dynamic>{
      'model': geminiLiveModel,
      'generationConfig': <String, dynamic>{
        'responseModalities': <String>[audioOutput ? 'AUDIO' : 'TEXT'],
      },
      'systemInstruction': <String, dynamic>{
        'parts': <Map<String, String>>[
          <String, String>{'text': systemInstruction},
        ],
      },
      'tools': <Map<String, dynamic>>[
        <String, dynamic>{
          'functionDeclarations': <Map<String, dynamic>>[
            <String, dynamic>{
              'name': voiceToolUpdateSowDocument,
              'description':
                  'Replaces the full text content of one Scope of Work '
                  'document in this project and saves it. Use when the user '
                  'asks to change, add to, or rewrite part of a SOW.',
              'parameters': <String, dynamic>{
                'type': 'OBJECT',
                'properties': <String, dynamic>{
                  'documentId': <String, dynamic>{
                    'type': 'STRING',
                    'description':
                        'The ID of the SOW document to update, exactly as '
                        'listed in the context.',
                  },
                  'updatedContent': <String, dynamic>{
                    'type': 'STRING',
                    'description':
                        'The COMPLETE updated document text — every section, '
                        'every line. Never truncated or summarised.',
                  },
                },
                'required': <String>['documentId', 'updatedContent'],
              },
            },
          ],
        },
      ],
      'inputAudioTranscription': <String, dynamic>{},
      // Output transcription only applies to audio responses; in TEXT mode
      // the reply text arrives in modelTurn parts directly.
      if (audioOutput) 'outputAudioTranscription': <String, dynamic>{},
      // NOTE: no realtimeInputConfig — server VAD stays enabled so the
      // conversation is hands-free with automatic barge-in.
    },
  });
}

/// Continuous microphone audio — raw 16-bit little-endian PCM @ 16kHz, base64.
String buildVoiceAgentAudioPayload(String base64Pcm) {
  return jsonEncode(<String, dynamic>{
    'realtimeInput': <String, dynamic>{
      'audio': <String, dynamic>{
        'mimeType': geminiLiveMimeType,
        'data': base64Pcm,
      },
    },
  });
}

String buildVoiceAgentToolResponsePayload(
  String id,
  String name,
  Map<String, dynamic> response,
) {
  return jsonEncode(<String, dynamic>{
    'toolResponse': <String, dynamic>{
      'functionResponses': <Map<String, dynamic>>[
        <String, dynamic>{'id': id, 'name': name, 'response': response},
      ],
    },
  });
}

// ─── Server message parsing ──────────────────────────────────────────────────

/// Extracts tool calls from a server message, if present.
/// Shape: { "toolCall": { "functionCalls": [{ "id", "name", "args" }] } }
Iterable<VoiceToolCall> extractVoiceToolCalls(
  Map<String, dynamic> message,
) sync* {
  final toolCall = message['toolCall'];
  if (toolCall is! Map<String, dynamic>) return;
  final calls = toolCall['functionCalls'];
  if (calls is! List) return;
  for (final call in calls) {
    if (call is! Map<String, dynamic>) continue;
    final name = call['name'] as String?;
    if (name == null || name.isEmpty) continue;
    yield VoiceToolCall(
      id: call['id'] as String? ?? '',
      name: name,
      args: call['args'] is Map
          ? Map<String, dynamic>.from(call['args'] as Map)
          : <String, dynamic>{},
    );
  }
}
