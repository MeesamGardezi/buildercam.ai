// Purpose: Renders one saved transcript row for the per-project history screen.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';

import '../../models/sow_transcript_model.dart';

class TranscriptHistoryTile extends StatelessWidget {
  const TranscriptHistoryTile({
    super.key,
    required this.transcript,
  });

  final SowTranscriptModel transcript;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final recordedAt = '${localizations.formatCompactDate(transcript.createdAt)} '
        '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(transcript.createdAt))}';
    final isCompleted = transcript.status == SowTranscriptStatus.completed;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    recordedAt,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s2,
                    vertical: AppSpacing.s1,
                  ),
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.successLight
                        : AppColors.dangerLight,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                  ),
                  child: Text(
                    transcript.status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          isCompleted ? AppColors.success : AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              _durationLabel(transcript.durationSeconds),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              transcript.rawTranscript,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  String _durationLabel(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes}m ${seconds.toString().padLeft(2, '0')}s';
  }
}
