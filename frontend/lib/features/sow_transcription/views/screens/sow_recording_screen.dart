// Purpose: Hosts the live SOW recording flow and provides the feature-scoped controller tree.
import 'package:buildercam/core/core.dart';
import 'package:buildercam/core/router/app_router.dart';
import 'package:buildercam/features/auth/auth_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../controllers/sow_recording_controller.dart';
import '../../services/gemini_live_service.dart';
import '../../services/sow_firestore_service.dart';
import '../../services/shared_prefs_service.dart';
import '../widgets/recording_control_button.dart';
import '../widgets/recording_status_bar.dart';
import '../widgets/transcript_live_display.dart';

class SowRecordingScreen extends StatefulWidget {
  const SowRecordingScreen({
    super.key,
    required this.projectId,
    this.createdBy,
    this.tokenProvider,
  });

  final String projectId;
  final String? createdBy;

  /// Optional callback to inject a Firebase ID token into backend requests.
  final Future<String?> Function()? tokenProvider;

  @override
  State<SowRecordingScreen> createState() => _SowRecordingScreenState();
}

class _SowRecordingScreenState extends State<SowRecordingScreen> {
  String? _lastErrorMessage;
  bool _canRecord = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPermission());
  }

  Future<void> _loadPermission() async {
    if (!mounted) return;
    final auth = context.read<AuthController>();
    final perm = await auth.permissionsForProject(widget.projectId);
    if (!mounted) return;
    setState(() => _canRecord = perm.canRecord);
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<GeminiLiveService>(
          create: (_) => createGeminiLiveService(),
          dispose: (_, service) {
            service.dispose();
          },
        ),
        Provider<SowBackendService>(
          create: (_) => SowBackendService(tokenProvider: widget.tokenProvider),
          dispose: (_, service) {
            service.dispose();
          },
        ),
        Provider<SowSharedPrefsService>(create: (_) => SowSharedPrefsService()),
        ChangeNotifierProvider<SowRecordingController>(
          create:
              (context) =>
                  SowRecordingController(
                      projectId: widget.projectId,
                      createdBy:
                          widget.createdBy ??
                          context.read<AuthController>().user?.uid ??
                          '',
                      sowBackendService: context.read<SowBackendService>(),
                      geminiLiveService: context.read<GeminiLiveService>(),
                      sharedPrefsService: context.read<SowSharedPrefsService>(),
                      onAutosaveCompleted: null,
                    )
                    ..loadHistory(widget.projectId)
                    ..restoreAutosavedDraft(),
        ),
      ],
      child: Consumer<SowRecordingController>(
        builder: (context, controller, _) {
          _handleErrorState(context, controller);
          final isConnecting =
              controller.recordingState == RecordingState.connecting;
          final isRecording =
              controller.recordingState == RecordingState.recording;
          final isSaving = controller.recordingState == RecordingState.saving;
          final isBusy = isConnecting || isSaving;

          return PopScope<void>(
            canPop: !isRecording,
            onPopInvokedWithResult: (didPop, _) async {
              if (didPop) return;
              final nav = Navigator.of(context);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Stop recording?'),
                  content: const Text(
                    'A recording is in progress. Stop and leave?',
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
              if (confirm == true) {
                await controller.stopRecording();
                if (mounted) nav.pop();
              }
            },
            child: Scaffold(
            appBar: AppBar(
              title: const Text('Scope of Work Transcription'),
              actions: [
                IconButton(
                  tooltip: 'Save Scope Transcript',
                  onPressed:
                      isBusy || controller.draftTranscript.trim().isEmpty
                          ? null
                          : () => controller.saveDraft(),
                  icon: const Icon(Icons.save_rounded),
                ),
                IconButton(
                  tooltip: 'History',
                  onPressed:
                      isBusy ? null : () => _openHistory(context, controller),
                  icon: const Icon(Icons.history_rounded),
                ),
              ],
            ),
            body: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: AppSpacing.sidebarWidth * 2,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.s4),
                        child: Column(
                          children: [
                            if (isRecording) ...[
                              RecordingStatusBar(
                                elapsedSeconds: controller.elapsedSeconds,
                              ),
                              const SizedBox(height: AppSpacing.s4),
                            ],
                            Expanded(
                              child: TranscriptLiveDisplay(
                                transcript: controller.draftTranscript,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.s4),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.s3,
                              ),
                              child: Column(
                                children: [
                                  if (!_canRecord)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: AppSpacing.s2,
                                      ),
                                      child: Text(
                                        'You don\'t have permission to record on this project.',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: AppColors.bodyMuted),
                                      ),
                                    ),
                                  RecordingControlButton(
                                    state: controller.recordingState,
                                    onPressed: !_canRecord
                                        ? null
                                        : () => isRecording
                                            ? controller.stopRecording()
                                            : controller.startRecording(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (isBusy)
                    const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    ),
                ],
              ),
            ),
            ),
          );
        },
      ),
    );
  }

  void _openHistory(BuildContext context, SowRecordingController controller) {
    context.pushNamed(
      AppRoute.sowHistory.name,
      pathParameters: {'projectId': widget.projectId},
      extra: SowHistoryArgs(controller: controller),
    );
  }

  void _handleErrorState(
    BuildContext context,
    SowRecordingController controller,
  ) {
    final message = controller.errorMessage;
    if (message == null) {
      _lastErrorMessage = null;
      return;
    }
    if (message == _lastErrorMessage) return;
    _lastErrorMessage = message;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: AppColors.danger, content: Text(message)),
      );
      context.read<SowRecordingController>().clearError();
    });
  }
}
