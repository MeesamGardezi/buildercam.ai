import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:web_socket_channel/io.dart';

import 'gemini_live_service_base.dart';

GeminiLiveService createGeminiLiveService() => _MobileGeminiLiveService();

class _MobileGeminiLiveService implements GeminiLiveService {
  final AudioRecorder _recorder = AudioRecorder();
  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();
  final StreamController<GeminiLiveError> _errorController =
      StreamController<GeminiLiveError>.broadcast();
  final List<int> _pendingPcmBytes = <int>[];

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _audioSubscription;
  Completer<void>? _setupCompleter;

  bool _isConnected = false;
  bool _isStreaming = false;
  bool _isDisposed = false;
  bool _isClosing = false;

  @override
  Stream<String> get transcriptStream => _transcriptController.stream;

  @override
  Stream<GeminiLiveError> get errorStream => _errorController.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect(String apiKey) async {
    if (_isDisposed) {
      throw const GeminiLiveError(
        GeminiLiveErrorType.unknown,
        'Gemini Live service has already been disposed.',
      );
    }

    if (_isConnected) {
      return;
    }

    await _closeSocket();

    final channel = IOWebSocketChannel.connect(buildGeminiLiveUri(apiKey));
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
      channel.sink.add(buildGeminiLiveSetupPayload());
      await _setupCompleter!.future.timeout(geminiLiveSetupTimeout);
      _isConnected = true;
    } catch (error) {
      final liveError = _normalizeConnectError(error);
      _emitError(liveError);
      await _closeSocket();
      throw liveError;
    }
  }

  @override
  Future<void> startStreaming() async {
    if (_isDisposed) {
      throw const GeminiLiveError(
        GeminiLiveErrorType.unknown,
        'Gemini Live service has already been disposed.',
      );
    }

    if (!_isConnected) {
      throw const GeminiLiveError(
        GeminiLiveErrorType.connectionFailed,
        'Gemini Live is not connected.',
      );
    }

    if (_isStreaming) {
      return;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      const error = GeminiLiveError(
        GeminiLiveErrorType.micPermissionDenied,
        'Microphone permission was denied.',
      );
      _emitError(error);
      throw error;
    }

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: geminiLiveSampleRate,
          numChannels: geminiLiveChannelCount,
        ),
      );

      _pendingPcmBytes.clear();
      try {
        if (_channel != null && _isConnected) {
          _channel!.sink.add(buildGeminiLiveActivityStartPayload());
        }
      } catch (_) {
        // Ignore if socket is not writable or already closed.
      }

      _audioSubscription = stream.listen(
        _bufferAudioBytes,
        onError: (Object error) {
          _emitError(
            GeminiLiveError(
              GeminiLiveErrorType.micUnavailable,
              'Microphone stream failed: $error',
            ),
          );
        },
      );
      _isStreaming = true;
    } catch (error) {
      final liveError = GeminiLiveError(
        GeminiLiveErrorType.micUnavailable,
        'Unable to start microphone capture: $error',
      );
      _emitError(liveError);
      throw liveError;
    }
  }

  @override
  Future<void> stopStreaming() async {
    _isClosing = true;

    if (_isStreaming) {
      try {
        await _recorder.stop();
      } catch (_) {
        // Ignore shutdown errors so socket teardown still happens.
      }
      await _audioSubscription?.cancel();
      _audioSubscription = null;
      _isStreaming = false;
      _flushPendingAudio(force: true);
      if (_channel != null && _isConnected) {
        try {
          _channel!.sink.add(buildGeminiLiveActivityEndPayload());
        } catch (_) {
          // Ignore late shutdown writes if the socket has already closed.
        }
      }
    }

    await Future<void>.delayed(geminiLiveChunkInterval);
    await _closeSocket();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    unawaited(_disposeAsync());
  }

  Future<void> _disposeAsync() async {
    await stopStreaming();
    await _transcriptController.close();
    await _errorController.close();
    _recorder.dispose();
  }

  void _bufferAudioBytes(Uint8List bytes) {
    _pendingPcmBytes.addAll(bytes);
    _flushPendingAudio();
  }

  void _flushPendingAudio({bool force = false}) {
    final chunkByteSize =
        geminiLiveSampleRate *
        geminiLiveChunkInterval.inMilliseconds ~/
        1000 *
        geminiLiveChannelCount *
        geminiLiveBytesPerSample;

    while (_pendingPcmBytes.length >= chunkByteSize ||
        (force && _pendingPcmBytes.isNotEmpty)) {
      final bytesToSend =
          force && _pendingPcmBytes.length < chunkByteSize
              ? _pendingPcmBytes.length
              : chunkByteSize;
      final pcmBytes = Uint8List.fromList(
        _pendingPcmBytes.sublist(0, bytesToSend),
      );
      _pendingPcmBytes.removeRange(0, bytesToSend);
      _sendAudioChunk(pcmBytes);
    }
  }

  void _sendAudioChunk(Uint8List pcmBytes) {
    if (!_isConnected || _channel == null || pcmBytes.isEmpty) {
      return;
    }

    _channel!.sink.add(buildGeminiLiveAudioPayload(base64Encode(pcmBytes)));
  }

  void _handleSocketMessage(dynamic rawMessage) {
    try {
      final decoded = decodeGeminiLiveMessage(rawMessage);
      if (decoded == null) {
        return;
      }

      final error = decoded['error'];
      if (error != null) {
        final liveError = parseGeminiLiveError(error);
        if (!(_setupCompleter?.isCompleted ?? true)) {
          _setupCompleter?.completeError(liveError);
        }
        _emitError(liveError);
        return;
      }

      if (decoded.containsKey('setupComplete')) {
        if (!(_setupCompleter?.isCompleted ?? true)) {
          _setupCompleter?.complete();
        }
        return;
      }

      for (final text in extractTranscriptTexts(decoded)) {
        _transcriptController.add(text);
      }
    } catch (error) {
      final liveError = GeminiLiveError(
        GeminiLiveErrorType.unknown,
        'Gemini Live returned a malformed message: $error',
      );
      if (!(_setupCompleter?.isCompleted ?? true)) {
        _setupCompleter?.completeError(liveError);
      }
      _emitError(liveError);
    }
  }

  void _handleSocketError(Object error) {
    _isConnected = false;
    final liveError = GeminiLiveError(
      GeminiLiveErrorType.connectionFailed,
      'Gemini Live WebSocket error: $error',
    );
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(liveError);
    }
    _emitError(liveError);
  }

  void _handleSocketDone() {
    _isConnected = false;
    if (_isClosing) {
      return;
    }

    final closeReason = [
      if (_channel?.closeCode != null) 'code ${_channel!.closeCode}',
      if ((_channel?.closeReason ?? '').trim().isNotEmpty)
        _channel!.closeReason!.trim(),
    ].join(' - ');
    final liveError = GeminiLiveError(
      GeminiLiveErrorType.socketClosed,
      closeReason.isEmpty
          ? 'Gemini Live connection closed unexpectedly.'
          : 'Gemini Live connection closed unexpectedly: $closeReason',
    );
    if (!(_setupCompleter?.isCompleted ?? true)) {
      _setupCompleter?.completeError(liveError);
    }
    _emitError(liveError);
  }

  Future<void> _closeSocket() async {
    _isConnected = false;
    _isStreaming = false;
    _pendingPcmBytes.clear();
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _channel?.sink.close();
    _channel = null;
    _setupCompleter = null;
  }

  GeminiLiveError _normalizeConnectError(Object error) {
    if (error is TimeoutException) {
      return const GeminiLiveError(
        GeminiLiveErrorType.setupTimeout,
        'Gemini Live setup timed out',
      );
    }

    return parseGeminiLiveError(
      error,
      fallbackMessage: 'Gemini Live connection failed.',
    );
  }

  void _emitError(GeminiLiveError error) {
    if (_isDisposed || _errorController.isClosed) {
      return;
    }
    _errorController.add(error);
  }
}
