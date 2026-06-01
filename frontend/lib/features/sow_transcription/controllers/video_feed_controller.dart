// Purpose: Manages camera initialisation, periodic image capture, and voice
// transcription during a video feed session.
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../../core/utils/web_platform.dart';
import '../models/captured_frame.dart';
import '../services/gemini_live_service.dart';

enum VideoFeedState { idle, initializing, recording, stopping }

class VideoFeedController extends ChangeNotifier {
  VideoFeedController({
    required this.projectId,
    required GeminiLiveService geminiLiveService,
    this.captureIntervalSeconds = 5,
  }) : _geminiLiveService = geminiLiveService;

  final String projectId;
  final GeminiLiveService _geminiLiveService;

  /// How often (in seconds) an image is automatically captured.
  final int captureIntervalSeconds;

  VideoFeedState state = VideoFeedState.idle;
  CameraController? cameraController;
  final List<CapturedFrame> capturedFrames = [];
  String liveTranscript = '';
  int elapsedSeconds = 0;
  String? errorMessage;

  StreamSubscription<String>? _transcriptSub;
  StreamSubscription<GeminiLiveError>? _errorSub;
  Timer? _elapsedTimer;
  Timer? _captureTimer;
  bool _isDisposed = false;

  bool get isRecording => state == VideoFeedState.recording;
  int get frameCount => capturedFrames.length;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> startFeed(String apiKey) async {
    if (state == VideoFeedState.recording ||
        state == VideoFeedState.initializing) {
      return;
    }

    state = VideoFeedState.initializing;
    errorMessage = null;
    _notifySafely();

    try {
      if (kIsWeb && !isMobileWeb) {
        throw UnsupportedError(
          'Video feed is not supported in the desktop web browser. '
          'Please use the iOS or Android app, or a mobile web browser.',
        );
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras are available on this device.');
      }

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false, // audio is handled by the Gemini Live mic stream
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await cameraController!.initialize();

      // Connect Gemini Live for live voice transcription.
      await _geminiLiveService.connect(apiKey);
      _transcriptSub =
          _geminiLiveService.transcriptStream.listen(_onTranscript);
      _errorSub = _geminiLiveService.errorStream.listen(_onGeminiError);
      await _geminiLiveService.startStreaming();

      capturedFrames.clear();
      liveTranscript = '';
      elapsedSeconds = 0;
      state = VideoFeedState.recording;
      _notifySafely();
      _startTimers();
    } catch (e) {
      state = VideoFeedState.idle;
      errorMessage = e.toString();
      _notifySafely();
    }
  }

  Future<void> stopFeed() async {
    if (state != VideoFeedState.recording) return;

    state = VideoFeedState.stopping;
    _notifySafely();

    // Stop timers and camera immediately so no more frames are captured.
    _stopTimers();
    try {
      await cameraController?.dispose();
    } catch (_) {}
    cameraController = null;
    _notifySafely(); // camera preview goes dark

    // Keep the Gemini transcript subscription alive for 3 extra seconds so
    // any speech that was still being processed can arrive before we close.
    await Future.delayed(const Duration(seconds: 3));

    await _transcriptSub?.cancel();
    _transcriptSub = null;
    await _errorSub?.cancel();
    _errorSub = null;

    try {
      await _geminiLiveService.stopStreaming();
    } catch (_) {}

    state = VideoFeedState.idle;
    _notifySafely();
  }

  // ── Frame capture ──────────────────────────────────────────────────────────

  Future<void> _captureFrame() async {
    final ctrl = cameraController;
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        ctrl.value.isTakingPicture ||
        state != VideoFeedState.recording) {
      return;
    }

    try {
      final file = await ctrl.takePicture();
      final bytes = await file.readAsBytes();
      capturedFrames.add(
        CapturedFrame(
          bytes: bytes,
          capturedAt: DateTime.now(),
          secondsElapsed: elapsedSeconds,
        ),
      );
      _notifySafely();
    } catch (_) {}
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  void _onTranscript(String text) {
    liveTranscript += text;
    _notifySafely();
  }

  void _onGeminiError(GeminiLiveError error) {
    errorMessage = error.message;
    _notifySafely();
  }

  void _startTimers() {
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSeconds++;
      _notifySafely();
    });
    _captureTimer = Timer.periodic(
      Duration(seconds: captureIntervalSeconds),
      (_) => _captureFrame(),
    );
    // Capture the very first frame immediately.
    _captureFrame();
  }

  void _stopTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  void _notifySafely() {
    if (!_isDisposed) notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopTimers();
    _transcriptSub?.cancel();
    _errorSub?.cancel();
    cameraController?.dispose();
    super.dispose();
  }
}
