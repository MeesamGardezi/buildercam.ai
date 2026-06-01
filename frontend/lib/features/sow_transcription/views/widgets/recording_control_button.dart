// Purpose: Renders the start, stop, and saving states for the recording action.
import 'package:buildercam/core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../controllers/sow_recording_controller.dart';

class RecordingControlButton extends StatelessWidget {
  const RecordingControlButton({
    super.key,
    required this.state,
    required this.onPressed,
    this.idleLabel = 'Start Recording',
  });

  final RecordingState state;
  final VoidCallback? onPressed;
  final String idleLabel;

  @override
  Widget build(BuildContext context) {
    final isConnecting = state == RecordingState.connecting;
    final isRecording = state == RecordingState.recording;
    final isSaving =
        state == RecordingState.connecting || state == RecordingState.saving;

    return SizedBox(
      height: AppSpacing.s12 + AppSpacing.s1,
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isSaving
            ? null
            : onPressed == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onPressed!();
                  },
        style: _buttonStyle(isRecording),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: isSaving
              ? Row(
                  key: ValueKey(state),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: AppSpacing.s5,
                      height: AppSpacing.s5,
                      child: CircularProgressIndicator(
                        strokeWidth: AppSpacing.s1,
                        color: AppColors.bodySubtle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Text(isConnecting ? 'Connecting...' : 'Working...'),
                  ],
                )
              : Row(
                  key: ValueKey(state),
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Text(isRecording ? 'Stop Recording' : idleLabel),
                  ],
                ),
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle(bool isRecording) {
    return AppButtons.primary().copyWith(
      minimumSize: WidgetStateProperty.all(
        const Size.fromHeight(AppSpacing.s12 + AppSpacing.s1),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return AppColors.border;
        }
        return isRecording ? AppColors.danger : AppColors.primary;
      }),
      foregroundColor: WidgetStateProperty.all(AppColors.surface),
    );
  }
}
