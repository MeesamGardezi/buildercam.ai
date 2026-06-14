// Purpose: Fullscreen hands-free voice assistant — talk to the agent about any
// SOW in the project while the conversation is transcribed live on screen.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../controllers/sow_voice_chat_controller.dart';
import '../../services/sow_firestore_service.dart';

class SowVoiceChatScreen extends StatefulWidget {
  const SowVoiceChatScreen({
    super.key,
    required this.projectId,
    this.tokenProvider,
  });

  final String projectId;
  final Future<String?> Function()? tokenProvider;

  @override
  State<SowVoiceChatScreen> createState() => _SowVoiceChatScreenState();
}

class _SowVoiceChatScreenState extends State<SowVoiceChatScreen>
    with SingleTickerProviderStateMixin {
  late final SowBackendService _backend;
  late final SowVoiceChatController _controller;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _backend = SowBackendService(tokenProvider: widget.tokenProvider);
    _controller = SowVoiceChatController(
      projectId: widget.projectId,
      backend: _backend,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
      lowerBound: 0.85,
      upperBound: 1.0,
    )..repeat(reverse: true);
    _controller.start();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _controller.dispose();
    _backend.dispose();
    super.dispose();
  }

  Future<void> _endAndClose() async {
    await _controller.end();
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      // Make sure the session is torn down (and history saved) on back nav.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _controller.end();
      },
      child: Scaffold(
        backgroundColor: AppColors.pageBackground,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          surfaceTintColor: AppColors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _endAndClose,
          ),
          title: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Voice Assistant',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  _controller.projectName.isEmpty
                      ? 'Loading…'
                      : _controller.projectName,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppColors.bodyMuted),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: AppColors.border),
          ),
        ),
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              switch (_controller.state) {
                case VoiceChatState.loading:
                case VoiceChatState.connecting:
                  return _ConnectingState(
                    label: _controller.state == VoiceChatState.loading
                        ? 'Loading project context…'
                        : 'Connecting to the assistant…',
                    theme: theme,
                  );
                case VoiceChatState.error:
                  return _ErrorState(
                    message: _controller.errorMessage ?? 'Something went wrong.',
                    theme: theme,
                    onClose: () => context.pop(),
                  );
                case VoiceChatState.listening:
                case VoiceChatState.speaking:
                case VoiceChatState.ended:
                  return Column(
                    children: [
                      Expanded(child: _buildTranscript(theme)),
                      _buildControlBar(theme),
                    ],
                  );
              }
            },
          ),
        ),
      ),
    );
  }

  // ── Transcript ──────────────────────────────────────────────────────────────

  Widget _buildTranscript(ThemeData theme) {
    final messages = _controller.messages;
    final userPartial = _controller.userPartial.trim();
    final agentPartial = _controller.agentPartial.trim();

    if (messages.isEmpty && userPartial.isEmpty && agentPartial.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.graphic_eq_rounded,
                  size: 44, color: AppColors.bodySubtle),
              const SizedBox(height: AppSpacing.s3),
              Text('Start talking', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.s2),
              Text(
                _controller.documentCount == 0
                    ? 'This project has no SOW documents yet — '
                        'you can still ask general questions.'
                    : 'Ask about any of the ${_controller.documentCount} SOW '
                        'document(s) in this project, or tell me what to change.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.bodyMuted),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Newest at the bottom; reverse keeps the latest line pinned while
    // partial transcription streams in.
    final entries = <_TranscriptEntry>[
      for (final m in messages) _TranscriptEntry(m.role, m.text, m.isEdit),
      if (userPartial.isNotEmpty) _TranscriptEntry('user', userPartial, false),
      if (agentPartial.isNotEmpty)
        _TranscriptEntry('model', agentPartial, false),
    ].reversed.toList(growable: false);

    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.s4),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _TranscriptBubble(entry: entry, theme: theme);
      },
    );
  }

  // ── Control bar ─────────────────────────────────────────────────────────────

  Widget _buildControlBar(ThemeData theme) {
    final state = _controller.state;
    final isSpeaking = state == VoiceChatState.speaking;
    final isEnded = state == VoiceChatState.ended;

    final String statusLabel;
    if (isEnded) {
      statusLabel = 'Conversation ended';
    } else if (_controller.muted) {
      statusLabel = 'Muted';
    } else if (isSpeaking) {
      statusLabel = 'Speaking…';
    } else {
      statusLabel = 'Listening…';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.s4, AppSpacing.s4, AppSpacing.s4, AppSpacing.s5),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status orb
          ScaleTransition(
            scale: isEnded ? const AlwaysStoppedAnimation(1.0) : _pulse,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isEnded
                    ? AppColors.surfaceRaised
                    : isSpeaking
                        ? AppColors.primary
                        : AppColors.blue100,
                border: Border.all(
                  color: isEnded ? AppColors.border : AppColors.primary,
                  width: 2,
                ),
              ),
              child: Icon(
                isEnded
                    ? Icons.check_rounded
                    : _controller.muted
                        ? Icons.mic_off_rounded
                        : isSpeaking
                            ? Icons.graphic_eq_rounded
                            : Icons.mic_rounded,
                size: 28,
                color: isSpeaking && !isEnded
                    ? Colors.white
                    : isEnded
                        ? AppColors.bodyMuted
                        : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            statusLabel,
            style:
                theme.textTheme.bodySmall?.copyWith(color: AppColors.bodyMuted),
          ),
          const SizedBox(height: AppSpacing.s4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isEnded) ...[
                OutlinedButton.icon(
                  onPressed: _controller.toggleMute,
                  icon: Icon(
                    _controller.muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    size: 18,
                  ),
                  label: Text(_controller.muted ? 'Unmute' : 'Mute'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor:
                        _controller.muted ? AppColors.danger : AppColors.body,
                    side: BorderSide(
                      color: _controller.muted
                          ? AppColors.danger
                          : AppColors.borderStrong,
                    ),
                    minimumSize: const Size(0, 44),
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                FilledButton.icon(
                  onPressed: _endAndClose,
                  icon: const Icon(Icons.call_end_rounded, size: 18),
                  label: const Text('End'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    minimumSize: const Size(0, 44),
                  ),
                ),
              ] else
                FilledButton.icon(
                  onPressed: () => context.pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Back to project'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(0, 44),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transcript bubble
// ─────────────────────────────────────────────────────────────────────────────

class _TranscriptEntry {
  const _TranscriptEntry(this.role, this.text, this.isEdit);
  final String role;
  final String text;
  final bool isEdit;

  bool get isUser => role == 'user';
}

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.entry, required this.theme});

  final _TranscriptEntry entry;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (entry.isEdit) {
      // Edit marker — centred chip instead of a speech bubble.
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.s3),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded,
                    size: 13, color: AppColors.success),
                const SizedBox(width: 5),
                Text(
                  entry.text,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.success),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isUser = entry.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 480),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
          decoration: BoxDecoration(
            color: isUser ? AppColors.primary : AppColors.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(AppSpacing.radiusLg),
              topRight: const Radius.circular(AppSpacing.radiusLg),
              bottomLeft: Radius.circular(
                  isUser ? AppSpacing.radiusLg : AppSpacing.radiusSm),
              bottomRight: Radius.circular(
                  isUser ? AppSpacing.radiusSm : AppSpacing.radiusLg),
            ),
            border: isUser ? null : Border.all(color: AppColors.border),
          ),
          child: Text(
            entry.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isUser ? Colors.white : AppColors.body,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Connecting / error states
// ─────────────────────────────────────────────────────────────────────────────

class _ConnectingState extends StatelessWidget {
  const _ConnectingState({required this.label, required this.theme});

  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            label,
            style:
                theme.textTheme.bodyMedium?.copyWith(color: AppColors.bodyMuted),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.theme,
    required this.onClose,
  });

  final String message;
  final ThemeData theme;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 44, color: AppColors.danger),
            const SizedBox(height: AppSpacing.s3),
            Text('Voice assistant unavailable',
                style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.s2),
            Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.bodyMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s4),
            OutlinedButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      ),
    );
  }
}
