// Purpose: Mobile implementation of the SOW voice assistant — Gemini Live for
// listening/turn-taking (mic via `record`), replies in TEXT spoken locally
// with flutter_tts, mirroring the urbox voice stack.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';

import 'gemini_live_service_base.dart'
    show
        GeminiLiveError,
        GeminiLiveErrorType,
        decodeGeminiLiveMessage,
        geminiLiveBytesPerSample,
        geminiLiveChannelCount,
        geminiLiveChunkInterval,
        geminiLiveInputSampleRate,
        geminiLiveSetupTimeout,
        parseGeminiLiveError;
import 'sow_voice_agent_service_base.dart';

SowVoiceAgentService createSowVoiceAgentService() =>
    _MobileSowVoiceAgentService();

class _MobileSowVoiceAgentService implements SowVoiceAgentService {
  final StreamController<SowVoiceEvent> _events =
      StreamController<SowVoiceEvent>.broadcast();
  final AudioRecorder _recorder = AudioRecorder();
  final FlutterTts _tts = FlutterTts();
  final List<int> _pendingPcmBytes = <int>[];

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _setupCompleter;

  /// Accumulates the model's TEXT reply for the current turn; spoken whole
  /// on turnComplete (the urbox pacing).
  final StringBuffer _turnBuffer = StringBuffer();

  bool _isConnected = false;
  bool _isDisposed = false;
  bool _isClosing = false;
  bool _userMuted = false;

  /// True while flutter_tts is speaking — silence is injected during playback
  /// so the server-VAD stream stays alive without echoing TTS audio back.
  bool _ttsSpeaking = false;

  /// Safety net: resets _ttsSpeaking if the flutter_tts completion callback
  /// never fires (a known platform bug on some Android versions).
  Timer? _ttsSpeakingTimeout;

  @override
  Stream<SowVoiceEvent> get events => _events.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect({
    required Uri uri,
    required String systemInstruction,
  }) async {
    if (_isDisposed) {
      throw const GeminiLiveError(
        GeminiLiveErrorType.unknown,
        'Voice agent service has already been disposed.',
      );
    }
    if (_isConnected) return;

    await _closeSocket();
    await _initTts();

    final channel = IOWebSocketChannel.connect(uri);
    _channel = channel;
    _isClosing = false;
    _setupCompleter = Completer<void>();

    _socketSubscription = channel.stream.listen(
      _handleSocketMessage,
      onError: _handleSocketError,
      onDone: _handleSocketDone,
    );

    try {
      await channel.ready.timeout(geminiLiveSetupTimeout);
      channel.sink.add(
        buildVoiceAgentSetupPayload(systemInstruction, audioOutput: false),
      );
      await _setupCompleter!.future.timeout(geminiLiveSetupTimeout);
      _isConnected = true;
      if (kDebugMode) debugPrint('[SowVoiceMobile] setupComplete received');
    } catch (error) {
      final liveError = error is TimeoutException
          ? const GeminiLiveError(
              GeminiLiveErrorType.setupTimeout,
              'Voice agent setup timed out',
            )
          : parseGeminiLiveError(
              error,
              fallbackMessage: 'Voice agent connection failed.',
            );
      _emitError(liveError.message);
      await _closeSocket();
      throw liveError;
    }

    await _startMicrophone();
  }

  @override
  Future<void> sendToolResponse(
    String id,
    String name,
    Map<String, dynamic> response,
  ) async {
    final channel = _channel;
    if (channel == null || !_isConnected) return;
    try {
      channel.sink.add(buildVoiceAgentToolResponsePayload(id, name, response));
    } catch (_) {
      // Socket already closed — the session is over anyway.
    }
  }

  @override
  void setMuted(bool muted) {
    _userMuted = muted;
  }

  @override
  Future<void> disconnect() async {
    _isClosing = true;
    await _stopMicrophone();
    await _stopTts();
    await _closeSocket();
    _emit(const VoiceDisconnected());
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    unawaited(_disposeAsync());
  }

  Future<void> _disposeAsync() async {
    _ttsSpeakingTimeout?.cancel();
    await disconnect();
    _recorder.dispose();
    await _events.close();
  }

  // ── Text-to-speech (urbox config) ───────────────────────────────────────────

  Future<void> _initTts() async {
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(1.5);
      await _tts.setPitch(1.2);
      await _tts.setVolume(1.0);
      _tts.setCompletionHandler(_onTtsDone);
      _tts.setCancelHandler(_onTtsDone);
      _tts.setErrorHandler((_) => _onTtsDone());
    } catch (e) {
      if (kDebugMode) debugPrint('[SowVoiceMobile] TTS init failed: $e');
    }
  }

  void _onTtsDone() {
    _ttsSpeakingTimeout?.cancel();
    _ttsSpeakingTimeout = null;
    if (!_ttsSpeaking) return;
    _ttsSpeaking = false;
    // Discard silence bytes buffered during TTS so real speech starts cleanly.
    _pendingPcmBytes.clear();
    _emit(const VoiceSpeakingChanged(false));
  }

  Future<void> _speak(String text) async {
    if (text.trim().isEmpty) return;
    _ttsSpeaking = true;
    _emit(const VoiceSpeakingChanged(true));
    // Safety net: ~80 ms per character, clamped to 3–30 s.
    // Fires _onTtsDone if the flutter_tts completion callback never comes.
    final timeoutMs = (text.length * 80).clamp(3000, 30000);
    _ttsSpeakingTimeout = Timer(Duration(milliseconds: timeoutMs), _onTtsDone);
    try {
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) debugPrint('[SowVoiceMobile] TTS speak failed: $e');
      _onTtsDone();
    }
  }

  Future<void> _stopTts() async {
    try {
      await _tts.stop();
    } catch (_) {}
    _onTtsDone();
  }

  // ── Microphone capture ──────────────────────────────────────────────────────

  Future<void> _startMicrophone() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      const error = GeminiLiveError(
        GeminiLiveErrorType.micPermissionDenied,
        'Microphone permission was denied.',
      );
      _emitError(error.message);
      throw error;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: geminiLiveInputSampleRate,
          numChannels: geminiLiveChannelCount,
        ),
      );
      _pendingPcmBytes.clear();
      _audioSubscription = stream.listen(
        _bufferAudioBytes,
        onError: (Object error) {
          _emitError('Microphone stream failed: $error');
        },
        onDone: () {
          // OS interrupted the audio session (phone call, BT disconnect, etc.)
          // — restart the mic so the session can continue.
          if (!_isClosing && _isConnected) {
            if (kDebugMode) {
              debugPrint('[SowVoiceMobile] mic stream ended unexpectedly, restarting');
            }
            unawaited(_startMicrophone());
          }
        },
      );
    } catch (error) {
      final liveError = GeminiLiveError(
        GeminiLiveErrorType.micUnavailable,
        'Unable to start microphone capture: $error',
      );
      _emitError(liveError.message);
      throw liveError;
    }
  }

  Future<void> _stopMicrophone() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // Ignore shutdown errors so socket teardown still happens.
    }
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    _pendingPcmBytes.clear();
  }

  void _bufferAudioBytes(Uint8List bytes) {
    if (!_isConnected) return;
    if (_userMuted) return;

    // While TTS is playing, inject silence instead of real mic audio.
    // This keeps the Gemini server-VAD stream alive (preventing stale-VAD
    // drop-outs) without echoing the TTS audio back through the open mic.
    final payload = _ttsSpeaking ? Uint8List(bytes.length) : bytes;
    _pendingPcmBytes.addAll(payload);

    final chunkByteSize = geminiLiveInputSampleRate *
        geminiLiveChunkInterval.inMilliseconds ~/
        1000 *
        geminiLiveChannelCount *
        geminiLiveBytesPerSample;

    while (_pendingPcmBytes.length >= chunkByteSize) {
      final chunk =
          Uint8List.fromList(_pendingPcmBytes.sublist(0, chunkByteSize));
      _pendingPcmBytes.removeRange(0, chunkByteSize);
      if (_channel != null) {
        _channel!.sink.add(buildVoiceAgentAudioPayload(base64Encode(chunk)));
      }
    }
  }

  // ── Server messages ─────────────────────────────────────────────────────────

  void _handleSocketMessage(dynamic rawMessage) {
    try {
      final decoded = decodeGeminiLiveMessage(rawMessage);
      if (decoded == null) return;

      final error = decoded['error'];
      if (error != null) {
        final liveError = parseGeminiLiveError(error);
        if (!(_setupCompleter?.isCompleted ?? true)) {
          _setupCompleter?.completeError(liveError);
        }
        _emitError(liveError.message);
        return;
      }

      if (decoded.containsKey('setupComplete')) {
        if (!(_setupCompleter?.isCompleted ?? true)) {
          _setupCompleter?.complete();
        }
        return;
      }

      for (final toolCall in extractVoiceToolCalls(decoded)) {
        if (kDebugMode) {
          debugPrint('[SowVoiceMobile] toolCall: ${toolCall.name}');
        }
        _emit(toolCall);
      }

      final serverContent = decoded['serverContent'];
      if (serverContent is! Map<String, dynamic>) return;

      if (serverContent['interrupted'] == true) {
        unawaited(_stopTts());
        _emit(const VoiceInterrupted());
      }

      final inputText = (serverContent['inputTranscription']
          as Map<String, dynamic>?)?['text'] as String?;
      if (inputText != null && inputText.isNotEmpty) {
        _emit(VoiceUserTranscriptDelta(inputText));
      }

      // TEXT modality — the reply arrives as modelTurn text parts.
      final modelTurn = serverContent['modelTurn'];
      if (modelTurn is Map<String, dynamic>) {
        final parts = modelTurn['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map<String, dynamic>) continue;
            final text = part['text'] as String?;
            if (text != null && text.isNotEmpty) {
              _turnBuffer.write(text);
              _emit(VoiceAgentTranscriptDelta(text));
            }
          }
        }
      }

      if (serverContent['turnComplete'] == true) {
        final reply = _turnBuffer.toString().trim();
        _turnBuffer.clear();
        _emit(const VoiceTurnComplete());
        if (reply.isNotEmpty) unawaited(_speak(reply));
      }
    } catch (error) {
      _emitError('Voice agent returned a malformed message: $error');
    }
  }

  void _handleSocketError(Object error) {
    _isConnected = false;
    final liveError = GeminiLiveError(
      GeminiLiveErrorType.connectionFailed,
      'Voice agent WebSocket error: $error',
    );
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(liveError);
    }
    _emitError(liveError.message);
  }

  void _handleSocketDone() {
    _isConnected = false;
    if (_isClosing) return;

    final closeReason = [
      if (_channel?.closeCode != null) 'code ${_channel!.closeCode}',
      if ((_channel?.closeReason ?? '').trim().isNotEmpty)
        _channel!.closeReason!.trim(),
    ].join(' - ');
    final liveError = GeminiLiveError(
      GeminiLiveErrorType.socketClosed,
      closeReason.isEmpty
          ? 'Voice agent connection closed unexpectedly.'
          : 'Voice agent connection closed unexpectedly: $closeReason',
    );
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(liveError);
    }
    _emitError(liveError.message);
    _emit(const VoiceDisconnected());
  }

  Future<void> _closeSocket() async {
    _isConnected = false;
    _turnBuffer.clear();
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setupCompleter = null;
  }

  void _emit(SowVoiceEvent event) {
    if (_isDisposed || _events.isClosed) return;
    _events.add(event);
  }

  void _emitError(String message) => _emit(VoiceErrorEvent(message));
}
