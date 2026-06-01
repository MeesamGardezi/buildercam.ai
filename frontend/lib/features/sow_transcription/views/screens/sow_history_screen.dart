// Purpose: Lists saved transcripts for a single project with pull-to-refresh support.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/sow_recording_controller.dart';
import '../widgets/transcript_history_tile.dart';

class SowHistoryScreen extends StatefulWidget {
  const SowHistoryScreen({
    super.key,
    required this.projectId,
  });

  final String projectId;

  @override
  State<SowHistoryScreen> createState() => _SowHistoryScreenState();
}

class _SowHistoryScreenState extends State<SowHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SowRecordingController>().loadHistory(widget.projectId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scope Transcript History')),
      body: Consumer<SowRecordingController>(
        builder: (context, controller, _) {
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => controller.loadHistory(widget.projectId),
            child: controller.history.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.s6),
                    children: [
                      const SizedBox(height: AppSpacing.s20),
                      const Icon(
                        Icons.library_books_outlined,
                        size: AppSpacing.s12,
                        color: AppColors.bodySubtle,
                      ),
                      const SizedBox(height: AppSpacing.s4),
                      Center(
                        child: Text(
                          'No scope transcripts yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.s4),
                    itemBuilder: (context, index) {
                      return TranscriptHistoryTile(
                        transcript: controller.history[index],
                      );
                    },
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.s3),
                    itemCount: controller.history.length,
                  ),
          );
        },
      ),
    );
  }
}
