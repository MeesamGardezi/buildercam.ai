// Purpose: Displays the live recording timer with a pulsing indicator and simple waveform.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';

class RecordingStatusBar extends StatefulWidget {
  const RecordingStatusBar({
    super.key,
    required this.elapsedSeconds,
  });

  final int elapsedSeconds;

  @override
  State<RecordingStatusBar> createState() => _RecordingStatusBarState();
}

class _RecordingStatusBarState extends State<RecordingStatusBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: AppColors.dangerLight,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Row(
            children: [
              FadeTransition(
                opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
                child: Container(
                  width: AppSpacing.s2,
                  height: AppSpacing.s2,
                  decoration: const BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Text(_formattedTime, style: theme.textTheme.labelMedium),
              const Spacer(),
              Row(
                children: List.generate(4, (index) {
                  return Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.s1),
                    child: Container(
                      width: AppSpacing.s1,
                      height: _barHeight(index),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusFull),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  String get _formattedTime {
    final minutes = (widget.elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (widget.elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  double _barHeight(int index) {
    final offset = (_controller.value + (index * 0.18)) % 1;
    return AppSpacing.s2 + (AppSpacing.s5 * offset);
  }
}
