// Purpose: Web implementation of the SOW voice assistant — full-duplex Gemini
// Live session with continuous mic streaming, 24kHz PCM playback and barge-in.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:web_socket_channel/html.dart';

import 'gemini_live_service_base.dart'
    show
        GeminiLiveError,
        GeminiLiveErrorType,
        decodeGeminiLiveMessage,
        extractAudioFromPart,
        geminiLiveBytesPerSample,
        geminiLiveChannelCount,
        geminiLiveChunkInterval,
        geminiLiveInputSampleRate,
        geminiLiveOutputSampleRate,
        geminiLiveSetupTimeout,
        parseGeminiLiveError;
import 'sow_voice_agent_service_base.dart';

SowVoiceAgentService createSowVoiceAgentService() => _WebSowVoiceAgentService();

class _WebSowVoiceAgentService implements SowVoiceAgentService {
  final StreamController<SowVoiceEvent> _events =
      StreamController<SowVoiceEvent>.broadcast();
  final List<int> _pendingPcmBytes = <int>[];

  HtmlWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _socketSubscription;
  Completer<void>? _setupCompleter;

  // ── Microphone capture (16kHz input) ──
  web.MediaStream? _mediaStream;
  web.AudioContext? _captureContext;
  web.MediaStreamAudioSourceNode? _sourceNode;
  web.ScriptProcessorNode? _processorNode;
  web.GainNode? _muteNode;
  double _resampleOffset = 0;
  Timer? _contextResumeTimer;

  // ── Agent audio playback (24kHz output) ──
  web.AudioContext? _playbackContext;
  final List<web.AudioBufferSourceNode> _activeSources =
      <web.AudioBufferSourceNode>[];
  double _nextPlayTime = 0;
  Timer? _speakingTimer;
  bool _wasSpeaking = false;

  bool _isConnected = false;
  bool _isDisposed = false;
  bool _isClosing = false;
  bool _muted = false;

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

    final channel = HtmlWebSocketChannel.connect(uri);
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
      channel.sink
          .add(buildVoiceAgentSetupPayload(systemInstruction, audioOutput: true));
      await _setupCompleter!.future.timeout(geminiLiveSetupTimeout);
      _isConnected = true;
      if (kDebugMode) debugPrint('[SowVoiceWeb] setupComplete received');
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
    _startSpeakingTimer();
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
    _muted = muted;
  }

  @override
  Future<void> disconnect() async {
    _isClosing = true;
    _speakingTimer?.cancel();
    _speakingTimer = null;
    await _stopMicrophone();
    _flushPlayback();
    await _closePlaybackContext();
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
    await disconnect();
    await _events.close();
  }

  // ── Microphone capture ──────────────────────────────────────────────────────

  Future<void> _startMicrophone() async {
    try {
      final constraints = web.MediaStreamConstraints(
        audio: web.MediaTrackConstraints(
          sampleRate:
              web.ConstrainULongRange(ideal: geminiLiveInputSampleRate),
          channelCount: web.ConstrainULongRange(ideal: geminiLiveChannelCount),
          // Echo cancellation is essential — the agent's voice plays through
          // the speakers while the mic is open.
          echoCancellation: web.ConstrainBooleanParameters(ideal: true),
        ),
      );

      final mediaStream = await web.window.navigator.mediaDevices
          .getUserMedia(constraints)
          .toDart;
      final captureContext = web.AudioContext(
        web.AudioContextOptions(
          sampleRate: geminiLiveInputSampleRate.toDouble(),
        ),
      );
      await captureContext.resume().toDart;

      final sourceNode = captureContext.createMediaStreamSource(mediaStream);
      final processorNode = captureContext.createScriptProcessor(1024, 1, 1);
      final muteNode = captureContext.createGain();
      muteNode.gain.value = 0;

      processorNode.onaudioprocess = ((web.Event event) {
        if (_muted || !_isConnected) return;
        final audioEvent = event as web.AudioProcessingEvent;
        final inputSamples = audioEvent.inputBuffer.getChannelData(0).toDart;
        final outputSamples = audioEvent.outputBuffer.getChannelData(0).toDart;
        outputSamples.fillRange(0, outputSamples.length, 0);

        final prepared =
            _prepareSamples(inputSamples, captureContext.sampleRate);
        _bufferPcmBytes(_float32ToPcm16(prepared));
      }).toJS;

      sourceNode.connect(processorNode);
      processorNode.connect(muteNode);
      muteNode.connect(captureContext.destination);

      _pendingPcmBytes.clear();
      _resampleOffset = 0;
      _mediaStream = mediaStream;
      _captureContext = captureContext;
      _sourceNode = sourceNode;
      _processorNode = processorNode;
      _muteNode = muteNode;

      // Browsers can suspend the AudioContext when the tab loses focus.
      // Poll and resume so onaudioprocess keeps firing after the user returns.
      _contextResumeTimer?.cancel();
      _contextResumeTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        final ctx = _captureContext;
        if (ctx != null && ctx.state == 'suspended') {
          try {
            await ctx.resume().toDart;
          } catch (_) {}
        }
      });
    } catch (error) {
      final message = error.toString();
      final liveError = message.contains('NotAllowedError')
          ? const GeminiLiveError(
              GeminiLiveErrorType.micPermissionDenied,
              'Microphone permission was denied.',
            )
          : GeminiLiveError(
              GeminiLiveErrorType.micUnavailable,
              'Unable to start microphone capture: $error',
            );
      _emitError(liveError.message);
      throw liveError;
    }
  }

  Future<void> _stopMicrophone() async {
    _contextResumeTimer?.cancel();
    _contextResumeTimer = null;
    _processorNode?.disconnect();
    _sourceNode?.disconnect();
    _muteNode?.disconnect();
    _processorNode?.onaudioprocess = null;

    final tracks =
        _mediaStream?.getAudioTracks().toDart ?? const <web.MediaStreamTrack>[];
    for (final track in tracks) {
      track.stop();
    }

    try {
      if (_captureContext != null && _captureContext!.state != 'closed') {
        await _captureContext!.close().toDart;
      }
    } catch (_) {
      // Best effort close.
    }

    _processorNode = null;
    _sourceNode = null;
    _muteNode = null;
    _mediaStream = null;
    _captureContext = null;
    _pendingPcmBytes.clear();
  }

  Float32List _prepareSamples(
    Float32List inputSamples,
    double sourceSampleRate,
  ) {
    if (sourceSampleRate == geminiLiveInputSampleRate) return inputSamples;

    final ratio = sourceSampleRate / geminiLiveInputSampleRate;
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
      output[index] = inputSamples[lowerIndex] * (1 - fraction) +
          inputSamples[upperIndex] * fraction;
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

    final chunkByteSize = geminiLiveInputSampleRate *
        geminiLiveChunkInterval.inMilliseconds ~/
        1000 *
        geminiLiveChannelCount *
        geminiLiveBytesPerSample;

    while (_pendingPcmBytes.length >= chunkByteSize) {
      final chunk =
          Uint8List.fromList(_pendingPcmBytes.sublist(0, chunkByteSize));
      _pendingPcmBytes.removeRange(0, chunkByteSize);
      _sendAudioChunk(chunk);
    }
  }

  void _sendAudioChunk(Uint8List pcmBytes) {
    if (!_isConnected || _channel == null || pcmBytes.isEmpty) return;
    _channel!.sink.add(buildVoiceAgentAudioPayload(base64Encode(pcmBytes)));
  }

  // ── Agent audio playback ────────────────────────────────────────────────────

  void _enqueuePlayback(Uint8List pcmBytes) {
    if (pcmBytes.length < geminiLiveBytesPerSample) return;

    final context = _playbackContext ??= web.AudioContext(
      web.AudioContextOptions(
        sampleRate: geminiLiveOutputSampleRate.toDouble(),
      ),
    );

    final sampleCount = pcmBytes.length ~/ geminiLiveBytesPerSample;
    final int16 = pcmBytes.buffer.asInt16List(
      pcmBytes.offsetInBytes,
      sampleCount,
    );
    final floats = Float32List(sampleCount);
    for (var i = 0; i < sampleCount; i++) {
      floats[i] = int16[i] / 32768.0;
    }

    final buffer = context.createBuffer(
      geminiLiveChannelCount,
      sampleCount,
      geminiLiveOutputSampleRate,
    );
    buffer.copyToChannel(floats.toJS, 0);

    final source = context.createBufferSource();
    source.buffer = buffer;
    source.connect(context.destination);

    final now = context.currentTime;
    if (_nextPlayTime < now) _nextPlayTime = now;
    source.start(_nextPlayTime);
    _nextPlayTime += sampleCount / geminiLiveOutputSampleRate;

    _activeSources.add(source);
    source.onended = ((web.Event _) {
      _activeSources.remove(source);
    }).toJS;
  }

  /// Stops all scheduled agent audio immediately (barge-in).
  void _flushPlayback() {
    for (final source in List<web.AudioBufferSourceNode>.of(_activeSources)) {
      try {
        source.stop();
      } catch (_) {
        // Source may have already ended.
      }
    }
    _activeSources.clear();
    _nextPlayTime = 0;
  }

  Future<void> _closePlaybackContext() async {
    try {
      if (_playbackContext != null && _playbackContext!.state != 'closed') {
        await _playbackContext!.close().toDart;
      }
    } catch (_) {
      // Best effort close.
    }
    _playbackContext = null;
  }

  void _startSpeakingTimer() {
    _speakingTimer?.cancel();
    _speakingTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      final context = _playbackContext;
      final speaking =
          context != null && _nextPlayTime > context.currentTime;
      if (speaking != _wasSpeaking) {
        _wasSpeaking = speaking;
        _emit(VoiceSpeakingChanged(speaking));
      }
    });
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
          debugPrint('[SowVoiceWeb] toolCall: ${toolCall.name}');
        }
        _emit(toolCall);
      }

      final serverContent = decoded['serverContent'];
      if (serverContent is! Map<String, dynamic>) return;

      if (serverContent['interrupted'] == true) {
        _flushPlayback();
        _emit(const VoiceInterrupted());
      }

      final inputText = (serverContent['inputTranscription']
          as Map<String, dynamic>?)?['text'] as String?;
      if (inputText != null && inputText.isNotEmpty) {
        _emit(VoiceUserTranscriptDelta(inputText));
      }

      final outputText = (serverContent['outputTranscription']
          as Map<String, dynamic>?)?['text'] as String?;
      if (outputText != null && outputText.isNotEmpty) {
        _emit(VoiceAgentTranscriptDelta(outputText));
      }

      final modelTurn = serverContent['modelTurn'];
      if (modelTurn is Map<String, dynamic>) {
        final parts = modelTurn['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map<String, dynamic>) continue;
            final audio = extractAudioFromPart(part);
            if (audio != null) _enqueuePlayback(audio);
          }
        }
      }

      if (serverContent['turnComplete'] == true) {
        _emit(const VoiceTurnComplete());
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
