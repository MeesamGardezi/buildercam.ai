// Purpose: Full-screen camera feed that captures periodic images and records
// voice via Gemini Live until the user presses "End Video".
import 'package:buildercam/core/core.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/video_feed_controller.dart';
import '../../models/captured_frame.dart';
import '../../services/gemini_live_service.dart';

class VideoFeedScreen extends StatelessWidget {
  const VideoFeedScreen({
    super.key,
    required this.projectId,
    this.onFeedComplete,
    this.captureIntervalSeconds = 5,
  });

  final String projectId;

  /// Called when the user ends the video session. Provides all captured frames
  /// and the accumulated live transcript.
  final void Function(
    List<CapturedFrame> frames,
    String transcript,
  )? onFeedComplete;

  /// How often (seconds) an image is automatically captured. Defaults to 5.
  final int captureIntervalSeconds;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<GeminiLiveService>(
          create: (_) => createGeminiLiveService(),
          dispose: (_, s) => s.dispose(),
        ),
        ChangeNotifierProvider<VideoFeedController>(
          create:
              (ctx) => VideoFeedController(
                projectId: projectId,
                geminiLiveService: ctx.read<GeminiLiveService>(),
                captureIntervalSeconds: captureIntervalSeconds,
              ),
        ),
      ],
      child: _VideoFeedBody(
        onFeedComplete: onFeedComplete,
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _VideoFeedBody extends StatefulWidget {
  const _VideoFeedBody({this.onFeedComplete});

  final void Function(List<CapturedFrame>, String)? onFeedComplete;

  @override
  State<_VideoFeedBody> createState() => _VideoFeedBodyState();
}

class _VideoFeedBodyState extends State<_VideoFeedBody> {
  String? _lastError;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<VideoFeedController>();

    _showErrorIfNew(controller.errorMessage);

    final isBusy = controller.state == VideoFeedState.initializing ||
        controller.state == VideoFeedState.stopping;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: PopScope<void>(
        canPop: !controller.isRecording,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final confirm = await _showStopDialog();
          if (confirm == true) await _handleEndVideo(controller);
        },
        child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──────────────────────────────────────────────
          _CameraPreviewLayer(controller: controller),

          // ── Top overlay: recording indicator + elapsed + frame count ────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: _TopOverlay(controller: controller),
            ),
          ),

          // ── Bottom panel: live transcript + action button ───────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _BottomPanel(
                controller: controller,
                onStart: () =>
                    controller.startFeed(ApiConfig.geminiApiKey),
                onEnd: () => _handleEndVideo(controller),
              ),
            ),
          ),

          // ── Busy spinner ────────────────────────────────────────────────
          if (isBusy)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        ],
      ),
        ),
      ),
    );
  }

  Future<void> _handleEndVideo(VideoFeedController controller) async {
    await controller.stopFeed();
    widget.onFeedComplete?.call(
      List.unmodifiable(controller.capturedFrames),
      controller.liveTranscript,
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  Future<bool?> _showStopDialog() {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End recording?'),
        content: const Text(
          'A recording is in progress. Stop and exit?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep recording'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop & exit'),
          ),
        ],
      ),
    );
  }

  void _showErrorIfNew(String? message) {
    if (message == null || message == _lastError) return;
    _lastError = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.danger,
          content: Text(message),
        ),
      );
    });
  }
}

// ── Camera preview ─────────────────────────────────────────────────────────

class _CameraPreviewLayer extends StatelessWidget {
  const _CameraPreviewLayer({required this.controller});

  final VideoFeedController controller;

  @override
  Widget build(BuildContext context) {
    final cam = controller.cameraController;
    if (cam == null || !cam.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.videocam_off, color: Colors.white38, size: 72),
        ),
      );
    }

    // Fill the screen, cropping to cover (portrait-aware).
    return LayoutBuilder(
      builder: (_, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: cam.value.previewSize?.height ?? 1,
              height: cam.value.previewSize?.width ?? 1,
              child: CameraPreview(cam),
            ),
          ),
        );
      },
    );
  }
}

// ── Top overlay ────────────────────────────────────────────────────────────

class _TopOverlay extends StatelessWidget {
  const _TopOverlay({required this.controller});

  final VideoFeedController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      child: Row(
        children: [
          // Recording dot + timer
          if (controller.isRecording) ...[
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.s2),
            _OverlayText(_formatDuration(controller.elapsedSeconds)),
          ],
          const Spacer(),
          // Frame count badge
          if (controller.frameCount > 0)
            _PillBadge(
              icon: Icons.photo_library_outlined,
              label: '${controller.frameCount}',
            ),
        ],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _OverlayText extends StatelessWidget {
  const _OverlayText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w600,
        fontSize: 15,
        shadows: [Shadow(blurRadius: 6, color: Colors.black87)],
      ),
    );
  }
}

class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: AppSpacing.s1),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom panel ──────────────────────────────────────────────────────────

class _BottomPanel extends StatelessWidget {
  const _BottomPanel({
    required this.controller,
    required this.onStart,
    required this.onEnd,
  });

  final VideoFeedController controller;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final isStopping = controller.state == VideoFeedState.stopping;
    final isInitializing = controller.state == VideoFeedState.initializing;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s10,
        AppSpacing.s4,
        AppSpacing.s5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Captured frame thumbnails ───────────────────────────────────
          if (controller.capturedFrames.isNotEmpty) ...[
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: controller.capturedFrames.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  final frame = controller.capturedFrames[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                    child: Image.memory(
                      frame.bytes,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
          ],

          // Live transcript bubble
          if (controller.liveTranscript.isNotEmpty) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 90),
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  controller.liveTranscript,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
          ],

          // Start / End button
          SizedBox(
            height: AppSpacing.s12 + AppSpacing.s2,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isInitializing || isStopping
                  ? null
                  : (controller.isRecording ? onEnd : onStart),
              icon: Icon(
                controller.isRecording
                    ? Icons.stop_rounded
                    : Icons.videocam_rounded,
                size: AppSpacing.s6,
              ),
              label: Text(
                controller.isRecording ? 'End Video' : 'Start Video',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    controller.isRecording ? Colors.red : AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.charcoal600,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusSm),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
