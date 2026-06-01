// Purpose: Guest-mode landing screen — lets unsigned users try the recording
// and video-feed flows without persisting to the cloud.
import 'package:buildercam/core/core.dart';
import 'package:buildercam/features/auth/auth_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';

class GuestHomeScreen extends StatelessWidget {
  const GuestHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/logos/buildercam-icon-64-transparent.png',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: AppSpacing.s2),
            const Text('Guest Preview'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => auth.signOut(),
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Sign In'),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.s2),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isWide ? AppSpacing.s6 : AppSpacing.s4,
            vertical: AppSpacing.s4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warningLight,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                  border: Border.all(color: AppColors.warning.withAlpha(80)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: Text(
                        'Guest mode — data saves locally only and will not sync to the cloud.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s5),
              Text('Try the features', style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.s3),
              if (isWide)
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _FeatureCard(
                          icon: Icons.mic_rounded,
                          iconColor: AppColors.primary,
                          iconBackground: AppColors.primaryLight,
                          title: 'SOW Voice Recording',
                          description:
                              'Dictate scope of work while Gemini Live '
                              'transcribes your speech in real time.',
                          buttonLabel: 'Open Recording',
                          onTap: () => _openRecording(context, auth),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s4),
                      Expanded(
                        child: _FeatureCard(
                          icon: Icons.videocam_rounded,
                          iconColor: const Color(0xFF7C3AED),
                          iconBackground: const Color(0xFFEDE9FE),
                          title: 'Video Feed',
                          description:
                              'Capture site images every 5 s while your '
                              'voice is recorded to build a visual SOW.',
                          buttonLabel: 'Open Video Feed',
                          onTap: () => _openVideoFeed(context),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: [
                    _FeatureCard(
                      icon: Icons.mic_rounded,
                      iconColor: AppColors.primary,
                      iconBackground: AppColors.primaryLight,
                      title: 'SOW Voice Recording',
                      description:
                          'Dictate scope of work while Gemini Live '
                          'transcribes your speech in real time.',
                      buttonLabel: 'Open Recording',
                      onTap: () => _openRecording(context, auth),
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    _FeatureCard(
                      icon: Icons.videocam_rounded,
                      iconColor: const Color(0xFF7C3AED),
                      iconBackground: const Color(0xFFEDE9FE),
                      title: 'Video Feed',
                      description:
                          'Capture site images every 5 s while your '
                          'voice is recorded to build a visual SOW.',
                      buttonLabel: 'Open Video Feed',
                      onTap: () => _openVideoFeed(context),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openRecording(BuildContext context, AuthController auth) {
    context.pushNamed(
      AppRoute.guestRecording.name,
      pathParameters: {'projectId': ApiConfig.demoProjectId},
      extra: SowRecordingArgs(
        projectId: ApiConfig.demoProjectId,
        createdBy: auth.user?.uid ?? 'guest',
      ),
    );
  }

  void _openVideoFeed(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    context.pushNamed(
      AppRoute.guestVideoFeed.name,
      pathParameters: {'projectId': ApiConfig.demoProjectId},
      extra: VideoFeedArgs(
        projectId: ApiConfig.demoProjectId,
        onFeedComplete: (frames, transcript) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Captured ${frames.length} frame'
                '${frames.length == 1 ? '' : 's'}.'
                '${transcript.isEmpty ? '' : ' "$transcript"'}',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        },
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.description,
    required this.buttonLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String description;
  final String buttonLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radius2xl),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radius2xl),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radius2xl),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    ),
                    child: Icon(icon, color: iconColor, size: 20),
                  ),
                  const Spacer(),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: AppColors.bodySubtle,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.s1),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.bodyMuted,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: onTap,
                  child: Text(buttonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
