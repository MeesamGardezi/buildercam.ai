// Purpose: Read-only history of past voice assistant conversations,
// reachable from SOW settings.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';

import '../../models/sow_chat_message.dart';
import '../../services/shared_prefs_service.dart';

class SowVoiceHistoryScreen extends StatefulWidget {
  const SowVoiceHistoryScreen({super.key});

  @override
  State<SowVoiceHistoryScreen> createState() => _SowVoiceHistoryScreenState();
}

class _SowVoiceHistoryScreenState extends State<SowVoiceHistoryScreen> {
  final _prefs = SowSharedPrefsService();
  List<SowVoiceConversation> _conversations = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final conversations = await _prefs.loadVoiceConversations();
    if (!mounted) return;
    setState(() {
      _conversations = conversations;
      _loading = false;
    });
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'All saved voice assistant conversations on this device will be '
          'deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _prefs.clearVoiceConversations();
    if (!mounted) return;
    setState(() => _conversations = []);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text('Conversation history'),
        actions: [
          if (_conversations.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear history',
              onPressed: _clearAll,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.s8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history_rounded,
                            size: 44, color: AppColors.bodySubtle),
                        const SizedBox(height: AppSpacing.s3),
                        Text('No conversations yet',
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: AppSpacing.s2),
                        Text(
                          'Voice assistant conversations are saved here '
                          'automatically.',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppColors.bodyMuted),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  itemCount: _conversations.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.s2),
                  itemBuilder: (context, index) {
                    final conversation = _conversations[index];
                    return _ConversationTile(
                      conversation: conversation,
                      theme: theme,
                      onTap: () => _openTranscript(conversation),
                    );
                  },
                ),
    );
  }

  void _openTranscript(SowVoiceConversation conversation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _TranscriptViewScreen(conversation: conversation),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.theme,
    required this.onTap,
  });

  final SowVoiceConversation conversation;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final edits = conversation.messages.where((m) => m.isEdit).length;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.blue100,
                borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              ),
              child: const Icon(Icons.graphic_eq_rounded,
                  color: AppColors.primary, size: 18),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.projectName.isEmpty
                        ? 'Voice conversation'
                        : conversation.projectName,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatDate(conversation.startedAt)} · '
                    '${conversation.messages.length} turns'
                    '${edits > 0 ? ' · $edits edit${edits == 1 ? '' : 's'}' : ''}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.bodyMuted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.bodyMuted),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Read-only transcript view
// ─────────────────────────────────────────────────────────────────────────────

class _TranscriptViewScreen extends StatelessWidget {
  const _TranscriptViewScreen({required this.conversation});

  final SowVoiceConversation conversation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          conversation.projectName.isEmpty
              ? 'Voice conversation'
              : conversation.projectName,
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.s4),
        itemCount: conversation.messages.length,
        itemBuilder: (context, index) {
          final message = conversation.messages[index];
          if (message.isEdit) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s3),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                        message.text,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppColors.success),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          final isUser = message.isUser;
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
                  borderRadius:
                      BorderRadius.circular(AppSpacing.radiusLg),
                  border:
                      isUser ? null : Border.all(color: AppColors.border),
                ),
                child: Text(
                  message.text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isUser ? Colors.white : AppColors.body,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
