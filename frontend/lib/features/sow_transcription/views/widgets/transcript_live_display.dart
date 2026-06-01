// Purpose: Shows the live transcript stream and keeps the view pinned to the latest text.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';

class TranscriptLiveDisplay extends StatefulWidget {
  const TranscriptLiveDisplay({
    super.key,
    required this.transcript,
  });

  final String transcript;

  @override
  State<TranscriptLiveDisplay> createState() => _TranscriptLiveDisplayState();
}

class _TranscriptLiveDisplayState extends State<TranscriptLiveDisplay> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant TranscriptLiveDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transcript != widget.transcript && widget.transcript.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        boxShadow: AppShadows.card,
      ),
      child: widget.transcript.trim().isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.s6),
                child: Text(
                  'Tap start and begin describing the scope of work.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.bodySubtle,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(AppSpacing.s4),
                child: SelectableText(
                  widget.transcript,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),
    );
  }

  void _scrollToBottom() {
    if (!_scrollController.hasClients) {
      return;
    }

    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }
}
