import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/html.dart';

import 'gemini_live_service_base.dart';

GeminiLiveService createGeminiLiveService() => _WebGeminiLiveService();

class _WebGeminiLiveService implements GeminiLiveService {
  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();
  final StreamController<GeminiLiveError> _errorController =
      StreamController<GeminiLiveError>.broadcast();
  final List<int> _pendingPcmBytes = <int>[];

  HtmlWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Completer<void>? _setupCompleter;

  web.MediaStream? _mediaStream;
  web.AudioContext? _audioContext;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.ScriptProcessorNode? _processorNode;
  web.GainNode? _muteNode;

  bool _isConnected = false;
  bool _isStreaming = false;
  bool _isDisposed = false;
  bool _isClosing = false;
  double _resampleOffset = 0;

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

    final channel = HtmlWebSocketChannel.connect(buildGeminiLiveUri(apiKey));
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
      if (kDebugMode) {
        debugPrint(
          '[GeminiLiveWeb] socket open, sending setup for $geminiLiveModel',
        );
      }
      channel.sink.add(buildGeminiLiveSetupPayload());
      await _setupCompleter!.future.timeout(geminiLiveSetupTimeout);
      _isConnected = true;
      if (kDebugMode) {
        debugPrint('[GeminiLiveWeb] setupComplete received');
      }
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

    try {
      final constraints = web.MediaStreamConstraints(
        audio: web.MediaTrackConstraints(
          sampleRate: web.ConstrainULongRange(ideal: geminiLiveSampleRate),
          channelCount: web.ConstrainULongRange(ideal: geminiLiveChannelCount),
          echoCancellation: web.ConstrainBooleanParameters(ideal: true),
        ),
      );

      final mediaStream =
          await web.window.navigator.mediaDevices
              .getUserMedia(constraints)
              .toDart;
      final audioContext = web.AudioContext(
        web.AudioContextOptions(sampleRate: geminiLiveSampleRate.toDouble()),
      );
      await audioContext.resume().toDart;

      final sourceNode = audioContext.createMediaStreamSource(mediaStream);
      final processorNode = audioContext.createScriptProcessor(1024, 1, 1);
      final muteNode = audioContext.createGain();
      muteNode.gain.value = 0;

      processorNode.onaudioprocess =
          ((web.Event event) {
            final audioEvent = event as web.AudioProcessingEvent;
            final inputSamples =
                audioEvent.inputBuffer.getChannelData(0).toDart;
            final outputSamples =
                audioEvent.outputBuffer.getChannelData(0).toDart;
            outputSamples.fillRange(0, outputSamples.length, 0);

            final preparedSamples = _prepareSamples(
              inputSamples,
              audioContext.sampleRate,
            );
            _bufferPcmBytes(_float32ToPcm16(preparedSamples));
          }).toJS;

      sourceNode.connect(processorNode);
      processorNode.connect(muteNode);
      muteNode.connect(audioContext.destination);

      try {
        if (_channel != null && _isConnected) {
          _channel!.sink.add(buildGeminiLiveActivityStartPayload());
        }
      } catch (_) {
        // Ignore if socket is not writable or already closed.
      }

      _pendingPcmBytes.clear();
      _resampleOffset = 0;
      _mediaStream = mediaStream;
      _audioContext = audioContext;
      _sourceNode = sourceNode;
      _processorNode = processorNode;
      _muteNode = muteNode;
      _isStreaming = true;
    } catch (error) {
      final message = error.toString();
      final liveError =
          message.contains('NotAllowedError')
              ? const GeminiLiveError(
                GeminiLiveErrorType.micPermissionDenied,
                'Microphone permission was denied.',
              )
              : GeminiLiveError(
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
    await _stopAudioCapture();
    if (_channel != null && _isConnected) {
      try {
        _channel!.sink.add(buildGeminiLiveActivityEndPayload());
      } catch (_) {
        // Ignore late shutdown writes if the socket has already closed.
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
  }

  Float32List _prepareSamples(
    Float32List inputSamples,
    double sourceSampleRate,
  ) {
    if (sourceSampleRate == geminiLiveSampleRate) {
      return inputSamples;
    }

    final ratio = sourceSampleRate / geminiLiveSampleRate;
    final estimatedLength =
        ((inputSamples.length - _resampleOffset) / ratio).floor();
    if (estimatedLength <= 0) {
      _resampleOffset = 0;
      return Float32List(0);
    }

    final output = Float32List(estimatedLength);
    var sourceIndex = _resampleOffset;

    for (var index = 0; index < estimatedLength; index++) {
      final lowerIndex = sourceIndex.floor().clamp(0, inputSamples.length - 1);
      final upperIndex = (lowerIndex + 1).clamp(0, inputSamples.length - 1);
      final fraction = sourceIndex - lowerIndex;
      final interpolated =
          inputSamples[lowerIndex] * (1 - fraction) +
          inputSamples[upperIndex] * fraction;
      output[index] = interpolated;
      sourceIndex += ratio;
    }

    _resampleOffset = sourceIndex - inputSamples.length;
    if (_resampleOffset.isNaN || _resampleOffset.isInfinite) {
      _resampleOffset = 0;
    }

    return output;
  }

  Uint8List _float32ToPcm16(Float32List samples) {
    final pcmBytes = ByteData(samples.length * geminiLiveBytesPerSample);
    for (var index = 0; index < samples.length; index++) {
      final sample = samples[index].clamp(-1.0, 1.0);
      final pcmValue =
          sample < 0 ? (sample * 32768).round() : (sample * 32767).round();
      pcmBytes.setInt16(
        index * geminiLiveBytesPerSample,
        pcmValue,
        Endian.little,
      );
    }
    return pcmBytes.buffer.asUint8List();
  }

  void _bufferPcmBytes(Uint8List pcmBytes) {
    _pendingPcmBytes.addAll(pcmBytes);
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
      final chunk = Uint8List.fromList(
        _pendingPcmBytes.sublist(0, bytesToSend),
      );
      _pendingPcmBytes.removeRange(0, bytesToSend);
      _sendAudioChunk(chunk);
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
      if (kDebugMode) {
        debugPrint('[GeminiLiveWeb] message: $rawMessage');
      }
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
        if (kDebugMode) {
          debugPrint('[GeminiLiveWeb] transcript: $text');
        }
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
    if (kDebugMode) {
      debugPrint('[GeminiLiveWeb] socket error: $error');
    }
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
    if (kDebugMode) {
      debugPrint(
        '[GeminiLiveWeb] socket closed code=${_channel?.closeCode} '
        'reason=${_channel?.closeReason}',
      );
    }
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

  Future<void> _stopAudioCapture() async {
    if (_isStreaming) {
      _processorNode?.disconnect();
      _sourceNode?.disconnect();
      _muteNode?.disconnect();
      _processorNode?.onaudioprocess = null;

      final tracks =
          _mediaStream?.getAudioTracks().toDart ??
          const <web.MediaStreamTrack>[];
      for (final track in tracks) {
        track.stop();
      }

      try {
        if (_audioContext != null && _audioContext!.state != 'closed') {
          await _audioContext!.close().toDart;
        }
      } catch (_) {
        // Best effort close.
      }

      _processorNode = null;
      _sourceNode = null;
      _muteNode = null;
      _mediaStream = null;
      _audioContext = null;
      _isStreaming = false;
      _flushPendingAudio(force: true);
    }
  }

  Future<void> _closeSocket() async {
    _isConnected = false;
    _isStreaming = false;
    _pendingPcmBytes.clear();
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
